#!/bin/sh
# Richtet Authelia als OIDC-Provider in Forgejo ein.
# Wird einmalig vom forgejo-init Container ausgeführt.
# Überspringt die Konfiguration, falls Authelia bereits registriert ist.
set -e

echo "[forgejo-init] Checking OAuth2 sources..."

if forgejo admin auth list 2>&1 | grep -q "Authelia"; then
  echo "[forgejo-init] Authelia already registered, skipping."
  exit 0
fi

echo "[forgejo-init] Registering Authelia as OIDC provider..."

forgejo admin auth add-oauth \
  --name "Authelia" \
  --provider openidConnect \
  --key forgejo \
  --secret "$AUTHELIA_OIDC_FORGEJO_SECRET" \
  --auto-discover-url "https://$AUTHELIA_SUBDOMAIN.$DOMAIN/.well-known/openid-configuration" \
  --skip-local-2fa \
  --scopes "openid,profile,email,groups" \
  --group-claim-name groups \
  --admin-group admins \
  --config /data/gitea/conf/app.ini

echo "[forgejo-init] Done. Users from the 'admins' group in Authelia are Forgejo admins."
