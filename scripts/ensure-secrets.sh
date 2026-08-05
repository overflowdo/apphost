#!/usr/bin/env bash
# Stellt sicher, dass ALLE per Bind-Mount eingehängten Secret-Dateien existieren,
# BEVOR der Stack startet.
#
# Warum das wichtig ist: fehlt das Ziel eines Bind-Mounts, legt Docker dort ein
# VERZEICHNIS an. Der Container startet dann scheinbar, liest aber Unsinn –
# z.B. zeigt Alertmanagers basic_auth.password_file auf ein Verzeichnis und jede
# Benachrichtigung scheitert, oder Authelia findet keine Nutzerdatenbank. Ist das
# Verzeichnis einmal da, hilft auch ein späteres Erzeugen der Datei nicht mehr,
# ohne den Ordner von Hand zu löschen.
#
# Dieses Skript wird sowohl von scripts/stack-up.sh (Alias `up`) als auch vom
# Alias `up-all` aufgerufen. Vorher hing der Pre-flight nur in stack-up.sh und
# deckte 2 der 8 Secret-Mounts ab – `up-all` (docker compose up -d) lief komplett
# ohne Absicherung, und genau das ist der wahrscheinliche Weg für eine bestehende
# Installation, die ein Update zieht.
#
# Die Generatoren sind idempotent: Bestehendes bleibt unangetastet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Altlast aus einer früheren Installation melden: nixos/install.sh hat Werte
# einmal mit verdoppeltem $ ($$) in die .env geschrieben. Das ist nur für
# docker compose richtig – `source` in den update-secrets-*-Skripten macht aus
# $$ die Prozess-ID, liest also bei jedem Lauf ein anderes Passwort. Wer damit
# `regen-secrets` ausführt, bekommt einen Argon2-Hash zu einem Wert, den
# niemand kennt, und kommt nicht mehr ins SSO. Nur melden, nicht selbst
# umschreiben: welche Schreibweise gemeint war, weiß nur der Mensch davor.
if [[ -f .env ]] && grep -qE '^[[:space:]]*[A-Z_][A-Z0-9_]*=[^'"'"'"#]*\$\$' .env; then
    echo "  ! Hinweis: in der .env stehen Werte mit verdoppeltem \$ (\$\$):"
    grep -nE '^[[:space:]]*[A-Z_][A-Z0-9_]*=[^'"'"'"#]*\$\$' .env | cut -d= -f1 | sed 's/^/      Zeile /'
    echo "    Diese Schreibweise lesen 'docker compose' und 'source' unterschiedlich."
    echo "    Richtig ist der Wert in einfachen Anführungszeichen, also"
    echo "        KEY='Som\$merRegen'    statt    KEY=Som\$\$merRegen"
    echo "    Solange du sie nicht anfasst, laufen die Container weiter – aber"
    echo "    'regen-secrets' erzeugt daraus falsche Passwörter. Siehe .env.example."
    echo
fi

# Datenverzeichnisse auf der Bulk-Platte: gehören sie der falschen UID, startet
# der zugehörige Dienst nicht, sondern kreiselt.
#
# nixos/modules/media-dirs.nix legt sie beim Boot mit den richtigen Rechten an –
# aber nur, WENN /mnt/media gemountet ist; sonst überspringt die Unit still
# (bewusst: nofail, das System soll ohne Bulk-Platte booten). Ist sie
# übersprungen und startet danach ein Container, legt Docker die fehlende
# Bind-Quelle selbst an: als remapped root mit 0755. Der Dienst läuft dann als
# UID 1000 bzw. 2999 und darf dort nicht schreiben:
#   opencloud: Can't start JetStream: mkdir /var/lib/opencloud/nats:
#              permission denied
#   radicale:  [Errno 13] Permission denied: '/data/collections'
# Beide melden das als fatal, Docker startet sie neu, und das geht endlos so
# weiter. Von aussen sieht man nur zwei Container, die nicht hochkommen.
if [[ -d /mnt/media ]] && ! mountpoint -q /mnt/media 2>/dev/null; then
    echo "FEHLER: /mnt/media ist nicht gemountet." >&2
    cat >&2 <<'HINWEIS'
