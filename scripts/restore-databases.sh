#!/usr/bin/env bash
# Spielt die Dumps aus scripts/backup-databases.sh wieder ein.
#
# Warum es dieses Skript gibt: backup-databases.sh endet mit dem Satz "ein
# Backup ist erst dann eines, wenn der Restore einmal durchgespielt wurde" –
# und genau dafür gab es nichts. Der Weg war undokumentiert und musste im
# Ernstfall improvisiert werden: Container stoppen, Volume-Mountpoint suchen,
# Datei mit den richtigen (unter userns-remap verschobenen!) Besitzrechten
# zurücklegen, WAL/SHM wegräumen. Wer das unter Zeitdruck zum ersten Mal macht,
# macht es falsch.
#
#   Auflisten:   sudo bash scripts/restore-databases.sh --list
#   Probelauf:   sudo bash scripts/restore-databases.sh --dry-run authelia
#   Einspielen:  sudo bash scripts/restore-databases.sh authelia
#                sudo bash scripts/restore-databases.sh --file /pfad/dump authelia
#   Alles:       sudo bash scripts/restore-databases.sh --all
#
# Ohne --file wird der NEUESTE Dump des jeweiligen Dienstes genommen.
# age-verschlüsselte Dumps (.age) brauchen den privaten Schlüssel:
#   sudo BACKUP_AGE_IDENTITY=/root/apphost-backup.key bash scripts/restore-databases.sh …
#
# Kommen die Dumps von der Wechselplatte statt aus /var/backups/apphost, vorher
# aus PBS herausholen (siehe proxmox/README.md) und mit --file darauf zeigen.
#
# ACHTUNG: Der Restore ÜBERSCHREIBT die laufende Datenbank. Das Skript stoppt
# den betroffenen Container, legt eine Sicherheitskopie des aktuellen Standes
# daneben und startet ihn danach wieder.
set -uo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/apphost}"
AGE_IDENTITY="${BACKUP_AGE_IDENTITY:-}"
DRY_RUN=false
ASSUME_YES=false
LIST_ONLY=false
EXPLICIT_FILE=""

# "<name>:<container>:<docker-volume>:<pfad-im-volume>" – dieselbe Liste wie in
# backup-databases.sh, ergänzt um den Container-Namen (den braucht nur der
# Restore, weil er ihn stoppen muss).
SQLITE_DBS=(
    "authelia:authelia:apphost_authelia_data:db.sqlite3"
    "grafana:grafana:apphost_grafana_data:grafana.db"
    "vaultwarden:vaultwarden:apphost_vaultwarden_data:db.sqlite3"
    "paperless:paperless:apphost_paperless_data:db.sqlite3"
    "grocy:grocy:apphost_grocy_config:data/grocy.db"
    "ntfy:ntfy:apphost_ntfy_data:users.db"
)
PG_NAME="immich-postgres"
# Diese Container schreiben in die Immich-Datenbank und müssen während des
# Restores aus sein, sonst laufen sie mitten in den psql-Lauf hinein.
PG_DEPENDENTS=(immich-server immich-ml)

KNOWN=(authelia grafana vaultwarden paperless grocy ntfy immich)

TARGETS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    LIST_ONLY=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --yes|-y)  ASSUME_YES=true; shift ;;
        --all)     TARGETS=("${KNOWN[@]}"); shift ;;
        --file)    EXPLICIT_FILE="${2:?--file braucht einen Pfad}"; shift 2 ;;
        -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "Unbekannte Option: $1" >&2; exit 1 ;;
        *)         TARGETS+=("$1"); shift ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen (Zugriff auf die Docker-Volumes)." >&2; exit 1; }
[[ -d "$BACKUP_DIR" ]] || { echo "Kein Backup-Verzeichnis: $BACKUP_DIR" >&2; exit 1; }

