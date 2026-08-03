#!/usr/bin/env bash
# Zeigt alle für dich relevanten Passwörter/Tokens an EINEM Ort – aus .env und
# den generierten Dateien unter secrets/.
#   Aufruf:  bash scripts/show-secrets.sh   (bzw. der Alias: secrets)
#
# NICHT teilen/pipen. Passwörter änderst du in .env (danach: regen-secrets +
# betroffene Container neu starten).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# || true: grep liefert bei keinem Treffer Exit 1 -> mit `set -o pipefail` würde
# eine Zuweisung `x="$(env_val …)"` das Skript unter `set -e` abbrechen.
env_val()  { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- || true; }
file_val() { [[ -f "$1" ]] && cat "$1" || echo "(fehlt – ggf. 'up' bzw. regen-secrets ausführen)"; }
line()     { printf '  %-24s %s\n' "$1" "$2"; }
hr()       { printf '%s\n' "══════════════════════════════════════════════════════════════"; }

hr
echo "  AppHost – Secrets & Logins        Quelle: .env + secrets/"
hr
echo
echo "▶ SSO (Authelia) – Login vor fast allen Web-Diensten"
line "Nutzer"   "$(env_val AUTHELIA_ADMIN_USER)"
line "Passwort" "$(env_val AUTHELIA_ADMIN_PASSWORD)"
echo
echo "▶ App-eigene Logins        (Nutzer / Passwort)"
line "Grafana"    "$(env_val GRAFANA_ADMIN_USER) / $(env_val GRAFANA_ADMIN_PASSWORD)  [derzeit NICHT nutzbar: Anmeldung nur über Authelia/OIDC. Erst verwendbar, nachdem GF_AUTH_DISABLE_LOGIN_FORM in compose/monitoring/grafana.yml auf false gesetzt und Grafana neu erzeugt wurde.]"
line "OpenCloud"  "admin / $(env_val OPENCLOUD_ADMIN_PASSWORD)"
line "ntfy"       "admin / $(env_val NTFY_ADMIN_PASSWORD)"
line "Bichon"     "admin / admin@bichon   (Image-Standard; 1. Login ändern: Settings->Profile)"
line "Grocy"      "SSO über Authelia (kein eigener Login)"
echo
echo "▶ Kalender – Radicale (für DAVx5 am Handy)"
# Nutzer: bevorzugt aus .env; fehlt RADICALE_USER dort, aus der htpasswd-Datei
# (Format 'user:$2y$...') lesen; sonst Default 'admin'.
rad_user="$(env_val RADICALE_USER)"
if [[ -z "$rad_user" && -f secrets/radicale_users ]]; then
    rad_user="$(cut -d: -f1 secrets/radicale_users 2>/dev/null | head -1 || true)"
fi
line "Nutzer"   "${rad_user:-admin}"
line "Passwort" "$(file_val secrets/radicale_password.txt)"
echo
echo "▶ Vaultwarden"
line "/admin-Panel" "Token: $(file_val secrets/vaultwarden_admin_token.txt)"
line "Nutzer-Login" "Registrierung AUS -> Konto in /admin einladen; Master-PW wählst du selbst"
echo
echo "▶ Immich – OIDC-Client-Secret (manuell in der Immich-Admin-UI eintragen)"
if [[ -f secrets/oidc-immich.env ]]; then
    grep -E "SECRET" secrets/oidc-immich.env | sed 's/^/  /' || true
else
    echo "  (fehlt)"
fi
echo
hr
echo "  Diese Ausgabe NICHT teilen. Ändern -> .env, dann: regen-secrets"
hr
