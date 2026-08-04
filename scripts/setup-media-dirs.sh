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
#   - opencloud: Container läuft als UID 1000        -> Host-Owner = Basis+1000
#                (opencloudeu/opencloud-rolling läuft NICHT als root; als Basis+0
#                 hätte der Prozess bei 0770 keinerlei Zugriff -> NATS/JetStream
#                 kann seinen Store nicht anlegen und OpenCloud crash-loopt)
#   - paperless: Entrypoint chownt selbst auf UID 1000 (läuft als root an)
#                -> Host-Owner = Basis+0 genügt
#   - jellyfin : liest nur (read-only); befüllt wird von apphost
#                -> Owner apphost, world-readable
set -euo pipefail

# Fest /mnt/media: der Pfad steht in den Compose-Dateien und in
# nixos/modules/media-disk.nix ohnehin fest, MEDIA_DIR wirkte nur hier und in
# Jellyfin und war damit eine Falle (siehe .env.example).
MEDIA_ROOT="/mnt/media"

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

# Dienste, die im Container als root starten -> Owner = remapped root (Basis).
#   immich   : Prozess bleibt root
#   paperless: startet als root, chownt intern selbst auf UID 1000
for svc in immich paperless; do
    dir="$MEDIA_ROOT/$svc"
    mkdir -p "$dir"
    chown "$REMAP_BASE:$REMAP_BASE" "$dir"
    chmod 0770 "$dir"
    echo "  $dir -> $REMAP_BASE:$REMAP_BASE (0770)"
done

# OpenCloud läuft als Container-UID 1000 (nicht root) -> Host-UID = Basis+1000.
# Owner Basis+0 würde dem Prozess bei 0770 jeden Zugriff verweigern, der
# eingebettete NATS/JetStream könnte seinen Store nicht anlegen ("storage
# directory is not a directory") und OpenCloud crash-loopt.
oc_dir="$MEDIA_ROOT/opencloud"
oc_uid="$((REMAP_BASE + 1000))"
mkdir -p "$oc_dir"
chown "$oc_uid:$oc_uid" "$oc_dir"
chmod 0770 "$oc_dir"
echo "  $oc_dir -> $oc_uid:$oc_uid (0770)"

# Radicale (Kalender/Kontakte) läuft im Container als root, der Dienst selbst als
# UID 2999. Der Container macht beim Start `chown -R radicale /data`; ein frisches
# Named Volume gehört Host-root(0) und ist im userns "nobody" -> chown scheitert
# (EPERM, Crashloop). Über diesen vorab auf Basis+2999 gesetzten Bind-Ordner wird
# der chown ein No-op und läuft durch. (Daten sind winzig; liegen der Konsistenz
# halber neben den übrigen Diensten auf /mnt/media.)
rad_dir="$MEDIA_ROOT/radicale"
rad_uid="$((REMAP_BASE + 2999))"
mkdir -p "$rad_dir"
chown "$rad_uid:$rad_uid" "$rad_dir"
chmod 0770 "$rad_dir"
echo "  $rad_dir -> $rad_uid:$rad_uid (0770)"

# Jellyfin-Mediathek: apphost befüllt sie, Jellyfin liest nur (read-only).
JELLY="$MEDIA_ROOT/jellyfin"
mkdir -p "$JELLY"
chown apphost:users "$JELLY"
chmod 0755 "$JELLY"
echo "  $JELLY -> apphost:users (0755, read-only für Jellyfin)"

echo
# Gestaffelt starten (Alias `up`), nicht `docker compose up -d`: beim
# gleichzeitigen Erststart schreiben Immich, OpenCloud und Paperless zusammen
# auf die USB-Platte und spiken den RAM - das hatte Host und VM gecrasht.
echo "Fertig. Jetzt Stack starten:  cd /opt/monorepo && bash scripts/stack-up.sh   (Alias: up)"
echo
echo "Falls ein Dienst 'permission denied' auf sein Datenverzeichnis loggt, läuft"
echo "er als Nicht-root-UID N im Container. Dann für diesen Dienst:"
echo "  sudo chown \$(( $REMAP_BASE + N )):\$(( $REMAP_BASE + N )) $MEDIA_ROOT/<dienst>"
