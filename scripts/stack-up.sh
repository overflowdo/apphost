#!/usr/bin/env bash
# Startet den AppHost-Stack GESTAFFELT statt alles auf einmal.
#
# Warum: beim gleichzeitigen Erststart schreiben Immich, OpenCloud und Paperless
# zeitgleich auf die USB-Bulk-Platte und spiken den RAM – das hatte Host + VM
# gecrasht. Dieses Skript bringt die Dienste in Phasen hoch und wartet nach jeder
# Phase, bis die Container "healthy" (bzw. "running", wenn kein Healthcheck
# definiert ist) sind, bevor die nächste – vor allem die nächste USB-schwere –
# Phase startet.
#
# Aufruf:  bash scripts/stack-up.sh   (bzw. der Alias `up`)
# Idempotent: bereits laufende Container bleiben laufen.
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/monorepo}"
PHASE_TIMEOUT="${PHASE_TIMEOUT:-180}"   # max. Wartezeit pro Phase (Sekunden)
cd "$COMPOSE_DIR"

dc() { docker compose "$@"; }

# Wartet, bis alle übergebenen SERVICES bereit sind (healthy, oder running falls
# kein Healthcheck). Bricht nach PHASE_TIMEOUT ab und fährt trotzdem fort.
wait_ready() {
    local start now cid health state pending svc
    local -a haenger
    start=$(date +%s)
    while :; do
        pending=0
        haenger=()
        for svc in "$@"; do
            cid=$(dc ps -q "$svc" 2>/dev/null | head -1)
            if [[ -z "$cid" ]]; then pending=1; haenger+=("$svc (kein Container)"); continue; fi
            health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo none)
            state=$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo missing)
            case "$health" in
                healthy) : ;;
                none)    [[ "$state" == running ]] || { pending=1; haenger+=("$svc ($state)"); } ;;
                *)       pending=1; haenger+=("$svc ($state, health: $health)") ;;
            esac
        done
        [[ "$pending" -eq 0 ]] && return 0
        now=$(date +%s)
        if [[ $((now - start)) -ge "$PHASE_TIMEOUT" ]]; then
            # Nicht nur "Timeout" melden: ohne die Namen sucht man den Grund
            # anschließend im gesamten Stack. Genau das ist passiert, als
            # backup-trigger im Kreisel lief (fehlendes /srv/hook) und die
            # Phase 180 Sekunden lang wortlos wartete.
            echo "    ! Timeout (${PHASE_TIMEOUT}s) – nicht bereit:"
            printf '        %s\n' "${haenger[@]}"
            echo "      Ursache steht im Log:  docker logs ${haenger[0]%% *} --tail 50"
            echo "      Die nächste Phase startet trotzdem."
            return 0
        fi
        sleep 3
    done
}

ram() { LC_ALL=C free -m | awk '/^Mem/{printf "    RAM: %s/%s MB benutzt\n",$3,$2}'; }

phase() {
    local title="$1"; shift
    echo "==> ${title}"
    dc up -d "$@"
    wait_ready "$@"
    ram
}

# --- Pre-flight: fehlende Secrets erzeugen (idempotent) ---------------------
# Prüft ALLE per Bind-Mount eingehängten Secret-Dateien. Liegt in einer eigenen
# Datei, weil der Alias `up-all` (docker compose up -d) sie ebenfalls aufruft.
bash scripts/ensure-secrets.sh

# Wer hier fehlt, wird von `up` NIE gestartet – auch wenn er in der
# include-Liste von docker-compose.yml steht. Genau das war mit backup-trigger
# passiert: der Container existierte nicht, das Dashboard zeigte einen roten
# Punkt und Traefik ein 404, weil es ohne Container keinen Router gibt.
# Die CI gleicht diese Liste seitdem gegen den gerenderten Stack ab
# (.github/workflows/ci.yml, Schritt "Startphasen gegen den Stack abgleichen").
# Nicht aufzuführen sind nur Container, die per depends_on mitkommen –
# socket-proxy hängt an Traefik, traefik-init und alloy-init an ihren Diensten.
phase "Phase 1  – Reverse Proxy + SSO"        traefik authelia
phase "Phase 2  – leichte Dienste (SSD)"      homepage ntfy bichon vaultwarden openspeedtest bento-pdf ca-download radicale grocy backup-trigger
phase "Phase 3  – Monitoring"                 prometheus grafana loki alertmanager node-exporter cadvisor alloy
phase "Phase 4  – Immich: DB + Cache"         immich-postgres immich-redis
phase "Phase 4b – Immich: Server"             immich-server
phase "Phase 4c – Immich: Machine Learning"   immich-machine-learning
phase "Phase 5  – OpenCloud + Collabora"      collabora opencloud
phase "Phase 5b – OpenCloud: Collaboration"   collaboration
phase "Phase 6  – Paperless"                  paperless-redis paperless
phase "Phase 7  – Jellyfin + Redis-Exporter"  jellyfin immich-redis-exporter paperless-redis-exporter

echo
echo "Fertig – Gesamtstatus:"
dc ps
