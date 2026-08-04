#!/usr/bin/env bash
# Richtet die VM-Seite des kalten Backups ein und prüft die ganze Kette.
#
#   backup-setup           einrichten (fragt nur, was fehlt) und danach prüfen
#   backup-setup --check   nur prüfen, nichts anlegen und nichts fragen
#
# Warum es das gibt: Nach dem Einspielen dieser Änderungen ist genau EIN Schritt
# nicht automatisierbar – die Zugangsdaten zum Proxmox Backup Server. Die kommen
# von der anderen Maschine und können nicht im Repo liegen. Alles andere
# (Verzeichnisse, Rechte, Timer, Knopf, Dashboard) erledigt `rebuild` bzw. `up`.
# Ohne dieses Skript wäre das ein Abschnitt in der Anleitung, den man abtippt
# und dabei falsch macht; so ist es ein Befehl, der am Ende sagt, ob es läuft.
#
# Idempotent: Vorhandenes bleibt unangetastet. Gefahrlos jederzeit erneut
# ausführbar – auch nur als Prüfung.
set -uo pipefail

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$ROOT_DIR/secrets/pbs.env"
KEYFILE="$ROOT_DIR/secrets/pbs-encryption.key"
STATE_DIR=/var/lib/apphost-backup/state
WEB_DIR=/var/lib/apphost-backup/web
TEXTFILE=/var/lib/node-exporter/textfile

