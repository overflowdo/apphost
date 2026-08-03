#!/usr/bin/env bash
#
# Unbeaufsichtigter Lauf (z.B. für Tests): die beiden interaktiven Abfragen
# lassen sich über Umgebungsvariablen vorbelegen –
#
#   APPHOST_PASSWORD_HASH   crypt(3)-Hash für den apphost-Nutzer (mkpasswd -m sha-512)
#   APPHOST_SSH_PUBKEY      SSH Public Key für den apphost-Nutzer
#   APPHOST_DISK_ENCRYPTION "true"/"false" – überspringt die LUKS-Abfrage
#
# Vorher wurden dafür die Positionsargumente $3 und $4 gelesen ($1/$2 gab es
# nie). Ein Passwort-Hash in argv ist zudem für jeden auf dem System via `ps`
# sichtbar – Umgebungsvariablen sind hier das kleinere Übel und passen zu dem,
# was das Skript beim Python-Schritt weiter unten ohnehin schon macht.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")
APP_DIR=/mnt/opt/monorepo

# Ein bisschen Farbe tut dem ganzen ja nicht weh. 
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' N='\033[0m'
info()  { echo -e "${G}▶${N}  $*"; }
warn()  { echo -e "${Y}⚠${N}  $*"; }
err()   { echo -e "${R}✖${N}  $*" >&2; exit 1; }

# Vorbedingungen
[[ $EUID -ne 0 ]] && err "Bitte als root ausführen: sudo bash nixos/install.sh"
[[ -f "$REPO_DIR/flake.nix" ]] || err "Kein Repo-Root gefunden (flake.nix fehlt in $REPO_DIR)"

cd "$REPO_DIR"

echo ""
echo "  Repo:    $REPO_DIR"
echo "  Dieses Skript:"
echo "  - partitioniert eine Festplatte (GPT + EFI + Swap + Btrfs)"
echo "  - installiert NixOS mit der AppHost-Hochsicherheitskonfiguration"
echo "  - legt den AppHost-Stack unter /opt/monorepo bereit"
echo ""

echo ""
echo "  Bitte wählen Sie ein sicheres Passwort für Ihren Nutzer."
echo "  Dieses Passwort wird für 'sudo' benötigt (zweiter Faktor nach SSH-Key)."
echo ""

if [[ -n "${APPHOST_PASSWORD_HASH:-}" ]]; then
  HASHED_PASSWORD="$APPHOST_PASSWORD_HASH"
  info "APPHOST_PASSWORD_HASH gesetzt, überspringe die Abfrage."
else
  while true; do
    read -rsp "  Passwort: " PW1; echo ""
    read -rsp "  Passwort bestätigen: " PW2; echo ""
    [[ "$PW1" == "$PW2" ]] && break
    warn "Passwörter stimmen nicht überein. Bitte erneut eingeben."
  done
  HASHED_PASSWORD="$(printf '%s' "$PW1" | nix run "${NIX_FLAGS[@]}" nixpkgs#mkpasswd -- -m sha-512 -s)"
  unset PW1 PW2
fi

echo "Passwort-Hash erzeugt"

echo ""
warn "WARNUNG: ALLE DATEN auf der Festplatte werden UNWIDERRUFLICH GELÖSCHT!"
echo ""
read -rp "  Bitte 'ja' eingeben um fortzufahren: " CONFIRM
[[ "$CONFIRM" == "ja" ]] || { echo ""; info "Abgebrochen."; exit 0; }

info "Schreibe Passwort-Hash nach /mnt/etc/apphost-password-hash (außerhalb des Repos)..."
# Wird erst nach disko geschriebe. Merker für später:
APPHOST_PW_HASH="$HASHED_PASSWORD"

# hardware-configuration.nix Platzhalter (wird eh überschrieben)
info "Erstelle hardware-configuration.nix Platzhalter..."
cat > nixos/hardware-configuration.nix << 'NIXEOF'
{ modulesPath, ... }:
{ imports = [ (modulesPath + "/installer/scan/not-detected.nix") ]; }
NIXEOF

# Festplattenverschlüsselung
echo ""
echo "  Optional kann die Root-Partition zusätzlich mit LUKS2 verschlüsselt werden."
echo "  Achtung: Danach wird bei JEDEM Boot eine Passphrase über die Server-Konsole benötigt"
echo "  > Kein unbeaufsichtigter Neustart, kein Boot ohne Konsolenzugriff (z.B. über die Proxmox-Konsole)."
echo ""
# Default JA. Ohne Verschlüsselung liegen alle Klartext-Passwörter unverschlüsselt
# auf der Platte: .env (Quelle des `secrets`-Alias), secrets/radicale_password.txt,
# secrets/vaultwarden_admin_token.txt. Wer die Platte (oder das Proxmox-Disk-Image)
# in die Hand bekommt, hat damit alles. Abschalten ist eine bewusste Entscheidung,
# kein Default.
if [[ -n "${APPHOST_DISK_ENCRYPTION:-}" ]]; then
  ENC_ANSWER="$APPHOST_DISK_ENCRYPTION"
  info "APPHOST_DISK_ENCRYPTION=$ENC_ANSWER gesetzt, überspringe die Abfrage."
else
  read -rp "  Festplattenverschlüsselung aktivieren? [J/n]: " ENC_ANSWER
fi
if [[ -z "$ENC_ANSWER" || "$ENC_ANSWER" =~ ^([jJyY]|[tT]rue) ]]; then
  DISK_ENCRYPTION=true
  warn "Festplattenverschlüsselung aktiviert (Standard). Die Passphrase wird gleich bei der Formatierung festgelegt."
else
  DISK_ENCRYPTION=false
  warn "Festplattenverschlüsselung DEAKTIVIERT – .env und secrets/ liegen unverschlüsselt auf der Platte."
fi

cat > "$REPO_DIR/nixos/disk-encryption.nix" << NIXEOF
# Automatisch von nixos/install.sh gesetzt. Manuelles Umschalten nur vo einer Neuinstallation sinnvoll
$DISK_ENCRYPTION
NIXEOF

SSH_KEY_REGEX='^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) [A-Za-z0-9+/]+=*( .*)?$'
if [[ -n "${APPHOST_SSH_PUBKEY:-}" ]]; then
  SSH_PUBKEY="$APPHOST_SSH_PUBKEY"
  info "APPHOST_SSH_PUBKEY gesetzt, überspringe die Abfrage."
else
  while true; do
    read -rp "  SSH Public Key: " SSH_PUBKEY
    [[ "$SSH_PUBKEY" =~ $SSH_KEY_REGEX ]] && break
    warn "Das sieht nicht wie ein gültiger SSH Public Key aus (muss z. B. mit 'ssh-ed25519 ' oder einem anderen gängigen key-format beginnen). Bitte erneut eingeben."
  done
fi

cat > "$REPO_DIR/nixos/ssh-key.nix" << NIXEOF
# Automatisch von nixos/install.sh gesetzt. Nachträglich änderbar durch Bearbeiten dieser Datei und anschließendes:
# >  sudo nixos-rebuild switch --flake /opt/monorepo#apphost
[
  "$SSH_PUBKEY"
]
NIXEOF

info "SSH Public Key gespeichert"

# disko Partitionierung
info "Starte disko (Partitionierung + Btrfs-Formatierung)..."
nix run "${NIX_FLAGS[@]}" github:nix-community/disko \
  -- --mode disko "$REPO_DIR/nixos/disko.nix"

info "Festplatte partitioniert und unter /mnt gemountet"

# Passwort-Hash in Datei auf dem Zielsystem schreiben
mkdir -p /mnt/etc
printf '%s' "$APPHOST_PW_HASH" > /mnt/etc/apphost-password-hash
chmod 600 /mnt/etc/apphost-password-hash
info "Passwort-Hash nach /mnt/etc/apphost-password-hash geschrieben"

# fileSystems, swapDevices und boot.initrd.luks.devices werden von disko deklarativ
# verwaltet und dürfen nicht in hardware-configuration.nix auftauchen (Konflikte -.-).
# Letzteres detektiert nixos-generate-config, weil disko den LUKS-Container beim
# Formatieren bereits geöffnet hat (per by-uuid statt disko's by-partlabel).
info "Generiere nixos/hardware-configuration.nix..."
nixos-generate-config \
  --root /mnt \
  --show-hardware-config \
  | awk '
      /^  fileSystems\./          { skip = 1 }
      skip && /^    \};/          { skip = 0; next }
      skip                        { next }
      /^  swapDevices /           { next }
      /^  boot\.initrd\.luks\.devices\./ { next }
      { print }
    ' > nixos/hardware-configuration.nix

