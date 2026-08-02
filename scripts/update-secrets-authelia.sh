#!/usr/bin/env bash
# Generates (or preserves) Authelia secrets:
#   secrets/authelia.env         – Authelia-interne Secrets + gehashte OIDC-Client-Secrets
#   secrets/authelia_oidc_jwks.pem  – RSA-4096-Key für OIDC-Token-Signierung
#   secrets/authelia_users.yml   – User-Datenbank mit gehashtem Admin-Passwort
#   secrets/oidc-grafana.env     – Grafana OIDC client secret
#   secrets/oidc-immich.env      – Immich OIDC client secret (manuell in UI eintragen)
#   secrets/oidc-paperless.env   – Paperless OIDC client secret + SOCIALACCOUNT_PROVIDERS
#
# Idempotent: bestehende Secrets werden beibehalten. Nur fehlende Werte werden neu erzeugt.
# Ausführen nach: Ersteinrichtung oder wenn ein Secret manuell gelöscht wurde.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
OUTPUT_ENV="$ROOT_DIR/secrets/authelia.env"
OUTPUT_JWKS="$ROOT_DIR/secrets/authelia_oidc_jwks.pem"
OUTPUT_USERS="$ROOT_DIR/secrets/authelia_users.yml"
SECRETS_DIR="$ROOT_DIR/secrets"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found. Copy .env.example to .env first." >&2
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Pflicht-Variablen aus .env
AUTHELIA_ADMIN_USER="${AUTHELIA_ADMIN_USER:-admin}"
AUTHELIA_ADMIN_EMAIL="${AUTHELIA_ADMIN_EMAIL:-}"
AUTHELIA_ADMIN_PASSWORD="${AUTHELIA_ADMIN_PASSWORD:-}"
AUTHELIA_SUBDOMAIN="${AUTHELIA_SUBDOMAIN:-auth}"
DOMAIN="${DOMAIN:-}"

if [[ -z "$AUTHELIA_ADMIN_PASSWORD" ]]; then
    echo "ERROR: AUTHELIA_ADMIN_PASSWORD is not set in $ENV_FILE" >&2
    exit 1
fi
if [[ -z "$DOMAIN" ]]; then
    echo "ERROR: DOMAIN is not set in $ENV_FILE" >&2
    exit 1
fi
if [[ -z "$AUTHELIA_ADMIN_EMAIL" ]]; then
    echo "ERROR: AUTHELIA_ADMIN_EMAIL is not set in $ENV_FILE" >&2
    exit 1
fi

_openssl() { nix-shell -p openssl --run "openssl $*"; }

gen_secret() {
    # 64 zufällige Hex-Zeichen (256 Bit Entropie)
    _openssl rand -hex 32
}

gen_client_secret() {
    # 32 zufällige Hex-Zeichen (128 Bit – ausreichend für OIDC)
    _openssl rand -hex 16
}

argon2_hash() {
    local password="$1"
    local salt
    salt=$(_openssl rand -hex 16)
    # -v 13  = Argon2 version 1.3 (argon2 CLI uses 13, not the 0x13=19 internal byte)
    # -m 16  = 2^16 KiB = 65536 KiB memory cost (matches Authelia config memory: 65536)
    printf '%s' "$password" | nix-shell -p libargon2 --run \
        "argon2 '$salt' -id -v 13 -m 16 -t 3 -p 4 -l 32 -e"
}

# Read a value from an env file where values are wrapped in single quotes.
# Returns empty string if the file or key doesn't exist.
read_secret() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    grep "^${key}='" "$file" 2>/dev/null | sed "s/^${key}='\(.*\)'$/\1/" || true
}

# 1. OIDC-JWKS-Key (RSA 4096). Nur erzeugen wenn noch nicht vorhanden
mkdir -p "$SECRETS_DIR"
if [[ ! -f "$OUTPUT_JWKS" ]]; then
    echo "Generating RSA-4096 OIDC signing key..."
    _openssl genrsa -out "$OUTPUT_JWKS" 4096 2>/dev/null
    chmod 640 "$OUTPUT_JWKS"
    echo "  -> $OUTPUT_JWKS"
else
    echo "Keeping existing OIDC signing key."
fi

# 2. Interne Authelia-Secrets. bestehende Werte beibehalten
echo "Loading/generating internal Authelia secrets..."
JWT_SECRET=$(read_secret "$OUTPUT_ENV" "AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET")
JWT_SECRET="${JWT_SECRET:-$(gen_secret)}"

SESSION_SECRET=$(read_secret "$OUTPUT_ENV" "AUTHELIA_SESSION_SECRET")
SESSION_SECRET="${SESSION_SECRET:-$(gen_secret)}"

