#!/usr/bin/env bash
# Meldet einen fehlgeschlagenen systemd-Dienst an ntfy.
#
# Aufruf: notify-failure.sh <unit-name>
# Verdrahtet über OnFailure= in nixos/modules/backup.nix – aktuell für
# apphost-db-backup, aide-check und docker-security-scan.
#
# Warum überhaupt: die reparierte Benachrichtigungskette hängt an Prometheus ->
# Alertmanager -> ntfy und sieht nur, was Prometheus scrapt. systemd-Dienste
# gehören nicht dazu: node-exporter läuft ohne --collector.systemd (dafür
# müsste ihm der D-Bus-Socket in den Container gereicht werden, was seine
# Isolation aufweicht). Ein Backup, dessen Ausfall still bleibt, ist genau der
# Fall, der erst beim Restore auffliegt – deshalb hier der direkte Weg.
#
# Gesendet wird an denselben ntfy-Topic wie kritische Alerts, mit demselben
# Nutzer (alertmanager, ACL rw auf apphost-critical). Erreichbar ist ntfy vom
# Host aus nur über Traefik auf :443, daher HTTPS gegen die lokale CA.
set -uo pipefail

UNIT="${1:-unbekannt}"
ROOT_DIR="${ROOT_DIR:-/opt/monorepo}"
ENV_FILE="$ROOT_DIR/.env"
PW_FILE="$ROOT_DIR/secrets/alertmanager_ntfy_password"
CA_FILE="/var/lib/apphost-ca/local-ca.crt"

read_env() {  # <key>
    { grep -m1 "^[[:space:]]*$1=" "$ENV_FILE" 2>/dev/null || true; } \
        | cut -d= -f2- | tr -d "\"' \r"
}

DOMAIN="$(read_env DOMAIN)"
NTFY_SUBDOMAIN="$(read_env NTFY_SUBDOMAIN)"
NTFY_SUBDOMAIN="${NTFY_SUBDOMAIN:-ntfy}"

# Die letzten Zeilen aus dem Journal mitschicken – ohne die ist die Meldung
# zwar da, aber wertlos.
DETAIL="$(journalctl -u "$UNIT" -n 15 --no-pager -o cat 2>/dev/null | tail -c 3000)"
BODY="Dienst: $UNIT
Host: $(uname -n)
Zeit: $(date '+%F %T %Z')

Letzte Journal-Zeilen:
${DETAIL:-（keine）}

Details: journalctl -u $UNIT -n 50"

# Immer auch ins Journal – falls ntfy selbst das Problem ist.
echo "apphost-notify-failure: $UNIT ist fehlgeschlagen." >&2

if [[ -z "$DOMAIN" || ! -f "$PW_FILE" ]]; then
    echo "apphost-notify-failure: DOMAIN oder $PW_FILE fehlt – keine Push-Nachricht möglich." >&2
    exit 0   # den ohnehin schon fehlgeschlagenen Dienst nicht zusätzlich verdecken
fi

CURL_ARGS=(-fsS --max-time 20
    -H "Title: Dienst fehlgeschlagen: $UNIT"
    -H "Priority: high"
    -H "Tags: rotating_light"
    -d "$BODY")
[[ -f "$CA_FILE" ]] && CURL_ARGS+=(--cacert "$CA_FILE")

# Zugangsdaten über eine Konfiguration auf stdin (-K -) statt über -u:
# alles in argv ist auf dem Host per `ps` mitlesbar. In der curl-Konfiguration
# müssen innerhalb der Anführungszeichen nur " und \ maskiert werden.
curl_config() {
    local pw
    pw="$(cat "$PW_FILE")"
    pw="${pw//\\/\\\\}"
    pw="${pw//\"/\\\"}"
    printf 'user = "alertmanager:%s"\n' "$pw"
}

if curl_config | curl -K - "${CURL_ARGS[@]}" "https://${NTFY_SUBDOMAIN}.${DOMAIN}/apphost-critical" >/dev/null; then
    echo "apphost-notify-failure: Meldung an ntfy zugestellt." >&2
else
    echo "apphost-notify-failure: Zustellung an ntfy fehlgeschlagen." >&2
fi

exit 0