info "hardware-configuration.nix generiert"

# ---- NixOS installieren ----
# Wichtig: Flake aus $REPO_DIR evaluieren (außerhalb von /mnt).
# Wäre die Quelle innerhalb von /mnt (dem --store-Ziel), schlägt Nix mit
# einem NAR-Hash-Assertion-Fehler fehl, weil Quelle und Ziel-Store kollidieren.
info "Starte nixos-install ohne Bootloader (dieser Vorgang wird einen Moment dauern)..."
# --no-bootloader: lanzaboote braucht Secure-Boot-Schlüssel zum Signieren,
# die noch nicht existieren. Wir erstellen sie danach und installieren den Bootloader separat.
nixos-install \
  --root /mnt \
  --flake "path:$REPO_DIR#apphost" \
  --no-root-passwd \
  --no-bootloader \
  --option extra-experimental-features "nix-command flakes"

echo "NixOS erfolgreich installiert! :party:"

# SecureBoot magie
# lanzaboote erwartet Schlüssel unter {pkiBundle}/keys/ = /etc/secureboot/keys/
# sbctl nutzt seinen internen State-Dir (/usr/share/secureboot oder Config).
# Wir schreiben dahereine sbctl-Config, die auf /etc/secureboot zeigt, bevor wir create-keys rufen.
echo "Generiere Secure Boot Schlüssel..."
# Das folgende Skript läuft IM Zielsystem (nixos-enter). Die einfachen
# Anführungszeichen sind Absicht: $TARGET und $SBCTL_CFG sollen dort expandiert
# werden, nicht hier.
# shellcheck disable=SC2016
if nixos-enter --root /mnt -- bash -c '
  set -euo pipefail
  TARGET=/etc/secureboot/keys
  mkdir -p "$TARGET" /etc/sbctl

  SBCTL_CFG=/etc/sbctl/configuration.json
  [ -f "$SBCTL_CFG" ] || printf '"'"'{"db_path":"/etc/secureboot"}'"'"' > "$SBCTL_CFG"

  sbctl create-keys

  # Falls sbctl die Config ignoriert hat und Keys woanders liegen -> kopieren
  if [ ! -f "$TARGET/db/db.pem" ]; then
    for src in /usr/share/secureboot /etc/secureboot; do
      if [ -f "$src/keys/db/db.pem" ]; then
        cp -r "$src/keys/." "$TARGET/"
        echo "Keys von $src/keys nach $TARGET kopiert"
        break
      fi
    done
  fi

  [ -f "$TARGET/db/db.pem" ] || { echo "FEHLER: Secure Boot Keys nicht gefunden! Das sollte nicht passieren."; exit 1; }
  echo "Keys erfolgreich unter $TARGET"
