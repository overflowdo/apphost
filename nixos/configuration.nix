{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./modules/security.nix
    ./modules/docker.nix
    ./modules/networking.nix
    ./modules/secureboot.nix
    ./modules/media-disk.nix
  ];

  # System
  system.stateVersion = "26.05";

  nixpkgs.config = {
    allowUnfree = false;
    allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "corefonts"
      "vista-fonts"
    ];
  };

  # Bootloader systemd-boot
  boot = {
    loader = {
      systemd-boot = {
        enable       = true;
        editor       = false;          # verhindert Passwort-Bypass
        consoleMode  = "max";
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
      timeout = 5;
    };

    # Hardened Kernel wurde mit 26.05 deaktiviert, weil er nicht mehr maintained wird. Stattdessen wird der Standard-Kernel mit Hardened-Optionen genutzt. Wenn der hardened Kernel wieder verfügbar ist, ggf wieder aktivieren?
    #kernelPackages = pkgs.linuxPackages_hardened;

    # Kernel-Module für Container-Betrieb
    kernelModules = [
      "br_netfilter"
      "overlay"
      "nf_conntrack"
      "vhost_vsock"   # Kata Containers braucht vsock
      "kvm_amd"       # oder kvm_intel je nach CPU
      "dm_crypt"
      # seit 26.05 müssen wir diese module scheinbar manuell laden, sonst funktioniert docker-compose up nicht mehr (er kann die nftables nicht erzeugen)
      "nf_nat"
      "iptable_nat"
      "iptable_filter"
      "ip6table_nat"
      "ip6table_filter"
      "xt_nat"
      "xt_MASQUERADE"
      "xt_addrtype"
      "xt_conntrack"
      "xt_multiport"
      "xt_tcpudp"
    ];

    # Ungenutzte/gefährliche Module blacklisten (CIS Benchmark)
    blacklistedKernelModules = [
      # Selten genutzte Netzwerk-Protokolle
      "dccp" "sctp" "rds" "tipc" "n-hdlc" "ax25" "netrom" "x25" "atm"
      "ieee802154" "rose" "econet" "af_802154" "ipx" "appletalk" "psnap"
      # Seltene Dateisysteme
      "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "udf"
      # Netzwerk-Dateisysteme
      "cifs" "nfs" "nfsv3" "nfsv4" "gfs2" "ksmbd"
      # Hardware
      "bluetooth" "btusb"
      "usb-storage" "uas" # Auskommentieren falls USB-Storage jemals gebraucht wird
      "firewire-core"
    ];

    # Kernel-Parameter – Härtung auf Boot-Ebene
    kernelParams = [
      # KASLR, SMEP, SMAP
      "randomize_va_space=2"
      "pti=on"                         # Page Table Isolation (Meltdown)
      "vsyscall=none"                  # Keine vsyscall-Page
      "debugfs=off"                    # Keine Debug-Informationen

      # volle Spectre/Meltdown Mitigations
      "spec_store_bypass_disable=on"
      "tsx=off"
      "tsx_async_abort=full,nosmt"
      "mds=full,nosmt"
      "l1tf=full,force"
      "retbleed=auto,nosmt"

      # Kernel Lockdown
      "lockdown=confidentiality"
      "module.sig_enforce=1"

      # IOMMU (verhindert DMA-Angriffe)
      "iommu=force"
      "amd_iommu=on"  
      "intel_iommu=on"
      "iommu.passthrough=0"

      # Heap-Schutz
      "page_alloc.shuffle=1"
      "page_poison=1"
      "slub_debug=FZP"
      "init_on_alloc=1"
      "init_on_free=1"

      # EFI/PCI
      "efi=disable_early_pci_dma"

      # Auditierung
      "audit=1"
    ];

    # Sysctls
    kernel.sysctl = {
      # Netzwerk-Härtung
      "net.ipv4.conf.all.rp_filter"                   = 1;
      "net.ipv4.conf.default.rp_filter"               = 1;
      "net.ipv4.conf.all.accept_source_route"         = 0;
      "net.ipv4.conf.default.accept_source_route"     = 0;
      "net.ipv6.conf.all.accept_source_route"         = 0;
      "net.ipv4.conf.all.send_redirects"              = 0;
      "net.ipv4.conf.default.send_redirects"          = 0;
      "net.ipv4.conf.all.accept_redirects"            = 0;
      "net.ipv4.conf.default.accept_redirects"        = 0;
      "net.ipv4.conf.all.secure_redirects"            = 0;
      "net.ipv4.conf.default.secure_redirects"        = 0;
      "net.ipv6.conf.all.accept_redirects"            = 0;
      "net.ipv6.conf.default.accept_redirects"        = 0;
      "net.ipv4.conf.all.log_martians"                = 1;
      "net.ipv4.conf.default.log_martians"            = 1;
      "net.ipv4.icmp_echo_ignore_broadcasts"          = 1;
      "net.ipv4.icmp_ignore_bogus_error_responses"    = 1;
      "net.ipv4.tcp_syncookies"                       = 1;
      "net.ipv4.tcp_rfc1337"                          = 1;
      "net.ipv4.tcp_timestamps"                       = 0;   # Verhindert Uptime-Fingerprinting
      "net.ipv4.tcp_fin_timeout"                      = 15;
      "net.ipv4.tcp_keepalive_time"                   = 300;
      "net.ipv4.tcp_keepalive_probes"                 = 5;
      "net.ipv4.tcp_keepalive_intvl"                  = 15;
      "net.ipv4.tcp_max_syn_backlog"                  = 4096;
      "net.ipv4.tcp_syn_retries"                      = 2;
      "net.ipv4.tcp_synack_retries"                   = 2;
      "net.core.bpf_jit_harden"                       = 2;
      "net.ipv4.conf.all.arp_ignore"                  = 1;
      "net.ipv4.conf.all.arp_announce"                = 2;
      "net.ipv4.neigh.default.gc_thresh3"             = 8192;
      "net.ipv4.neigh.default.gc_thresh2"             = 4096;
      "net.ipv4.neigh.default.gc_thresh1"             = 2048;

      # IPv6 Härtung
      "net.ipv6.conf.all.accept_ra"                   = 0;
      "net.ipv6.conf.default.accept_ra"               = 0;
      "net.ipv6.conf.all.autoconf"                    = 0;
      "net.ipv6.conf.default.autoconf"                = 0;

      # Container-Networking aktivieren
      "net.ipv4.ip_forward"                           = 1;
      "net.bridge.bridge-nf-call-iptables"            = 1;
      "net.bridge.bridge-nf-call-ip6tables"           = 1;

      # Kernel/Memory-Härtung
      "kernel.kptr_restrict"             = 2;      # Keine Kernel-Pointer-Leaks
      "kernel.dmesg_restrict"            = 1;      # dmesg nur für root
      "kernel.unprivileged_bpf_disabled" = 1;      # eBPF nur privilegiert
      "net.core.bpf_jit_enable"          = 0;       # BPF JIT deaktiviert
      "kernel.perf_event_paranoid"       = 3;      # Keine Perf-Events für normale User
      "kernel.randomize_va_space"        = 2;
      "vm.mmap_rnd_bits"                 = 32;
      "vm.mmap_rnd_compat_bits"          = 16;
      "kernel.yama.ptrace_scope"         = 2;      # Nur PTRACE_TRACEME
      "kernel.sysrq"                     = 0;      # SysRq komplett deaktiviert
      "fs.suid_dumpable"                 = 0;      # Keine Core-Dumps für setuid
      "fs.protected_hardlinks"           = 1;
      "fs.protected_symlinks"            = 1;
      "fs.protected_fifos"               = 2;
      "fs.protected_regular"             = 2;
      "vm.swappiness"                    = 10;
      "kernel.pid_max"                   = 65536;
      "kernel.unprivileged_userns_clone" = 1;      # User-Namespaces für Docker

      # Puffer für Docker-Netzwerk
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_rmem" = "4096 87380 16777216";
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";

      # Overcommit für Valkey
      "vm.overcommit_memory" = 1;
    };
  };

  # Locale & Zeitzone
  i18n = {
    defaultLocale  = "de_DE.UTF-8";
    supportedLocales = [ "de_DE.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];
  };
  time.timeZone = "Europe/Berlin";

  # Benutzer immutable, kein mutableUsers
  users = {
    mutableUsers = false;

    users = {
      # Haupt-Administratorkonto
      apphost = {
        isNormalUser    = true;
        home            = "/home/apphost";
        createHome      = true;
        extraGroups     = [ "docker" "systemd-journal" "wheel" ];
        shell           = pkgs.bash;
        openssh.authorizedKeys.keys = import ./ssh-key.nix;
        hashedPasswordFile = "/etc/apphost-password-hash";
      };

      # Root-Login vollständig sperren
      root = {
        hashedPassword = "!";
        openssh.authorizedKeys.keys = [];
      };
    };

    # Docker-Gruppe
    groups.docker = {};
  };

  # System-Pakete
  environment.systemPackages = with pkgs; [
    # Basis-Tools
    vim nano curl wget git htop iotop
    lsof netcat-gnu nmap tcpdump
    tmux screen unzip zip
    jq yq rsync rclone

    # Sicherheits-Tools
    apparmor-utils
    audit
    lynis           # Security-Audit
    aide            # File-Integrity-Monitoring

    # Container-Tools
    docker-compose
    skopeo

    # Monitoring/Diagnose
    sysstat
    prometheus-node-exporter

    # Kryptographie
    gnupg
    age
    openssl

    # Netzwerk
    iptables
    nftables
    iproute2
    bridge-utils
  ];

  # Fonts (Collabora benutzt unfree fonts fürs rendern)
  fonts.fontDir.enable = true;
  fonts.fontconfig.enable = false;
  fonts.packages = with pkgs; [
    corefonts
    vista-fonts
  ];

  # Shell-Aliase
  environment.shellAliases = {
    # Updates aus dem Repo holen (nur apphost/-Pfad, siehe install.sh)
    pull = "cd /opt/monorepo && sudo git pull";

    # NixOS rebuilden
    rebuild      = "sudo nixos-rebuild switch --flake path:/opt/monorepo#apphost";
    rebuild-boot = "sudo nixos-rebuild boot   --flake path:/opt/monorepo#apphost";

    # Updates holen, Flake-Inputs aktualisieren + sofort rebuilden
    update = "pull && cd /opt/monorepo && sudo nix flake update && sudo nixos-rebuild switch --flake path:/opt/monorepo#apphost";

    # Nix-Store aufräumen
    gc = "sudo nix-collect-garbage --delete-older-than 30d && sudo nix store optimise";

    # Docker-Stack
    up   = "cd /opt/monorepo && docker compose up -d";
    down = "cd /opt/monorepo && docker compose down";
    logs = "cd /opt/monorepo && docker compose logs -f";

    # Schnellstatus
    status = "systemctl status --no-pager docker && docker ps";

    # Secrets neu generieren (nach Passwortänderungen in .env)
    regen-secrets = "cd /opt/monorepo && bash scripts/update-secrets-authelia.sh && bash scripts/update-secrets-ntfy.sh";
  };

  # SSH – maximale Härtung
  services.openssh = {
    enable = true;
    openFirewall = false;  # Firewall manuell verwaltet (networking.nix)

    settings = {
      # Authentifizierung
      PermitRootLogin              = "no";
      PasswordAuthentication       = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication         = true;

      # Sitzungs-Härtung
      X11Forwarding                = false;
      AllowTcpForwarding           = "no";
      AllowAgentForwarding         = false;
      PermitTunnel                 = "no";
      PermitUserEnvironment        = false;
      MaxAuthTries                 = 3;
      MaxSessions                  = 3;
      LoginGraceTime               = 30;
      ClientAliveInterval          = 300;
      ClientAliveCountMax          = 2;
      TCPKeepAlive                 = false;

      # Nur starke Algorithmen
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
      ];
      KexAlgorithms = [
        "mlkem768x25519-sha256"               # PQ-hybrid. Todo: Only PQ? 
        "sntrup761x25519-sha512@openssh.com"  # PQ-hybrid. Todo: Only PQ? 
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
        "diffie-hellman-group16-sha512"
        "diffie-hellman-group18-sha512"
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
      ];

      # Banner
      Banner = "/etc/ssh/banner.txt";
    };

    hostKeys = [
      { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
      { type = "rsa"; bits = 4096; path = "/etc/ssh/ssh_host_rsa_key"; }
    ];
  };

  # SSH-Banner (rechtliche Absicherung)
  environment.etc."ssh/banner.txt".text = ''
    ╔══════════════════════════════════════════════════════════════╗
    ║         AUTORISIERTER ZUGRIFF IST AUSSCHLIESSLICH            ║
    ║         FÜR BERECHTIGTE BENUTZER GESTATTET.                  ║
    ║         Alle Aktivitäten werden protokolliert.               ║
    ╚══════════════════════════════════════════════════════════════╝
  '';

  # Automatische Updates (flake-basiert, zieht vom lokalen Repository)
  system.autoUpgrade = {
    enable        = true;
    flake         = "/opt/monorepo";
    allowReboot   = false;            # Manueller Reboot nach Kernel-Updates
    dates         = "04:30";
    flags         = [ "--no-build-output" ];
    randomizedDelaySec = "15min";
  };

  # Journal mit persistenten Logs, 4GB Limit
  services.journald.extraConfig = ''
    Storage=persistent
    Compress=yes
    SystemMaxUse=4G
    SystemKeepFree=1G
    MaxRetentionSec=3months
    ForwardToSyslog=no
    Audit=yes
  '';

  # Nix-Daemon Härtung & GC
  nix = {
    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 30d";
    };

    settings = {
      auto-optimise-store      = true;
      experimental-features    = [ "nix-command" "flakes" ];
      allowed-users            = [ "@wheel" "apphost" ];
      trusted-users            = [ "root" ];
      sandbox                  = true;
      max-jobs                 = "auto";
      cores                    = 0;
      substituters             = [ "https://cache.nixos.org" ];
      trusted-public-keys      = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
    };
  };

  # Chrony (Network Time Secure also NTP via TLS)
  services.chrony = {
    enable = true;
    servers = [];  # NTS-Server werden in extraConfig definiert
    extraConfig = ''
      # NTS-authentifizierte Server (erfordern kein UDP 123 – nur TCP 443/4460)
      server time.cloudflare.com iburst nts
      server nts.netnod.se iburst nts
      server ptbtime1.ptb.de iburst nts

      # NTS-Schlüssel zwischen Neustarts zwischenspeichern
      ntsdumpdir /var/lib/chrony

      makestep 1.0 3
      maxdistance 1.5
      leapsecmode slew
      maxslewrate 1000
      authselectmode require
    '';
  };
  services.timesyncd.enable = false; # Chrony ersetzt timesyncd

  # DNS muss vor chrony verfügbar sein (sonst scheitert initstepslew)
  systemd.services.chronyd.after = [
    "network-online.target"
    "nss-lookup.target"
  ];
  systemd.services.chronyd.wants = [ "network-online.target" ];

  # PAM – Login-Limits
  security.pam = {
    loginLimits = [
      { domain = "*"; type = "hard"; item = "core";    value = "0";     }
      { domain = "*"; type = "hard"; item = "nofile";  value = "65536"; }
      { domain = "*"; type = "soft"; item = "nofile";  value = "32768"; }
    ];
  };
}
