{ config, pkgs, lib, ... }:
let
  userns = import ../lib/userns.nix;
in
{
  # Kernel-Module für Container-Runtimes
  boot.kernelModules = [
    "vhost_vsock"   # Für Kata Containers (vsock-Kommunikation)
    "vhost_net"     # Für Kata Containers Netzwerk
    "kvm"           # KVM-Virtualisierung (Basis für Kata)
  ];

  # Docker Daemon-Konfiguration
  virtualisation.docker = {
    enable     = true;
    autoPrune  = {
      enable   = true;
      dates    = "weekly";
      # KEIN "--volumes" und kein "--all":
      #  - Docker lehnt "--volumes" zusammen mit "--filter until=..." ab
      #    ("The 'until' filter is not supported with '--volumes'"). Der Dienst
      #    brach damit bei JEDEM Lauf sofort ab und hat nie etwas aufgeräumt –
      #    aufgefallen wäre das erst über HostDiskSpaceLow.
      #  - "--volumes" ist hier ohnehin gefährlich: bei gestopptem Stack gelten
      #    alle Volumes als unbenutzt, das Kommando würde Immich-, Paperless-
      #    und Vaultwarden-Daten löschen.
      #  - "--all" würde auch Images entfernen, die nur gerade nicht laufen.
      # Übrig bleibt das Sichere: gestoppte Container, ungenutzte Netzwerke,
      # dangling Images und Build-Cache älter als 30 Tage.
      flags    = [ "--filter" "until=720h" ];
    };

    # Docker-Daemon Optionen
    daemon.settings = {
      runtimes = {
        # gVisor KVM-Platform (systrap geht nicht wegen kernel.yama.ptrace_scope=2)
        runsc = {
          path        = "${pkgs.gvisor}/bin/runsc";
          runtimeArgs = [
            "--platform=kvm"
            "--host-uds=open"
            "--network=sandbox"
            "--debug=false"
            "--file-access=exclusive"
          ];
        };
      };

      # Default ohne gVisor/Kata. Kompatibel mit allen Containern und Servern; Es gab vereinzelnt Probleme
      "default-runtime" = "runc";

      # uid remap für garantiert rootless container
      "userns-remap" = "default";

      iptables    = true;
      ip6tables   = true;
      "ip-forward" = true;
      "userland-proxy" = false;  # Keine Userland-Proxy sondern direktes iptables

      # DNS für Container explizit auf den Pi-hole (.5). Ohne das verwirft Docker
      # den systemd-resolved-Stub (127.0.0.53) aus /etc/resolv.conf (Loopback ist
      # im Container nicht erreichbar) und fällt auf 8.8.8.8 zurück -> Container
      # lösen *.apphost.lan NICHT auf und der OIDC-Token-Call scheitert, obwohl der
      # Host den Namen kennt. FritzBox (.1) als Fallback, falls der Pi-hole down ist.
      dns = [ "192.168.178.5" "192.168.178.1" ];

      # Sauberes logging mit rotation & compression
      "log-driver" = "json-file";
      "log-opts" = {
        "max-size" = "10m";
        "max-file" = "5";
        "compress" = "true";
        "labels"   = "service,environment";
      };

      # Zugriff nur via Unix-Socket (keine TCP-Ports exposeen)
      hosts = [ "unix:///var/run/docker.sock" ];

      "containerd" = "/run/containerd/containerd.sock";

      # Metrics auf der docker0-Bridge exposen, damit der Prometheus-Container
      # sie über die Gateway-IP 172.17.0.1 scrapen kann (127.0.0.1 wäre nur
      # host-lokal und aus dem Container nicht erreichbar).
      metrics-addr  = "172.17.0.1:9323";
      # containerd-snapshotter ist inkompatibel mit userns-remap (Docker verweigert sonst den Start);
    };
  };

  # gVisor, Kata-Runtime & trivy
  environment.systemPackages = with pkgs; [
    gvisor
    kata-runtime
    trivy
  ];

  # dockremap für sichere container in jedem fall. UID/GID-Bereich siehe ../lib/userns.nix
  users.users.dockremap = {
    isSystemUser = true;
    group        = "dockremap";
    subUidRanges = [{ startUid = userns.remapBase; count = userns.remapCount; }];
    subGidRanges = [{ startGid = userns.remapBase; count = userns.remapCount; }];
  };
  users.groups.dockremap = {};

  # Auch der Prune-Dienst meldet sich, wenn er scheitert (Template-Unit in
  # modules/backup.nix). Vorher wäre ein Dauerfehler nur über den vollen
  # Datenträger aufgefallen.
  systemd.services.docker-prune.onFailure = [ "apphost-notify-failure@%n.service" ];

  systemd.services.docker = {
    serviceConfig = {
      # Resource Limits für Docker-Daemon selbst
      LimitNOFILE = 1048576;
      LimitNPROC  = "infinity";
      LimitCORE   = 0;
    };
  };

  # Docker-Socket nur für docker-Gruppe zugänglich
  systemd.tmpfiles.rules = [
    "d /run/docker 0750 root docker -"
    # Traefik-Access-Log (fail2ban-Jail traefik-auth in modules/security.nix liest
    # es). Der Traefik-Container läuft als Container-root -> Host-UID = remapBase.
    "d /var/log/traefik 0750 ${toString userns.remapBase} ${toString userns.remapBase} -"
  ];

  # Containerd (für Kata Containers)
  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins."io.containerd.grpc.v1.cri" = {
        sandboxImage = "registry.k8s.io/pause:3.9";
        containerd.runtimes = {
          kata-runtime = {
            runtimeType = "io.containerd.kata.v2";
            options.ConfigPath = "${pkgs.kata-runtime}/share/defaults/kata-containers/configuration.toml";
          };
        };
      };
    };
  };

  # containerd-Dienst braucht Zugriff auf den kata
  systemd.services.containerd.path = [ pkgs.kata-runtime ];

  # Automatische Docker-Sicherheits-Scans
  systemd.services.docker-security-scan = {
    description = "Weekly Docker Image Security Scan";
    startAt     = "Mon 02:00";
    # Fehlschlag per Push melden (Template-Unit in modules/backup.nix).
    # ACHTUNG, was das heißt: trivy läuft bewusst mit --exit-code 0, der Scan
    # ist informativ. Diese Unit schlägt also NICHT bei Funden fehl, sondern
    # nur, wenn der Scan selbst nicht laufen kann (Docker weg, trivy kaputt,
    # Log nicht schreibbar). Für die Funde selbst gibt es bewusst keinen Alarm
    # – bei wöchentlich neuen CVEs wäre das ein Dauerton. Stattdessen steht
    # die Anzahl am Ende des Logs.
    onFailure   = [ "apphost-notify-failure@%n.service" ];
    # jq: der Scan zaehlt jetzt Funde statt Textzeilen (siehe unten).
    path = [ pkgs.docker pkgs.trivy pkgs.jq pkgs.coreutils ];
    script      = ''
      LOG=/var/log/docker-security-scan.log
      : > "$LOG"
      crit=0
      high=0

      # Vorher stand hier `grep -c "HIGH"` bzw. `grep -c "CRITICAL"` ueber der
      # Tabellenausgabe. Das zaehlt ZEILEN, die das Wort enthalten – also auch
      # Kopfzeilen, Paketnamen und CVE-Beschreibungen, in denen "CRITICAL"
      # vorkommt. Die Zahl unter "Zusammenfassung" war damit frei erfunden, und
      # zwar in beide Richtungen: Mehrfachtreffer pro Zeile fehlten, dafuer
      # zaehlte jede erwaehnende Zeile mit. Jetzt kommt sie aus dem JSON, das
      # trivy ohnehin erzeugen kann – ein Lauf je Image, kein zweiter Durchgang.
      for image in $(docker ps --format "{{.Image}}" | sort -u); do
        json=$(trivy image --severity HIGH,CRITICAL --exit-code 0 \
                 --no-progress --format json "$image" 2>/dev/null || echo '{}')
        c=$(printf '%s' "$json" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' 2>/dev/null || echo 0)
        h=$(printf '%s' "$json" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")]     | length' 2>/dev/null || echo 0)
        crit=$((crit + c))
        high=$((high + h))

        printf '\n=== %s  (CRITICAL=%s HIGH=%s)\n' "$image" "$c" "$h" >> "$LOG"
        # Nur die Zeilen, die man tatsaechlich braucht – inklusive der Frage,
        # ob es ueberhaupt einen Fix gibt. Ohne die ist eine CVE-Liste nur eine
        # Liste.
        printf '%s' "$json" \
          | jq -r '.Results[]?.Vulnerabilities[]?
                   | "  \(.Severity)\t\(.VulnerabilityID)\t\(.PkgName) \(.InstalledVersion) -> \(.FixedVersion // "kein Fix verfuegbar")"' \
            2>/dev/null | sort -u >> "$LOG" || true
      done

      # Kurzfazit ans Ende, damit man nicht das ganze Log lesen muss.
      echo "" >> "$LOG"
      echo "Zusammenfassung: $crit CRITICAL, $high HIGH (Details: less $LOG)" | tee -a "$LOG"
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  # seccomp-Profil für Docker
  environment.etc."docker/seccomp-default.json".source =
    "${pkgs.docker}/etc/docker/seccomp-default.json";
}
