#!/usr/bin/env bash
# Sichert die Nutzdaten der VM auf die angesteckte Wechselplatte (Proxmox
# Backup Server).
#
# Aufruf:
#   bash scripts/media-backup.sh            # nur wenn der letzte Erfolg alt ist
#   bash scripts/media-backup.sh --force    # immer (Knopf auf backup.<domain>)
#
# Automatisch: systemd-Timer apphost-media-backup (alle 10 Minuten) und die
# path-Unit, die auf den Knopf reagiert – beides in nixos/modules/backup.nix.
#
# WARUM EIN TIMER UND KEIN AUSLÖSER VOM HOST:
# Die Platte hängt am Proxmox-Host, die Daten liegen in der VM. Der naheliegende
# Weg wäre eine SSH-Verbindung vom Host in die VM – die ist bewusst NICHT
# gebaut. Stattdessen fragt die VM regelmäßig PBS, ob der Datastore erreichbar
# ist. Ist er es nicht, endet dieses Skript kommentarlos mit 0. Damit gibt es
# keine Zugangsdaten und keinen Shell-Zugriff über die Maschinengrenze; das
# einzige Geheimnis ist ein PBS-API-Token, das ausschließlich Snapshots anlegen
# und lesen darf (Datastore.Backup + Datastore.Audit) – nicht löschen, nicht
# prunen, nichts anderes sehen.
#
# ZWEI PLATTEN, ZWEI DATASTORES: PBS-Datastore-Namen sind eindeutig, zwei
# Wechselplatten sind also zwei Datastores (cold-a, cold-b). Das Skript probiert
# alle konfigurierten durch und nimmt den, der gerade da ist. Genau daraus fällt
# auch die Plattenkennung für Metrik und Anzeige ab.
set -uo pipefail

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

ROOT_DIR="${ROOT_DIR:-/opt/monorepo}"
CONF="${PBS_CONF:-$ROOT_DIR/secrets/pbs.env}"
STATE_DIR="/var/lib/apphost-backup/state"
WEB_DIR="/var/lib/apphost-backup/web"
TEXTFILE_DIR="/var/lib/node-exporter/textfile"
# Mindestabstand zwischen zwei Läufen, solange die Platte steckt. Ohne das
# liefe alle 10 Minuten ein Backup, sobald die Platte einen Abend dranhängt.
MIN_INTERVAL="${MIN_INTERVAL:-86400}"

log() { echo "media-backup: $*"; }