' ; then
  info "Secure Boot Schlüssel erzeugt: /etc/secureboot"
else
  warn "sbctl fehlgeschlagen – nach dem Neustart manuell: sudo sbctl create-keys && sudo nixos-rebuild boot"
fi

# ---- Bootloader installieren ----
info "Installiere Bootloader (lanzaboote signiert EFI-Binaries)..."
if nixos-enter --root /mnt -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot; then
  info "Bootloader installiert"
else
  warn "Bootloader-Installation fehlgeschlagen – nach dem Neustart manuell:"
  warn "  sudo nixos-rebuild boot --flake /opt/monorepo#apphost"
fi

# Das Repo gehört meist dem Nutzer, der es geklont hat (z.B. "nixos"), während dieses
# Skript per sudo als root läuft. Ohne safe.directory verweigert git seit einigen Versionen
# jede Operation darauf ("detected dubious ownership"). Live-ISO ist ephemer, daher pauschal statt gezielt. Scheiß egal.
git config --global --add safe.directory '*'

MONOREPO_ROOT="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
MONOREPO_REMOTE=""
[[ -n "$MONOREPO_ROOT" ]] && MONOREPO_REMOTE="$(git -C "$MONOREPO_ROOT" remote get-url origin 2>/dev/null || true)"

if [[ -n "$MONOREPO_REMOTE" ]]; then
  MONOREPO_BRANCH="$(git -C "$MONOREPO_ROOT" rev-parse --abbrev-ref HEAD)"
  CHECKOUT_DIR="/mnt/opt/monorepo"

  info "Richte aktualisierbares Git-Repo unter /opt/monorepo ein..."
  mkdir -p /mnt/opt
  # Standalone-Repo: komplettes Repo auschecken. (Der frühere Sparse-Checkout
  # stammte aus der Monorepo-Zeit, in der nur das Unterverzeichnis apphost/
  # ausgecheckt wurde; bei einem Unterverzeichnis "." hätte er die Ordner
  # nixos/, compose/, config/ nicht mit ausgecheckt.)
  git clone --branch "$MONOREPO_BRANCH" "$MONOREPO_ROOT" "$CHECKOUT_DIR"
  git -C "$CHECKOUT_DIR" remote set-url origin "$MONOREPO_REMOTE"

  # Maschinenspezifische Dateien sind gitignored (siehe .gitignore) und daher nach dem
  # Checkout nicht vorhanden. Aus $REPO_DIR nachziehen, wo sie in diesem Lauf gerade frisch erzeugt wurden.
  for f in nixos/hardware-configuration.nix nixos/ssh-key.nix nixos/disk-encryption.nix; do
    cp "$REPO_DIR/$f" "$APP_DIR/$f"
  done
