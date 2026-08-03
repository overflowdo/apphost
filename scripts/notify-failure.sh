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
CA_FILE="${CA_FILE:-/var/lib/apphost-ca/local-ca.crt}"

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

URL="https://${NTFY_SUBDOMAIN}.${DOMAIN}/apphost-critical"

# Erst mit dem System-Truststore, erst danach mit der lokalen CA.
#
# --cacert ERSETZT den Truststore, es ergänzt ihn nicht. local-ca.crt wird von
# apphost-local-ca.service in JEDER Konfiguration erzeugt, auch wenn der Stack
# mit echter Domain und Let's-Encrypt-Zertifikat läuft (der Weg, den install.sh
# ausdrücklich offenhält). Ein festes --cacert hätte dort die Verifikation
# gebrochen. Reihenfolge also: normaler Weg zuerst, lokale CA als Rückfall.
#
# curls stderr wird je Versuch eingefangen und NUR ausgegeben, wenn am Ende
# nichts durchkam. Sonst stünde im Journal bloß "fehlgeschlagen" ohne Grund –
# und ob es an TLS, Auth, DNS oder ntfy selbst lag, wäre nicht mehr zu sehen.
# "2>&1 >/dev/null" (in dieser Reihenfolge) leitet stderr in die Substitution
# und wirft stdout weg.
# Die Zuweisung steht direkt in der if-Bedingung: so entscheidet der Exit-Status
# des Kommandos, und die Ausgabe landet trotzdem in der Variablen. Ein separates
# "$?" danach wäre brüchig (und ShellCheck SC2181 weist zu Recht darauf hin).
if err_default="$(curl_config | curl -K - "${CURL_ARGS[@]}" "$URL" 2>&1 >/dev/null)"; then
    echo "apphost-notify-failure: Meldung an ntfy zugestellt." >&2
elif [[ -f "$CA_FILE" ]]; then
    if err_localca="$(curl_config | curl -K - "${CURL_ARGS[@]}" --cacert "$CA_FILE" "$URL" 2>&1 >/dev/null)"; then
        echo "apphost-notify-failure: Meldung an ntfy zugestellt (lokale CA)." >&2
    else
        echo "apphost-notify-failure: Zustellung an ntfy fehlgeschlagen." >&2
        echo "  mit System-Truststore: ${err_default:-（keine Ausgabe）}" >&2
        echo "  mit lokaler CA:        ${err_localca:-（keine Ausgabe）}" >&2
    fi
else
    echo "apphost-notify-failure: Zustellung an ntfy fehlgeschlagen." >&2
    echo "  curl: ${err_default:-（keine Ausgabe）}" >&2
fi

exit 0
