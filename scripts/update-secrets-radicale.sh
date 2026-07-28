#!/usr/bin/env bash
# Erzeugt die Radicale-Nutzerdatei (htpasswd, bcrypt):
#   secrets/radicale_users         – user:bcrypt-hash (von Radicale gelesen)
#   secrets/radicale_password.txt  – Klartext-Passwort (für den DAVx5-Login am Handy)
#
# Nutzer kommt aus .env (RADICALE_USER, Default "admin"). Das Passwort wird einmalig
# zufällig erzeugt und bleibt danach erhalten (idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
SECRETS_DIR="$ROOT_DIR/secrets"
USERS_FILE="$SECRETS_DIR/radicale_users"
PW_FILE="$SECRETS_DIR/radicale_password.txt"

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE fehlt." >&2; exit 1; }

set -a; # shellcheck source=/dev/null
source "$ENV_FILE"; set +a
RADICALE_USER="${RADICALE_USER:-admin}"

mkdir -p "$SECRETS_DIR"

if [[ -f "$USERS_FILE" && -f "$PW_FILE" ]]; then
    echo "Radicale-Nutzerdatei existiert bereits – behalte sie."
    exit 0
fi

# Zufälliges Passwort (nur beim ersten Mal). openssl ist auf dem Live-ISO nicht da
# -> via nix; bcrypt-Hash via mkpasswd.
PW="$(nix run --extra-experimental-features 'nix-command flakes' nixpkgs#openssl -- rand -hex 16 2>/dev/null || openssl rand -hex 16)"
HASH="$(printf '%s' "$PW" | nix-shell -p mkpasswd --run 'mkpasswd -m bcrypt -s' 2>/dev/null || mkpasswd -m bcrypt "$PW")"

printf '%s:%s\n' "$RADICALE_USER" "$HASH" > "$USERS_FILE"
# 644, damit der Radicale-Container die Datei per Bind-Mount lesen kann: unter
# userns-remap läuft er als hohe Host-UID (= "nobody" für apphost-owned Dateien);
# 640 wäre dort unlesbar. Es ist nur ein bcrypt-Hash, daher world-readable ok.
chmod 644 "$USERS_FILE"
printf '%s\n' "$PW" > "$PW_FILE"
chmod 600 "$PW_FILE"

echo "  -> $USERS_FILE ($RADICALE_USER, bcrypt)"
echo "  -> $PW_FILE (Klartext-Passwort für DAVx5)"
echo ""
echo "DAVx5-Login:  Nutzer '$RADICALE_USER', Passwort siehe: cat $PW_FILE"