Damit landen Immich-Fotos, Paperless-Dokumente und OpenCloud-Dateien auf der
Systemplatte statt auf der Bulk-Platte – und zwar unbemerkt, weil die Dienste
einfach in das leere Verzeichnis schreiben. Der Mount ist in
nixos/modules/media-disk.nix deklariert (nofail), das System bootet also auch
ohne die Platte durch. Nachsehen:

  systemctl status mnt-media.mount --no-pager -l
  ls -l /dev/disk/by-id/ | grep -i scsi1     # ist die Platte durchgereicht?
  lsblk -f                                   # Dateisystem in Ordnung?

Fehlt das Gerät, hängt die Platte nicht (mehr) an scsi1 der VM – auf dem
Proxmox-Host mit `qm config <vmid>` prüfen.
HINWEIS
    exit 1
fi

if [[ -d /mnt/media ]]; then
    base="$(awk -F: '$1=="dockremap"{print $2}' /etc/subuid 2>/dev/null | head -1)"
    if [[ -n "${base:-}" ]]; then
        # "<dienst>:<erlaubte Offsets, durch Komma>" – Ableitung wie in
        # nixos/modules/media-dirs.nix. paperless darf BEIDES sein: die Unit
        # setzt Basis+0, der Entrypoint chownt beim ersten Start selbst auf
        # Container-UID 1000 (= Basis+1000). Beides ist ein gesunder Zustand.
        falsch=()
        for eintrag in "immich:0" "paperless:0,1000" "opencloud:1000" "radicale:2999"; do
            svc="${eintrag%%:*}"; offsets="${eintrag##*:}"
            dir="/mnt/media/$svc"
            [[ -d "$dir" ]] || continue
            ist="$(stat -c %u "$dir" 2>/dev/null || echo '?')"
            ok=0; erwartet=""
            for off in ${offsets//,/ }; do
                erwartet+="$((base + off)) "
                [[ "$ist" == "$((base + off))" ]] && ok=1
            done
            [[ "$ok" == 1 ]] || falsch+=("$dir: gehört $ist, erwartet ${erwartet% }")
        done
        if [[ ${#falsch[@]} -gt 0 ]]; then
            echo "FEHLER: Datenverzeichnisse mit falschem Eigentümer:" >&2
            printf '  %s\n' "${falsch[@]}" >&2
            cat >&2 <<'HINWEIS'
Betroffene Dienste kreiseln damit beim Start (OpenCloud: JetStream-Store,
Radicale: /data/collections). Richten:

  sudo systemctl restart apphost-media-dirs.service
  ls -land /mnt/media/*
  up
HINWEIS
            exit 1
        fi
    fi
fi

# Dieselbe Falle wie unten, aber auf HOST-Seite: Dateien aus /var/lib, die per
# Bind-Mount in Container gehen. Existiert die Datei beim Erzeugen des
# Containers nicht, legt Docker dort ein VERZEICHNIS an – und zwar auf dem
# Host, wo es dann liegen bleibt.
#
# Passiert ist das mit /var/lib/apphost-ca/ca-bundle.crt. Folge: grafana,
# paperless und collaboration bekamen ein Verzeichnis als Zertifikatsbündel
# untergeschoben. Der einzige Hinweis war eine Warnung im Minutentakt
#   tls: failed to verify certificate: x509: certificate signed by unknown
#   authority
# Kein Container stirbt daran, es funktioniert nur die TLS-Prüfung nicht mehr –
# also genau die Sorte Fehler, die monatelang übersehen wird.
#
# Diese Dateien erzeugt nixos/modules/local-ca.nix, nicht ein Skript hier;
# deshalb nur melden und abbrechen statt selbst reparieren.
CA_FILES=(
    /var/lib/apphost-ca/ca-bundle.crt
    /var/lib/apphost-ca/local-ca.crt
)
ca_kaputt=()
for f in "${CA_FILES[@]}"; do
    [[ -d "$f" ]] && ca_kaputt+=("$f")
done
if [[ ${#ca_kaputt[@]} -gt 0 ]]; then
    echo "FEHLER: Docker hat aus diesen CA-Dateien Verzeichnisse gemacht:" >&2
    printf '  %s\n' "${ca_kaputt[@]}" >&2
    cat >&2 <<'HINWEIS'
Betroffene Container prüfen TLS damit nicht mehr (Grafana, Paperless,
collaboration). So geradeziehen:

  docker compose stop grafana paperless collaboration
  sudo rmdir /var/lib/apphost-ca/ca-bundle.crt /var/lib/apphost-ca/local-ca.crt 2>/dev/null
  sudo systemctl restart apphost-local-ca.service
  ls -l /var/lib/apphost-ca/          # müssen jetzt Dateien sein
  docker compose rm -sf grafana paperless collaboration
  up
HINWEIS
    exit 1
fi

# "<datei>:<generator>" – alle Dateien, die in compose/**/*.yml per Bind-Mount
# eingehängt werden. Neue secret-basierte Dienste hier ergänzen.
SECRETS=(
    "secrets/authelia.env:update-secrets-authelia.sh"
    "secrets/authelia_oidc_jwks.pem:update-secrets-authelia.sh"
    "secrets/authelia_users.yml:update-secrets-authelia.sh"
    "secrets/oidc-grafana.env:update-secrets-authelia.sh"
    "secrets/oidc-paperless.env:update-secrets-authelia.sh"
    "secrets/ntfy.env:update-secrets-ntfy.sh"
    "secrets/alertmanager_ntfy_password:update-secrets-ntfy.sh"
    "secrets/radicale_users:update-secrets-radicale.sh"
)

missing_generators=()
blocked=()

for entry in "${SECRETS[@]}"; do
    file="${entry%%:*}"
    generator="${entry##*:}"

    # Der Klassiker: Docker hat aus dem fehlenden Mount-Ziel ein Verzeichnis
    # gemacht. Das muss weg, sonst schreibt der Generator daneben.
    if [[ -d "$file" ]]; then
        if rmdir "$file" 2>/dev/null; then
            echo "  ! $file war ein (leeres) Verzeichnis – entfernt."
        else
            blocked+=("$file")
            continue
        fi
    fi

    if [[ ! -f "$file" ]]; then
        missing_generators+=("$generator")
    fi
done

if [[ ${#blocked[@]} -gt 0 ]]; then
    echo "FEHLER: folgende Pfade sind nicht-leere Verzeichnisse, wo eine Datei hingehört:" >&2
    printf '  %s\n' "${blocked[@]}" >&2
    echo "Bitte prüfen und von Hand entfernen, dann erneut starten." >&2
    exit 1
fi

if [[ ${#missing_generators[@]} -eq 0 ]]; then
    exit 0
fi

# Generatoren deduplizieren und der Reihe nach ausführen.
for generator in $(printf '%s\n' "${missing_generators[@]}" | sort -u); do
    echo "==> Pre-flight: Secrets fehlen -> scripts/$generator"
    bash "scripts/$generator"
    echo
done

# Nachkontrolle: hat wirklich alles geklappt?
still_missing=()
for entry in "${SECRETS[@]}"; do
    file="${entry%%:*}"
    [[ -f "$file" ]] || still_missing+=("$file")
done

if [[ ${#still_missing[@]} -gt 0 ]]; then
    echo "WARNUNG: diese Secret-Dateien fehlen weiterhin:" >&2
    printf '  %s\n' "${still_missing[@]}" >&2
    echo "Die betroffenen Container werden mit einem Verzeichnis statt einer Datei starten." >&2
    exit 1
fi
