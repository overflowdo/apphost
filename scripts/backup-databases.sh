#!/usr/bin/env bash
# Erzeugt ANWENDUNGSKONSISTENTE Datenbank-Dumps nach /var/backups/apphost.
#
# Warum das nötig ist: die Sicherung des Stacks sind Proxmox-VM-Snapshots
# (Installationsanleitung, Kapitel "Proxmox-Backups"). Die sind crash-konsistent
# – sie halten den Zustand der Blockgeräte fest, nicht den der Anwendungen. Für
# Postgres (Immich) und die SQLite-Datenbanken (Authelia, Grafana, Vaultwarden,
# Paperless) heißt das: der Snapshot kann eine Datei mitten in einer Transaktion
# erwischen, inklusive halb geschriebenem WAL. Beim Zurückspielen ist das im
# besten Fall eine Recovery, im schlechtesten eine korrupte Datei. Der
# Unterschied zwischen "Backup vorhanden" und "Backup wiederherstellbar".
#
# Dieses Skript legt vor dem Snapshot saubere Dumps ab, die dann als normale
# Dateien mitgesichert werden:
#   - Postgres: pg_dump im Container (transaktionskonsistent per Definition)
#   - SQLite:   .backup über die SQLite-Online-Backup-API. Die ist explizit für
#               laufende Datenbanken gedacht und kopiert eine in sich stimmige
#               Momentaufnahme, auch wenn parallel geschrieben wird. Ein simples
#               `cp` waere genau das nicht.
#
# Aufruf: sudo bash scripts/backup-databases.sh
# Automatisch: systemd-Timer apphost-db-backup (nixos/modules/backup.nix), 02:30.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/apphost}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"

[[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen (Zugriff auf die Docker-Volumes)." >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

fail=0
note() { echo "  $*"; }

# --- Postgres (Immich) ------------------------------------------------------
# pg_dump im Container: nutzt die Credentials aus dessen Umgebung, kein Passwort
# auf der Kommandozeile und damit nichts in der Prozessliste des Hosts.
if docker ps --format '{{.Names}}' | grep -qx immich-postgres; then
    out="$BACKUP_DIR/immich-postgres_${STAMP}.sql.gz"
    if docker exec immich-postgres \
         sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
         | gzip -9 > "$out"; then
        note "immich-postgres -> $(basename "$out") ($(du -h "$out" | cut -f1))"
    else
        echo "  ! pg_dump für immich-postgres fehlgeschlagen" >&2
        rm -f "$out"
        fail=1
    fi
else
    note "immich-postgres läuft nicht – übersprungen"
fi

# --- SQLite -----------------------------------------------------------------
# "<name>:<docker-volume>:<pfad-im-volume>"
SQLITE_DBS=(
    "authelia:apphost_authelia_data:db.sqlite3"
    "grafana:apphost_grafana_data:grafana.db"
    "vaultwarden:apphost_vaultwarden_data:db.sqlite3"
    "paperless:apphost_paperless_data:db.sqlite3"
)

for entry in "${SQLITE_DBS[@]}"; do
    IFS=':' read -r name volume relpath <<< "$entry"

    mountpoint="$(docker volume inspect -f '{{.Mountpoint}}' "$volume" 2>/dev/null || true)"
    if [[ -z "$mountpoint" ]]; then
        note "$name: Volume $volume nicht gefunden – übersprungen"
        continue
    fi

    src="$mountpoint/$relpath"
    if [[ ! -f "$src" ]]; then
        note "$name: $relpath (noch) nicht vorhanden – übersprungen"
        continue
    fi

    out="$BACKUP_DIR/${name}_${STAMP}.sqlite"
    # .backup statt cp: konsistente Kopie trotz laufender Schreiber.
    if sqlite3 "file:$src?mode=ro" ".backup '$out'"; then
        gzip -9f "$out"
        note "$name -> $(basename "$out").gz ($(du -h "$out.gz" | cut -f1))"
    else
        echo "  ! sqlite3 .backup für $name fehlgeschlagen" >&2
        rm -f "$out"
        fail=1
    fi
done

chmod 0600 "$BACKUP_DIR"/* 2>/dev/null || true

# --- Aufräumen --------------------------------------------------------------
deleted="$(find "$BACKUP_DIR" -maxdepth 1 -type f -mtime "+$KEEP_DAYS" -print -delete | wc -l)"
[[ "$deleted" -gt 0 ]] && note "$deleted Dump(s) älter als $KEEP_DAYS Tage entfernt"

echo "Dumps liegen in $BACKUP_DIR – sie werden vom Proxmox-Snapshot als normale Dateien mitgesichert."
exit "$fail"
