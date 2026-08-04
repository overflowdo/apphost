#!/usr/bin/env bash
# Läuft auf dem PROXMOX-HOST, nicht in der VM.
#
# Wird von udev gestartet, sobald eine der beiden Wechselplatten angesteckt wird
# (99-apphost-coldbackup.rules). Ablauf:
#
#   1. PBS-Datastore einhängen
#   2. vzdump der VM in denselben Datastore
#   3. warten, bis die VM ihr Medien-Backup abgelegt hat
#      (sie merkt selbst, dass der Datastore antwortet – ihr Timer läuft alle
#      10 Minuten, der Knopf auf backup.<domain> geht sofort)
#   4. prune -> verify (Stichprobe) -> garbage-collect (nur wenn fällig)
#   5. aushängen
#
# BEWUSST KEIN SSH IN DIE VM. Die beiden Seiten koordinieren sich ausschließlich
# über den Datastore: der Host sieht, wann ein neuer Medien-Snapshot da ist, die
# VM sieht, ob der Datastore antwortet. Damit gibt es keinen Shell-Zugriff und
# keine Zugangsdaten über die Maschinengrenze.
#
# Installation siehe proxmox/README.md.
set -uo pipefail

DATASTORE="${1:?Datastore-Name als erstes Argument (cold-a|cold-b)}"

# Wie lange auf das Medien-Backup der VM gewartet wird. Die Erstsicherung von
# ~1,5 TB dauert Stunden – lieber großzügig als mittendrin abbrechen.
WAIT_MAX="${WAIT_MAX:-43200}"        # 12 h
IDLE_AFTER="${IDLE_AFTER:-900}"      # 15 min ohne laufende Task = fertig
VMID="${VMID:-100}"
GC_INTERVAL_DAYS="${GC_INTERVAL_DAYS:-30}"
STATE_DIR=/var/lib/apphost-coldbackup

log() { echo "coldbackup[$DATASTORE]: $*"; logger -t apphost-coldbackup "$*"; }

mkdir -p "$STATE_DIR"

# --- 1. Einhängen -----------------------------------------------------------
log "hänge Datastore ein"
if ! proxmox-backup-manager datastore mount "$DATASTORE"; then
    log "FEHLER: Einhängen fehlgeschlagen – Platte oder Datastore prüfen."
    exit 1
fi
MOUNT_TS=$(date +%s)

# Ab hier IMMER aushängen, auch bei Abbruch. Eine Platte, die eingehängt
# liegenbleibt, wird beim Abziehen beschädigt – und man merkt es erst, wenn man
# das Backup braucht.
cleanup() {
    log "hänge Datastore aus"
    proxmox-backup-manager datastore unmount "$DATASTORE" \
        || log "WARNUNG: Aushängen fehlgeschlagen – NICHT abziehen, von Hand prüfen!"
}
trap cleanup EXIT INT TERM

# --- 2. VM-Abbild -----------------------------------------------------------
# Nur die Systemplatte; /mnt/media ist eine durchgereichte physische Platte und
# von vzdump ohnehin nicht erfassbar – die sichert die VM selbst dateibasiert.
log "vzdump VM $VMID"
if vzdump "$VMID" --storage "$DATASTORE" --mode snapshot --notes-template '{{guestname}} kalt'; then
    log "vzdump fertig"
else
    log "WARNUNG: vzdump fehlgeschlagen – Medien-Backup läuft trotzdem weiter"
fi

# --- 3. Auf das Medien-Backup der VM warten ---------------------------------
# Erkennungsmerkmal: ein Snapshot der Gruppe host/apphost, der NACH dem
# Einhängen entstanden ist. Rein lokale Abfrage, kein Kontakt zur VM.
log "warte auf das Medien-Backup der VM (max. $((WAIT_MAX / 3600)) h)"
seen=false
last_activity=$MOUNT_TS
while :; do
    now=$(date +%s)

    newest="$(proxmox-backup-manager snapshot list "$DATASTORE" --output-format json 2>/dev/null \
              | jq -r '[.[] | select(."backup-type"=="host" and ."backup-id"=="apphost")
                         | ."backup-time"] | max // 0' 2>/dev/null || echo 0)"
    if [[ "${newest:-0}" -gt "$MOUNT_TS" ]]; then
        if [[ "$seen" != true ]]; then log "Medien-Snapshot da"; seen=true; fi
        last_activity="$newest"
    fi

    running="$(proxmox-backup-manager task list --output-format json 2>/dev/null \
               | jq -r '[.[] | select(.status=="running")] | length' 2>/dev/null || echo 0)"
    [[ "${running:-0}" -gt 0 ]] && last_activity=$now

    if [[ "$seen" == true && $((now - last_activity)) -ge "$IDLE_AFTER" ]]; then
        log "seit $((IDLE_AFTER / 60)) min keine Aktivität – weiter mit dem Aufräumen"
        break
    fi
    if [[ $((now - MOUNT_TS)) -ge "$WAIT_MAX" ]]; then
        log "WARNUNG: Zeitlimit erreicht, ohne dass die VM fertig wurde – räume trotzdem auf"
        break
    fi
    sleep 60
done

# --- 4. Aufräumen -----------------------------------------------------------
# Reihenfolge ist wichtig: prune markiert nur, verify prüft, GC gibt frei.
# Bei 14-Tage-Rhythmus im Wechsel sieht jede Platte alle 4 Wochen einen Lauf.
log "prune"
proxmox-backup-manager prune-job list >/dev/null 2>&1  # existiert die Job-Verwaltung?
proxmox-backup-client prune host/apphost \
    --repository "localhost:$DATASTORE" \
    --keep-last 6 --keep-monthly 12 --keep-yearly 2 \
    || log "WARNUNG: prune fehlgeschlagen"

# Stichprobe statt Vollprüfung: ein kompletter verify liest die ganze Platte und
# dauert bei 1,5 TB Stunden, die die Platte zusätzlich am Netz hängt.
log "verify (nur was älter als 30 Tage ungeprüft ist)"
proxmox-backup-manager verify "$DATASTORE" --outdated-after 30 \
    || log "WARNUNG: verify fehlgeschlagen"

# GC liest den kompletten Chunk-Bestand – teuer. Nur wenn wirklich fällig,
# sonst hängt die Platte jedes Mal Stunden länger als nötig.
GC_STAMP="$STATE_DIR/last-gc-$DATASTORE"
last_gc=$(cat "$GC_STAMP" 2>/dev/null || echo 0)
if [[ $(( ($(date +%s) - last_gc) / 86400 )) -ge "$GC_INTERVAL_DAYS" ]]; then
    log "garbage-collect (letzte vor $(( ($(date +%s) - last_gc) / 86400 )) Tagen)"
    if proxmox-backup-manager garbage-collection start "$DATASTORE"; then
        date +%s > "$GC_STAMP"
    else
        log "WARNUNG: garbage-collection fehlgeschlagen"
    fi
else
    log "garbage-collect noch nicht fällig – übersprungen"
fi

log "fertig"
# cleanup() hängt aus (trap)
