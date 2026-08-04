# Kaltes Backup auf Wechselplatten (Proxmox-Host)

Dieser Ordner enthält den Teil der Backup-Kette, der auf dem **Proxmox-Host**
läuft und nicht in der VM. Er ist hier versioniert, weil er sonst das einzige
Stück Infrastruktur ohne Quelle im Repo wäre.

## Warum das so gebaut ist

`/mnt/media` ist eine per `qm set 100 -scsi1 …` durchgereichte physische Platte.
**vzdump sichert sie nicht** – es sichert nur Volumes, die auf einem PVE-Storage
liegen. Fotos, Dokumente, Cloud-Dateien und Kalender lagen damit auf genau einem
Datenträger ohne jede Kopie. Deshalb zwei Wege in denselben Datastore:

| Was | Von wo | Wie |
|---|---|---|
| VM-Systemplatte | Host | `vzdump` |
| `/mnt/media`, Docker-Volumes, `/opt/monorepo`, DB-Dumps | VM | `proxmox-backup-client` (dateibasiert) |

Die Platte hängt **normalerweise nicht am Host**. Das ist Absicht: Ein Angreifer
mit Root kann jede angeschlossene Platte, jeden Share und jede Retention
löschen. Was nicht steckt, kann er nicht anfassen. Der Preis ist ein Fenster in
der Größe des Steck-Rhythmus (14 Tage) – deshalb zwei Platten im Wechsel.

**Es gibt kein SSH vom Host in die VM.** Beide Seiten koordinieren sich nur über
den Datastore: Der Host sieht, wann ein neuer Medien-Snapshot da ist; die VM
fragt alle 10 Minuten, ob der Datastore antwortet. Das einzige Geheimnis ist ein
PBS-API-Token in der VM, das nur anlegen und lesen darf.

## Die Wechselplatten werden NICHT an die VM durchgereicht

> [!CAUTION]
> **Kein `qm set 100 -scsi2 …` für `cold-a`/`cold-b`.** Die Wechselplatten
> bleiben beim Host. PBS läuft dort, hängt den Datastore selbst ein und ist der
> einzige, der die Platte anfasst. Reicht man sie zusätzlich an die VM durch,
> kann PBS sie nicht mehr einhängen (das Gerät ist von QEMU belegt) – und im
> schlimmsten Fall schreiben zwei Systeme auf dasselbe Dateisystem.

Hier sind zwei völlig verschiedene Platten im Spiel, die leicht verwechselt
werden:

| Platte | Wo | Durchgereicht? | Konfiguration |
|---|---|---|---|
| **Datenplatte** 4 TB → `/mnt/media` | in der VM sichtbar | **ja**, als `scsi1` | `qm set 100 -scsi1 …`, steht dauerhaft in `/etc/pve/qemu-server/100.conf`; Mount via `nixos/modules/media-disk.nix` |
| **Wechselplatten** `cold-a` (4 TB) / `cold-b` (5 TB) | nur am Host | **nein** | udev-Regel + PBS-Datastore, siehe unten |

Für beide ist **nichts weiter einzurichten**, damit es nach einem Neustart oder
beim Anstecken automatisch funktioniert:

- Die Datenplatte steht in der VM-Konfiguration und wird bei jedem Start der VM
  wieder angehängt. Der `by-id`-Pfad ist stabil.
- Die Wechselplatten brauchen **keinen fstab-Eintrag und keinen Automounter**.
  Das Anstecken erkennt die udev-Regel an der Seriennummer, das Einhängen macht
  PBS über `datastore mount`, das Aushängen erledigt das Skript am Ende. Ein
  zusätzlicher fstab-Eintrag würde PBS dabei nur in die Quere kommen.

> [!NOTE]
> `scripts/proxmox-harden.sh` setzt `blacklist uas` in
> `/etc/modprobe.d/99-disable-usb.conf`. Die Wechselplatten laufen deshalb im
> BOT-Modus statt mit UAS. Für die vielen kleinen Chunk-Dateien eines
> PBS-Datastores kann das spürbar sein – beim ersten Lauf die Übertragungsrate
> im Blick behalten (`journalctl -fu apphost-coldbackup@cold-a`). Ist sie
> unbrauchbar, lässt sich UAS gezielt für diese beiden Seriennummern wieder
> zulassen, statt die Blacklist ganz zu entfernen.

## Einmalige Einrichtung

### 1. PBS auf dem Host installieren

```bash
echo "deb http://download.proxmox.com/debian/pbs $(. /etc/os-release; echo "$VERSION_CODENAME") pbs-no-subscription" \
  > /etc/apt/sources.list.d/pbs-install.list
apt update && apt install proxmox-backup-server jq
```

> PBS neben PVE zu betreiben ist unterstützt, aber nicht für Produktion
> empfohlen (beide teilen ein Schicksal). Hier ist das in Ordnung: Der Wert
> liegt auf der **abgezogenen Platte**. Geht der Host kaputt, installierst du
> PBS neu und hängst den Datastore wieder ein.

### 2. Platten vorbereiten

Beide Platten **physisch mit A und B beschriften**. Dann je Platte, einzeln
angesteckt:

```bash
lsblk -o NAME,SIZE,SERIAL,MODEL          # Seriennummer notieren!
sgdisk --zap-all /dev/sdX
sgdisk --new=1:0:0 --typecode=1:8300 /dev/sdX
mkfs.ext4 -L cold-a -m 0 /dev/sdX1       # bzw. cold-b
```

