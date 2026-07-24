#!/bin/sh
# Wird vom traefik-init-Container bei jedem Start ausgeführt (siehe
# compose/infrastructure/traefik.yml). Rendert /src/traefik.template.yml nach
# /rendered/traefik.yml, indem die Platzhalter ${DOMAIN}, ${ACME_EMAIL} und
# ${ACME_DNS_PROVIDER} aus der Umgebung (aus der .env via Compose) eingesetzt
# werden.
#
# Warum überhaupt gerendert wird: Traefiks statische Konfiguration stammt aus
# genau EINER Quelle (Datei ODER CLI ODER Env) – die Quellen sind gegenseitig
# ausschließend. Sobald eine traefik.yml existiert, werden TRAEFIK_*-Env-Vars
# für die statische Konfiguration ignoriert. Deshalb müssen DOMAIN/ACME_EMAIL
# vor dem Start in die Datei geschrieben werden.
#
# Bewusst nur POSIX sh + sed (busybox), damit das unverändert im schlanken,
# alpine-basierten Traefik-Image läuft – kein zusätzliches Image, kein
# envsubst/gettext nötig.
set -eu

: "${DOMAIN:?DOMAIN ist nicht gesetzt (in .env eintragen)}"
: "${ACME_EMAIL:?ACME_EMAIL ist nicht gesetzt (in .env eintragen)}"
: "${ACME_DNS_PROVIDER:?ACME_DNS_PROVIDER ist nicht gesetzt (in .env eintragen)}"

TEMPLATE="/src/traefik.template.yml"
OUTPUT="/rendered/traefik.yml"

# Nur die drei bekannten Platzhalter ersetzen; alle anderen $-Zeichen bleiben
# unangetastet. Domain/E-Mail/Provider enthalten kein '|', daher als Trenner ok.
sed \
    -e "s|\${DOMAIN}|${DOMAIN}|g" \
    -e "s|\${ACME_EMAIL}|${ACME_EMAIL}|g" \
    -e "s|\${ACME_DNS_PROVIDER}|${ACME_DNS_PROVIDER}|g" \
    "$TEMPLATE" > "$OUTPUT"

echo "traefik-init: $OUTPUT gerendert (DOMAIN=${DOMAIN}, ACME_EMAIL=${ACME_EMAIL}, DNS=${ACME_DNS_PROVIDER})"
