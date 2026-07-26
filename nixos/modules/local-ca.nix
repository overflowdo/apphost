# Erzeugt DEKLARATIV eine lokale CA + ein Server-Zertifikat für die lokale Domain
# (Standard: apphost.lan + *.apphost.lan) nach /var/lib/apphost-ca – automatisch
# beim Boot bzw. bei `nixos-rebuild switch`, sofern noch nicht vorhanden.
#
# Warum: im rein lokalen Betrieb (kein Let's Encrypt) liefert Traefik sonst nur ein
# generisches self-signed Zertifikat, dem die OIDC-Backends (Grafana/Immich/
# Paperless) beim Server-zu-Server-Token-Call NICHT vertrauen. Mit einer eigenen CA:
#   - Traefik liefert ein von dieser CA signiertes Zertifikat aus
#     (config/traefik/dynamic/tls.yml -> defaultCertificate, Mount /certs-local).
#   - Die OIDC-Backends bekommen die CA gemountet und vertrauen ihr
#     (NODE_EXTRA_CA_CERTS / REQUESTS_CA_BUNDLE / GF_..._TLS_CLIENT_CA).
#   - Importiert man local-ca.crt in Browser/Handy, sind auch dort alle
#     Zertifikatswarnungen weg (Alias `ca` gibt die Datei aus).
#
# Kein Pi-hole nötig: reine lokale Krypto. Idempotent – bestehende Schlüssel bleiben.
{ lib, pkgs, ... }:
let
  domain    = "apphost.lan";   # <- bei Domainwechsel hier anpassen
  caDir     = "/var/lib/apphost-ca";
  # userns-remap: der Traefik-Container läuft als root (UID 0) -> Host-UID = Basis.
  # Muss zur dockremap-Basis in modules/docker.nix passen (Standard 100000).
  remapBase = 100000;
in {
  systemd.services.apphost-local-ca = {
    description = "Generate local CA + server certificate for ${domain}";
    wantedBy = [ "multi-user.target" ];
    before   = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssl pkgs.coreutils ];
    script = ''
      set -euo pipefail
      mkdir -p ${caDir}
      cd ${caDir}

      # 1. CA (Schlüssel + selbstsigniertes Root-Zertifikat, 10 Jahre)
      if [ ! -f ca.key ] || [ ! -f local-ca.crt ]; then
        openssl genrsa -out ca.key 4096
        openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
          -subj "/O=AppHost/CN=AppHost Local CA" -out local-ca.crt
      fi

      # 2. Server-Zertifikat für ${domain} + *.${domain} (825 Tage, von der CA signiert)
      if [ ! -f apphost.key ] || [ ! -f apphost.crt ]; then
        openssl genrsa -out apphost.key 2048
        openssl req -new -key apphost.key -subj "/CN=${domain}" -out apphost.csr
        printf 'subjectAltName=DNS:${domain},DNS:*.${domain}\nextendedKeyUsage=serverAuth\n' > san.ext
        openssl x509 -req -in apphost.csr -CA local-ca.crt -CAkey ca.key \
          -CAcreateserial -days 825 -sha256 -extfile san.ext -out apphost.crt
        rm -f apphost.csr san.ext
      fi

      # 3. Rechte:
      #    - local-ca.crt ist öffentlich -> 0644, jeder Container darf es lesen.
      #    - apphost.key/.crt liest der Traefik-Container (userns-root = ${toString remapBase}).
      #    - ca.key ist der Vertrauensanker -> nur root, nie gemountet.
      chmod 0644 local-ca.crt apphost.crt
      chown ${toString remapBase}:${toString remapBase} apphost.key apphost.crt
      chmod 0640 apphost.key
      chmod 0600 ca.key
    '';
  };
}
