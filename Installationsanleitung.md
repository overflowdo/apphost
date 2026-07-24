# Installations- und Betriebsanleitung

## Inhaltsverzeichnis

**Teil 1 – Installation**

1. [Voraussetzungen](#1-voraussetzungen)
2. [Absicherung der Proxmox-Node](#2-absicherung-der-proxmox-node)
3. [NixOS-ISO in Proxmox bereitstellen](#3-nixos-iso-in-proxmox-bereitstellen)
4. [Virtuelle Maschine erstellen](#4-virtuelle-maschine-erstellen)
5. [Initiale NixOS-Konfiguration](#5-initiale-nixos-konfiguration)
6. [Installation](#6-installation)
7. [Secure Boot einrichten](#7-secure-boot-einrichten)
8. [Stack starten](#8-stack-starten)
9. [AIDE initialisieren](#9-aide-initialisieren)

**Teil 2 – Betrieb und Wartung**

10. [Verwaltungs-Aliase](#10-verwaltungs-aliase)
11. [Passwörter ändern](#11-passwörter-ändern)
12. [AIDE Integritätsprüfung](#12-aide-integritätsprüfung)
13. [Container-Sicherheitsbericht](#13-container-sicherheitsbericht)
14. [Tor-Onion-Adresse anzeigen](#14-tor-onion-adresse-anzeigen)
15. [Automatische Container-Updates mit RenovateBot](#15-automatische-container-updates-mit-renovatebot)
16. [Proxmox-Backups einrichten](#16-proxmox-backups-einrichten)

**Anhang**

- [Quellen](#quellen)

---

# Teil 1 – Installation

## 1. Voraussetzungen

Vor Beginn der Installation müssen folgende Bedingungen erfüllt sein:

- Eine installierte und erreichbare Proxmox-Node [[1]](#quelle-1).
- Netzwerkzugang zur Proxmox-Weboberfläche und per SSH.
- Eine eigene Domain mit der Möglichkeit, DNS-Einträge zu verwalten.
- Zugang zum Router, um statische DHCP-Vergabe einzurichten.
- Ein Cloudflare-Konto für die DNS-01-ACME-Challenge [[7]](#quelle-7) (kostenlos). Details siehe [Cloudflare API-Token erstellen](#cloudflare-api-token-erstellen) in Abschnitt 6.
- Ein SSH-Schlüsselpaar auf dem lokalen Rechner (Admin-Client). Falls noch keines existiert, siehe [Abschnitt 6, SSH-Key für den Admin-Nutzer](#6-installation).

> [!NOTE]
> Domain und Cloudflare API-Token können auf Anfrage von uns bereitgestellt werden. In diesem Fall entfallen die Schritte zur eigenen Domain-Registrierung und Token-Erstellung.

---

## 2. Absicherung der Proxmox-Node

> [!WARNING]
> Dieser Schritt ist durchzuführen, sofern die Proxmox-Node noch nicht gehärtet wurde.

Das Repository enthält das Skript `scripts/proxmox-harden.sh`, das die folgenden Punkte automatisiert:

- SSH-Passwort-Authentifizierung deaktivieren, nur noch Key-Login erlaubt
- Moderne Cipher-Suites und SSH-Session-Härtung
- Alle USB-Inputs deaktivieren (usb-storage, uas, usbhid)
- UEFI- und Secure-Boot-Status prüfen und reporten

### Voraussetzung: SSH-Key hinterlegen

> [!WARNING]
> Das Skript prüft, ob ein SSH Public Key in `/root/.ssh/authorized_keys` hinterlegt ist. Falls nicht, bricht es mit einer Anleitung ab. Ohne Key würde die Passwort-Deaktivierung den Remote-Zugriff dauerhaft sperren.

Falls noch kein Key hinterlegt ist, zunächst vom lokalen Rechner:

```bash
ssh-copy-id root@<PROXMOX-IP>
```

Danach den Key-Login in einem **neuen Terminal** testen (bestehende Session offen lassen!):

```bash
ssh -i <pfad-zum-private-key> root@<PROXMOX-IP>
```

### Skript ausführen

Das Skript kann direkt vom Proxmox-Host aus dem Repository geladen und ausgeführt werden, ein vorheriges Klonen ist nicht nötig:

```bash
curl -fsSL https://raw.githubusercontent.com/<TODO>/main/scripts/proxmox-harden.sh | sudo bash
```

> [!NOTE]
> Wer den Skriptinhalt vor der Ausführung prüfen möchte, kann ihn zunächst herunterladen:
>
> ```bash
> curl -fsSL <URL> -o proxmox-harden.sh
> less proxmox-harden.sh
> sudo bash proxmox-harden.sh
> ```

Das Skript gibt am Ende eine Zusammenfassung mit allen Warnungen aus. Anschließend:

1. SSH-Login in neuem Terminal erneut testen.
2. Neustart durchführen, die USB-Blacklist greift erst nach einem Reboot vollständig:
   ```bash
   reboot
   ```
3. Nach dem Neustart Secure Boot im Proxmox-UI kontrollieren:
   _Host → Summary → Boot Mode_

### Manuelle Maßnahmen (nicht scriptbar)

- **Updates:** Regelmäßig auf Updates prüfen und einspielen (`apt update && apt upgrade`).
- **UEFI-Passwort:** Muss im Mainboard-BIOS gesetzt werden, die Vorgehensweise ist herstellerspezifisch.

---

## 3. NixOS-ISO in Proxmox bereitstellen

1. In der Proxmox-Weboberfläche den gewünschten **Speicher** auswählen (z.B. `local`).
2. Auf **ISO Images → Download from URL** klicken.
3. Folgende URL eingeben:
   ```
   https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso
   ```
4. Auf **Query URL** klicken, danach auf **Download**.
5. Warten, bis der Download abgeschlossen ist.

---

## 4. Virtuelle Maschine erstellen

### Grundkonfiguration

1. In Proxmox auf **Create VM** klicken und **Advanced Options** aktivieren.
2. **Name:** `apphost`
3. **OS – ISO Image:** Zuvor heruntergeladenes NixOS-Minimal-ISO auswählen.
4. **System:**
   - Machine: `q35`
   - BIOS: `OVMF`
   - EFI Storage: lokalen Speicher wählen (z.B. `local`)
   - **Haken bei „Pre-Enroll keys" entfernen**
   - TPM aktivieren, TPM Storage: `local`

### Datenträger

- Falls der Host eine SSD verwendet: Haken bei **SSD Emulation** setzen.
- **Größe:** Mindestens **50 GB**, empfohlen mehr.

### CPU

- Sockets: `1`
- Kerne: Anzahl der physischen Kerne des Hostsystems (abzüglich reservierter Kerne für andere Systeme).
- Typ: `host` (empfohlen, beste Performance). Alternativ: Standard belassen, das bedeutet schlechtere Performance bei minimalem Sicherheitsgewinn durch Security by Obscurity.
- **Nested Virtualisierung:** Wird in der Standardkonfiguration nicht benötigt und kann deaktiviert bleiben. Nur erforderlich, falls die optionalen Sandbox-Runtimes (Kata/gVisor) genutzt werden sollen. Hintergrund dazu siehe Projektdokumentation.

### Arbeitsspeicher

- **Mindestens 16 GB**, empfohlen **32 GB**.
- Auf den maximal vertretbaren Wert setzen.

### Netzwerk

Standardeinstellungen beibehalten. Auf **Finish** klicken.

---

## 5. Initiale NixOS-Konfiguration

### VM starten und IP ermitteln

1. Die VM `apphost` starten.
2. Auf den Reiter **Console** klicken.
3. IP-Adresse ermitteln:
   ```bash
   ip a s
   ```
   Die IP-Adresse ist magenta eingefärbt, es ist die erste Adresse beim Interface `ens18` (bzw. dem Interface, das nicht `lo` ist). Beispielausgabe:
   ```
   1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 ...
       inet 127.0.0.1/8 scope host lo
   2: ens18: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
       link/ether bc:24:11:d1:34:dd brd ff:ff:ff:ff:ff:ff
       inet 192.168.99.145/24 brd 192.168.99.255 scope global dynamic noprefixroute ens18
          valid_lft 72378sec preferred_lft 61578sec
       inet6 fe80::be24:11ff:fed1:34dd/64 scope link
   ```
   In diesem Beispiel lautet die IP-Adresse `192.168.99.145`.
4. Temporäres Passwort setzen:
   ```bash
   passwd
   ```

> [!WARNING]
> Die Konsole verwendet ein **US-Tastaturlayout**: keine Umlaute, Z und Y sind vertauscht. Das Passwort darf einfach sein, es dient nur der initialen Verbindung und wird anschließend geändert.

### DNS und DHCP konfigurieren

1. Einen **Wildcard-A-Eintrag** in der eigenen Domain anlegen:
   - Name: `*`
   - Adresse: ermittelte IP des Servers
   - TTL: 2 Minuten
2. Im Router die IP-Adresse **statisch per DHCP** vergeben.

---

## 6. Installation

### Per SSH verbinden

```bash
ssh nixos@<IP-ADRESSE>
```

Der Prompt sollte lauten:

```
[nixos@nixos:~]$
```

### Repository klonen und Installation starten

1. Repository klonen:
   ```bash
   git clone https://github.com/LucaDev/LFM-Team-Blue.git
   ```
2. Installationsskript ausführen:
   ```bash
   sudo ./LFM-Team-Blue/apphost/nixos/install.sh
   ```

Das Skript partitioniert die Festplatte, installiert NixOS [[3]](#quelle-3), generiert die Secure-Boot-Schlüssel, installiert den Bootloader, fragt die `.env`-Werte ab (Domain, ACME E-Mail, Cloudflare-Token, Authelia-Zugangsdaten), generiert die restlichen Secrets (Ntfy) automatisch und startet das System anschließend neu. Die folgenden Unterabschnitte beschreiben die interaktiven Prompts in der Reihenfolge, in der sie tatsächlich erscheinen.

### Passwort für den Admin-Nutzer setzen

Als erstes fragt das Skript nach einem Passwort für den `apphost`-Nutzer (mit Bestätigung):

```
Passwort:
Passwort bestätigen:
```

> [!NOTE]
> Dieses Passwort ist **nicht** identisch mit dem in [Abschnitt 5](#5-initiale-nixos-konfiguration) per `passwd` gesetzten temporären Passwort des Live-ISO-Nutzers `nixos` – jenes wird mit der Installation obsolet, da die Festplatte komplett neu beschrieben wird. Das hier gesetzte Passwort wird ausschließlich für `sudo` als zweiter Faktor nach dem SSH-Key benötigt.

Direkt danach folgt die Sicherheitsabfrage vor der Partitionierung:

```
Bitte 'ja' eingeben um fortzufahren:
```

> [!WARNING]
> Ab hier werden **alle Daten auf der Zielfestplatte unwiderruflich gelöscht**. Nur mit `ja` bestätigen, wenn die richtige Festplatte ausgewählt ist.

### Optionale Festplattenverschlüsselung

Direkt danach fragt das Skript, ob die Root-Partition zusätzlich mit LUKS2 verschlüsselt werden soll:

```
Festplattenverschlüsselung aktivieren? [j/N]:
```

Standardmäßig ist die Verschlüsselung **aus** (Antwort einfach mit Enter überspringen). Bei `j`/`ja` wird direkt im Anschluss eine Passphrase für die Formatierung festgelegt.

> [!WARNING]
> Eine verschlüsselte Root-Partition muss bei **jedem** Boot mit dieser Passphrase über die Server-Konsole (z.B. die Proxmox-Konsole) entsperrt werden. Automatische Neustarts, etwa nach Kernel-Updates, bleiben dann so lange stehen, bis die Passphrase eingegeben wurde. Wer keinen regelmäßigen Konsolenzugriff hat, sollte die Verschlüsselung deaktiviert lassen.

Die Einstellung lässt sich auch ohne den interaktiven Dialog umschalten, indem `nixos/disk-encryption.nix` vor der Installation manuell auf `true`/`false` gesetzt wird. Ein nachträgliches Umschalten auf einem bereits installierten System ist nicht möglich, da dafür die Festplatte neu partitioniert werden muss.

### SSH-Key für den Admin-Nutzer

Direkt danach fragt das Skript nach einem **SSH Public Key**, der für den Login als `apphost`-Nutzer hinterlegt wird:

```
SSH Public Key:
```

> [!WARNING]
> Passwort-Login ist deaktiviert, der hier hinterlegte SSH-Key ist der einzige Anmeldeweg zum Server. Das zuvor gesetzte Passwort wird ausschließlich für `sudo` als zweiter Faktor benötigt.

Falls auf dem **lokalen Rechner** (nicht auf dem Server!) noch kein SSH-Schlüsselpaar existiert, zunächst dort eines erzeugen:

```bash
ssh-keygen -t ed25519
```

Die Standardpfade (`~/.ssh/id_ed25519` bzw. `~/.ssh/id_ed25519.pub` unter Windows mit dem gleichen Dateinamen in `C:\Users\<Nutzername>\.ssh`) können mit Enter übernommen werden, am besten mit Passphrase für eine weitere Schutzschicht.

Anschließend den Public Key (Endung: .pub) anzeigen und beim Prompt einfügen:

```bash
cat ~/.ssh/id_ed25519.pub

Beispielausgabe:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjUx5YA3RwdM0xfXY7KMZb3N3BrK1tDyJ/qcQQvBWJE luca@Laptop-von-Luca.local
```

Der Key wird automatisch nach `nixos/ssh-key.nix` geschrieben und kann dort jederzeit nachträglich angepasst werden (z.B. um weitere Keys zu ergänzen). Änderungen an dieser Datei werden erst nach einem `rebuild` (siehe Aliase) wirksam.

Nach diesem Prompt partitioniert und formatiert das Skript die Festplatte, installiert NixOS und richtet Secure Boot sowie den Bootloader ein – ohne weitere Eingaben. Erst danach folgt die `.env`-Konfiguration:

### Cloudflare API-Token erstellen

#### Warum Cloudflare?

Für gültige TLS-Zertifikate (Let's Encrypt) wird die **ACME DNS-01-Challenge** [[7]](#quelle-7) verwendet. Bei dieser Methode beweist der Server den Besitz einer Domain, indem er einen temporären TXT-Eintrag in der DNS-Zone anlegt. Let's Encrypt prüft den Eintrag und stellt bei Erfolg das Zertifikat aus.

Der Vorteil: Der Server muss dafür nicht aus dem Internet erreichbar sein. Ports 80/443 können vollständig hinter dem Router verbleiben. Cloudflare dient hier ausschließlich als DNS-Anbieter, der diesen TXT-Eintrag setzen darf. Es fließen **keinerlei sensible Inhalte** an Cloudflare.

> [!NOTE]
> **Andere DNS-Anbieter sind ebenfalls möglich** (z.B. Hetzner DNS, Namecheap, Porkbun). Cloudflare wurde gewählt, weil es registrar-unabhängig ist: Die DNS-Verwaltung kann auf Cloudflare umgezogen werden, unabhängig davon, wo die Domain registriert ist. Alle von Traefik unterstützten Anbieter sind in der Traefik-Dokumentation zu den ACME-DNS-Providern gelistet [[9]](#quelle-9). Bei Verwendung eines anderen Anbieters muss `ACME_DNS_PROVIDER` in der `.env` entsprechend gesetzt und der passende API-Key-Variablenname verwendet werden.

#### Cloudflare API-Token generieren

Die folgenden Schritte orientieren sich an der offiziellen Cloudflare-Dokumentation zum Erstellen von API-Tokens [[8]](#quelle-8).

1. Unter **dash.cloudflare.com** einloggen.
2. Oben rechts auf das Profilbild klicken → **My Profile** → Reiter **API Tokens**.
3. **Create Token** klicken.
4. Die Vorlage **„Edit zone DNS"** auswählen und auf **Use template** klicken.
5. Unter **Zone Resources** einstellen:
   - _Include_ → _Specific zone_ → eigene Domain auswählen
6. Optional: unter **Client IP Address Filtering** die IP des Servers eintragen, um den Token auf diese IP zu beschränken.
7. **Continue to summary** → **Create Token**.
8. Den angezeigten Token **sofort kopieren**. Er wird nur einmal angezeigt.

> [!WARNING]
> Der Token benötigt ausschließlich die Berechtigung `Zone:DNS:Edit` für die jeweilige Zone. Keinen globalen API-Key verwenden, ein scoped Token minimiert den Schaden bei versehentlicher Exposition.

Der Token wird im nächsten Schritt als `CF_DNS_API_TOKEN` in die `.env`-Datei eingetragen.

#### Beispiel

![Beispielbild](docs/Cloudflare%20API%20Key.png)

### .env konfigurieren

Nach Abschluss der Installation (NixOS, Secure Boot, Bootloader) fragt das Skript noch die restlichen Werte für die `.env`-Datei ab:

```
Domain (z.B. example.com):
ACME E-Mail (Let's Encrypt):
Cloudflare API Token:
Authelia Admin-Nutzer [admin]:
Authelia Admin-E-Mail [<ACME E-Mail>]:
Authelia Admin-Passwort:
Authelia Admin-Passwort (bestätigen):
```

> [!NOTE]
> **Ntfy-Passwörter werden automatisch als zufällige Zeichenketten generiert**, dafür ist keine Eingabe nötig. Alle Werte – auch die hier abgefragten – können jederzeit nachträglich in `/opt/monorepo/apphost/.env` angepasst werden, siehe [Abschnitt 11](#11-passwörter-ändern).

Anschließend generiert das Skript die Secrets für Authelia und Ntfy und startet automatisch neu.

### Erneut per SSH verbinden

Alten SSH-Fingerprint entfernen und neu verbinden:

```bash
ssh-keygen -R <IP-ADRESSE>
ssh apphost@<IP-ADRESSE>
```

---

## 7. Secure Boot einrichten

Secure Boot wird über `sbctl` [[5]](#quelle-5) verwaltet, das mittels des NixOS-Moduls `lanzaboote` [[6]](#quelle-6) in die Konfiguration eingebunden ist.

1. Secure-Boot-Schlüssel eintragen:
   ```bash
   sudo sbctl enroll-keys --tpm-eventlog
   ```
2. System neu starten:
   ```bash
   sudo reboot now
   ```
3. Secure-Boot-Status prüfen:
   ```bash
   sudo sbctl status
   ```
   Die Ausgabe sollte wie folgt aussehen:
   ```
   Installed:  [OK] sbctl is installed
   Owner GUID: <...>
   Setup Mode: [OK] Disabled
   Secure Boot:[OK] Enabled
   Vendor Keys: tpm-eventlog
   ```

---

## 8. Stack starten

Das Installationsskript hat die `.env` bereits befüllt und alle Secrets generiert. Nach dem Neustart genügen drei Schritte.

### Stack erstmals starten

```bash
cd /opt/monorepo/apphost
docker compose up -d
```

### Tor-Adresse eintragen

Nach dem ersten Start die Onion-Adresse ermitteln und in die `.env` eintragen, damit alle Dienste sie kennen:

```bash
bash scripts/show-onion-address.sh
vim .env        # TOR_DOMAIN=<adresse>.onion eintragen
docker compose up -d
```

### OIDC-Clients einrichten

`scripts/update-secrets-authelia.sh` (läuft automatisch im Installationsskript, siehe [Abschnitt 6](#6-installation)) richtet Authelia [[10]](#quelle-10) als zentralen SSO/OIDC-Provider ein. Danach sind noch ein paar Schritte nötig, damit die einzelnen Dienste die neuen Secrets übernehmen bzw. sich gegen Authelia registrieren:

1. **Authelia deployen** (nur nötig, wenn Authelia-Secrets isoliert neu generiert wurden, nicht beim ersten `docker compose up -d`):

   ```bash
   docker compose up -d authelia authelia-redis
   ```

2. **Immich OIDC (manuell):** Der Immich-OIDC-Client kann nicht automatisch konfiguriert werden und muss einmalig in der Immich Admin-UI eingetragen werden (siehe Immich-Dokumentation zu OAuth [[11]](#quelle-11)):

   _Administration → Settings → OAuth_

   | Feld          | Wert                                      |
   | ------------- | ----------------------------------------- |
   | Issuer URL    | `https://${AUTHELIA_SUBDOMAIN}.${DOMAIN}` |
   | Client ID     | `immich`                                  |
   | Client Secret | siehe unten                               |

   ```bash
   # Client Secret anzeigen:
   grep AUTHELIA_OIDC_IMMICH_SECRET secrets/oidc-immich.env
   ```

3. **Grafana und Paperless neu starten**, damit sie die (neu generierten) OIDC-Secrets übernehmen:

   ```bash
   docker compose up -d grafana paperless
   ```

4. **Forgejo OIDC:** `forgejo-init` richtet den OIDC-Client beim ersten `docker compose up` automatisch ein. Bei Bedarf (z. B. nach einer Secret-Rotation) manuell erneut ausführen:
   ```bash
   docker compose run --rm forgejo-init
   ```

> [!NOTE]
> **Passwörter ändern:** Nach Änderungen an Passwörtern in der `.env` müssen die Secrets neu generiert und der Stack neu gestartet werden. Details siehe [Abschnitt 11](#11-passwörter-ändern).

---

## 9. AIDE initialisieren

AIDE (Advanced Intrusion Detection Environment) [[12]](#quelle-12) überwacht die Integrität des Dateisystems und erkennt unbefugte Änderungen. Direkt nach der Installation wird die Referenzdatenbank einmalig angelegt.

1. Datenbank initialisieren:
   ```bash
   aide --init && cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
   ```
2. Erste Integritätsprüfung ausführen:
   ```bash
   aide --check
   ```

Die laufende Überwachung im Betrieb ist in [Abschnitt 12](#12-aide-integritätsprüfung) beschrieben.

---

# Teil 2 – Betrieb und Wartung

Für häufige Verwaltungsaufgaben sind Shell-Aliase definiert, die nach dem Login als `apphost` direkt verfügbar sind.

## 10. Verwaltungs-Aliase

### NixOS-System aktualisieren

| Alias          | Beschreibung                                                                                                                                                   |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pull`         | Holt Repo-Updates (`git pull` in `/opt/monorepo`) – nur der `apphost/`-Pfad des Monorepos wird dabei übertragen.                                               |
| `update`       | `pull`, danach Flake-Inputs aktualisieren (zieht neue NixOS-Channel-Version) **und** sofort rebuilden.                                                         |
| `rebuild`      | System neu bauen und **sofort** aktivieren, ohne Flake-Inputs zu aktualisieren. Nützlich nach Änderungen an Konfigurationsdateien.                             |
| `rebuild-boot` | System neu bauen, Aktivierung erst **beim nächsten Neustart**. Sinnvoll, wenn Kernel-Updates ein Reboot erfordern, ohne den laufenden Betrieb zu unterbrechen. |
| `gc`           | Nix-Store aufräumen: löscht Generationen älter als 30 Tage und optimiert den Store (Deduplizierung via Hard-Links).                                            |

> [!WARNING]
> `update` und `rebuild` aktivieren die neue Konfiguration sofort (_switch_). Falls etwas schiefgeht, kann beim nächsten Reboot über das Boot-Menü eine ältere Generation ausgewählt werden (max. 10 Generationen werden vorgehalten).

### Docker-Stack verwalten

| Alias           | Beschreibung                                                        |
| --------------- | ------------------------------------------------------------------- |
| `up`            | Alle Container starten bzw. aktualisieren (`docker compose up -d`)  |
| `down`          | Alle Container stoppen                                              |
| `logs`          | Log-Stream aller Container (`docker compose logs -f`)               |
| `status`        | Docker-Daemon-Status und laufende Container (`docker ps`)           |
| `regen-secrets` | Alle Secrets neu generieren (nach Passwortänderungen in der `.env`) |

Nach dem Mergen eines RenovateBot-PRs genügt `up`, um die aktualisierten Images zu ziehen und die Container neu zu starten.

---

## 11. Passwörter ändern

Bei Änderungen von Ntfy-, Authelia- oder anderen Secrets in der `.env` müssen diese neu generiert und der betroffene Dienst neu gestartet werden:

```bash
vim /opt/monorepo/apphost/.env   # Passwort anpassen
regen-secrets           # alle Secrets neu generieren
up                      # Stack neu starten
```

---

## 12. AIDE Integritätsprüfung

Nach der initialen Einrichtung ([Abschnitt 9](#9-aide-initialisieren)) läuft AIDE im Betrieb automatisch:

- Eine **tägliche** automatische Prüfung erfolgt über einen systemd-Service.
- Überwacht werden u. a. `/etc`, `/bin`, `/sbin`, `/lib*`, `/usr/bin`, `/usr/sbin`, `/boot` und `/opt/monorepo/apphost/config`.

Eine manuelle Prüfung ist jederzeit möglich:

```bash
aide --check
```

> [!NOTE]
> Nach legitimen Systemänderungen (z.B. einem größeren Update) sollte die Referenzdatenbank neu erstellt werden, damit die täglichen Prüfungen keine Fehlalarme melden:
>
> ```bash
> aide --init && cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
> ```

---

## 13. Container-Sicherheitsbericht

Ein automatischer Container-Sicherheitsbericht wird jeden **Montag um 02:00 Uhr** mit dem Security-Scanner **Trivy** [[13]](#quelle-13) erstellt und unter `/var/log/docker-security-scan.log` abgelegt. Trivy prüft alle laufenden Images auf HIGH/CRITICAL-Schwachstellen.

```bash
less /var/log/docker-security-scan.log
```

---

## 14. Tor-Onion-Adresse anzeigen

Die `.onion`-Adresse (Onion Service v3 [[15]](#quelle-15)) wird beim ersten Start des Tor-Containers automatisch generiert und ist persistent. Sie kann jederzeit angezeigt werden:

```bash
bash /opt/monorepo/apphost/scripts/show-onion-address.sh
```

Beispielausgabe:

```
Tor Onion-Adresse (Hidden Service v3)
https://<26-stellige-adresse>.onion
```

> [!NOTE]
> Alle Dienste sind unter `<subdomain>.<onion-adresse>` erreichbar, z.B. `dashboard.<adresse>.onion`. Der Tor-Browser-Hinweis auf das selbstsignierte Zertifikat ist normal: Tor erzeugt kein öffentlich vertrauenswürdiges TLS-Zertifikat, da die Onion-Kommunikation bereits Ende-zu-Ende verschlüsselt ist.
>
> Die Adresse muss nach der Erstinstallation in die `.env`-Datei eingetragen werden:
> `TOR_DOMAIN=<adresse>.onion`

---

## 15. Automatische Container-Updates mit RenovateBot

Alle Container-Image-Updates erfolgen automatisiert über RenovateBot [[14]](#quelle-14) direkt im GitHub-Repository. Es ist keine manuelle Versionspflege erforderlich.

### Wie es funktioniert

RenovateBot überwacht kontinuierlich das Repository und erkennt neue Versionen von Container-Images in den `docker-compose`-Dateien. Sobald ein Update verfügbar ist, öffnet RenovateBot automatisch einen Pull Request mit der aktualisierten Image-Version. Dieser PR kann geprüft, getestet und anschließend gemergt werden. Die Änderung landet dann beim nächsten `docker compose up -d` (Alias `up`) auf dem Server.

### Vorteile

- **Keine veralteten Images:** Updates werden zuverlässig erkannt, ohne dass jemand manuell auf neue Releases achten muss.
- **Nachvollziehbarkeit:** Jede Aktualisierung ist als einzelner Commit im Git-Verlauf dokumentiert (wann, was und warum geändert wurde).
- **Kontrollierter Rollout:** Updates werden als Pull Request vorgeschlagen, nicht sofort eingespielt. Änderungen können vor dem Merge begutachtet oder in einer Testumgebung validiert werden.
- **Sicherheitsrelevanz:** Gepatchte Images mit Sicherheitsfixes werden zeitnah erkannt. In Kombination mit dem wöchentlichen Container-Sicherheitsscan entsteht eine kontinuierliche Angriffsflächen-Reduktion.

> [!NOTE]
> Ein vollautomatisches Mergen (ohne manuellen Review) ist mit RenovateBot ebenfalls möglich, muss jedoch explizit aktiviert werden und wurde hier zunächst bewusst nicht eingerichtet.

---

## 16. Proxmox-Backups einrichten

Damit die komplette `apphost`-VM im Notfall wiederhergestellt werden kann, sollten regelmäßige Backups auf Ebene von Proxmox eingerichtet werden [[2]](#quelle-2). Proxmox bringt dafür ein eigenes Werkzeug mit, das sich vollständig über die Weboberfläche steuern lässt. Es sichert die komplette VM (also Festplatten, Konfiguration, TPM, etc.), nicht nur einzelne Dateien.

### Backup-Speicher festlegen

1. In Proxmox auf **Datacenter → Storage** gehen.
2. Sicherstellen, dass ein Storage existiert, der den Content-Typ **„VZDump backup file"** erlaubt (z.B. `local` oder ein per NFS/CIFS eingebundener Netzwerkspeicher).

> [!WARNING]
> Backups sollten möglichst auf einem externen oder Netzwerk-Speicher liegen und der bekannten 3-2-1 Regel folgen. Liegt das Backup nur auf derselben Festplatte wie die VM, ist es bei einem Hardware-Ausfall der Node ebenfalls verloren.

### Geplantes Backup anlegen

1. Auf **Datacenter → Backup → Add** klicken.
2. Folgende Einstellungen wählen:
   - **VM:** `apphost`
   - **Storage:** den zuvor festgelegten Backup-Speicher
   - **Schedule:** z.B. täglich um `03:00`
   - **Mode:** `Snapshot` (die VM läuft während des Backups weiter). Alternativen sind `Suspend` oder `Stop` für noch sauberere Backups.
   - **Compression:** `ZSTD` (guter Kompromiss aus Kompression und Geschwindigkeit)
3. **Retention** festlegen, damit der Speicher nicht vollläuft, z.B. die letzten 7 täglichen und 4 wöchentlichen Backups behalten.

### Manuelles Backup

Ein Backup lässt sich auch jederzeit von Hand auslösen:

_VM `apphost` → Backup → Backup now_

### Wiederherstellung

1. _VM `apphost` → Backup_ öffnen.
2. Das gewünschte Backup auswählen und auf **Restore** klicken.

> [!WARNING]
> Ein Restore überschreibt die bestehende VM! Im Zweifel das Backup zunächst als neue VM mit anderer ID wiederherstellen. Es empfiehlt sich, eine Wiederherstellung gelegentlich zu testen, denn ein Backup ist nur dann etwas wert, wenn der Restore im Ernstfall auch funktioniert.

---

# Anhang

## Quellen

Im Fließtext wird mit `[[n]]` auf die folgenden externen Quellen verwiesen. Die Nummerierung folgt der Reihenfolge der ersten Erwähnung im Dokument. Dieselben Quellen sind zusätzlich als BibTeX-Einträge in `Doku/Definitionen/literatur.bib` hinterlegt (Schlüssel jeweils in Klammern), damit sie bei Bedarf auch aus der LaTeX-Dokumentation zitiert werden können.

1. <a id="quelle-1"></a>Proxmox Server Solutions GmbH: _Proxmox VE Documentation_. https://pve.proxmox.com/pve-docs/ (`proxmoxve_docs`)
2. <a id="quelle-2"></a>Proxmox Server Solutions GmbH: _Backup and Restore (vzdump)_. https://pve.proxmox.com/pve-docs/chapter-vzdump.html (`proxmox_vzdump`)
3. <a id="quelle-3"></a>NixOS Foundation: _NixOS Manual_. https://nixos.org/manual/nixos/stable/ (`nixos_manual`)
4. <a id="quelle-4"></a>NixOS Foundation: _Release Channels_. https://channels.nixos.org/ (`nixos_channels`)
5. <a id="quelle-5"></a>Foxboron: _sbctl – Secure Boot Key Manager_. https://github.com/Foxboron/sbctl (`sbctl_github`)
6. <a id="quelle-6"></a>nix-community: _lanzaboote – Secure Boot for NixOS_. https://github.com/nix-community/lanzaboote (`lanzaboote_github`)
7. <a id="quelle-7"></a>Let's Encrypt (ISRG): _DNS-01 Challenge_. https://letsencrypt.org/docs/challenge-types/#dns-01-challenge (`letsencrypt_dns01`)
8. <a id="quelle-8"></a>Cloudflare: _Create an API Token_. https://developers.cloudflare.com/fundamentals/api/get-started/create-token/ (`cloudflare_api_token`)
9. <a id="quelle-9"></a>Traefik Labs: _ACME – Supported DNS Providers_. https://doc.traefik.io/traefik/https/acme/#providers (`traefik_acme_providers`)
10. <a id="quelle-10"></a>Authelia: _Documentation_. https://www.authelia.com/overview/prologue/introduction/ (`authelia_docs`)
11. <a id="quelle-11"></a>Immich: _OAuth/OIDC Configuration_. https://immich.app/docs/administration/oauth (`immich_oauth`)
12. <a id="quelle-12"></a>AIDE Project: _Advanced Intrusion Detection Environment_. https://aide.github.io/ (`aide_project`)
13. <a id="quelle-13"></a>Aqua Security: _Trivy Documentation_. https://trivy.dev/ (`trivy_docs`)
14. <a id="quelle-14"></a>Mend.io: _RenovateBot Documentation_. https://docs.renovatebot.com/ (`renovatebot_docs`)
15. <a id="quelle-15"></a>The Tor Project: _Onion Services_. https://community.torproject.org/onion-services/ (`tor_onion_services`)
