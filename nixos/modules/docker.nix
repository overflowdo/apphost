{ config, pkgs, lib, ... }:
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
      flags    = [ "--all" "--volumes" "--filter" "until=720h" ];
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

  # dockremap für sichere container in jedem fall. UID/GID 100000-165536 für rootless remap
  users.users.dockremap = {
    isSystemUser = true;
    group        = "dockremap";
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
  };
  users.groups.dockremap = {};

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
    script      = ''
      docker ps --format "{{.Image}}" | sort -u | while read image; do
        ${pkgs.trivy}/bin/trivy image --severity HIGH,CRITICAL \
          --exit-code 0 --no-progress "$image" 2>/dev/null || true
      done | tee /var/log/docker-security-scan.log
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
