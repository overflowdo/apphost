# Sicherung: Datenbank-Dumps (täglich, lokal) und Nutzdaten-Backup auf die
# Wechselplatte (beim Anstecken, Proxmox Backup Server).
#
# TEIL 1 – Datenbank-Dumps
#
# Die eigentliche Sicherung des Stacks sind Proxmox-VM-Snapshots. Die sind
# crash-konsistent: sie halten den Zustand der Blockgeräte fest, nicht den der
# Anwendungen. Ein Postgres- oder SQLite-File kann darin mitten in einer
# Transaktion erwischt werden. Deshalb legt dieser Timer vorher saubere Dumps
# ab (pg_dump bzw. SQLite-Online-Backup-API), die der Snapshot dann als normale
# Dateien mitnimmt – siehe scripts/backup-databases.sh.
#
# Zeitpunkt: 02:30, also VOR dem wöchentlichen Trivy-Scan (Mo 02:00 ist bereits
# durch) und mit Abstand zum Proxmox-Backup-Fenster. Passt die Backup-Zeit in
# Proxmox nicht dazu, hier anpassen.
{ config, pkgs, lib, ... }:
let
  # nginx-Unprivileged läuft im Container als UID 101; unter userns-remap ist das
  # auf dem Host remapBase + 101.
  remapBase = (import ../lib/userns.nix).remapBase;
  triggerUid = toString (remapBase + 101);
