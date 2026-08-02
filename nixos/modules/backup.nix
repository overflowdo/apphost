# Anwendungskonsistente Datenbank-Dumps vor dem Proxmox-Snapshot.
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
{
  # sqlite3 wird vom Backup-Skript für ".backup" gebraucht.
  environment.systemPackages = [ pkgs.sqlite ];

  # Meldet fehlgeschlagene Dienste per Push. Ohne das bliebe ein gescheitertes
  # Backup still in systemd stehen: die Benachrichtigungskette geht über
  # Prometheus -> Alertmanager -> ntfy und sieht nur, was Prometheus scrapt –
  # systemd-Units gehören nicht dazu. node-exporter mit --collector.systemd
  # nachzurüsten wäre die Alternative, bräuchte aber den D-Bus-Socket im
  # Container und weicht dessen Isolation auf.
  # Testen: sudo systemctl start apphost-notify-failure@apphost-db-backup.service
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
}
