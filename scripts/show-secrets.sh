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
echo "▶ Authelia – Zweiter Faktor (TOTP/WebAuthn)"
echo "  Pflicht für: traefik. / prometheus. / alertmanager.<domain> und vault.<domain>/admin"
# Authelia verschickt den Registrierungslink NICHT per Mail, sondern über den
# filesystem-Notifier in /data/notification.txt im Container (kein SMTP
# konfiguriert). Ohne diesen Link steht man beim ersten Aufruf eines
# 2FA-geschützten Dienstes vor einer Aufforderung, die sich nicht erfüllen
# lässt – deshalb hier direkt mit ausgeben.
if ! command -v docker >/dev/null 2>&1; then
    line "Registrierungslink" "(docker nicht verfügbar)"
elif ! running="$(docker ps --format '{{.Names}}' 2>/dev/null)"; then
    # Eigener Zweig, damit ein nicht erreichbarer Daemon (bzw. fehlende
    # Gruppenmitgliedschaft) nicht als "Container läuft nicht" erscheint.
    line "Registrierungslink" "(Docker-Daemon nicht erreichbar – in der Gruppe 'docker'?)"
elif ! printf '%s\n' "$running" | grep -qx authelia; then
    line "Registrierungslink" "(Container 'authelia' läuft nicht – erst 'up' ausführen)"
else
    notify="$(docker exec authelia cat /data/notification.txt 2>/dev/null || true)"
    # Letzter Eintrag gewinnt: die Datei wird angehängt, der jüngste Link steht
    # unten. Bewusst über ein generisches URL-Muster statt über einen festen
    # Pfad – der unterscheidet sich je nach Authelia-Version.
    link="$(printf '%s' "$notify" | grep -oE 'https://[^[:space:]"<>]+' | tail -1 || true)"
    if [[ -n "$link" ]]; then
        subject="$(printf '%s' "$notify" | grep -E '^Subject:' | tail -1 \
                   | cut -d: -f2- | sed 's/^ *//' || true)"
        line "Letzte Anforderung" "${subject:-(ohne Betreff)}"
        line "Registrierungslink" "$link"
        echo "  -> im Browser öffnen; der Link ist kurzlebig und nur einmal gültig."
    else
        line "Registrierungslink" "keine offene Anforderung"
        echo "  -> erst einen 2FA-Dienst aufrufen und dort 'Register device' klicken,"
        echo "     danach diesen Befehl erneut ausführen."
    fi
fi
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
