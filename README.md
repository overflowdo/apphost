# Self‑hosted Cloud‑ & Homelab‑Stack

Deklarativ provisionierter Server (**NixOS + Docker Compose**) mit zentralem Reverse Proxy (Traefik), Single‑Sign‑On (Authelia), Monitoring und einer Reihe selbst gehosteter Dienste – installiert als gehärtete VM auf einer Proxmox‑Node.

Die vollständige Installations‑ und Betriebsanleitung liegt in **[Installationsanleitung.md](Installationsanleitung.md)**.

## Struktur

| Pfad                                       | Inhalt                                                                                                   |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| [`docker-compose.yml`](docker-compose.yml) | Haupt‑Einstiegspunkt: definiert die Docker‑Netzwerke und bindet alle Service‑Stacks per `include` ein.  |
| [`compose/`](compose/)                     | Die einzelnen Service‑Stacks, nach Kategorie gruppiert (siehe unten).                                    |
| [`config/`](config/)                       | Konfigurationsdateien der Dienste (Traefik, Authelia, Prometheus, Grafana, Homepage, …).                |
| [`nixos/`](nixos/)                         | NixOS‑Systemkonfiguration: Flake, `disko`‑Partitionierung, Härtungs‑Module und `install.sh`.            |
| [`scripts/`](scripts/)                     | Betriebs‑ und Secret‑Skripte (Proxmox‑Härtung, Secret‑Generierung, Tor‑Onion‑Adresse anzeigen).         |
| [`renovate.json`](renovate.json)           | Renovate‑Konfiguration für automatische Container‑Image‑Updates.                                         |
| [`Quellen.md`](Quellen.md)                 | Externe Quellen und Referenzen zur Dokumentation.                                                        |

## Enthaltene Dienste

| Kategorie        | Dienste                                                                 |
| ---------------- | ---------------------------------------------------------------------- |
| Infrastruktur    | Traefik (Reverse Proxy), Authelia (SSO/OIDC)                           |
| Cloud            | OpenCloud, Collabora Online                                            |
| Medien           | Jellyfin, Immich                                                       |
| Dokumente        | Paperless‑ngx, BentoPDF                                                |
| Monitoring       | Prometheus, Grafana, Loki, Alertmanager, node/cAdvisor‑Exporter       |
| Kommunikation    | ntfy (Push), Bichon (Mail‑Archiv)                                      |
| Tools            | Homepage (Dashboard), Vaultwarden, OpenSpeedTest                       |

## Kurzüberblick Installation

1. Proxmox‑Node bereitstellen und mit `scripts/proxmox-harden.sh` härten.
2. NixOS‑Minimal‑ISO in Proxmox laden und eine VM anlegen (UEFI/OVMF + TPM, Secure Boot).
3. In der VM das Repository klonen und `nixos/install.sh` ausführen – partitioniert, installiert NixOS, richtet Secure Boot ein, fragt die `.env`‑Werte ab und generiert die restlichen Secrets automatisch.
4. Nach dem Neustart `docker compose up -d` – der komplette Stack startet hinter Traefik.

Details, inklusive Betrieb und Wartung (Updates, Backups, AIDE, Renovate), siehe [Installationsanleitung.md](Installationsanleitung.md).