else
  warn "Kein Git-Remote unter $REPO_DIR gefunden. Wurde die Ursprungskopie heruntergeladen und nicht geklont? Kopiere Repo ohne Versionierung (kein 'git pull' auf dem Server möglich)."
  mkdir -p "$APP_DIR"
  cp -r "$REPO_DIR"/. "$APP_DIR"
fi

# .env konfigurieren
echo ""
echo -e "  ${B}Konfiguration${N}"
echo -e "  Für Dienste, in die du dich selbst einloggst (Authelia, Grafana, OpenCloud,"
echo -e "  ntfy, Radicale, Vaultwarden), kannst du gleich eigene Passwörter vergeben –"
echo -e "  oder Enter für ein zufälliges. Interne Secrets (DB, JWT, …) immer zufällig."
echo -e "  Alle Werte können nach dem Neustart in /opt/monorepo/.env geändert werden."
echo ""

# data/ und secrets/ sind nicht Teil des Git-Checkouts (siehe .gitignore). Hier mit Besitz/Rechten für den apphost-Nutzer
# (regen-secrets & so laufen ohne sudo). Namen "apphost"/"docker" lösen nur innerhalb des Ziel-Systems auf, daher via nixos-enter.
nixos-enter --root /mnt -- bash -c '
  set -euo pipefail
  mkdir -p /opt/monorepo/data /opt/monorepo/secrets
  chown -R apphost:docker /opt/monorepo
  chmod 0750 /opt/monorepo /opt/monorepo/compose /opt/monorepo/config /opt/monorepo/data
  chmod 0700 /opt/monorepo/secrets
'

_prompt() {
    local label="$1" default="${2:-}" silent="${3:-}"
    local val
    if [[ "$silent" == "secret" ]]; then
        read -rsp "  ${label}: " val; echo "" >&2
    else
        if [[ -n "$default" ]]; then
            read -rp "  ${label} [${default}]: " val
            val="${val:-$default}"
        else
            read -rp "  ${label}: " val
        fi
    fi
    printf '%s' "$val"
}

ENV_DOMAIN=""
while [[ -z "$ENV_DOMAIN" ]]; do
    ENV_DOMAIN=$(_prompt "Domain – öffentlich für Let's Encrypt (z.B. example.com) oder lokal (z.B. apphost.lan)")
done

# Der Cloudflare-Token ist OPTIONAL. Leer lassen für rein lokalen Betrieb ohne
# Let's Encrypt: Traefik serviert dann automatisch ein self-signed Zertifikat
# (einmalige Browser-Warnung). Die Let's-Encrypt-/Cloudflare-Config bleibt
# erhalten – trägt man später eine echte Domain + Token in die .env ein, holt
# Traefik beim nächsten Start automatisch echte Zertifikate.
# Die ACME-E-Mail hat einen Default, damit die Traefik-Config nie eine leere
# E-Mail enthält (bei leerem Token wird ACME ohnehin nicht durchlaufen).
ENV_ACME_EMAIL=$(_prompt "ACME E-Mail (Let's Encrypt)" "admin@$ENV_DOMAIN")

