# Externe Quellen zur Apphost-Dokumentation

## 1. Betriebssystem, Boot & Firmware

- **NixOS (deklarativ, reproduzierbar, Generationen/Rollback)**: <https://nixos.org/manual/nixos/stable/> - offizielles NixOS-Handbuch.
- **Nix Flakes**: <https://nix.dev/concepts/flakes.html> - offizielle Einführung; Referenz im Nix-Manual: <https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html>.
- **disko (deklarative Partitionierung)**: <https://github.com/nix-community/disko> - Projekt-Repo inkl. Doku (`docs/`).
- **Btrfs / zstd-Kompression**: <https://btrfs.readthedocs.io/en/latest/Compression.html> - offizielle Btrfs-Doku zur Kompression; Mount-Optionen: <https://btrfs.readthedocs.io/en/latest/ch-mount-options.html>.
- **Secure Boot mit lanzaboote**: <https://github.com/nix-community/lanzaboote> - Secure Boot & Measured Boot für NixOS; Doku: <https://nix-community.github.io/lanzaboote/>.
- **sbctl (Secure-Boot-Key-Management)**: <https://github.com/Foxboron/sbctl> - offizielles Repo (`enroll-keys`, `status`).
- **UEFI Secure Boot (Konzept)**: <https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot> - gut gepflegte Referenz; formaler Standard: UEFI-Spezifikation des UEFI Forum (<https://uefi.org/specifications>).
- **TPM 2.0**: <https://trustedcomputinggroup.org/resource/tpm-library-specification/> - TCG TPM-2.0-Spezifikation.
- **Kernel Lockdown / Module-Signatur / Sicherheits-Sysctls**: <https://docs.kernel.org/admin-guide/> - Linux-Kernel Admin-Guide (u. a. `module.sig_enforce`, `init_on_alloc`/`init_on_free`, IOMMU, CPU-Mitigationen unter `admin-guide/hw-vuln/`).
- **CPU-Mitigationen (Spectre/Meltdown/MDS)**: <https://docs.kernel.org/admin-guide/hw-vuln/index.html> - Hardware-Vulnerabilities-Doku des Kernels.
- **ASLR / Kernel-Härtung-Parameter**: <https://docs.kernel.org/admin-guide/sysctl/kernel.html> - `kernel.*`-Sysctls (u. a. `randomize_va_space`, `kptr_restrict`).
- **CIS Benchmarks**: <https://www.cisecurity.org/cis-benchmarks> - Center for Internet Security, Hardening-Benchmarks.

## 2. Netzwerk, Firewall & Krypto

- **nftables**: <https://wiki.nftables.org/> - offizielles Netfilter/nftables-Wiki.
- **Default-Deny / Firewall-Policy**: NIST SP 800-41 Rev. 1, „Guidelines on Firewalls and Firewall Policy": <https://csrc.nist.gov/pubs/sp/800/41/r1/final> - empfiehlt explizit Default-Deny.
- **Fail2ban**: <https://github.com/fail2ban/fail2ban> - offizielles Repo (inkl. Wiki).
- **DNS-over-TLS (DoT)**: RFC 7858 - <https://www.rfc-editor.org/rfc/rfc7858>.
- **DNSSEC**: RFC 4033 (Einstieg der Reihe 4033/4034/4035) - <https://www.rfc-editor.org/rfc/rfc4033>.
- **Quad9 (Resolver)**: <https://www.quad9.net/> - offizielle Website.
- **Cloudflare DNS / 1.1.1.1**: <https://developers.cloudflare.com/1.1.1.1/> - offizielle Cloudflare-Doku zum Resolver.
- **NTS (Network Time Security)**: RFC 8915 - <https://www.rfc-editor.org/rfc/rfc8915>.
- **WireGuard**: <https://www.wireguard.com/> - offizielle Website inkl. Whitepaper.
- **OPNsense**: <https://docs.opnsense.org/> - offizielle Dokumentation.
- **OpenSSH (Härtung, Key-Auth, Post-Quantum)**: <https://www.openssh.com/releasenotes.html> - Release Notes (PQ-Kex `sntrup761x25519`, `mlkem768x25519`); Konfig-Manpages: <https://man.openbsd.org/sshd_config>.
- **GrapheneOS**: <https://grapheneos.org/> - offizielle Website/Doku.

## 3. Tor / Zensurresistenter Zugriff

- **Tor Onion Services v3**: <https://community.torproject.org/onion-services/> - offizielle Tor-Project-Doku; Überblick: <https://community.torproject.org/onion-services/overview/>.
- **Tor-Spezifikation (Onion v3)**: <https://spec.torproject.org/rend-spec-v3> - technische Spezifikation.

## 4. Reverse Proxy, Authentifizierung & Zertifikate

- **Traefik**: <https://doc.traefik.io/traefik/> - offizielle Dokumentation.
- **Traefik ACME / Let's Encrypt**: <https://doc.traefik.io/traefik/reference/install-configuration/tls/certificate-resolvers/acme/> - Certificate Resolvers (DNS-01).
- **Traefik ForwardAuth-Middleware**: <https://doc.traefik.io/traefik/middlewares/http/forwardauth/>.
- **Unterstützte DNS-Provider (lego)**: <https://go-acme.github.io/lego/dns/> - Traefik nutzt intern lego; Liste aller DNS-Provider.
- **ACME-Protokoll**: RFC 8555 - <https://www.rfc-editor.org/rfc/rfc8555>.
- **ACME DNS-01-Challenge (Erklärung)**: <https://letsencrypt.org/docs/challenge-types/> - Challenge-Typen bei Let's Encrypt.
- **Let's Encrypt**: <https://letsencrypt.org/> - offizielle Website.
- **Authelia**: <https://www.authelia.com/> - offizielle Doku; OIDC-Provider: <https://www.authelia.com/configuration/identity-providers/openid-connect/provider/>; Forward-Auth: <https://www.authelia.com/integration/proxies/forwarded-headers/>.
- **OpenID Connect (OIDC)**: OpenID Connect Core 1.0 - <https://openid.net/specs/openid-connect-core-1_0.html>.
- **OAuth 2.0 (Grundlage von OIDC)**: RFC 6749 - <https://www.rfc-editor.org/rfc/rfc6749>.
- **Argon2id (Passwort-Hashing)**: RFC 9106 - <https://www.rfc-editor.org/rfc/rfc9106>.
- **bcrypt**: kein offizieller RFC/Standard; kanonische Quelle ist das USENIX-Paper Provos & Mazières, „A Future-Adaptable Password Scheme" (1999) - <https://www.usenix.org/legacy/events/usenix99/provos.html>.
- **Keycloak (zum Vergleich erwähnt)**: <https://www.keycloak.org/documentation>.
- **Envoy Gateway (ersetzt)**: <https://gateway.envoyproxy.io/>.
- **Kubernetes Gateway API**: <https://gateway-api.sigs.k8s.io/>.
- **Docker Socket Proxy**: <https://github.com/Tecnativa/docker-socket-proxy> - eingeschränkter, nur-lesender Zugriff auf die Docker-API.

## 5. Container, Härtung & Supply-Chain

- **Docker Compose**: <https://docs.docker.com/compose/> - offizielle Doku.
- **Compose `include` / Mehrere Compose-Dateien**: <https://docs.docker.com/compose/how-tos/multiple-compose-files/include/>.
- **`no-new-privileges`, `read_only`, `cap_drop`/`cap_add`, `security_opt`**: <https://docs.docker.com/reference/compose-file/services/> - Compose-Service-Referenz.
- **Linux Capabilities / Runtime-Privilegien**: <https://docs.docker.com/engine/containers/run/#runtime-privilege-and-linux-capabilities>.
- **tmpfs in Docker**: <https://docs.docker.com/engine/storage/tmpfs/>.
- **Ressourcenlimits (CPU/Memory)**: <https://docs.docker.com/engine/containers/resource_constraints/>.
- **Seccomp (Default-Profil)**: <https://docs.docker.com/engine/security/seccomp/>.
- **AppArmor (mit Docker)**: <https://docs.docker.com/engine/security/apparmor/>.
- **User-Namespace-Remapping**: <https://docs.docker.com/engine/security/userns-remap/>.
- **Kata Containers**: <https://katacontainers.io/> - Projektseite; Doku: <https://github.com/kata-containers/kata-containers/tree/main/docs>.
- **gVisor**: <https://gvisor.dev/docs/>.
- **Trivy (CVE-Scan)**: <https://trivy.dev/> - offizielle Doku; Repo: <https://github.com/aquasecurity/trivy>.
- **Renovate (RenovateBot)**: <https://docs.renovatebot.com/> - offizielle Doku.
- **Linux Audit Daemon (auditd)**: <https://github.com/linux-audit/audit-documentation/wiki> - Upstream-Doku-Wiki.
- **AIDE (Integritätsprüfung)**: <https://aide.github.io/> - offizielle Website; Repo: <https://github.com/aide/aide>.

## 6. Monitoring & Alerting

- **Prometheus**: <https://prometheus.io/docs/> - offizielle Doku.
- **Grafana Loki**: <https://grafana.com/docs/loki/latest/>.
- **Grafana**: <https://grafana.com/docs/grafana/latest/>.
- **Alertmanager**: <https://prometheus.io/docs/alerting/latest/alertmanager/>.
- **node_exporter**: <https://github.com/prometheus/node_exporter>.
- **cAdvisor**: <https://github.com/google/cadvisor>.
- **Grafana Alloy**: <https://grafana.com/docs/alloy/latest/> - Log-Collector (Promtail-Nachfolger, Promtail ist seit März 2026 EOL).
- **ntfy (Self-hosted Push)**: <https://docs.ntfy.sh/> - offizielle Doku.

## 7. Speicher & Cache

- **Garage (S3-kompatibel)**: <https://garagehq.deuxfleurs.fr/> - offizielle Doku (Deuxfleurs).
- **Valkey (In-Memory-Datastore)**: <https://valkey.io/> - offizielle Website; Hintergrund Linux Foundation: <https://www.linuxfoundation.org/press/linux-foundation-launches-open-source-valkey-community>.
- **Dragonfly (zum Vergleich erwähnt)**: <https://www.dragonflydb.io/docs>.

## 8. Virtualisierung & Backups

- **Proxmox VE**: <https://pve.proxmox.com/pve-docs/> - offizielle Doku; Wiki: <https://pve.proxmox.com/wiki/Main_Page>.
- **Proxmox Backup & Restore (vzdump)**: <https://pve.proxmox.com/wiki/Backup_and_Restore>; Manpage: <https://pve.proxmox.com/pve-docs/vzdump.1.html>.
- **3-2-1-Backup-Regel**: CISA, „Back Up Your Data" / „Data Backup Options" - <https://www.cisa.gov/audiences/small-and-medium-businesses/secure-your-business/back-up-business-data>.

## 9. Installierte Applikationen

- **Immich**: <https://immich.app/> (Doku: <https://immich.app/docs>).
- **Jellyfin**: <https://jellyfin.org/docs/>.
- **Paperless-ngx**: <https://docs.paperless-ngx.com/>.
- **BentoPDF**: <https://github.com/alam00000/bentopdf> (Doku: <https://www.bentopdf.com/docs/self-hosting/>).
- **OpenCloud**: <https://docs.opencloud.eu/> (Website: <https://opencloud.eu/>).
- **Collabora Online**: <https://www.collaboraonline.com/> (Doku: <https://sdk.collaboraonline.com/>).
- **Euro-Office (Fork von ONLYOFFICE, nicht Collabora)**: <https://github.com/Euro-Office>.
- **Forgejo**: <https://forgejo.org/docs/latest/>.
- **Vaultwarden**: <https://github.com/dani-garcia/vaultwarden/wiki> (Community-Server-Info: <https://www.vaultwarden.net/>).
- **Bichon (Mail-Archiver)**: <https://github.com/rustmailer/bichon>.
- **Homepage (Dashboard)**: <https://gethomepage.dev/>.