STORAGE_KEY=$(read_secret "$OUTPUT_ENV" "AUTHELIA_STORAGE_ENCRYPTION_KEY")
STORAGE_KEY="${STORAGE_KEY:-$(gen_secret)}"

HMAC_SECRET=$(read_secret "$OUTPUT_ENV" "AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET")
HMAC_SECRET="${HMAC_SECRET:-$(gen_secret)}"

# 3. OIDC-Client-Secrets. Bestehende Werte beibehalten, nur neue hashen
echo "Loading/generating OIDC client secrets..."

GRAFANA_SECRET=$(read_secret "$SECRETS_DIR/oidc-grafana.env" "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET")
GRAFANA_SECRET_HASH=$(read_secret "$OUTPUT_ENV" "OIDC_GRAFANA_SECRET_HASH")
if [[ -z "$GRAFANA_SECRET" ]] || [[ -z "$GRAFANA_SECRET_HASH" ]]; then
    GRAFANA_SECRET=$(gen_client_secret)
    echo "  Hashing Grafana secret..."
    GRAFANA_SECRET_HASH=$(argon2_hash "$GRAFANA_SECRET")
fi

IMMICH_SECRET=$(read_secret "$SECRETS_DIR/oidc-immich.env" "AUTHELIA_OIDC_IMMICH_SECRET")
IMMICH_SECRET_HASH=$(read_secret "$OUTPUT_ENV" "OIDC_IMMICH_SECRET_HASH")
if [[ -z "$IMMICH_SECRET" ]] || [[ -z "$IMMICH_SECRET_HASH" ]]; then
    IMMICH_SECRET=$(gen_client_secret)
    echo "  Hashing Immich secret..."
    IMMICH_SECRET_HASH=$(argon2_hash "$IMMICH_SECRET")
fi

PAPERLESS_SECRET=$(read_secret "$SECRETS_DIR/oidc-paperless.env" "AUTHELIA_OIDC_PAPERLESS_SECRET")
PAPERLESS_SECRET_HASH=$(read_secret "$OUTPUT_ENV" "OIDC_PAPERLESS_SECRET_HASH")
if [[ -z "$PAPERLESS_SECRET" ]] || [[ -z "$PAPERLESS_SECRET_HASH" ]]; then
    PAPERLESS_SECRET=$(gen_client_secret)
    echo "  Hashing Paperless secret..."
    PAPERLESS_SECRET_HASH=$(argon2_hash "$PAPERLESS_SECRET")
fi

# 4. Admin-Passwort hashen (für users_database.yml) immer neu hashen
echo "Hashing admin password..."
ADMIN_HASH=$(argon2_hash "$AUTHELIA_ADMIN_PASSWORD")

# 5. secrets/authelia.env schreiben (nur Authelia-interne Secrets + Hashes)
cat > "$OUTPUT_ENV" <<EOF
# Generated by scripts/update-secrets-authelia.sh. Do not edit manually!
# Used exclusively by the Authelia container.

# Authelia internal secrets
AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET='${JWT_SECRET}'
AUTHELIA_SESSION_SECRET='${SESSION_SECRET}'
AUTHELIA_STORAGE_ENCRYPTION_KEY='${STORAGE_KEY}'
AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET='${HMAC_SECRET}'

# OIDC client secret hashes (used by Authelia configuration.yml template).
# Kein AUTHELIA_-Präfix: template-only, sonst versucht Authelia sie als Config-Key
# zu mappen ("configuration environment variable not expected"-Warnung).
OIDC_GRAFANA_SECRET_HASH='${GRAFANA_SECRET_HASH}'
OIDC_IMMICH_SECRET_HASH='${IMMICH_SECRET_HASH}'
OIDC_PAPERLESS_SECRET_HASH='${PAPERLESS_SECRET_HASH}'
EOF
chmod 600 "$OUTPUT_ENV"
echo "  -> $OUTPUT_ENV"

# 5b. Per-service OIDC secret files (only the secret each service needs)
cat > "$SECRETS_DIR/oidc-grafana.env" <<EOF
# Generated by scripts/update-secrets-authelia.sh. Do not edit manually.
# Loaded by Grafana container only.
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET='${GRAFANA_SECRET}'
EOF
chmod 600 "$SECRETS_DIR/oidc-grafana.env"
echo "  -> $SECRETS_DIR/oidc-grafana.env"

cat > "$SECRETS_DIR/oidc-immich.env" <<EOF
# Generated by scripts/update-secrets-authelia.sh. Do not edit manually!
# Not loaded by any container. Configure manually in Immich Admin-UI.
# Administration -> Settings -> OAuth -> Client Secret
AUTHELIA_OIDC_IMMICH_SECRET='${IMMICH_SECRET}'
EOF
chmod 600 "$SECRETS_DIR/oidc-immich.env"
echo "  -> $SECRETS_DIR/oidc-immich.env"

