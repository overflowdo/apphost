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

      # Traefik: fehlgeschlagene Anmeldungen (Authelia-ForwardAuth,
      # Radicale-Basic-Auth, Vaultwarden).
      #
      # WICHTIG – eigener Hook: fail2ban hängt seine Kette per Default in den
      # input-Hook. Traffic auf 80/443 wird von Docker aber in prerouting per
      # DNAT auf den Traefik-Container umgeschrieben und läuft danach über
      # FORWARD; der input-Hook sieht ihn nie. Ein Ban blieb damit für alles
      # hinter Traefik wirkungslos – Authelia-Login, Radicale, Vaultwarden,
      # Jellyfin. Nur das sshd-Jail unten funktionierte, weil sshd ein echter
      # Host-Dienst ist.
      #
      # chain_priority -150 sorgt dafür, dass die Kette VOR den
      # Docker-Regeln und vor dem eigenen forward-Chain aus modules/networking.nix
      # (Priorität 0) greift. Die Parameter sind Init-Optionen von fail2bans
      # eigener nftables-Action, es ist also keine selbstgebaute Action nötig.
      #
      # Prüfen: sudo nft list table inet f2b-table
      traefik-auth = {
        settings = {
          enabled  = true;
          port     = "80,443";
          logpath  = "/var/log/traefik/access.log";
          maxretry = 5;
          findtime = "10m";
          bantime  = "1h";
          filter   = "traefik-auth";
          # ALLPORTS, nicht multiport: die multiport-Variante erzeugt
          # "tcp dport { 80,443 }". Im forward-Hook stimmt das nicht mehr –
          # Docker hat in prerouting längst auf 172.23.1.2:8081/:8443 gedreht
          # (Port-Mapping in compose/infrastructure/traefik.yml). Die Ban-Regel
          # hätte also nie gematcht. port="8081,8443" wäre die Alternative,
          # koppelt das Jail aber an das Compose-Port-Mapping. Ein Ban ist
          # ohnehin IP-basiert, ein Port-Match bringt hier nichts.
          # Gegenprobe: sudo nft list table inet f2b-table -> es darf KEIN
          # "dport" in der Regel stehen.
          action   = ''nftables-allports[name=traefik-auth, protocol=tcp, chain=f2b-forward, chain_hook=forward, chain_priority=-150]'';
          # Ohne ignoreip sperrt sich der Admin selbst aus, sobald die Bans
          # wirken: Container-interne Aufrufe (Homepage-Widgets, Healthchecks)
          # kommen aus 172.16.0.0/12 und dürfen nie zu einem Ban führen.
          # Das LAN steht BEWUSST NICHT hier: der Stack ist nur aus dem LAN
          # erreichbar (DNS-01, keine Portfreigabe) – wer 192.168.178.0/24
          # ignoriert, schaltet das Jail komplett ab. Die eigene Workstation
          # kann man bei Bedarf einzeln ergänzen.
          ignoreip = "127.0.0.1/8 ::1 172.16.0.0/12";
        };
      };
    };

    extraPackages = [ pkgs.ipset ];
  };

  # Fail2ban Filter für Traefik.
  #
  # ZWEI Dinge sind hier entscheidend:
  #
  # 1. Feldreihenfolge. Traefik schreibt das Access-Log mit logrus.JSONFormatter,
  #    der die Felder als Go-Map serialisiert – encoding/json sortiert Map-Keys
  #    ALPHABETISCH. In der Zeile steht also immer:
  #      ClientHost ... DownstreamStatus ... RequestHost ... RequestPath ... ServiceName
  #    Eine failregex, die RequestPath VOR DownstreamStatus erwartet, matcht nie.
  #    (Genau der Fehler steckte in der zuvor ergänzten Vaultwarden-Zeile.)
  #
  # 2. Eingrenzung auf echte Anmeldeversuche. Ein pauschales "jede 401" ist ein
  #    Selbstschuss: Authelias Session läuft nach 15 Minuten Inaktivität ab,
  #    und ein offener Homepage-Tab pollt weiter. forward-auth antwortet auf
  #    diese XHR mit 401 (die 302 gibt es nur für Accept: text/html) – fünf
  #    davon in Sekunden, und maxretry=5 hätte den eigenen Rechner für eine
  #    Stunde ausgesperrt, mit bantime-increment eskalierend bis 48 Stunden.
  #    Gezählt werden deshalb nur Stellen, an denen wirklich Zugangsdaten
  #    geprüft werden:
  #      - Authelia: /api/firstfactor und /api/secondfactor/* -> 401
  #      - Vaultwarden: /identity/connect/token -> 400 (invalid_grant, OAuth2)
  #      - Radicale: Basic-Auth bei JEDEM Request, es gibt keinen Login-Pfad ->
  #        deshalb über ServiceName statt über den Pfad. Das ist zugleich
  #        unabhängig von RADICALE_SUBDOMAIN.
  environment.etc."fail2ban/filter.d/traefik-auth.conf".text = ''
    [Definition]
    failregex = ^.*"ClientHost":"<HOST>".*"DownstreamStatus":401.*"RequestPath":"/api/(first|second)factor.*$
                ^.*"ClientHost":"<HOST>".*"DownstreamStatus":400.*"RequestPath":"/identity/connect/token".*$
                ^.*"ClientHost":"<HOST>".*"DownstreamStatus":401.*"ServiceName":"radicale@docker".*$
    ignoreregex =
    datepattern = "StartUTC":"%%Y-%%m-%%dT%%H:%%M:%%S
  '';

  # AIDE – File Integrity Monitoring
  # Manuelle Ausführung: aide --check
  # Die Datenbank legt der aide-check-Dienst unten beim ersten Lauf selbst an
  # und zieht sie nach jedem nixos-rebuild automatisch neu. Manuell erzwingen:
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
    # Check lief nie. rmd160 und crc32 hängen davon ab, gegen welche
    # Krypto-Bibliothek nixpkgs AIDE baut, und sind hier bewusst NICHT drin:
    # sha512+sha256 sind immer vorhanden und reichen völlig. Dazu die
    # üblichen Metadaten (Rechte, Inode, Links, Owner, Größe, mtime/ctime).
    NORMAL = p+i+n+u+g+s+m+c+sha512+sha256

    # Überwachte Pfade. /bin, /sbin, /lib, /lib64, /usr/bin und /usr/sbin sind
    # hier RAUS: auf NixOS gibt es sie nicht bzw. nur als einzelne Symlinks
    # (/bin/sh, /usr/bin/env) – AIDE meldete sie schlicht als fehlend.
    # Alles Ausführbare liegt im /nix/store und ist dort ohnehin
    # hash-adressiert und read-only.
    /boot NORMAL
    /etc NORMAL
    # Nicht nur config/: aus compose/ und scripts/ laufen Dinge als root
    # (systemd-Timer rufen backup-databases.sh und notify-failure.sh direkt aus
    # diesem Verzeichnis auf). Eine Änderung dort ist genauso relevant wie eine
    # in /etc.
    /opt/monorepo/config NORMAL
    /opt/monorepo/compose NORMAL
    /opt/monorepo/scripts NORMAL
    /opt/monorepo/nixos NORMAL
    /root NORMAL
    /home/apphost/.ssh NORMAL

    !/proc
    !/sys
    !/dev
    !/run
    !/tmp
    !/var/tmp
    # /etc besteht auf NixOS größtenteils aus Symlinks in den Store; diese
    # beiden Dateien schreibt das System selbst bei jedem Boot neu.
    !/etc/resolv.conf
    !/etc/machine-id
  '';

  systemd.services.aide-check = {
    description = "AIDE File Integrity Check";
    startAt     = "daily";
    # Fehlschlag per Push melden (Template-Unit in modules/backup.nix).
    onFailure   = [ "apphost-notify-failure@%n.service" ];
    # Die Datenbank wurde nirgends initialisiert -> der Dienst gab jeden Tag nur
    # den Hinweis "Datenbank nicht gefunden" aus und hat nie geprüft. Jetzt legt
    # er sie beim ersten Lauf selbst an.
    #
    # Zweite Baustelle: /etc besteht auf NixOS fast vollständig aus Symlinks in
    # den Nix-Store und wird bei JEDEM `nixos-rebuild switch` komplett neu
    # verlinkt. Ohne Gegenmaßnahme meldet der tägliche Report danach hunderte
    # Änderungen – reines Rauschen, in dem ein echter Treffer untergeht. Deshalb
    # merkt sich der Dienst die System-Generation: ändert sie sich, wird die
    # Baseline EINMAL neu gezogen statt einen Report zu erzeugen. Zwischen zwei
    # Rebuilds ist jede Abweichung dann eine echte.
    script      = ''
      set -u
      mkdir -p /var/lib/aide

      # Die Kennung umfasst die System-Generation UND den Stand von
      # /opt/monorepo. Grund: AIDE überwacht auch compose/, scripts/ und
      # nixos/ – der Alias `pull` ändert genau die, ohne die System-Generation
      # zu berühren. Ohne den zweiten Teil käme nach jedem `pull` beim
      # nächsten 02:30-Lauf eine Push-Meldung mit dem kompletten git-Diff.
      REPO_REV="$(${pkgs.git}/bin/git -C /opt/monorepo rev-parse HEAD 2>/dev/null || echo none)"
      GEN="$(readlink -f /run/current-system)+$REPO_REV"
      STAMP=/var/lib/aide/system-generation

      if [ ! -f /var/lib/aide/aide.db ]; then
        REASON="keine Datenbank vorhanden"
      elif [ "$(cat "$STAMP" 2>/dev/null || echo none)" != "$GEN" ]; then
        REASON="System-Generation oder Repo-Stand geändert (nixos-rebuild / pull)"
      else
        REASON=""
      fi

      if [ -n "$REASON" ]; then
        # Vor dem Neu-Ziehen NOCH EINMAL gegen die alte Baseline prüfen und den
        # Report wegschreiben. Sonst entstünde genau die Lücke, die eine
        # automatische Neu-Baseline mit sich bringt: eine Manipulation, die
        # zeitlich mit einem nixos-rebuild zusammenfällt, wäre nie gemeldet
        # worden – und `rebuild`/`update` sind Aliase, die jederzeit laufen.
        # Der Report enthält dann zwar auch das Rebuild-Rauschen, aber er
        # existiert und ist nachlesbar.
        if [ -f /var/lib/aide/aide.db ]; then
          REPORT="/var/log/aide-vor-rebaseline-$(date +%Y%m%d-%H%M%S).log"
          echo "AIDE: Report gegen die alte Baseline -> $REPORT"
          ${pkgs.aide}/bin/aide --check > "$REPORT" 2>&1 || true
          # Nur die letzten zehn aufheben.
          ls -1t /var/log/aide-vor-rebaseline-*.log 2>/dev/null \
            | tail -n +11 | xargs -r rm -f
        fi

        echo "AIDE: $REASON -> Baseline wird neu erstellt (aide --init)."
        ${pkgs.aide}/bin/aide --init
        mv -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db
        printf '%s' "$GEN" > "$STAMP"
        echo "AIDE: Baseline erstellt. Ab dem nächsten Lauf wird wieder geprüft."
        exit 0
      fi

      # KEIN "|| true": AIDE meldet Funde über den Exit-Code (1 = neue,
      # 2 = gelöschte, 4 = geänderte Dateien, kombinierbar; ab 14 interne
      # Fehler). Mit "|| true" endete die Unit immer mit 0 und das OnFailure
      # oben hätte nie ausgelöst – der Push-Kanal wäre für AIDE tot gewesen und
      # ein Integritätsfund hätte nur in /var/log/aide.log gestanden.
      #
      # Die Form "|| rc=$?" ist nötig, weil NixOS systemd.services.<n>.script
      # mit "set -e" wrappt (makeJobScript): ein blankes `aide --check` würde
      # bei einem Fund SOFORT abbrechen. Die Unit endete zwar trotzdem mit dem
      # richtigen Exit-Code, aber die erklärende Zeile unten – die
      # notify-failure.sh aus dem Journal mitschickt – käme nie zustande.
      # Ein Befehl links von "||" ist von set -e ausgenommen.
      rc=0
      ${pkgs.aide}/bin/aide --check || rc=$?
      if [ "$rc" -ne 0 ]; then
        echo "AIDE: Abweichungen oder Fehler festgestellt (exit $rc) – Details in /var/log/aide.log"
      fi
      exit "$rc"
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
