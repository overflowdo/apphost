# Legt die Bind-Mount-Zielordner unter /mnt/media DEKLARATIV an und setzt die
# Besitzrechte passend zur userns-remap-Konfiguration – automatisch beim Boot,
# als root, VOR docker.service. Ersetzt das manuelle `sudo bash
# scripts/setup-media-dirs.sh` (das bleibt als Handbetrieb/Debug erhalten).
#
# Warum als root-oneshot: der chown auf die remapped Container-UIDs (Basis+N)
# darf nur root. `up` läuft als apphost und kann das nicht – deshalb hier
# deklarativ, damit die Ordner immer bereitstehen und kein Dienst wegen falscher
# Ownership crash-loopt (die "nobody"-Falle: ein von Docker frisch als Host-root
# angelegtes Verzeichnis erscheint im userns als "nobody").
#
# Ownership-Logik (Container-UID + dockremap-Basis, Standard 100000 – muss zu
# modules/docker.nix passen):
#   immich, paperless -> Basis+0     (Container laufen als root)
#   opencloud         -> Basis+1000  (Container-UID 1000; sonst kein JetStream-Store)
#   radicale          -> Basis+2999  (Dienst-UID 2999; Container macht chown -R /data)
#   jellyfin          -> apphost:users, read-only (apphost befüllt, Container liest)
{ pkgs, ... }:
{
  systemd.services.apphost-media-dirs = {
    description = "Create/own /mnt/media service dirs for userns-remapped containers";
    wantedBy = [ "multi-user.target" ];
    # Nach dem Mount der Bulk-Platte, aber VOR Docker (Container brauchen die Ordner).
    after    = [ "mnt-media.mount" ];
    wants    = [ "mnt-media.mount" ];
    before   = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils pkgs.util-linux pkgs.gawk ];
    script = ''
      set -euo pipefail
      MEDIA=/mnt/media

      # nofail-Mount: ist die Platte nicht da, sauber überspringen statt zu failen.
      if ! mountpoint -q "$MEDIA"; then
        echo "media-dirs: $MEDIA nicht gemountet -> übersprungen"
        exit 0
      fi

      # dockremap-Basis aus /etc/subuid (userns-remap "default"), Fallback 100000.
      BASE="$(awk -F: '$1=="dockremap"{print $2}' /etc/subuid 2>/dev/null | head -1)"
      BASE="''${BASE:-100000}"

      own() {  # <dir> <uid=gid> <mode>
        mkdir -p "$1"
        chown "$2:$2" "$1"
        chmod "$3" "$1"
        echo "  $1 -> $2:$2 ($3)"
      }

      # Container laufen als root -> Owner = Basis+0
      own "$MEDIA/immich"    "$BASE"            0770
      own "$MEDIA/paperless" "$BASE"            0770
      # OpenCloud läuft als Container-UID 1000 -> Basis+1000
      own "$MEDIA/opencloud" "$((BASE + 1000))" 0770
      # Radicale-Dienst-UID 2999 -> Basis+2999
      own "$MEDIA/radicale"  "$((BASE + 2999))" 0770

      # Jellyfin-Mediathek: apphost befüllt sie, Jellyfin liest nur (read-only).
      mkdir -p "$MEDIA/jellyfin"
      chown apphost:users "$MEDIA/jellyfin"
      chmod 0755 "$MEDIA/jellyfin"
      echo "  $MEDIA/jellyfin -> apphost:users (0755, read-only für Jellyfin)"
    '';
  };
}