[[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen (liest /var/lib/docker/volumes)." >&2; exit 1; }

if [[ ! -f "$CONF" ]]; then
    log "$CONF fehlt – Backup nicht eingerichtet. Siehe Installationsanleitung, Kapitel Backup."
    exit 0
fi
# shellcheck source=/dev/null
source "$CONF"

: "${PBS_HOST:?PBS_HOST fehlt in $CONF}"
: "${PBS_TOKEN:?PBS_TOKEN fehlt in $CONF}"
: "${PBS_SECRET:?PBS_SECRET fehlt in $CONF}"
: "${PBS_DATASTORES:?PBS_DATASTORES fehlt in $CONF}"
KEYFILE="${PBS_KEYFILE:-$ROOT_DIR/secrets/pbs-encryption.key}"

mkdir -p "$STATE_DIR" "$WEB_DIR" "$TEXTFILE_DIR"

# proxmox-backup-client liest das Token-Geheimnis aus PBS_PASSWORD und den
# Zertifikats-Fingerabdruck aus PBS_FINGERPRINT. Beides über die Umgebung, nicht
# über argv – auf dem Host ist argv per `ps` für jeden lesbar.
export PBS_PASSWORD="$PBS_SECRET"
[[ -n "${PBS_FINGERPRINT:-}" ]] && export PBS_FINGERPRINT

# --- Metrik + Statusdatei neu erzeugen -------------------------------------
# Die .prom-Datei wird bei JEDEM Lauf aus allen Zustandsdateien neu gebaut, nicht
# fortgeschrieben. Sonst verschwände der Zeitstempel der gerade nicht
# angesteckten Platte – und genau der ist der interessante (BackupRotationStalled
# in config/prometheus/rules/alerts.yml schlägt an, wenn eine Platte zu lange
# im Schrank liegt).
# Zustand je Platte liegt in einzelnen Dateien unter $STATE_DIR:
#   <ds>            Zeitpunkt des letzten ERFOLGS (epoch)
#   <ds>.duration   Dauer des letzten Laufs in Sekunden
#   <ds>.status     1 = letzter Lauf ok, 0 = fehlgeschlagen
#   <ds>.used       belegte Bytes im Datastore (aus dem letzten status-Aufruf)
#   <ds>.total      Größe des Datastores in Bytes
st() { cat "$STATE_DIR/$1" 2>/dev/null || echo "${2:-0}"; }

write_metrics() {  # <aktueller-datastore-oder-leer> <online 0|1> <running 0|1>
    local current="${1:-}" online="${2:-0}" running="${3:-0}" tmp ds ts v
    tmp="$(mktemp "$TEXTFILE_DIR/.apphost_backup.XXXXXX")"
    {
        echo "# HELP apphost_backup_last_success_timestamp_seconds Zeitpunkt des letzten erfolgreichen Medien-Backups je Wechselplatte."
        echo "# TYPE apphost_backup_last_success_timestamp_seconds gauge"
        # Nur Platten, die schon mindestens einmal gesichert wurden. Eine Serie
        # mit dem Wert 0 hieße für Prometheus "letztes Backup 1970" und ließe
        # am Tag der Einrichtung sofort alle drei Backup-Alarme feuern. Ist
        # noch nie etwas gelaufen, fehlt die Metrik ganz – dafür ist
        # BackupMetricMissing da.
        for ds in $PBS_DATASTORES; do
            ts="$(st "$ds")"
            [[ "$ts" -gt 0 ]] && \
                echo "apphost_backup_last_success_timestamp_seconds{disk=\"$ds\"} $ts"
        done

        echo "# HELP apphost_backup_duration_seconds Laufzeit des letzten Medien-Backups je Wechselplatte."
        echo "# TYPE apphost_backup_duration_seconds gauge"
        for ds in $PBS_DATASTORES; do
            v="$(st "$ds.duration")"
            [[ "$v" -gt 0 ]] && echo "apphost_backup_duration_seconds{disk=\"$ds\"} $v"
        done

        echo "# HELP apphost_backup_last_run_success Ob der letzte Lauf je Wechselplatte erfolgreich war (1/0)."
        echo "# TYPE apphost_backup_last_run_success gauge"
        for ds in $PBS_DATASTORES; do
            [[ -f "$STATE_DIR/$ds.status" ]] && \
                echo "apphost_backup_last_run_success{disk=\"$ds\"} $(st "$ds.status")"
        done

        # Füllstand der Wechselplatte. Kommt aus demselben status-Aufruf, mit dem
        # geprüft wird, ob die Platte überhaupt steckt – kostet also nichts extra.
        # Die Werte der GERADE NICHT angesteckten Platte bleiben stehen: sie sind
        # der letzte bekannte Stand und genau die Zahl, die man sehen will, bevor
        # man entscheidet, ob die Platte noch reicht.
        echo "# HELP apphost_backup_datastore_used_bytes Belegter Platz im Datastore der Wechselplatte."
        echo "# TYPE apphost_backup_datastore_used_bytes gauge"
        for ds in $PBS_DATASTORES; do
            v="$(st "$ds.used")"
            [[ "$v" -gt 0 ]] && echo "apphost_backup_datastore_used_bytes{disk=\"$ds\"} $v"
        done
        echo "# HELP apphost_backup_datastore_total_bytes Größe des Datastores der Wechselplatte."
        echo "# TYPE apphost_backup_datastore_total_bytes gauge"
        for ds in $PBS_DATASTORES; do
            v="$(st "$ds.total")"
            [[ "$v" -gt 0 ]] && echo "apphost_backup_datastore_total_bytes{disk=\"$ds\"} $v"
        done

        echo "# HELP apphost_backup_datastore_online Ob gerade eine Wechselplatte erreichbar ist."
        echo "# TYPE apphost_backup_datastore_online gauge"
        echo "apphost_backup_datastore_online $online"
        echo "# HELP apphost_backup_running Ob gerade ein Medien-Backup läuft."
        echo "# TYPE apphost_backup_running gauge"
        echo "apphost_backup_running $running"
    } > "$tmp"
    # Der Textfile-Collector liest das Verzeichnis unabhängig von uns; eine halb
    # geschriebene Datei ergäbe kaputte Metriken. Deshalb atomar tauschen.
    chmod 0644 "$tmp"
    mv -f "$tmp" "$TEXTFILE_DIR/apphost_backup.prom"

    local newest=0 newest_ds="–"
    for ds in $PBS_DATASTORES; do
        ts="$(cat "$STATE_DIR/$ds" 2>/dev/null || echo 0)"
        if [[ "$ts" -gt "$newest" ]]; then newest="$ts"; newest_ds="$ds"; fi
    done
    # age_days und last_success_iso sind fertig formatiert, damit weder die
    # Statusseite noch das Homepage-Widget ein Zeitformat raten muss.
    # Bewusst Bash-Arithmetik statt awk: die Unit bekommt in
    # nixos/modules/backup.nix nur coreutils/grep/curl/bash in ihren PATH, ein
    # gawk-Aufruf würde dort schlicht nicht gefunden.
    local age_days="-1" iso="nie"
    if [[ "$newest" -gt 0 ]]; then
        age_days="$(( ( $(date +%s) - newest ) / 86400 ))"
        iso="$(date -d "@$newest" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
    fi
    # Dauer und Füllstand der zuletzt benutzten Platte, fertig aufbereitet –
    # die Statusseite und das Homepage-Widget sollen nichts rechnen müssen.
    local dur used total pct dur_text
    dur="$(st "$newest_ds.duration")"
    used="$(st "$newest_ds.used")"; total="$(st "$newest_ds.total")"
    pct=-1
    [[ "$total" -gt 0 ]] && pct=$(( used * 100 / total ))
    if   [[ "$dur" -le 0 ]];    then dur_text="–"
    elif [[ "$dur" -lt 60 ]];   then dur_text="${dur} s"
    elif [[ "$dur" -lt 3600 ]]; then dur_text="$(( dur / 60 )) min"
    else dur_text="$(( dur / 3600 )) h $(( (dur % 3600) / 60 )) min"
    fi
    tmp="$(mktemp "$WEB_DIR/.status.XXXXXX")"
    printf '{"last_success":%s,"last_success_iso":"%s","age_days":%s,"disk":"%s","datastore_online":%s,"running":%s,"duration_seconds":%s,"duration_text":"%s","used_percent":%s,"current":"%s"}\n' \
        "$newest" "$iso" "$age_days" "$newest_ds" \
        "$([[ "$online" == 1 ]] && echo true || echo false)" \
        "$([[ "$running" == 1 ]] && echo true || echo false)" \
        "$dur" "$dur_text" "$pct" "${current:-}" > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$WEB_DIR/status.json"
}

# --- Welche Platte steckt? --------------------------------------------------
REPO=""
DATASTORE=""
for ds in $PBS_DATASTORES; do
    candidate="${PBS_TOKEN}@${PBS_HOST}:${ds}"
    # Ein Aufruf, zwei Zwecke: Ist die Platte nicht angesteckt, meldet PBS den
    # Datastore als offline und der Aufruf scheitert – das IST die Prüfung, ohne
    # Fehlertexte zu parsen. Klappt er, steht in der Antwort gleich der
    # Füllstand, den das Dashboard zeigt.
    if status_json="$(proxmox-backup-client status --repository "$candidate" \
                        --output-format json 2>/dev/null)"; then
        REPO="$candidate"; DATASTORE="$ds"
        # Fehlt jq oder ändert PBS das Format, bleibt der Füllstand einfach
        # leer – das Backup selbst darf daran nicht scheitern.
        used="$(printf '%s' "$status_json" | jq -r '.used // 0' 2>/dev/null || echo 0)"
        total="$(printf '%s' "$status_json" | jq -r '.total // 0' 2>/dev/null || echo 0)"
        [[ "$used"  =~ ^[0-9]+$ ]] && echo "$used"  > "$STATE_DIR/$ds.used"
        [[ "$total" =~ ^[0-9]+$ ]] && echo "$total" > "$STATE_DIR/$ds.total"
        break
    fi
done

if [[ -z "$REPO" ]]; then
    log "keine Wechselplatte erreichbar – übersprungen."
    write_metrics "" 0 0
    exit 0
fi
log "Datastore $DATASTORE erreichbar."

# --- Muss überhaupt gesichert werden? ---------------------------------------
LAST="$(st "$DATASTORE")"
AGE=$(( $(date +%s) - LAST ))
if [[ "$FORCE" != true && "$LAST" -gt 0 && "$AGE" -lt "$MIN_INTERVAL" ]]; then
    log "letzter Lauf auf $DATASTORE vor $((AGE / 3600)) h – noch nichts zu tun."
    write_metrics "$DATASTORE" 1 0
    exit 0
fi

# --- Sichern ----------------------------------------------------------------
# Was NICHT mitkommt:
#   /mnt/media/jellyfin        wiederbeschaffbar, würde die Größe dominieren
#   *_prometheus_data          reine Telemetrie, bis 50 GB
#   *_loki_data                dito
#   *_immich_ml_cache          Modell-Cache, lädt sich neu
#   *_jellyfin_cache           Thumbnails, bauen sich neu
# Alles andere kommt mit – auch Volumes, an die gerade niemand denkt. Der
# Fehlerfall dieser Richtung ist "unnötig gesichert", der umgekehrten "still
# verloren". Nur einer der beiden tut weh.
KEY_ARGS=()
if [[ -f "$KEYFILE" ]]; then
    KEY_ARGS=(--keyfile "$KEYFILE")
else
    log "WARNUNG: $KEYFILE fehlt – es wird UNVERSCHLÜSSELT gesichert."
fi

log "starte Backup nach $DATASTORE …"
# running=1 SOFORT rausschreiben, nicht erst am Ende: bei 1,5 TB läuft der
# erste Durchgang Stunden, und genau in dieser Zeit will man auf dem Dashboard
# sehen, dass etwas passiert – statt einer Kachel, die unverändert das alte
# Backup-Alter zeigt.
write_metrics "$DATASTORE" 1 1
STARTED=$(date +%s)
if proxmox-backup-client backup \
        media.pxar:/mnt/media \
        volumes.pxar:/var/lib/docker/volumes \
        repo.pxar:"$ROOT_DIR" \
        dumps.pxar:/var/backups/apphost \
        --repository "$REPO" \
        --backup-id apphost \
        --exclude '/jellyfin' \
        --exclude '/apphost_prometheus_data' \
        --exclude '/apphost_loki_data' \
        --exclude '/apphost_immich_ml_cache' \
        --exclude '/apphost_jellyfin_cache' \
        --exclude '/.git' \
        "${KEY_ARGS[@]}"; then
    rc=0
else
    rc=$?
fi
DURATION=$(( $(date +%s) - STARTED ))
echo "$DURATION" > "$STATE_DIR/$DATASTORE.duration"

# Belegung nach dem Lauf neu abfragen – vorher ist sie um genau das falsch, was
# der Lauf gerade geschrieben hat, und der Füllstand ist die Zahl, wegen der man
# aufs Dashboard schaut.
if status_json="$(proxmox-backup-client status --repository "$REPO" \
                    --output-format json 2>/dev/null)"; then
    used="$(printf '%s' "$status_json" | jq -r '.used // 0' 2>/dev/null || echo 0)"
    total="$(printf '%s' "$status_json" | jq -r '.total // 0' 2>/dev/null || echo 0)"
    [[ "$used"  =~ ^[0-9]+$ ]] && echo "$used"  > "$STATE_DIR/$DATASTORE.used"
    [[ "$total" =~ ^[0-9]+$ ]] && echo "$total" > "$STATE_DIR/$DATASTORE.total"
fi

if [[ "$rc" -eq 0 ]]; then
    date +%s > "$STATE_DIR/$DATASTORE"
    echo 1 > "$STATE_DIR/$DATASTORE.status"
    write_metrics "$DATASTORE" 1 0
    log "fertig ($DATASTORE) nach ${DURATION}s."
else
    echo 0 > "$STATE_DIR/$DATASTORE.status"
    write_metrics "$DATASTORE" 1 0
    log "FEHLGESCHLAGEN nach ${DURATION}s (exit $rc)."
    exit "$rc"
fi

# --- Fertigmeldung ----------------------------------------------------------
# Bewusst über notify-failure.sh's Gegenstück NICHT gelöst: eine Erfolgsmeldung
# gehört nicht in eine OnFailure-Kette. Direkt an denselben ntfy-Topic, mit den
# Zugangsdaten, die in der VM ohnehin liegen.
PW_FILE="$ROOT_DIR/secrets/alertmanager_ntfy_password"
DOMAIN="$(grep -m1 '^[[:space:]]*DOMAIN=' "$ROOT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d "\"' \r")"
NTFY_SUB="$(grep -m1 '^[[:space:]]*NTFY_SUBDOMAIN=' "$ROOT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d "\"' \r")"
NTFY_SUB="${NTFY_SUB:-ntfy}"
if [[ -n "$DOMAIN" && -f "$PW_FILE" ]]; then
    # Zugangsdaten über eine curl-Konfiguration auf stdin, nicht per -u:
    # alles in argv ist per `ps` mitlesbar. Gleiches Muster wie notify-failure.sh.
    # Als Funktion, weil stdin nach dem ersten Versuch aufgebraucht wäre – der
    # Rückfall auf die lokale CA bekäme sonst eine leere Konfiguration.
    curl_config() {
        local pw; pw="$(cat "$PW_FILE")"
        pw="${pw//\\/\\\\}"; pw="${pw//\"/\\\"}"
        printf 'user = "alertmanager:%s"\n' "$pw"
    }
    NOTE_ARGS=(-fsS --max-time 20
        -H "Title: Backup fertig ($DATASTORE)"
        -H "Tags: floppy_disk"
        -d "Medien-Backup auf $DATASTORE abgeschlossen.
Dauer: $(( DURATION / 3600 )) h $(( (DURATION % 3600) / 60 )) min
Platte belegt: $(st "$DATASTORE.used") von $(st "$DATASTORE.total") Bytes

Der Host räumt jetzt noch auf (Prune/Verify/GC) und hängt die Platte aus.
Abziehen, sobald PBS den Datastore ausgehängt hat.")
    URL="https://${NTFY_SUB}.${DOMAIN}/apphost-critical"
    # Erst mit dem System-Truststore, dann mit der lokalen CA (--cacert ERSETZT
    # den Truststore, deshalb nicht fest verdrahtet – bei echter Domain mit
    # Let's-Encrypt-Zertifikat wäre das sonst der Bruch).
    if ! curl_config | curl -K - "${NOTE_ARGS[@]}" "$URL" >/dev/null 2>&1 \
       && ! curl_config | curl -K - "${NOTE_ARGS[@]}" \
              --cacert /var/lib/apphost-ca/local-ca.crt "$URL" >/dev/null 2>&1; then
        log "Fertigmeldung an ntfy nicht zugestellt (das Backup selbst war erfolgreich)."
    fi
fi
exit 0
