# =============================================================================
# NixOS Sicherheitsmodul – AppArmor, Audit, Fail2ban, sudo-Härtung
# =============================================================================
{ config, pkgs, lib, ... }:
{
  # AppArmor – Mandatory Access Control
  security.apparmor = {
    enable                  = true;
    killUnconfinedConfinables = true;
    packages                = [ pkgs.apparmor-profiles ];
    enableCache             = true;
  };

  # sudo Konfiguration
  security.sudo = {
    enable              = true;
    execWheelOnly       = true;
    wheelNeedsPassword  = true;
    extraConfig = ''
      # Keine Umgebungsvariablen weiterleiten um injections zu verhindern
      Defaults env_reset
      Defaults secure_path="/run/current-system/sw/bin:/run/current-system/sw/sbin"
      # Logging für sauberen Auth-Log: WER hat WANN WAS aufgerufen.
      Defaults logfile=/var/log/sudo.log
      # Bewusst KEIN log_input/log_output: das protokollierte die komplette
      # Sitzungs-Ein-/Ausgabe im Klartext nach /var/log/sudo-io. Damit landete
      # z.B. bei `sudo bash scripts/show-secrets.sh` jedes Passwort und jeder
      # Token in einer Logdatei (die zudem von keiner Rotation erfasst war).
      # Der Nutzen (Session-Replay) steht auf einem Single-Admin-Host in keinem
      # Verhältnis zu einem zweiten Klartext-Depot aller Secrets.
      # Sitzungs-Timeout
      Defaults timestamp_timeout=5
      Defaults passwd_tries=3
    '';
  };

  # Audit-Daemon für CIS-konformes Audit-Logging
  security.audit = {
    enable = true;
    # Audit-Backlog-Limit erhöhen (Standard 64 reichte manchmal nicht für Docker-Workloads)
    backlogLimit = 8192;
    rules  = [
      # Zeitänderungen
      "-a always,exit -F arch=b64 -S clock_settime -k time-change"
      "-a always,exit -F arch=b32 -S clock_settime -k time-change"
      "-w /etc/localtime -p wa -k time-change"

      # Benutzer-/Gruppen-Änderungen (nur Pfade die auf NixOS existieren)
      "-w /etc/group -p wa -k identity"
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"

      # Netzwerk-Konfiguration
      "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale"
      "-w /etc/hosts -p wa -k system-locale"

      # Berechtigungseskalation
      "-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k setuid"

      # Sudo
      "-w /etc/sudoers -p wa -k scope"
      "-w /etc/sudoers.d/ -p wa -k scope"

      # Kernel-Module via Syscall
      "-a always,exit -F arch=b64 -S init_module -S delete_module -k modules"
      "-a always,exit -F arch=b32 -S init_module -S delete_module -k modules"

      # Docker – nur echte User-Sessions (auid>=1000), keine Container-Daemon-Events sonst zu viel Spam.
      # ACHTUNG: -w und -F lassen sich NICHT kombinieren, auditctl weist die Regel
      # ab ("-w" ist nur die Kurzform für eine Regel ohne weitere Filter). Deshalb
      # ausgeschrieben als exit-Regel mit -F dir= und -F perm=.
      "-a always,exit -F dir=/var/lib/docker -F perm=wa -F auid>=1000 -F auid!=4294967295 -k docker"
      "-w /etc/docker/ -p rwa -k docker"

      # Löschoperationen keine Container-Events sonst zu viel Spam
      "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid!=4294967295 -k delete"

      # Datei-Berechtigungsänderungen (auid!=4294967295 = hat eine Login-Session)
      "-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid!=4294967295 -k perm_mod"
      "-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid!=4294967295 -k perm_mod"

      # Fehlgeschlagene Zugriffe auf sensitive Verzeichnisse.
      # Auch hier: -F dir= verträgt sich nicht mit -S/-F arch, auditctl lehnte die
      # alte Regel ab. Ohne -S gilt sie für alle Zugriffe auf den Teilbaum.
      "-a always,exit -F dir=/etc -F perm=r -F success=0 -F auid!=4294967295 -k unauth"
    ];
  };

  # Fail2ban – Brute-Force-Schutz
  services.fail2ban = {
    enable = true;

    maxretry    = 3;
    bantime     = "15m";
    bantime-increment = {
      enable       = true;
      maxtime      = "48h";  # Max 2 Tage
      overalljails = true;
    };

    jails = {
      # SSH-Brute-Force.
      # backend = systemd ist auf NixOS PFLICHT: es gibt kein /var/log/auth.log,
      # sshd loggt ausschließlich ins Journal. Mit dem alten logpath startete das
      # Jail nicht bzw. sah nie einen Fehlversuch – der Schutz existierte nur auf
      # dem Papier.
      sshd = {
        settings = {
          enabled  = true;
          port     = "22";
          filter   = "sshd";
          backend  = "systemd";
          journalmatch = "_SYSTEMD_UNIT=sshd.service + _COMM=sshd";
          maxretry = 3;
          bantime  = "2h";
        };
      };

      # Traefik: 401er (Authelia-ForwardAuth, Radicale-Basic-Auth, Vaultwarden).
      # Traefik loggt jetzt zusätzlich in eine Datei (config/traefik/traefik.template.yml
      # -> accessLog.filePath), die per Bind-Mount auf /var/log/traefik liegt;
      # vorher ging alles nur nach stdout und der logpath zeigte ins Leere.
      traefik-auth = {
        settings = {
          enabled  = true;
          port     = "80,443";
          logpath  = "/var/log/traefik/access.log";
          maxretry = 5;
          findtime = "10m";
          bantime  = "1h";
          filter   = "traefik-auth";
        };
      };
    };

    extraPackages = [ pkgs.ipset ];
  };

  # Fail2ban Filter für Traefik.
  # Traefik schreibt das Access-Log als JSON (format: json) – die alte failregex
  # erwartete Common Log Format und hätte nie gematcht. Deshalb hier direkt auf
  # die JSON-Felder: "ClientHost":"<IP>" ... "DownstreamStatus":401.
  # Die Reihenfolge der Felder ist bei Traefik stabil (ClientHost vor Status);
  # zur Sicherheit erlaubt .* beliebige Felder dazwischen.
  environment.etc."fail2ban/filter.d/traefik-auth.conf".text = ''
    [Definition]
    failregex = ^.*"ClientHost":"<HOST>".*"DownstreamStatus":(401|403).*$
    ignoreregex =
    datepattern = "StartUTC":"%%Y-%%m-%%dT%%H:%%M:%%S
  '';

  # AIDE – File Integrity Monitoring
  # Manuelle Ausführung: aide --check
  # Die Datenbank legt der aide-check-Dienst unten beim ersten Lauf selbst an.
  # Nach beabsichtigten Systemänderungen neu einlesen:
  #   sudo rm /var/lib/aide/aide.db && sudo systemctl start aide-check
  environment.etc."aide.conf".text = ''
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    database_new=file:/var/lib/aide/aide.db.new
    gzip_dbout=yes
    report_url=file:/var/log/aide.log
    report_url=stdout

    # tiger, haval und gost sind in aktuellen AIDE-Versionen entfernt – standen
    # sie hier drin, ließ sich die Konfiguration gar nicht erst parsen und der
    # Check lief nie. Übrig bleiben die tatsächlich verfügbaren Hashes plus die
    # üblichen Metadaten-Attribute (Rechte, Inode, Owner, Größe, mtime/ctime).
    NORMAL = p+i+n+u+g+s+m+c+sha512+sha256+rmd160+crc32

    /etc NORMAL
    /bin NORMAL
    /sbin NORMAL
    /lib NORMAL
    /lib64 NORMAL
    /usr/bin NORMAL
    /usr/sbin NORMAL
    /boot NORMAL
    /opt/monorepo/config NORMAL

    !/proc
    !/sys
    !/dev
    !/run
    !/tmp
    !/var/tmp
  '';

  systemd.services.aide-check = {
    description = "AIDE File Integrity Check";
    startAt     = "daily";
    # Die Datenbank wurde nirgends initialisiert -> der Dienst gab jeden Tag nur
    # den Hinweis "Datenbank nicht gefunden" aus und hat nie geprüft. Jetzt legt
    # er sie beim ersten Lauf selbst an (Baseline) und prüft ab dem zweiten Lauf.
    script      = ''
      set -u
      mkdir -p /var/lib/aide

      if [ ! -f /var/lib/aide/aide.db ]; then
        echo "AIDE: keine Datenbank vorhanden -> lege Baseline an (aide --init)."
        ${pkgs.aide}/bin/aide --init
        mv -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db
        echo "AIDE: Baseline erstellt. Ab dem nächsten Lauf wird geprüft."
        exit 0
      fi

      ${pkgs.aide}/bin/aide --check || true
    '';
    serviceConfig.Type = "oneshot";
  };

  # Kernel-Sicherheitsmodule
  security = {
    lockKernelModules = true;    # Verhindert das Laden von nicht erlaubten Kernel-Modulen
    protectKernelImage = true;   # /dev/mem, /dev/kmem Schutz
    allowUserNamespaces = true;  # Für Docker user-namespace remapping benötigt
  };

  # auditd – Daemon + Konfiguration
  security.auditd.enable = true;

  # Logrotate
  services.logrotate = {
    enable = true;
    settings = {
      "/var/log/sudo.log" = {
        rotate     = 12;
        monthly    = true;
        compress   = true;
        missingok  = true;
        notifempty = true;
      };
      # Traefik-Access-Log (Quelle des fail2ban-Jails). copytruncate, weil
      # Traefik im Container das Handle offen hält und kein Reopen-Signal bekommt.
      "/var/log/traefik/access.log" = {
        rotate       = 7;
        daily        = true;
        compress     = true;
        missingok    = true;
        notifempty   = true;
        copytruncate = true;
      };
    };
  };
}