in
{
  # sqlite3 wird vom Backup-Skript für ".backup" gebraucht,
  # proxmox-backup-client vom Medien-Backup auf die Wechselplatte.
  environment.systemPackages = [ pkgs.sqlite pkgs.proxmox-backup-client ];

  # Meldet fehlgeschlagene Dienste per Push. Ohne das bliebe ein gescheitertes
  # Backup still in systemd stehen: die Benachrichtigungskette geht über
  # Prometheus -> Alertmanager -> ntfy und sieht nur, was Prometheus scrapt –
  # systemd-Units gehören nicht dazu. node-exporter mit --collector.systemd
  # nachzurüsten wäre die Alternative, bräuchte aber den D-Bus-Socket im
  # Container und weicht dessen Isolation auf.
  # Testen – der Instanzname ist der VOLLE Unit-Name, %n expandiert
  # apphost-db-backup zu "apphost-db-backup.service". Der Testaufruf muss das
  # nachbilden, sonst prüft man einen anderen Pfad als den Ernstfall:
  #   sudo systemctl start 'apphost-notify-failure@apphost-db-backup.service.service'
  systemd.services."apphost-notify-failure@" = {
    description = "Report a failed unit (%i) to ntfy";
    path = [ pkgs.curl pkgs.systemd pkgs.coreutils pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /opt/monorepo/scripts/notify-failure.sh %i";
    };
    unitConfig.ConditionPathExists = "/opt/monorepo/scripts/notify-failure.sh";
  };

  systemd.services.apphost-db-backup = {
    description = "Application-consistent database dumps for the AppHost stack";
    after = [ "docker.service" ];
    wants = [ "docker.service" ];
    path  = [ pkgs.docker pkgs.sqlite pkgs.gzip pkgs.age pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.bash ];
    # Fehlschlag (auch ein Teilfehlschlag -> exit 1) geht als Push raus.
    onFailure = [ "apphost-notify-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /opt/monorepo/scripts/backup-databases.sh";
    };
    # Fehlt das Repo (z.B. vor der Erstinstallation), läuft der Dienst gar nicht
    # erst an, statt als "failed" stehen zu bleiben.
    unitConfig.ConditionPathExists = "/opt/monorepo/scripts/backup-databases.sh";
  };

  systemd.timers.apphost-db-backup = {
    description = "Daily application-consistent database dumps";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "02:30";
      Persistent = true;          # nach einem Ausfall nachholen
      RandomizedDelaySec = "5m";
    };
  };

  # ===========================================================================
  # Medien-Backup auf die Wechselplatte (Proxmox Backup Server)
  # ===========================================================================
  #
  # Die eigentliche Sicherung der Nutzdaten. Bis hierher gab es sie NICHT:
  # /mnt/media ist eine per `qm set 100 -scsi1 …` durchgereichte physische
  # Platte, und vzdump sichert ausschließlich Volumes, die auf einem
  # PVE-Storage liegen. Fotos, Dokumente, Cloud-Dateien und Kalender lagen
  # damit auf genau einem Datenträger ohne jede Kopie.
  #
  # Ablauf: Wechselplatte wird am Proxmox-Host angesteckt -> udev hängt den
  # PBS-Datastore ein (siehe proxmox/) -> der Timer hier merkt beim nächsten
  # Tick, dass der Datastore antwortet, und sichert. Kein SSH, keine
  # Zugangsdaten über die Maschinengrenze; einziges Geheimnis ist ein
  # PBS-API-Token, das nur anlegen und lesen darf.
  systemd.tmpfiles.rules = [
    "d /var/lib/apphost-backup       0755 root root -"
    "d /var/lib/apphost-backup/state 0700 root root -"
    "d /var/lib/apphost-backup/web   0755 root root -"
    # Einziges Verzeichnis, in das der backup-trigger-Container schreiben darf.
    "d /var/lib/apphost-backup/web/hook      0770 ${triggerUid} ${triggerUid} -"
    "d /var/lib/apphost-backup/web/hook/.tmp 0770 ${triggerUid} ${triggerUid} -"
    # Textfile-Collector des node-exporter (compose/monitoring/exporters.yml
    # hängt das Verzeichnis read-only ein).
    "d /var/lib/node-exporter          0755 root root -"
    "d /var/lib/node-exporter/textfile 0755 root root -"
  ];

  systemd.services.apphost-media-backup = {
    description = "Back up VM payload data to the attached removable PBS datastore";
    after = [ "docker.service" ];
    path  = [ pkgs.proxmox-backup-client pkgs.curl pkgs.coreutils pkgs.gnugrep pkgs.bash ];
    # Läuft die Platte gerade nicht, endet das Skript mit 0 – ein Fehlschlag
    # bedeutet hier also wirklich einen Fehler und darf pushen.
    onFailure = [ "apphost-notify-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /opt/monorepo/scripts/media-backup.sh";
      # Ein Lauf über 1,5 TB dauert; der zweite Lauf danach ist dank
      # Deduplizierung kurz. Kein Timeout, sonst bricht ausgerechnet die
      # Erstsicherung ab.
      TimeoutStartSec = "infinity";
      # Eine noch offene Knopf-Anforderung mitnehmen: läuft der Timer-Lauf
      # ohnehin gerade an, wäre ein zweiter Lauf direkt danach sinnlos.
      ExecStartPre = "${pkgs.coreutils}/bin/rm -f /var/lib/apphost-backup/web/hook/run";
    };
    unitConfig.ConditionPathExists = "/opt/monorepo/scripts/media-backup.sh";
  };

  systemd.timers.apphost-media-backup = {
    description = "Poll for an attached removable backup disk";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitInactiveSec = "10m";
      RandomizedDelaySec = "1m";
    };
  };

  # Der Knopf auf backup.<domain>. Der backup-trigger-Container legt die Datei
  # an (compose/tools/backup-trigger.yml), diese Unit sieht sie und startet den
  # Lauf. Der INHALT der Datei wird nie gelesen – es gibt nichts zu injizieren,
  # und der Container braucht keinerlei Rechte außer "Datei anlegen".
  systemd.paths.apphost-media-backup-trigger = {
    description = "Watch for the backup button on backup.<domain>";
    wantedBy = [ "paths.target" ];
    pathConfig = {
      PathExists = "/var/lib/apphost-backup/web/hook/run";
      Unit = "apphost-media-backup-forced.service";
    };
  };

  # Eigene Unit für den Knopf: --force übergeht den 24-Stunden-Mindestabstand.
  # Wer drückt, will jetzt ein Backup, nicht die Auskunft "heute schon gelaufen".
  systemd.services.apphost-media-backup-forced = {
    description = "Manually triggered payload backup (button on backup.<domain>)";
    after = [ "docker.service" ];
    path  = [ pkgs.proxmox-backup-client pkgs.curl pkgs.coreutils pkgs.gnugrep pkgs.bash ];
    onFailure = [ "apphost-notify-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/rm -f /var/lib/apphost-backup/web/hook/run";
      ExecStart = "${pkgs.bash}/bin/bash /opt/monorepo/scripts/media-backup.sh --force";
      TimeoutStartSec = "infinity";
    };
    # KEIN Conflicts= auf den Timer-Lauf: das würde einen bereits laufenden
    # Backup-Lauf ABBRECHEN statt ihn abzuwarten – bei einer Erstsicherung über
    # Stunden genau das Falsche. Überlappung ist ohnehin unwahrscheinlich: nach
    # einem erfolgreichen Lauf ist der Zeitstempel frisch und der Timer-Lauf
    # endet sofort mit "noch nichts zu tun".
    unitConfig.ConditionPathExists = "/opt/monorepo/scripts/media-backup.sh";
  };
}
