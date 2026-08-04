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
14. [Automatische Container-Updates mit RenovateBot](#14-automatische-container-updates-mit-renovatebot)
15. [Proxmox-Backups einrichten](#15-proxmox-backups-einrichten)

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

### Datenplatte für Fotos, Dokumente und Dateien

Der Stack erwartet **zusätzlich zur Systemplatte** einen zweiten Datenträger, der nach `/mnt/media` gemountet wird. Dort liegen die eigentlichen Nutzdaten: Immich-Fotos, Paperless-Dokumente, OpenCloud-Dateien und die Radicale-Kalender. `nixos/modules/media-disk.nix` mountet ihn fest über

```
/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
```

Die Platte muss der VM deshalb **als `scsi1`** durchgereicht werden – entweder als weiterer virtueller Datenträger oder als durchgereichte physische Platte:

```bash
# Beispiel: physische USB-/SATA-Platte an die VM 100 durchreichen
qm set 100 -scsi1 /dev/disk/by-id/<deine-platte>
```

Prüfen lässt sich der Name nach dem ersten Boot in der VM mit `ls -l /dev/disk/by-id/`. Weicht er ab, den Pfad in `nixos/modules/media-disk.nix` anpassen und `rebuild` ausführen.

> [!WARNING]
> Der Mount ist mit `nofail` konfiguriert, damit ein fehlender Datenträger den Host nicht am Booten hindert. Die Kehrseite: **fehlt die Platte, fällt es nicht sofort auf.** `apphost-media-dirs` überspringt sich dann stillschweigend, Docker legt `/mnt/media/*` als root-eigene Verzeichnisse auf der Systemplatte an, und Immich, OpenCloud und Radicale laufen in die „nobody"-Falle (Container starten in einer Crash-Schleife, weil ihnen die Ordner nicht gehören).
>
> Dafür gibt es jetzt den Alert `MediaDiskMissing`. Manuell prüfen:
>
> ```bash
> mountpoint /mnt/media && df -h /mnt/media
> ```
>
> Wurden bereits falsche Verzeichnisse auf der Systemplatte angelegt: Stack stoppen (`down`), dann **mit Schutzabfrage** aufräumen. Der Guard ist kein Zierrat – ohne ihn löscht derselbe Befehl bei eingehängter Platte sämtliche Fotos und Dokumente:
>
> ```bash
> down
> if mountpoint -q /mnt/media; then
>   echo "ABBRUCH: Platte ist eingehängt – hier steht nichts zum Aufräumen."
> else
>   sudo rm -rf /mnt/media/*
> fi
> # Platte einhängen (oder Host neu starten), dann:
> sudo systemctl start apphost-media-dirs
> up
> ```

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
Festplattenverschlüsselung aktivieren? [J/n]:
```

Standardmäßig ist die Verschlüsselung **an** (Antwort einfach mit Enter bestätigen); direkt im Anschluss wird eine Passphrase für die Formatierung festgelegt. Mit `n`/`nein` wird sie abgeschaltet.

Hintergrund: Ohne Verschlüsselung liegen alle Klartext-Zugangsdaten unverschlüsselt auf der Platte – `.env` (die Quelle des `secrets`-Alias), `secrets/radicale_password.txt` und `secrets/vaultwarden_admin_token.txt`. Wer die Platte oder das Proxmox-Disk-Image in die Hand bekommt, hat damit sämtliche Passwörter des Stacks.

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

#### Nachträglicher Wechsel: lokal → echte Domain mit Let's Encrypt

Der Cloudflare-Token ist optional. Ohne ihn läuft der Stack rein lokal: `apphost-local-ca.service` erzeugt eine eigene CA, Traefik liefert deren Zertifikat aus, und die OIDC-Backends vertrauen ihr über gemountete Zertifikatsdateien.

Trägt man später Domain und Token in die `.env` ein, holt Traefik beim nächsten Start echte Zertifikate. Damit dabei auch die **Server-zu-Server**-Aufrufe (OIDC-Token/Userinfo von Grafana, Immich und Paperless gegen Authelia) weiter funktionieren, bekommen Paperless und Grafana nicht mehr die lokale CA allein gemountet, sondern `ca-bundle.crt` — die System-CAs **plus** die lokale CA:

| Dienst | Variable | Verhalten |
| --- | --- | --- |
| Immich | `NODE_EXTRA_CA_CERTS` | **ergänzt** den Truststore |
| Paperless | `REQUESTS_CA_BUNDLE` | **ersetzt** den Truststore → braucht das Bundle |
| Grafana | `GF_AUTH_GENERIC_OAUTH_TLS_CLIENT_CA` | **ersetzt** den Truststore → braucht das Bundle |

Ohne das Bundle würde der Token-Call bei Paperless und Grafana in dem Moment brechen, in dem Traefik ein Let's-Encrypt-Zertifikat ausliefert — die Dienste würden dann nur noch der lokalen CA vertrauen. Das Bundle erzeugt `apphost-local-ca.service` bei jedem Boot neu, damit Aktualisierungen der System-CAs mitkommen.

Nach dem Eintragen von Domain und Token also:

```bash
sudo nixos-rebuild switch --flake path:/opt/monorepo#apphost   # Zertifikat + Bundle für die neue Domain
up-all                                                         # Container mit neuen Werten neu erzeugen
```

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
ntfy Admin-Passwort (leer = zufällig):
OpenCloud Admin-Passwort (leer = zufällig):
Grafana Admin-Passwort (leer = zufällig):
Radicale/Kalender-Passwort (DAVx5 am Handy) (leer = zufällig):
Vaultwarden /admin-Token (leer = zufällig):
```

> [!NOTE]
> **Für die Dienste, in die du dich selbst einloggst** (Authelia, ntfy, OpenCloud, Grafana, Radicale, Vaultwarden), kannst du direkt ein eigenes, merkbares Passwort vergeben – oder **Enter drücken für ein zufälliges** (empfehlenswert für alles, was du nicht am Handy tippst). Rein interne Secrets (DB, JWT, Paperless, Collabora …) werden immer automatisch generiert. Alle Werte lassen sich jederzeit nachträglich in `/opt/monorepo/.env` ändern, siehe [Abschnitt 11](#11-passwörter-ändern).

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
cd /opt/monorepo
up          # bzw. bash scripts/stack-up.sh
```

> [!IMPORTANT]
> Hier stand `cd /opt/monorepo/apphost && docker compose up -d`. Beides war
> falsch: das Verzeichnis `apphost/` stammt aus der Monorepo-Zeit und existiert
> nicht mehr (der Befehl bricht mit „No such file or directory“ ab), und
> `docker compose up -d` startet **alle** Container gleichzeitig. Beim Erststart
> schreiben Immich, OpenCloud und Paperless dann zusammen auf die USB-Platte und
> haben Host und VM zum Absturz gebracht – genau dagegen ist
> `scripts/stack-up.sh` (Alias `up`) gebaut, das gestaffelt hochfährt.

### OIDC-Clients einrichten

`scripts/update-secrets-authelia.sh` (läuft automatisch im Installationsskript, siehe [Abschnitt 6](#6-installation)) richtet Authelia [[10]](#quelle-10) als zentralen SSO/OIDC-Provider ein. Danach sind noch ein paar Schritte nötig, damit die einzelnen Dienste die neuen Secrets übernehmen bzw. sich gegen Authelia registrieren:

1. **Authelia deployen** (nur nötig, wenn Authelia-Secrets isoliert neu generiert wurden, nicht beim ersten Start):

   ```bash
   docker compose up -d authelia
   ```

   > Hier stand `docker compose up -d authelia authelia-redis`. Einen Container
   > `authelia-redis` gibt es im Stack nicht – Authelia speichert seine Sitzungen
   > in SQLite (`storage.local` in `config/authelia/configuration.yml`). Der Befehl
   > wäre mit einem Fehler abgebrochen, ohne Authelia neu zu starten.

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

### Zweiter Faktor für die Admin-Oberflächen

Diese Adressen stehen in `config/authelia/configuration.yml` auf `two_factor` – wer dort hineinkommt, sieht bzw. verändert die komplette Infrastruktur oder verwaltet Konten:

| Adresse | Was dahinter liegt |
| --- | --- |
| `traefik.<domain>` | Reverse-Proxy-Dashboard |
| `prometheus.<domain>` | Metriken und Query-API |
| `alertmanager.<domain>` | Alarme, Silences |
| `vault.<domain>/admin` | Vaultwarden-Adminpanel (Konten, Einladungen, 2FA anderer Nutzer) |
| `bichon.<domain>` | Mail-Archiv – die gesamte Korrespondenz im Volltext, auch die „Passwort zurücksetzen“-Mails aller anderen Dienste |

Der Vaultwarden-**Tresor** selbst bleibt davon unberührt – die Bitwarden-Clients können kein Browser-SSO. Alle übrigen Dienste bleiben bei `one_factor`.

Beim **ersten** Aufruf einer dieser Adressen verlangt Authelia deshalb die Registrierung eines zweiten Faktors (TOTP-App oder WebAuthn/Passkey). Authelia verschickt dafür einen Bestätigungslink – allerdings nicht per Mail, sondern über den `filesystem`-Notifier in eine Datei im Container (es ist kein SMTP konfiguriert).

Der Link steht in der Ausgabe von `secrets`, zusammen mit allen anderen Zugangsdaten:

```bash
secrets        # bzw. bash /opt/monorepo/scripts/show-secrets.sh
```

```
▶ Authelia – Zweiter Faktor (TOTP/WebAuthn)
  Pflicht für: traefik. / prometheus. / alertmanager.<domain> und vault.<domain>/admin
  Letzte Anforderung       Authelia: Register your mobile
  Registrierungslink       https://auth.<domain>/one-time-code?token=…
  -> im Browser öffnen; der Link ist kurzlebig und nur einmal gültig.
```

Reihenfolge also: geschützte Adresse aufrufen, im Portal **Register device** klicken, dann `secrets` ausführen und den Link öffnen. Danach den Faktor registrieren (TOTP: QR-Code mit einer Authenticator-App scannen) – ab dann funktioniert der Login normal.

Direkt geht es weiterhin mit `docker exec authelia cat /data/notification.txt`.

> [!NOTE]
> Ohne diesen Schritt bleibt man vor einer Aufforderung stehen, die sich nicht erfüllen lässt. Wer keinen zweiten Faktor möchte, setzt die betroffenen Regeln in `config/authelia/configuration.yml` zurück auf `policy: one_factor` und startet Authelia neu (`docker compose up -d --force-recreate authelia`).

### Kalender (Radicale) & Vorratsverwaltung (Grocy)

**Radicale (CalDAV/CardDAV)** läuft mit eigener Basic-Auth – bewusst **nicht** hinter Authelia, weil DAVx5 kein Browser-SSO macht. Zugangsdaten anzeigen:

```bash
secrets                             # zeigt Nutzer + Passwort
cat secrets/radicale_password.txt   # nur das Passwort (für DAVx5)
```

Standard-Nutzer ist `admin`. Am Handy per **DAVx5** einbinden (Basis-URL `https://cal.${DOMAIN}`, Nutzer `admin`, Passwort s. o.); die Kalender/Kontakte erscheinen dann in der nativen Samsung-Kalender-App (inkl. Widget). Passwort neu setzen: `RADICALE_USER` in `.env`, dann `regen-secrets`.

**Grocy (Vorratsverwaltung)** ist bewusst reduziert auf **Bestand** (inkl. Standorten Kühlschrank/Regal/Keller), **Verbrauchen/Kaufen**, **Einkaufsliste** und **Barcode-Scanner**. Nicht benötigte Module (Rezepte, Speiseplan, Hausarbeiten, Aufgaben, Batterien, Geräte, Kalender) sind **declarativ** über `config/grocy/config.php` abgeschaltet – die Datei wird read-only nach `/config/data/config.php` gemountet und von Grocy als Override vor `config-dist.php` geladen. Module (de)aktivieren = `FEATURE_FLAG_*` dort anpassen, dann:

```bash
docker compose up -d --force-recreate grocy
```

Produkte gruppieren (z. B. verschiedene Tomatensoßen) – kein Flag nötig, eingebaut:

- **Produktgruppen** (Stammdaten) – reine Kategorie/Sortierung.
- **Eltern-/Kind-Produkte** – „egal welche Sorte zählt als ein Bestand" mit kumuliertem Mindestbestand.

**Login:** Grocy nutzt echtes Single-Sign-on über Authelia (Reverse-Proxy-Auth, `config/grocy/config.php`) – **kein zweiter Login**. Der Authelia-Login (dein custom Passwort) ist die einzige Anmeldung; der übermittelte Nutzername (i. d. R. `admin`) wird auf den gleichnamigen Grocy-Nutzer abgebildet. Damit das sicher ist, entfernt die `authelia-chain` client-gesetzte `Remote-User`-Header, bevor Authelia den authentifizierten Wert setzt (`config/traefik/dynamic/middlewares.yml`).

---

## 9. AIDE initialisieren

AIDE (Advanced Intrusion Detection Environment) [[12]](#quelle-12) überwacht die Integrität des Dateisystems und erkennt unbefugte Änderungen.

Die Referenzdatenbank wird **automatisch** angelegt: Der systemd-Service `aide-check` legt beim ersten Lauf die Baseline an und prüft ab dem zweiten Lauf gegen sie. Wer nicht bis zum nächsten Timer warten will, stößt ihn direkt an:

```bash
sudo systemctl start aide-check
journalctl -u aide-check -n 50 --no-pager
```

Die laufende Überwachung im Betrieb ist in [Abschnitt 12](#12-aide-integritätsprüfung) beschrieben.

---

# Teil 2 – Betrieb und Wartung

Für häufige Verwaltungsaufgaben sind Shell-Aliase definiert, die nach dem Login als `apphost` direkt verfügbar sind.

## 10. Verwaltungs-Aliase

### NixOS-System aktualisieren

| Alias          | Beschreibung                                                                                                                                                   |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pull`         | Holt Repo-Updates (`git pull` in `/opt/monorepo`).                                                                                                            |
| `update`       | `pull`, danach Flake-Inputs aktualisieren (zieht neue NixOS-Channel-Version) **und** sofort rebuilden.                                                         |
| `rebuild`      | System neu bauen und **sofort** aktivieren, ohne Flake-Inputs zu aktualisieren. Nützlich nach Änderungen an Konfigurationsdateien.                             |
| `rebuild-boot` | System neu bauen, Aktivierung erst **beim nächsten Neustart**. Sinnvoll, wenn Kernel-Updates ein Reboot erfordern, ohne den laufenden Betrieb zu unterbrechen. |
| `gc`           | Nix-Store aufräumen: löscht Generationen älter als 30 Tage und optimiert den Store (Deduplizierung via Hard-Links).                                            |

> [!WARNING]
> `update` und `rebuild` aktivieren die neue Konfiguration sofort (_switch_). Falls etwas schiefgeht, kann beim nächsten Reboot über das Boot-Menü eine ältere Generation ausgewählt werden (max. 10 Generationen werden vorgehalten).

### Docker-Stack verwalten

| Alias           | Beschreibung                                                        |
| --------------- | ------------------------------------------------------------------- |
| `up`            | Stack **gestaffelt** starten: erzeugt fehlende Secrets und fährt die USB-/RAM-schweren Dienste nacheinander hoch (`scripts/stack-up.sh`) |
| `up-all`        | Alle Container **auf einmal** starten – erzeugt vorher ebenfalls fehlende Secrets (`scripts/ensure-secrets.sh`), dann `docker compose up -d`. Notnagel |
| `down`          | Alle Container stoppen                                              |
| `logs`          | Log-Stream aller Container (`docker compose logs -f`)               |
| `status`        | Docker-Daemon-Status und laufende Container (`docker ps`)           |
| `secrets`       | Alle Passwörter/Tokens (aus `.env` + `secrets/`) an einem Ort anzeigen – inklusive des Authelia-2FA-Registrierungslinks |
| `regen-secrets` | Alle Secrets neu generieren (nach Passwortänderungen in der `.env`) |
| `ca`            | Lokales CA-Zertifikat ausgeben (zum Import in Browser/Handy)         |
| `backup-db`     | Anwendungskonsistente Datenbank-Dumps nach `/var/backups/apphost` ziehen (läuft sonst täglich 02:30) |
| `help`          | Übersicht aller Verwaltungsbefehle                                  |

### Backup auf die Wechselplatte

| Alias           | Beschreibung                                                        |
| --------------- | ------------------------------------------------------------------- |
| `backup-setup`  | **Einmalig** nach der Installation: fragt die PBS-Zugangsdaten ab, legt den Verschlüsselungsschlüssel an (**ausdrucken!**) und prüft anschließend die ganze Kette |
| `backup-check`  | Nur prüfen – läuft alles? Jederzeit gefahrlos aufrufbar             |
| `backup-now`    | Sofort sichern, statt auf den 10-Minuten-Timer zu warten. Steckt keine Platte, passiert nichts. Gleichbedeutend mit dem Knopf auf `https://backup.<domain>` |
| `backup-status` | Wann zuletzt gesichert, auf welche Platte, wie lange es lief        |
| `restore-db`    | Datenbanken aus den Dumps zurückspielen (`--list` zeigt die vorhandenen an) |

Einzelheiten zur Einrichtung stehen in [`proxmox/README.md`](proxmox/README.md).

Nach dem Mergen eines RenovateBot-PRs genügt `up`, um die aktualisierten Images zu ziehen und die Container neu zu starten.

> [!NOTE]
> `up` ist bewusst gestaffelt (nicht `docker compose up -d`), damit Immich/OpenCloud/Paperless nicht gleichzeitig auf die USB-Platte schreiben und den Host überlasten. Für einen schnellen „alles auf einmal"-Start gibt es `up-all`.

---

## 11. Passwörter ändern

Bei Änderungen von Ntfy-, Authelia- oder anderen Secrets in der `.env` müssen diese neu generiert und der betroffene Dienst neu gestartet werden:

```bash
vim /opt/monorepo/.env   # Passwort anpassen
regen-secrets            # alle Secrets neu generieren
up                       # Stack neu starten
```

> [!IMPORTANT]
> Werte, die eines von `$ ` `` ` `` `"` `\` oder ein Leerzeichen enthalten, gehören in
> **einfache** Anführungszeichen: `GRAFANA_ADMIN_PASSWORD='Som$merRegen'`. Die
> `.env` wird von drei Parsern gelesen (`docker compose`, `source`, `grep`), und
> nur so lesen alle drei denselben Wert. Ein Apostroph (`'`) im Wert selbst geht
> nicht – dafür kennt Compose keine Fluchtsequenz. Details im Kopf von
> `.env.example`.

---

## 12. AIDE Integritätsprüfung

Nach der initialen Einrichtung ([Abschnitt 9](#9-aide-initialisieren)) läuft AIDE im Betrieb automatisch:

- Eine **tägliche** automatische Prüfung erfolgt über einen systemd-Service.
- Überwacht werden `/boot`, `/etc`, `/root`, `/home/apphost/.ssh` sowie aus dem Repo `config/`, `compose/`, `scripts/`, `nixos/`, `docker-compose.yml`, `flake.nix` und `flake.lock` (jeweils unter `/opt/monorepo`).
- **Nicht** überwacht werden `/bin`, `/sbin`, `/lib*`, `/usr/bin` und `/usr/sbin`: die gibt es auf NixOS nicht bzw. nur als einzelne Symlinks – AIDE meldete sie schlicht als fehlend. Alles Ausführbare liegt im `/nix/store` und ist dort ohnehin hash-adressiert und read-only.
- Ebenfalls bewusst außen vor: `.env`, `secrets/` und `data/` unter `/opt/monorepo` – die ändern sich legitim. Deshalb stehen die Repo-Pfade einzeln statt pauschal als `/opt/monorepo`.

Eine manuelle Prüfung ist jederzeit möglich:

```bash
aide --check
```

> [!NOTE]
> Nach einem `nixos-rebuild` zieht der Dienst die Referenzdatenbank **automatisch** neu: `/etc` besteht auf NixOS fast vollständig aus Symlinks in den Nix-Store und wird bei jedem Rebuild neu verlinkt – ohne das wäre der tägliche Report danach reines Rauschen. Dafür merkt sich der Dienst die aktive System-Generation. Zwischen zwei Rebuilds ist jede gemeldete Abweichung also eine echte.
>
> Von Hand erzwingen lässt sich die Neu-Baseline so:
>
> ```bash
> sudo rm /var/lib/aide/aide.db && sudo systemctl start aide-check
> ```

---

## 13. Container-Sicherheitsbericht

Ein automatischer Container-Sicherheitsbericht wird jeden **Montag um 02:00 Uhr** mit dem Security-Scanner **Trivy** [[13]](#quelle-13) erstellt und unter `/var/log/docker-security-scan.log` abgelegt. Trivy prüft alle laufenden Images auf HIGH/CRITICAL-Schwachstellen.

```bash
less /var/log/docker-security-scan.log
```

---

## 14. Automatische Container-Updates mit RenovateBot

Alle Container-Image-Updates erfolgen automatisiert über RenovateBot [[14]](#quelle-14) direkt im GitHub-Repository. Es ist keine manuelle Versionspflege erforderlich.

### Wie es funktioniert

RenovateBot überwacht kontinuierlich das Repository und erkennt neue Versionen von Container-Images in den `docker-compose`-Dateien. Sobald ein Update verfügbar ist, öffnet RenovateBot automatisch einen Pull Request mit der aktualisierten Image-Version. Dieser PR kann geprüft, getestet und anschließend gemergt werden. Die Änderung landet dann beim nächsten `docker compose up -d` (Alias `up`) auf dem Server.

### Vorteile

- **Keine veralteten Images:** Updates werden zuverlässig erkannt, ohne dass jemand manuell auf neue Releases achten muss.
- **Nachvollziehbarkeit:** Jede Aktualisierung ist als einzelner Commit im Git-Verlauf dokumentiert (wann, was und warum geändert wurde).
- **Kontrollierter Rollout:** Updates werden als Pull Request vorgeschlagen, nicht sofort eingespielt. Änderungen können vor dem Merge begutachtet oder in einer Testumgebung validiert werden.
- **Sicherheitsrelevanz:** Gepatchte Images mit Sicherheitsfixes werden zeitnah erkannt. In Kombination mit dem wöchentlichen Container-Sicherheitsscan entsteht eine kontinuierliche Angriffsflächen-Reduktion.

> [!NOTE]
> Automerge ist **teilweise aktiv** (`renovate.json`), nicht abgeschaltet:
>
> | Was | Verhalten |
> | --- | --- |
> | Digest-Pins unpinned Images (`pinDigest`, `digest`) | automatisch gemergt, gesammelt in einem PR |
> | Patch-Updates zustandsloser Dienste (node-exporter, cAdvisor, redis_exporter, Alloy, nginx-unprivileged, openspeedtest, BentoPDF, homepage, socket-proxy) | automatisch gemergt nach 3 Tagen Reifezeit |
> | Alles mit Datenbank oder Migration (Immich, Paperless, OpenCloud, Authelia, Vaultwarden, Grafana, …) | bleibt manuell |
>
> Die Trennlinie ist der Zustand: Dienste ohne eigene Daten lassen sich mit einem Tag zurück zurückrollen, alles andere nicht.

---

## 15. Proxmox-Backups einrichten

Damit die komplette `apphost`-VM im Notfall wiederhergestellt werden kann, sollten regelmäßige Backups auf Ebene von Proxmox eingerichtet werden [[2]](#quelle-2). Proxmox bringt dafür ein eigenes Werkzeug mit, das sich vollständig über die Weboberfläche steuern lässt. Es sichert die Systemplatte der VM samt Konfiguration und TPM.

> [!CAUTION]
> **vzdump sichert `/mnt/media` NICHT.** Die 4-TB-Datenplatte ist per
> `qm set 100 -scsi1 /dev/disk/by-id/…` als physisches Gerät durchgereicht, und
> vzdump kann ausschließlich Volumes sichern, die auf einem PVE-Storage liegen –
> ein durchgereichtes Rohgerät wird übersprungen. Ohne eine zweite Vorkehrung
> lägen also **Immich-Fotos, Paperless-Dokumente, OpenCloud-Dateien und
> Radicale-Kalender auf genau einem Datenträger ohne jede Kopie**.
>
> Dafür gibt es das kalte Backup auf Wechselplatten: zwei USB-Platten im
> Wechsel, die nur zum Sichern angesteckt und danach wieder abgezogen werden.
> Einrichtung und Ablauf: **[`proxmox/README.md`](proxmox/README.md)**.
> Ob es läuft, sagt die Kachel „Archivierung" auf dem Dashboard – und wenn
> nicht, die Alarme `BackupOverdue` / `BackupRotationStalled` per ntfy.

### Datenbank-Dumps (läuft automatisch)

Ein VM-Snapshot ist **crash-konsistent**: Er hält den Zustand der Blockgeräte fest, nicht den der Anwendungen. Für die Postgres-Datenbank von Immich und die SQLite-Datenbanken von Authelia, Grafana, Vaultwarden und Paperless heißt das, dass der Snapshot eine Datei mitten in einer Transaktion erwischen kann – beim Zurückspielen ist das im besten Fall eine Recovery, im schlechtesten eine korrupte Datei.

Deshalb legt der systemd-Timer `apphost-db-backup` täglich um **02:30** saubere Dumps unter `/var/backups/apphost` ab (`pg_dumpall` für Postgres, die SQLite-Online-Backup-API für den Rest). Die liegen dort als normale Dateien und werden vom Proxmox-Snapshot einfach mitgesichert. Aufbewahrt werden 14 Tage. Jeder SQLite-Dump wird direkt nach dem Schreiben mit `PRAGMA quick_check` gegengeprüft – ein unbrauchbares Backup soll dort auffallen und nicht erst beim Restore.

Schlägt der Lauf fehl, geht eine Push-Nachricht an ntfy (Topic `apphost-critical`, dieselbe Kette wie die kritischen Alerts). Dafür sorgt eine `OnFailure=`-Unit, die auch an `aide-check` und `docker-security-scan` hängt – systemd-Dienste tauchen sonst in keinem Alert auf, weil Prometheus sie nicht scrapt. Testen:

```bash
sudo systemctl start apphost-notify-failure@apphost-db-backup.service
```

```bash
backup-db                                   # von Hand anstoßen
systemctl status apphost-db-backup          # letzter Lauf
ls -lh /var/backups/apphost                 # vorhandene Dumps
```

> [!NOTE]
> **Backups, die den Host verlassen**, brauchen eine eigene Verschlüsselung: die Paperless-Datenbank enthält alle Dokument-Metadaten im Klartext, und die Schlüssel für die verschlüsselten Teile (Authelia-TOTP-Secrets, Grafana-Datasource-Secrets) liegen in derselben `.env` auf derselben Platte. Dafür `BACKUP_AGE_RECIPIENT` in der `.env` auf einen age-Public-Key setzen – dann wird jeder Dump zusätzlich mit `age` verschlüsselt und das Klartext-Original entfernt.
>
> ```bash
> age-keygen -o ~/apphost-backup.key          # Schlüsselpaar (Public Key wird ausgegeben)
> age -d -i ~/apphost-backup.key datei.age    # entschlüsseln
> ```

> [!WARNING]
> **OpenCloud ist nicht abgedeckt.** Es hält seine Metadaten in einem eingebetteten NATS/JetStream-KV-Store, nicht in einer Datenbank, die sich von außen konsistent dumpen ließe – dort bleibt es beim crash-konsistenten Snapshot. Wer das sauber will, stoppt den Dienst für den Snapshot kurz (`docker compose stop opencloud`).
>
> Und: Ein Backup ist erst dann eines, wenn der Restore einmal durchgespielt wurde. Für den Immich-Dump gilt das besonders, weil er voraussetzt, dass `POSTGRES_USER=immich` im Image tatsächlich Superuser ist. Einmal in eine Wegwerf-VM zurückspielen, bevor man sich darauf verlässt.

Wiederherstellen (Beispiele):

```bash
# Postgres (Immich) – pg_dumpall-Dump geht gegen die Wartungs-DB
gunzip -c /var/backups/apphost/immich-postgres_<stamp>.sql.gz \
  | docker exec -i immich-postgres psql -U immich -d postgres

# SQLite (hier Vaultwarden) – Container vorher stoppen
docker compose stop vaultwarden
gunzip -c /var/backups/apphost/vaultwarden_<stamp>.sqlite.gz \
  > "$(docker volume inspect -f '{{.Mountpoint}}' apphost_vaultwarden_data)/db.sqlite3"
docker compose start vaultwarden
```


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