G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' B='\033[0;34m' N='\033[0m'
ok()   { echo -e "  ${G}✔${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; PROBLEMS=$((PROBLEMS + 1)); }
bad()  { echo -e "  ${R}✖${N} $*"; PROBLEMS=$((PROBLEMS + 1)); }
head_() { echo; echo -e "${B}$*${N}"; }
PROBLEMS=0

# ---------------------------------------------------------------------------
# 1. Zugangsdaten
# ---------------------------------------------------------------------------
head_ "1. Zugang zum Proxmox Backup Server"

if [[ -f "$CONF" ]]; then
    ok "$CONF vorhanden"
elif [[ "$CHECK_ONLY" == true ]]; then
    bad "$CONF fehlt – 'backup-setup' ohne --check ausführen"
else
    echo "  Die Werte stammen aus der Einrichtung auf dem Proxmox-Host,"
    echo "  siehe proxmox/README.md Schritt 4."
    echo
    read -rp "  IP des Proxmox-Hosts: " new_host
    read -rp "  Token-ID [apphost@pbs!backup]: " new_token
    new_token="${new_token:-apphost@pbs!backup}"
    read -rsp "  Token-Secret: " new_secret; echo
    read -rp "  Fingerabdruck des PBS-Zertifikats (leer = überspringen): " new_fp
    read -rp "  Datastores [cold-a cold-b]: " new_ds
    new_ds="${new_ds:-cold-a cold-b}"

    if [[ -z "$new_host" || -z "$new_secret" ]]; then
        bad "Host und Secret sind Pflicht – abgebrochen, nichts geschrieben."
        exit 1
    fi

    mkdir -p "$(dirname "$CONF")"
    umask 077
    cat > "$CONF" <<EOF
# Von scripts/backup-setup.sh angelegt. Zugang zum Proxmox Backup Server.
# Das Token darf ausschliesslich Snapshots anlegen und lesen
# (Datastore.Backup + Datastore.Audit) - nicht loeschen, nicht prunen.
PBS_HOST='${new_host}'
PBS_TOKEN='${new_token}'
PBS_SECRET='${new_secret}'
PBS_FINGERPRINT='${new_fp}'
PBS_DATASTORES='${new_ds}'
EOF
    chmod 600 "$CONF"
    ok "$CONF angelegt (0600)"
fi

# ---------------------------------------------------------------------------
# 2. Verschlüsselungsschlüssel
# ---------------------------------------------------------------------------
head_ "2. Verschlüsselungsschlüssel"

if [[ -f "$KEYFILE" ]]; then
    ok "$KEYFILE vorhanden"
elif [[ "$CHECK_ONLY" == true ]]; then
    warn "$KEYFILE fehlt – es würde UNVERSCHLÜSSELT gesichert"
elif ! command -v proxmox-backup-client >/dev/null 2>&1; then
    bad "proxmox-backup-client nicht gefunden – erst 'rebuild' ausführen"
else
    # --kdf none: ohne Passphrase, sonst könnte kein automatischer Lauf den
    # Schlüssel benutzen. Der Schutz liegt darin, dass die Datei 0600 in einem
    # 0700-Verzeichnis auf einer LUKS-verschlüsselten Platte liegt.
    if proxmox-backup-client key create "$KEYFILE" --kdf none; then
        chmod 600 "$KEYFILE"
        ok "Schlüssel erzeugt"
        echo
        echo -e "${Y}  ══════════════════════════════════════════════════════════${N}"
        echo -e "${Y}  JETZT AUSDRUCKEN. Ohne diesen Schlüssel ist jedes Backup${N}"
        echo -e "${Y}  Zufallsrauschen – auch für dich.${N}"
        echo -e "${Y}  Nicht (nur) in Vaultwarden ablegen: Vaultwarden ist genau${N}"
        echo -e "${Y}  das, was du damit wiederherstellst.${N}"
        echo -e "${Y}  ══════════════════════════════════════════════════════════${N}"
        echo
        proxmox-backup-client key paperkey "$KEYFILE" || true
        echo
        read -rp "  Weggelegt? [Enter] "
    else
        bad "Schlüssel konnte nicht erzeugt werden"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Was `rebuild` und `up` gebaut haben sollten
# ---------------------------------------------------------------------------
head_ "3. Systemseite (kommt aus rebuild / up)"

for d in "$STATE_DIR" "$WEB_DIR" "$TEXTFILE"; do
    if [[ -d "$d" ]]; then ok "$d"; else bad "$d fehlt – 'rebuild' ausführen"; fi
done

# Der Knopf schreibt als Container-UID 101, auf dem Host also REMAP_BASE+101.
# Stimmt die Ownership nicht, klickt man ins Leere und merkt es nie.
HOOK="$WEB_DIR/hook"
if [[ -d "$HOOK" ]]; then
    base="$(awk -F: '$1=="dockremap"{print $2}' /etc/subuid 2>/dev/null | head -1)"
    if [[ -n "$base" ]]; then
        want=$((base + 101)); have="$(stat -c '%u' "$HOOK")"
        if [[ "$have" == "$want" ]]; then
            ok "Knopf-Verzeichnis gehört $want"
        else
            bad "$HOOK gehört $have, erwartet $want – 'rebuild' ausführen"
        fi
    else
        warn "dockremap nicht in /etc/subuid – userns-remap aktiv?"
    fi
else
    bad "$HOOK fehlt – 'rebuild' ausführen"
fi

for u in apphost-media-backup.timer apphost-media-backup-trigger.path; do
    if systemctl is-enabled --quiet "$u" 2>/dev/null; then
        ok "$u aktiv"
    else
        bad "$u nicht aktiv – 'rebuild' ausführen"
    fi
done

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx backup-trigger; then
    ok "Container backup-trigger läuft"
else
    warn "Container backup-trigger läuft nicht – 'up' ausführen"
fi

# ---------------------------------------------------------------------------
# 4. Verbindungstest
# ---------------------------------------------------------------------------
head_ "4. Verbindung zum PBS"

if [[ ! -f "$CONF" ]]; then
    warn "ohne $CONF kein Test möglich"
elif ! command -v proxmox-backup-client >/dev/null 2>&1; then
    bad "proxmox-backup-client nicht gefunden – 'rebuild' ausführen"
else
    # shellcheck source=/dev/null
    source "$CONF"
    export PBS_PASSWORD="${PBS_SECRET:-}"
    [[ -n "${PBS_FINGERPRINT:-}" ]] && export PBS_FINGERPRINT
    reachable=0
    for ds in ${PBS_DATASTORES:-}; do
        if proxmox-backup-client status \
             --repository "${PBS_TOKEN}@${PBS_HOST}:${ds}" >/dev/null 2>&1; then
            ok "$ds erreichbar (Platte steckt)"
            reachable=$((reachable + 1))
        else
            # Das ist der NORMALFALL: die Platten liegen im Schrank. Nur wenn
            # KEINE der beiden antwortet UND auch keine steckt, ist das eine
            # offene Frage – deshalb hier kein Fehler.
            echo "    · $ds nicht erreichbar (Platte abgezogen – normal)"
        fi
    done
    if [[ "$reachable" -eq 0 ]]; then
        echo
        echo "  Keine Platte angesteckt. Zum echten Test eine anstecken und"
        echo "  'backup-setup --check' erneut ausführen – dann muss mindestens"
        echo "  ein Datastore erreichbar sein. Antwortet dort auch mit"
        echo "  angesteckter Platte keiner, stimmen Token, Fingerabdruck oder"
        echo "  die Einrichtung auf dem Host nicht (proxmox/README.md)."
    fi
fi

# ---------------------------------------------------------------------------
# 5. Bisherige Läufe
# ---------------------------------------------------------------------------
head_ "5. Bisherige Sicherungen"

if [[ -f "$WEB_DIR/status.json" ]]; then
    cat "$WEB_DIR/status.json"
else
    echo "  noch nie gelaufen"
fi

# ---------------------------------------------------------------------------
head_ "Ergebnis"
if [[ "$PROBLEMS" -eq 0 ]]; then
    ok "VM-Seite vollständig."
    echo
    echo "  Bleibt manuell (einmalig, auf dem PROXMOX-HOST – andere Maschine,"
    echo "  vom Repo aus nicht erreichbar): PBS installieren, Platten als ext4"
    echo "  formatieren, Datastores cold-a/cold-b anlegen, Skript + udev-Regel"
    echo "  installieren. Schritt für Schritt: proxmox/README.md"
    echo
    echo "  Danach: Platte anstecken, warten oder auf https://backup.<domain>"
    echo "  den Knopf drücken. Status: 'backup-status' oder das Grafana-"
    echo "  Dashboard 'AppHost – Backup'."
else
    warn "$PROBLEMS Punkt(e) offen – siehe oben."
fi
echo
exit 0