cat > "$SECRETS_DIR/oidc-paperless.env" <<EOF
# Generated by scripts/update-secrets-authelia.sh. Do not edit manually!
# Loaded by Paperless-NGX container only.
AUTHELIA_OIDC_PAPERLESS_SECRET='${PAPERLESS_SECRET}'
PAPERLESS_SOCIALACCOUNT_PROVIDERS='{"openid_connect": {"OAUTH_PKCE_ENABLED": true, "APPS": [{"provider_id": "authelia", "name": "Authelia", "client_id": "paperless", "secret": "${PAPERLESS_SECRET}", "settings": {"server_url": "https://${AUTHELIA_SUBDOMAIN}.${DOMAIN}/.well-known/openid-configuration"}}]}}'
EOF
chmod 600 "$SECRETS_DIR/oidc-paperless.env"
echo "  -> $SECRETS_DIR/oidc-paperless.env"

# 6. secrets/authelia_users.yml schreiben.
# Erst löschen: bei regen-secrets läuft dieses Skript als apphost (nicht root);
# gehört die alte Datei der remapped Container-UID (siehe unten), kann apphost sie
# nicht überschreiben (EACCES), wohl aber im apphost-eigenen secrets/-Ordner
# löschen und neu anlegen. Die neue Datei gehört dann wieder apphost.
rm -f "$OUTPUT_USERS"
cat > "$OUTPUT_USERS" <<EOF
# Generated by scripts/update-secrets-authelia.sh. Do not edit manually!
# Authelia user database (file-backend).
# Add further users here or use Authelia's admin UI after first login.
users:
  ${AUTHELIA_ADMIN_USER}:
    disabled: false
    displayname: "${AUTHELIA_ADMIN_USER}"
    password: '${ADMIN_HASH}'
    email: ${AUTHELIA_ADMIN_EMAIL}
    groups:
      - admins
      - users
EOF
# users.yml enthält nur einen Passwort-HASH und wird bei jedem Lauf neu
# geschrieben. Damit es der Authelia-Container (userns-remap -> Host-UID 101000,
# aus Sicht der Datei "other") lesen kann, OHNE dass wir es der Container-UID
# übereignen (was root bräuchte und regen-secrets als apphost verbieten würde),
# ist es host-owned + world-readable (0644). Auf einem Single-Admin-Host ist ein
# world-lesbarer argon2id-Hash vertretbar (argon2id, nicht bcrypt – siehe
# argon2_hash() oben und config/authelia/configuration.yml).
chmod 0644 "$OUTPUT_USERS"
echo "  -> $OUTPUT_USERS (0644, host-owned)"

SUBUID_FILE="/etc/subuid"
[[ "$ROOT_DIR" == /mnt/* ]] && SUBUID_FILE="/mnt/etc/subuid"
REMAP_BASE="$(awk -F: '$1=="dockremap"{print $2}' "$SUBUID_FILE" 2>/dev/null || true)"

if [[ -n "$REMAP_BASE" ]]; then
    REMAP_UID="$((REMAP_BASE + 1000))"
    # oidc_jwks.pem ist ein privater Signaturschlüssel -> bleibt 0640 und wird IM
    # Authelia-Container gelesen (userns-remap: Container-UID 1000 = Host
    # REMAP_BASE+1000). Er muss der remapped UID gehören, sonst erscheint er im
    # Container als "nobody" ohne Leserecht und Authelia bricht ab. Chown geht nur
    # als root -> passiert bei der Erstinstallation. Bei regen-secrets als apphost
    # bleibt der bestehende Schlüssel unverändert (wird oben ohnehin behalten),
    # daher hier nur unter root chownen statt hart zu scheitern.
    if [[ "$(id -u)" -eq 0 ]]; then
        chown "$REMAP_UID:$REMAP_UID" "$OUTPUT_JWKS"
        echo "  -> $OUTPUT_JWKS -> $REMAP_UID:$REMAP_UID (userns-remap, im Container gelesen)"
    fi
    # authelia.env dagegen wird per env_file von "docker compose" auf dem HOST
    # gelesen -> muss dem Deploy-Nutzer gehören (Owner des Repo-Verzeichnisses),
    # nicht der Container-UID. Sonst kann docker compose die env_file nicht lesen.
    chown --reference="$ROOT_DIR" "$OUTPUT_ENV"
    echo "  -> $OUTPUT_ENV an Repo-Owner angeglichen (env_file, host-seitig gelesen)"
else
    echo "WARNING: dockremap nicht in /etc/subuid gefunden. Ownership nicht gesetzt" >&2
fi

echo ""
echo "Done!"
echo ""