if [[ "$LIST_ONLY" == true ]]; then
    echo "Dumps in $BACKUP_DIR (neueste zuerst):"
    # find statt ls: ls parst sich schlecht, sobald ein Dateiname etwas
    # Ungewöhnliches enthält (SC2012).
    find "$BACKUP_DIR" -maxdepth 1 -type f -printf '%T@ %f\n' 2>/dev/null \
        | sort -rn | cut -d' ' -f2- | sed 's/^/  /' | grep . || echo "  (leer)"
    exit 0
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "Kein Dienst angegeben. Bekannt: ${KNOWN[*]}" >&2
    echo "Hilfe: bash scripts/restore-databases.sh --help" >&2
    exit 1
fi
if [[ -n "$EXPLICIT_FILE" && ${#TARGETS[@]} -ne 1 ]]; then
    echo "--file gilt für genau EINEN Dienst." >&2
    exit 1
fi

run()  { if [[ "$DRY_RUN" == true ]]; then echo "    [dry-run] $*"; else "$@"; fi; }
note() { echo "    $*"; }

confirm() {
    [[ "$DRY_RUN" == true || "$ASSUME_YES" == true ]] && return 0
    local answer
    read -rp "  $1 [ja/NEIN]: " answer
    [[ "$answer" == "ja" ]]
}

# Namensschema aus backup-databases.sh: <name>_<YYYY-MM-DD_HHMMSS>.<endung>[.age]
latest_dump() {
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "$1_*" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-
}

# Entpackt nach stdout: erst age (falls .age), dann gzip (falls .gz). Die
# Klartext-Zwischenstufe landet nie als eigene Datei auf der Platte.
decode_dump() {
    local f="$1"
    if [[ "$f" == *.age ]]; then
        [[ -n "$AGE_IDENTITY" ]] || {
            echo "  ! $f ist age-verschlüsselt – BACKUP_AGE_IDENTITY=<keyfile> setzen." >&2; return 1; }
        [[ -f "$AGE_IDENTITY" ]] || { echo "  ! Schlüsseldatei $AGE_IDENTITY fehlt." >&2; return 1; }
        age -d -i "$AGE_IDENTITY" "$f"
    else
        cat "$f"
    fi | if [[ "${f%.age}" == *.gz ]]; then gzip -dc; else cat; fi
}

container_running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

fail=0

restore_sqlite() {
    local name="$1" entry n container="" volume relpath dump mountpoint target
    for entry in "${SQLITE_DBS[@]}"; do
        IFS=':' read -r n container volume relpath <<< "$entry"
        [[ "$n" == "$name" ]] && break
        container=""
    done
    [[ -n "$container" ]] || { echo "  ! Unbekannter Dienst: $name" >&2; fail=1; return; }

    dump="${EXPLICIT_FILE:-$(latest_dump "$name")}"
    [[ -n "$dump" && -f "$dump" ]] || { echo "  ! Kein Dump für $name in $BACKUP_DIR" >&2; fail=1; return; }

    mountpoint="$(docker volume inspect -f '{{.Mountpoint}}' "$volume" 2>/dev/null || true)"
    [[ -n "$mountpoint" ]] || { echo "  ! Volume $volume nicht gefunden" >&2; fail=1; return; }
    target="$mountpoint/$relpath"

    echo "==> $name"
    note "Dump: $dump"
    note "Ziel: $target"
    confirm "Aktuelle Datenbank von '$name' überschreiben?" || { note "übersprungen."; return; }

    # Erst daneben entpacken und PRÜFEN, dann tauschen. Bei einem kaputten Dump
    # bleibt der laufende Stand damit unangetastet.
    local staged="$target.restore-$$"
    if ! decode_dump "$dump" > "$staged" 2>/dev/null; then
        rm -f "$staged"; echo "  ! Entpacken fehlgeschlagen" >&2; fail=1; return
    fi
    if ! sqlite3 "$staged" "PRAGMA quick_check;" | grep -qx ok; then
        rm -f "$staged"; echo "  ! Dump besteht PRAGMA quick_check nicht – Abbruch" >&2; fail=1; return
    fi

    local was_running=false
    if container_running "$container"; then
        note "stoppe $container …"
        run docker stop "$container" >/dev/null
        was_running=true
    fi

    # Besitzer und Rechte der ALTEN Datei übernehmen. Unter userns-remap gehören
    # die Dateien einer hohen Host-UID (Basis+N); eine als root zurückgelegte
    # Datei erschiene im Container als "nobody" und der Dienst startet nicht mehr.
    if [[ -f "$target" ]]; then
        local owner mode keep
        owner="$(stat -c '%u:%g' "$target")"
        mode="$(stat -c '%a' "$target")"
        keep="$target.vor-restore-$(date +%Y%m%d-%H%M%S)"
        note "Sicherheitskopie des aktuellen Standes: $keep"
        run cp -a "$target" "$keep"
        run chown "$owner" "$staged"
        run chmod "$mode" "$staged"
    fi

    # WAL/SHM gehören zur ersetzten Datei und würden sich sonst beim Öffnen über
    # den frisch eingespielten Stand legen.
    run rm -f "$target-wal" "$target-shm"
    run mv -f "$staged" "$target"
    [[ "$DRY_RUN" == true ]] && rm -f "$staged"
    note "eingespielt."

    if [[ "$was_running" == true ]]; then
        note "starte $container …"
        run docker start "$container" >/dev/null
    fi
}

restore_postgres() {
    local dump dep stopped=()
    dump="${EXPLICIT_FILE:-$(latest_dump "$PG_NAME")}"
    [[ -n "$dump" && -f "$dump" ]] || { echo "  ! Kein Dump für immich in $BACKUP_DIR" >&2; fail=1; return; }

    echo "==> immich (Postgres)"
    note "Dump: $dump"
    container_running "$PG_NAME" || {
        echo "  ! $PG_NAME läuft nicht – erst starten: docker start $PG_NAME" >&2; fail=1; return; }
    confirm "Immich-Datenbank überschreiben (pg_dumpall --clean)?" || { note "übersprungen."; return; }

    for dep in "${PG_DEPENDENTS[@]}"; do
        if container_running "$dep"; then
            note "stoppe $dep …"
            run docker stop "$dep" >/dev/null
            stopped+=("$dep")
        fi
    done

    # Der Dump stammt aus pg_dumpall --clean --if-exists und wird gegen die
    # Wartungsdatenbank "postgres" gefahren – er legt Rollen und die Datenbank
    # immich selbst wieder an. ON_ERROR_STOP=1, damit ein Fehler nicht
    # stillschweigend eine halb wiederhergestellte Datenbank hinterlässt.
    if [[ "$DRY_RUN" == true ]]; then
        note "[dry-run] decode_dump | docker exec -i $PG_NAME psql -v ON_ERROR_STOP=1 …"
    elif decode_dump "$dump" \
           | docker exec -i "$PG_NAME" sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres' >/dev/null; then
        note "eingespielt."
    else
        echo "  ! psql-Restore fehlgeschlagen – Datenbank kann unvollständig sein." >&2
        fail=1
    fi

    for dep in "${stopped[@]}"; do
        note "starte $dep …"
        run docker start "$dep" >/dev/null
    done
}

[[ "$DRY_RUN" == true ]] && { echo "(Probelauf – es wird nichts verändert)"; echo; }

for t in "${TARGETS[@]}"; do
    case "$t" in
        immich|immich-postgres)                       restore_postgres ;;
        authelia|grafana|vaultwarden|paperless|grocy|ntfy) restore_sqlite "$t" ;;
        *) echo "  ! Unbekannter Dienst: $t (bekannt: ${KNOWN[*]})" >&2; fail=1 ;;
    esac
    echo
done

if [[ "$fail" -eq 0 ]]; then
    echo "Fertig. Den betroffenen Dienst im Browser gegenprüfen, bevor du dich darauf verlässt."
else
    echo "Mit Fehlern beendet – siehe Meldungen oben." >&2
fi
exit "$fail"