**ext4, nicht btrfs.** Ein PBS-Datastore besteht aus Millionen Chunk-Dateien von
1–4 MB. Auf btrfs erzeugt Copy-on-Write dabei erhebliche Fragmentierung; die
Gegenmaßnahme (`chattr +C`) schaltet ausgerechnet die Prüfsummen ab, wegen derer
man btrfs nimmt. Die Integritätsprüfung macht hier ohnehin PBS selbst über seine
`verify`-Jobs. `-m 0` schenkt dir die 5 % Root-Reserve, die auf einer
Backup-Platte nichts nützt.

Platte A hat 4 TB, Platte B 5 TB. Die Aufbewahrung richtet sich nach der
kleineren.

### 3. Removable Datastores anlegen

In der PBS-Oberfläche (`https://<host>:8007`) → **Datastore → Add Datastore**,
dabei **„Removable datastore"** ankreuzen und das Gerät wählen. Namen exakt
`cold-a` und `cold-b` – auf die greifen Skript und udev-Regel zu.

### 4. Zugang für die VM

```bash
proxmox-backup-manager user create apphost@pbs
proxmox-backup-manager user generate-token apphost@pbs backup   # Secret notieren!

# Nur anlegen und lesen. KEIN Datastore.Prune, KEIN Datastore.Modify:
# ein übernommener Stack soll seine eigene Backup-Historie nicht löschen können.
for ds in cold-a cold-b; do
  proxmox-backup-manager acl update "/datastore/$ds" DatastoreBackup \
    --auth-id 'apphost@pbs!backup'
done

proxmox-backup-manager cert info | grep -i fingerprint   # für PBS_FINGERPRINT
```

### 5. Skript und Units installieren

```bash
install -m 0755 apphost-coldbackup.sh /usr/local/sbin/apphost-coldbackup.sh
install -m 0644 apphost-coldbackup@.service /etc/systemd/system/
systemctl daemon-reload

# Seriennummern aus Schritt 2 eintragen, DANN kopieren:
$EDITOR 99-apphost-coldbackup.rules
install -m 0644 99-apphost-coldbackup.rules /etc/udev/rules.d/
udevadm control --reload
```

### 6. VM konfigurieren

In der VM `/opt/monorepo/secrets/pbs.env` anlegen (`chmod 600`):

```sh
PBS_HOST=192.168.178.<proxmox-host>
PBS_TOKEN='apphost@pbs!backup'
PBS_SECRET='<Secret aus Schritt 4>'
PBS_FINGERPRINT='<Fingerabdruck aus Schritt 4>'
PBS_DATASTORES='cold-a cold-b'
```

Verschlüsselungsschlüssel erzeugen (in der VM):

```bash
proxmox-backup-client key create /opt/monorepo/secrets/pbs-encryption.key --kdf none
chmod 600 /opt/monorepo/secrets/pbs-encryption.key
proxmox-backup-client key paperkey /opt/monorepo/secrets/pbs-encryption.key
```

> **Der Papierausdruck ist ab jetzt das Wertvollste, das du besitzt.**
> Ohne den Schlüssel ist jedes Backup Zufallsrauschen. Ausdrucken, offline
> weglegen – und **nicht nur in Vaultwarden**, denn Vaultwarden ist genau das,
> was du damit wiederherstellst.

Dann `rebuild`, damit Timer und Knopf aktiv werden.

## Der Ablauf danach

1. Platte anstecken → udev startet `apphost-coldbackup@cold-X.service`
2. Host: Datastore einhängen → `vzdump` der VM
3. VM: merkt binnen 10 Minuten, dass der Datastore antwortet, und sichert.
   Schneller geht es über den Knopf auf `https://backup.<domain>`
4. VM schickt „fertig" per ntfy
5. Host: prune → verify (Stichprobe) → GC (nur alle 30 Tage) → aushängen
6. Erst **nach dem Aushängen** abziehen:
   `journalctl -u apphost-coldbackup@cold-a -n 20`

Das Ganze läuft am besten über Nacht. Die Garbage Collection liest den gesamten
Chunk-Bestand – bei 1,5 TB sind das Stunden, nicht Minuten.

## Überwachung

Das Backup-Alter je Platte geht als Prometheus-Metrik in die bestehende
Alarmkette (`config/prometheus/rules/alerts.yml`):

| Alarm | ab |
|---|---|
| `BackupOverdue` (warning) | 21 Tage ohne Backup |
| `BackupCritical` (critical) | 35 Tage |
| `BackupRotationStalled` (warning) | eine **einzelne** Platte 70 Tage nicht dran |
| `BackupMetricMissing` (warning) | die Überwachung selbst ist ausgefallen |

`BackupRotationStalled` ist der wichtigste: Der typische Fehler mit zwei
Wechselplatten ist, immer zur griffbereiten zu greifen und erst im Ernstfall zu
merken, dass die andere ein halbes Jahr alt ist.

## Zurückspielen

```bash
# Was ist da?
proxmox-backup-client snapshots --repository 'apphost@pbs!backup@<host>:cold-a'

# Einzelne Datei/Ordner
proxmox-backup-client restore host/apphost/<zeitstempel> media.pxar /ziel \
  --repository … --keyfile /opt/monorepo/secrets/pbs-encryption.key

# Datenbanken: scripts/restore-databases.sh
```

**Ein Backup ist erst dann eines, wenn der Restore einmal durchgespielt wurde.**
`/mnt/media` ist gerade noch leer – ein besserer Zeitpunkt zum Üben kommt nicht
wieder.
