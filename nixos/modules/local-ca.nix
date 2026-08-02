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
  # Fallback-Domain. Die tatsächliche Domain kommt zur Laufzeit aus
  # /opt/monorepo/.env (DOMAIN=...) – dieselbe Quelle, aus der auch Traefik und
  # die Compose-Router ihre Hostnamen ziehen. Sonst passt das Default-Zertifikat
  # bei abweichender Domain nicht (sniStrict: false kaschiert das nur).
  fallbackDomain = "apphost.lan";
  envFile   = "/opt/monorepo/.env";
  caDir     = "/var/lib/apphost-ca";
  # userns-remap: der Traefik-Container läuft als root (UID 0) -> Host-UID = Basis.
  remapBase = (import ../lib/userns.nix).remapBase;
in {
  systemd.services.apphost-local-ca = {
    description = "Generate local CA + server certificate for the local domain";
    wantedBy = [ "multi-user.target" ];
    before   = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssl pkgs.coreutils pkgs.gnused pkgs.gnugrep ];
    script = ''
      set -euo pipefail

      # Domain aus der .env lesen (dieselbe, die Compose/Traefik verwenden).
      # "|| true": fehlt die .env (Erstinstallation), greift der Fallback unten,
      # statt dass der Dienst wegen set -e/pipefail abbricht.
      DOMAIN="$( { sed -n "s/^[[:space:]]*DOMAIN[[:space:]]*=[[:space:]]*//p" ${envFile} 2>/dev/null \
                   || true; } | head -1 | tr -d "\"' \r")"
      DOMAIN="''${DOMAIN:-${fallbackDomain}}"
      echo "local-ca: Domain = $DOMAIN"

      mkdir -p ${caDir}
      cd ${caDir}

      # Passt ein vorhandenes Server-Zertifikat nicht mehr zur Domain (z.B. weil
      # DOMAIN in der .env geändert wurde), wird es neu ausgestellt. Die CA selbst
      # bleibt bestehen – sonst müsste sie auf allen Geräten neu importiert werden.
      if [ -f apphost.crt ] \
         && ! openssl x509 -in apphost.crt -noout -text | grep -q "DNS:$DOMAIN\b"; then
        echo "local-ca: Zertifikat passt nicht zu $DOMAIN -> wird neu ausgestellt"
        rm -f apphost.crt apphost.key
      fi

      # 1. CA (Schlüssel + selbstsigniertes Root-Zertifikat, 10 Jahre).
      #    basicConstraints CA:TRUE + keyUsage keyCertSign sind PFLICHT, sonst
      #    lehnen Browser die CA ab (auch wenn Go/Grafana sie via CertPool
      #    akzeptiert -> "nicht sicher" trotz Import). Explizit via -addext, weil
      #    der Default je nach openssl.cnf diese Extensions NICHT setzt.
      if [ ! -f ca.key ] || [ ! -f local-ca.crt ]; then
        openssl genrsa -out ca.key 4096
        openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
          -subj "/O=AppHost/CN=AppHost Local CA" \
          -addext "basicConstraints=critical,CA:TRUE" \
          -addext "keyUsage=critical,keyCertSign,cRLSign" \
          -addext "subjectKeyIdentifier=hash" \
          -out local-ca.crt
      fi

      # 2. Server-Zertifikat für $DOMAIN + *.$DOMAIN (825 Tage, von der CA signiert)
      if [ ! -f apphost.key ] || [ ! -f apphost.crt ]; then
        openssl genrsa -out apphost.key 2048
        openssl req -new -key apphost.key -subj "/CN=$DOMAIN" -out apphost.csr
        {
          printf 'basicConstraints=CA:FALSE\n'
          printf 'keyUsage=critical,digitalSignature,keyEncipherment\n'
          printf 'extendedKeyUsage=serverAuth\n'
          printf 'subjectAltName=DNS:%s,DNS:*.%s\n' "$DOMAIN" "$DOMAIN"
          printf 'subjectKeyIdentifier=hash\n'
          printf 'authorityKeyIdentifier=keyid,issuer\n'
        } > san.ext
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
