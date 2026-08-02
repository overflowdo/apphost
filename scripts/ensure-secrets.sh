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
