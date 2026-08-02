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
#               `cp` wäre genau das nicht.
#
# Aufruf: sudo bash scripts/backup-databases.sh
# Automatisch: systemd-Timer apphost-db-backup (nixos/modules/backup.nix), 02:30.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKUP_DIR="${BACKUP_DIR:-/var/backups/apphost}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"

# BACKUP_AGE_RECIPIENT aus der .env holen (optional, siehe unten). Bewusst
# gezielt EINE Variable statt die ganze .env zu sourcen – hier laufen sonst
# sämtliche Passwörter des Stacks durch die Umgebung eines root-Prozesses.
if [[ -z "${BACKUP_AGE_RECIPIENT:-}" && -f "$ROOT_DIR/.env" ]]; then
    BACKUP_AGE_RECIPIENT="$( { grep -m1 '^[[:space:]]*BACKUP_AGE_RECIPIENT=' "$ROOT_DIR/.env" || true; } \
                             | cut -d= -f2- | tr -d "\"' \r")"
fi

[[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen (Zugriff auf die Docker-Volumes)." >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

fail=0
note() { echo "  $*"; }

# --- Postgres (Immich) ------------------------------------------------------
# pg_dumpall statt pg_dump: so empfiehlt es Immich selbst für sein Image, weil
# damit auch Rollen und Datenbank-übergreifende Objekte mitkommen (relevant für
# die vectorchord-/pgvector-Extensions). Läuft im Container, nutzt die
# Credentials aus dessen Umgebung – kein Passwort auf der Kommandozeile und
# damit nichts in der Prozessliste des Hosts.
if docker ps --format '{{.Names}}' | grep -qx immich-postgres; then
    out="$BACKUP_DIR/immich-postgres_${STAMP}.sql.gz"
    if docker exec immich-postgres \
         sh -c 'pg_dumpall -U "$POSTGRES_USER" --clean --if-exists' \
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
    #
    # Bewusst OHNE ?mode=ro: eine Datenbank im WAL-Modus lässt sich nicht
    # zuverlässig read-only öffnen. SQLite braucht dafür die -shm-Datei, und
    # mit mode=ro darf es sie nicht anlegen – existiert sie gerade nicht (kein
    # Schreiber angehängt) und ist das -wal nicht leer, scheitert der Aufruf
    # mit "unable to open database file". Vaultwarden fährt per Default mit
    # ENABLE_DB_WAL=true, ist also genau der Kandidat dafür. Das Skript läuft
    # als root, und die Online-Backup-API nimmt nur einen Shared Lock: die
    # Quelle wird nicht verändert. (?immutable=1 wäre die echte read-only
    # Variante, ist bei laufenden Schreibern aber gerade NICHT sicher.)
    if ! sqlite3 "$src" ".backup '$out'"; then
        echo "  ! sqlite3 .backup für $name fehlgeschlagen" >&2
        rm -f "$out"
        fail=1
        continue
    fi

    # Den erzeugten Dump gegenprüfen – ein unbrauchbares Backup soll hier
    # auffallen und nicht erst beim Restore.
    if ! sqlite3 "$out" "PRAGMA quick_check;" | grep -qx ok; then
        echo "  ! Dump von $name besteht PRAGMA quick_check nicht" >&2
        rm -f "$out"
        fail=1
        continue
    fi

    gzip -9f "$out"
    note "$name -> $(basename "$out").gz ($(du -h "$out.gz" | cut -f1))"
done

# --- Optionale Verschlüsselung ---------------------------------------------
# Auf der Platte reichen 0700/0600 zusammen mit der LUKS-Verschlüsselung des
# Roots. Verlässt ein Backup aber das Haus (Proxmox-Storage auf einem NAS,
# Kopie in die Cloud), braucht es eine eigene: die Paperless-DB enthält alle
# Dokument-Metadaten im Klartext, und die Schlüssel für die verschlüsselten
# Teile (AUTHELIA_STORAGE_ENCRYPTION_KEY, GF_SECURITY_SECRET_KEY) liegen in
# derselben .env auf derselben Platte.
# Setze BACKUP_AGE_RECIPIENT (age-Public-Key, z.B. age1ql3z...) in der .env,
# dann wird jeder Dump zusaetzlich mit age verschlüsselt und das Klartext-
# Original entfernt. Entschlüsseln: age -d -i <key> <datei>.age
if [[ -n "${BACKUP_AGE_RECIPIENT:-}" ]]; then
    for f in "$BACKUP_DIR"/*_"${STAMP}"*; do
        [[ -f "$f" && "$f" != *.age ]] || continue
        if age -r "$BACKUP_AGE_RECIPIENT" -o "$f.age" "$f"; then
            rm -f "$f"
            note "verschlüsselt -> $(basename "$f").age"
        else
            echo "  ! age-Verschlüsselung von $(basename "$f") fehlgeschlagen" >&2
            fail=1
        fi
    done
fi

chmod 0600 "$BACKUP_DIR"/* 2>/dev/null || true

# --- Aufräumen --------------------------------------------------------------
deleted="$(find "$BACKUP_DIR" -maxdepth 1 -type f -mtime "+$KEEP_DAYS" -print -delete | wc -l)"
[[ "$deleted" -gt 0 ]] && note "$deleted Dump(s) älter als $KEEP_DAYS Tage entfernt"

# --- Nicht abgedeckt --------------------------------------------------------
# OpenCloud hält seine Metadaten in einem eingebetteten NATS/JetStream-KV-Store,
# nicht in einer Datenbank, die sich von außen konsistent dumpen ließe. Dort
# bleibt es beim crash-konsistenten Snapshot. Wer das sauber will, muss den
# Dienst für den Snapshot kurz stoppen (docker compose stop opencloud).
#
# UND: ein Backup ist erst dann eines, wenn der Restore einmal durchgespielt
# wurde. Für den Immich-Dump gilt das besonders – er setzt voraus, dass
# POSTGRES_USER=immich im Image tatsaechlich Superuser ist. Einmal in eine
# Wegwerf-VM zurückspielen, bevor man sich darauf verlässt.
echo "Dumps liegen in $BACKUP_DIR – sie werden vom Proxmox-Snapshot als normale Dateien mitgesichert."
exit "$fail"
