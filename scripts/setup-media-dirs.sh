#!/usr/bin/env bash
# Legt die Service-Unterordner auf der Bulk-Platte (/mnt/media) an und setzt die
# Besitzrechte passend zur userns-remap-Konfiguration (dockremap, siehe
# nixos/modules/docker.nix). Ohne das können die Container nicht in ihre
# gebindeten Verzeichnisse schreiben.
#
# EINMALIG ausführen: nachdem die 4-TB-Platte unter /mnt/media gemountet ist und
# bevor der Stack (neu) gestartet wird. Idempotent – erneutes Ausführen ist ok.
#
# Ownership-Logik (userns-remap verschiebt Container-UIDs um die dockremap-Basis):
#   - immich  : Container läuft als root            -> Host-Owner = Basis+0
#   - opencloud: Container läuft als root            -> Host-Owner = Basis+0
#   - paperless: Entrypoint chownt selbst auf UID 1000 (läuft als root an)
#                -> Host-Owner = Basis+0 genügt
#   - jellyfin : liest nur (read-only); befüllt wird von apphost
#                -> Owner apphost, world-readable
set -euo pipefail

MEDIA_ROOT="${MEDIA_DIR:-/mnt/media}"

if [[ $EUID -ne 0 ]]; then
    echo "Bitte mit sudo ausführen." >&2
    exit 1
fi

if ! mountpoint -q "$MEDIA_ROOT"; then
    echo "WARNUNG: $MEDIA_ROOT ist kein Mountpoint – ist die 4-TB-Platte gemountet?" >&2
    echo "         (Abbruch, sonst landet alles auf der SSD.)" >&2
    exit 1
fi

# dockremap-Basis aus /etc/subuid (userns-remap = "default" -> Nutzer dockremap).
REMAP_BASE="$(awk -F: '$1=="dockremap"{print $2}' /etc/subuid | head -1)"
if [[ -z "${REMAP_BASE:-}" ]]; then
    echo "FEHLER: dockremap nicht in /etc/subuid gefunden – ist userns-remap aktiv?" >&2
    exit 1
fi
echo "dockremap-Basis: $REMAP_BASE"

# Schreibende Dienste -> Owner = remapped root (Basis).
for svc in immich opencloud paperless; do
    dir="$MEDIA_ROOT/$svc"
    mkdir -p "$dir"
    chown "$REMAP_BASE:$REMAP_BASE" "$dir"
    chmod 0770 "$dir"
    echo "  $dir -> $REMAP_BASE:$REMAP_BASE (0770)"
done

# Jellyfin-Mediathek: apphost befüllt sie, Jellyfin liest nur (read-only).
JELLY="$MEDIA_ROOT/jellyfin"
mkdir -p "$JELLY"
chown apphost:users "$JELLY"
chmod 0755 "$JELLY"
echo "  $JELLY -> apphost:users (0755, read-only für Jellyfin)"

echo
echo "Fertig. Jetzt Stack starten:  cd /opt/monorepo && docker compose up -d"
echo
echo "Falls ein Dienst 'permission denied' auf sein Datenverzeichnis loggt, läuft"
echo "er als Nicht-root-UID N im Container. Dann für diesen Dienst:"
echo "  sudo chown \$(( $REMAP_BASE + N )):\$(( $REMAP_BASE + N )) $MEDIA_ROOT/<dienst>"
