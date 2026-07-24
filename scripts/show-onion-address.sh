#!/usr/bin/env bash
# Prints the Tor hidden service .onion address.
set -euo pipefail

HOSTNAME_FILE=/var/lib/tor/hidden_service/hostname

ONION=$(docker exec tor cat "$HOSTNAME_FILE" 2>/dev/null || true)

if [[ -z "$ONION" ]]; then
    echo "ERROR: Could not read onion address. Is the tor container running?" >&2
    echo "       docker compose -f compose/infrastructure/tor.yml up -d" >&2
    exit 1
fi

echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║  Tor Onion-Adresse (Hidden Service v3)                                   ║"
echo "╠══════════════════════════════════════════════════════════════════════════╣"
echo "║  https://$ONION  ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo
echo "Wert für .env: TOR_DOMAIN=$ONION"