ENV_CF_TOKEN=$(_prompt "Cloudflare API Token – optional, leer = self-signed" "" secret)

ENV_AUTH_USER=$(_prompt "Authelia Admin-Nutzer" "admin")
ENV_AUTH_EMAIL=$(_prompt "Authelia Admin-E-Mail" "$ENV_ACME_EMAIL")

ENV_AUTH_PW=""
while true; do
    ENV_AUTH_PW=$(_prompt  "Authelia Admin-Passwort" "" secret)
    ENV_AUTH_PW2=$(_prompt "Authelia Admin-Passwort (bestätigen)" "" secret)
    [[ "$ENV_AUTH_PW" == "$ENV_AUTH_PW2" ]] && break
    warn "Passwörter stimmen nicht überein."
done
unset ENV_AUTH_PW2

# Zufällige Passwörter/Secrets für alle Dienste, die eigene Zugangsdaten brauchen.
# openssl ist auf dem Live-ISO nicht vorinstalliert, daher wie mkpasswd via nix run.
_randhex() { nix run "${NIX_FLAGS[@]}" nixpkgs#openssl -- rand -hex "${1:-16}"; }

# Fragt nach einem WUNSCH-Passwort (mit Bestätigung). Enter/leer -> es wird ein
# zufälliges erzeugt. So kannst du dir bei Diensten, in die du dich selbst
# einloggst, ein merkbares Passwort geben (statt langer Zufalls-Hex, die man am
# Handy nicht tippen mag).
_prompt_pw_or_random() {
    local label="$1" pw pw2
    while true; do
        pw=$(_prompt "$label (leer = zufällig)" "" secret)
        [[ -z "$pw" ]] && { _randhex; return; }
        pw2=$(_prompt "$label bestätigen" "" secret)
        [[ "$pw" == "$pw2" ]] && { printf '%s' "$pw"; return; }
        warn "Passwörter stimmen nicht überein."
    done
}

echo ""
echo -e "  ${B}Dienst-Passwörter${N} – jeweils eigenes vergeben oder Enter für zufällig."
echo ""
# Dienste, in die du dich SELBST einloggst -> optional eigenes (merkbares) Passwort.
ENV_NTFY_ADMIN="$(_prompt_pw_or_random "ntfy Admin-Passwort")"
ENV_OPENCLOUD_ADMIN="$(_prompt_pw_or_random "OpenCloud Admin-Passwort")"
ENV_GRAFANA_ADMIN="$(_prompt_pw_or_random "Grafana Admin-Passwort")"
ENV_RADICALE_PW="$(_prompt_pw_or_random "Radicale/Kalender-Passwort (DAVx5 am Handy)")"

# Rein interne Secrets (werden nie manuell eingegeben) -> immer zufällig.
ENV_NTFY_ALERT="$(_randhex)"
ENV_IMMICH_DB="$(_randhex)"
ENV_IMMICH_JWT="$(_randhex 32)"
ENV_PAPERLESS_SECRET="$(_randhex 32)"
ENV_PAPERLESS_REDIS="$(_randhex)"
ENV_COLLABORA_ADMIN="$(_randhex)"
ENV_GRAFANA_SECRET="$(_randhex 32)"

# Vaultwarden ADMIN_TOKEN: Vaultwarden empfiehlt, hier einen Argon2-Hash statt eines
# Klartext-Tokens zu hinterlegen. Das Klartext-Token (für den /admin-Login) landet
# separat in secrets/vaultwarden_admin_token.txt, da es aus dem Hash nicht mehr
# rekonstruierbar ist.
_argon2_hash() {
    local password="$1" salt
    salt="$(_randhex)"
    printf '%s' "$password" | nix-shell -p libargon2 --run \
        "argon2 '$salt' -e -id -k 65540 -t 3 -p 4"
}
ENV_VAULTWARDEN_TOKEN_PLAIN="$(_prompt_pw_or_random "Vaultwarden /admin-Token")"
ENV_VAULTWARDEN_TOKEN_HASH="$(_argon2_hash "$ENV_VAULTWARDEN_TOKEN_PLAIN")"

ENV_FILE="$APP_DIR/.env"
cp "$APP_DIR/.env.example" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Werte in .env eintragen (Python für sicheres Escaping beliebiger Zeichen).
# Secrets werden per Umgebungsvariable durchgereicht (nicht als Argv), damit sie nicht
# über die Prozessliste (ps) einsehbar sind.
# python3 ist auf dem Live-ISO nicht vorinstalliert, daher wie openssl/mkpasswd via nix run.
DOMAIN="$ENV_DOMAIN" ACME_EMAIL="$ENV_ACME_EMAIL" CF_DNS_API_TOKEN="$ENV_CF_TOKEN" \
AUTHELIA_ADMIN_USER="$ENV_AUTH_USER" AUTHELIA_ADMIN_EMAIL="$ENV_AUTH_EMAIL" AUTHELIA_ADMIN_PASSWORD="$ENV_AUTH_PW" \
NTFY_ADMIN_PASSWORD="$ENV_NTFY_ADMIN" NTFY_ALERTMANAGER_PASSWORD="$ENV_NTFY_ALERT" \
IMMICH_DB_PASSWORD="$ENV_IMMICH_DB" IMMICH_JWT_SECRET="$ENV_IMMICH_JWT" \
PAPERLESS_SECRET_KEY="$ENV_PAPERLESS_SECRET" PAPERLESS_REDIS_PASSWORD="$ENV_PAPERLESS_REDIS" \
OPENCLOUD_ADMIN_PASSWORD="$ENV_OPENCLOUD_ADMIN" RADICALE_PASSWORD="$ENV_RADICALE_PW" \
COLLABORA_ADMIN_PASSWORD="$ENV_COLLABORA_ADMIN" \
GRAFANA_ADMIN_PASSWORD="$ENV_GRAFANA_ADMIN" GRAFANA_SECRET_KEY="$ENV_GRAFANA_SECRET" \
VAULTWARDEN_ADMIN_TOKEN="$ENV_VAULTWARDEN_TOKEN_HASH" \
nix run "${NIX_FLAGS[@]}" nixpkgs#python3 -- - "$ENV_FILE" << 'PYEOF'
import os, re, sys
env_file = sys.argv[1]
keys = [
    'DOMAIN', 'ACME_EMAIL', 'CF_DNS_API_TOKEN',
    'AUTHELIA_ADMIN_USER', 'AUTHELIA_ADMIN_EMAIL', 'AUTHELIA_ADMIN_PASSWORD',
    'NTFY_ADMIN_PASSWORD', 'NTFY_ALERTMANAGER_PASSWORD',
    'IMMICH_DB_PASSWORD', 'IMMICH_JWT_SECRET',
    'PAPERLESS_SECRET_KEY', 'PAPERLESS_REDIS_PASSWORD',
    'OPENCLOUD_ADMIN_PASSWORD',
    'RADICALE_PASSWORD',
    'COLLABORA_ADMIN_PASSWORD',
    'GRAFANA_ADMIN_PASSWORD', 'GRAFANA_SECRET_KEY',
    'VAULTWARDEN_ADMIN_TOKEN',
]
with open(env_file) as f:
    content = f.read()
for key in keys:
    # Escapen von $ -> $$, damit docker-compose die Variablen nicht interpoliert
    value = os.environ[key].replace('$', '$$')
    pattern = rf'^({re.escape(key)}=).*'
    new, n = re.subn(pattern, lambda m: m.group(1) + value, content, flags=re.MULTILINE)
    content = new if n else content + f'\n{key}={value}'
with open(env_file, 'w') as f:
    f.write(content)
PYEOF

unset ENV_AUTH_PW ENV_CF_TOKEN ENV_VAULTWARDEN_TOKEN_HASH ENV_RADICALE_PW
info ".env konfiguriert"

# Vaultwarden-Admin-Token: Klartext separat sichern (wird für den /admin-Login benötigt;
# in .env steht nur der Argon2-Hash, aus dem sich das Token nicht zurückgewinnen lässt).
mkdir -p "$APP_DIR/secrets"
printf '%s\n' "$ENV_VAULTWARDEN_TOKEN_PLAIN" > "$APP_DIR/secrets/vaultwarden_admin_token.txt"
chmod 600 "$APP_DIR/secrets/vaultwarden_admin_token.txt"
unset ENV_VAULTWARDEN_TOKEN_PLAIN
info "Vaultwarden Admin-Token gespeichert: /opt/monorepo/secrets/vaultwarden_admin_token.txt"

# Secrets generieren (läuft im Live-System, nix ist verfügbar)
info "Generiere Secrets (lädt benötigte Nix-Pakete, dauert einen Moment...)"
cd "$APP_DIR"

for script in update-secrets-authelia update-secrets-ntfy update-secrets-radicale; do
    if bash "scripts/${script}.sh"; then
        info "${script} ✓"
    else
        warn "${script} fehlgeschlagen – nach Neustart manuell ausführen:"
        warn "  bash /opt/monorepo/scripts/${script}.sh"
    fi
done

# Ownership final korrigieren: .env und die frisch generierten Secrets wurden
# nach dem ersten chown (weiter oben) als root angelegt und wären damit für den
# apphost-Nutzer nicht lesbar – "docker compose" läuft aber als apphost. Daher
# hier erneut rekursiv setzen (Modes wie 600/700 bleiben, nur der Owner stimmt).
# Namen "apphost"/"docker" lösen nur im Zielsystem auf -> via nixos-enter.
info "Setze Besitzrechte für /opt/monorepo (apphost:docker)..."
nixos-enter --root /mnt -- chown -R apphost:docker /opt/monorepo

# Ausnahme vom rekursiven chown oben: oidc_jwks.pem (privater Signaturschlüssel)
# wird IM Authelia-Container gelesen. Unter userns-remap ist Container-UID 1000 =
# Host REMAP_BASE+1000; als apphost (Host-UID 1000) gehörend erschiene er im
# Container als "nobody" ohne Leserecht -> Authelia bricht beim Laden der Config
# ab ("permission denied" auf /config/oidc_jwks.pem). Daher jwks auf die remap-UID
# setzen. authelia_users.yml dagegen bleibt host-owned + world-readable (0644, nur
# ein Passwort-Hash): so liest der Container es UND `regen-secrets` kann es später
# als apphost (nicht root) neu schreiben. authelia.env NICHT umsetzen: die liest
# "docker compose" per env_file auf dem Host (als apphost) und muss apphost gehören.
REMAP_BASE="$(awk -F: '$1=="dockremap"{print $2}' /mnt/etc/subuid 2>/dev/null | head -1)"
if [[ -n "$REMAP_BASE" ]]; then
  AUTHELIA_UID=$((REMAP_BASE + 1000))
  nixos-enter --root /mnt -- chown "$AUTHELIA_UID:$AUTHELIA_UID" \
    /opt/monorepo/secrets/authelia_oidc_jwks.pem
  nixos-enter --root /mnt -- chmod 0644 /opt/monorepo/secrets/authelia_users.yml
  info "Authelia: jwks -> $AUTHELIA_UID:$AUTHELIA_UID (userns-remap), users.yml -> 0644 host-owned"
else
  warn "dockremap nicht in /mnt/etc/subuid gefunden – Authelia-Container-Secret nicht umgesetzt."
  warn "  Nach Neustart manuell: sudo chown 101000:101000 /opt/monorepo/secrets/authelia_oidc_jwks.pem"
fi

cd "$REPO_DIR"

echo ""
echo -e "${G}NixOS-Installation erfolgreich abgeschlossen!${N}"
echo ""
echo -e "  ${B}Nach dem Neustart:${N}"
echo ""
echo -e "  ${B}1.${N} SSH-Login:     ssh apphost@<IP-ADRESSE>"
echo -e "  ${B}2.${N} Stack starten: cd /opt/monorepo && docker compose up -d"
echo -e "  ${B}3.${N} Vaultwarden Admin-Token: cat /opt/monorepo/secrets/vaultwarden_admin_token.txt"
echo ""

for i in 5 4 3 2 1; do
  echo -ne "\r  ${Y}Neustart in ${i} Sekunden... (Strg+C zum Abbrechen)${N}  "
  sleep 1
done
echo ""
reboot now
