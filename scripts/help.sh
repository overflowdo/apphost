#!/usr/bin/env bash
# Übersicht aller Verwaltungsbefehle (Alias: help). Muss zu den shellAliases in
# nixos/configuration.nix und der Alias-Tabelle in Installationsanleitung.md passen.
cat <<'EOF'

  AppHost – Verwaltungsbefehle
  ══════════════════════════════════════════════════════════════

  Docker-Stack
    up             Stack GESTAFFELT starten: erzeugt fehlende Secrets und fährt
                   die USB-/RAM-schweren Dienste nacheinander hoch
    up-all         Alle Container auf einmal (docker compose up -d) – Notnagel
    down           Alle Container stoppen
    logs           Live-Logs aller Container
    status         Docker-Daemon-Status + laufende Container

  NixOS-System
    rebuild        Konfiguration bauen und SOFORT aktivieren
    rebuild-boot   Konfiguration bauen, erst beim nächsten Boot aktivieren
    pull           Repo-Updates holen (git pull)
    update         pull + Flake-Inputs aktualisieren + rebuild
    gc             Nix-Store aufräumen (Generationen > 30 Tage)

  Secrets & Zertifikate
    secrets        Alle Passwörter/Tokens (.env + secrets/) + Authelia-2FA-Link
    regen-secrets  Secrets neu generieren (nach Passwortänderung in .env)
    ca             Lokales CA-Zertifikat ausgeben (Import in Browser/Handy)
    backup-db      Datenbank-Dumps nach /var/backups/apphost (täglich 02:30 automatisch)

    help           Diese Übersicht

  ══════════════════════════════════════════════════════════════

EOF
