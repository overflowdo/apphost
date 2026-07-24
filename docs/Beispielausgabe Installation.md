```
[nixos@nixos:~]$ sudo ./LFM-Team-Blue/apphost/nixos/install.sh

  Repo:    /home/nixos/LFM-Team-Blue/apphost
  Dieses Skript:
  - partitioniert eine Festplatte (GPT + EFI + Swap + Btrfs)
  - installiert NixOS mit der AppHost-Hochsicherheitskonfiguration
  - legt den AppHost-Stack unter /opt/apphost bereit


  Bitte wählen Sie ein sicheres Passwort für Ihren Nutzer.
  Dieses Passwort wird für 'sudo' benötigt (zweiter Faktor nach SSH-Key).

  Passwort:
  Passwort bestätigen:
Passwort-Hash erzeugt

⚠  WARNUNG: ALLE DATEN auf der Festplatte werden UNWIDERRUFLICH GELÖSCHT!

  Bitte 'ja' eingeben um fortzufahren: ja
▶  Schreibe Passwort-Hash nach /mnt/etc/apphost-password-hash (außerhalb des Repos)...
▶  Erstelle hardware-configuration.nix Platzhalter...

  Optional kann die Root-Partition zusätzlich mit LUKS2 verschlüsselt werden.
  Achtung: Danach wird bei JEDEM Boot eine Passphrase über die Server-Konsole benötigt
  > Kein unbeaufsichtigter Neustart, kein Boot ohne Konsolenzugriff (z.B. über die Proxmox-Konsole).

  Festplattenverschlüsselung aktivieren? [j/N]: j
⚠  Festplattenverschlüsselung aktiviert. Die Passphrase wird gleich bei der Formatierung festgelegt.
  SSH Public Key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjUx5YA3RwdM0xfXY7KMZb3N3BrK1tDyJ/qcQQvBWJE luca@Laptop-von-Luca.local
▶  SSH Public Key gespeichert
▶  Starte disko (Partitionierung + Btrfs-Formatierung)...
disko version 1.13.0-dirty
evaluation warning: the diskoScript output is deprecated and will be removed, please open an issue if you're using it!
umount: /mnt/var unmounted
umount: /mnt/tmp unmounted
umount: /mnt/opt unmounted
umount: /mnt/nix unmounted
umount: /mnt/boot unmounted
umount: /mnt unmounted
++ realpath /dev/sda
+ disk=/dev/sda
+ lsblk -a -f
NAME          FSTYPE      FSVER            LABEL                      UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
loop0         squashfs    4.0                                                                                    0   100% /nix/.ro-store
loop1
loop2
loop3
loop4
loop5
loop6
loop7
sda
├─sda1        vfat        FAT32                                       21D9-462B
├─sda2
└─sda3        crypto_LUKS 2                                           8fa90fd1-ae30-4bce-b951-a3d596908701
  └─cryptroot btrfs                        nixos                      fc73368f-38fa-4406-bcc3-5fc22723f0fc
sr0           iso9660     Joliet Extension nixos-minimal-26.05-x86_64 1980-01-01-00-00-00-00                     0   100% /iso
+ lsblk --output-all --json
+ bash -x
++ dirname /nix/store/94pqsnzjf0qivgnqhsn8dkyhay03l335-disk-deactivate/disk-deactivate
+ jq -r -f /nix/store/94pqsnzjf0qivgnqhsn8dkyhay03l335-disk-deactivate/zfs-swap-deactivate.jq
+ lsblk --output-all --json
+ bash -x
++ dirname /nix/store/94pqsnzjf0qivgnqhsn8dkyhay03l335-disk-deactivate/disk-deactivate
+ jq -r --arg disk_to_clear /dev/sda -f /nix/store/94pqsnzjf0qivgnqhsn8dkyhay03l335-disk-deactivate/disk-deactivate.jq
+ set -fu
+ wipefs --all -f /dev/sda1
/dev/sda1: 8 bytes were erased at offset 0x00000052 (vfat): 46 41 54 33 32 20 20 20
/dev/sda1: 1 byte was erased at offset 0x00000000 (vfat): eb
/dev/sda1: 2 bytes were erased at offset 0x000001fe (vfat): 55 aa
++ type zdb
++ zdb -l /dev/sda2
++ sed -nr 's/ +name: '\''(.*)'\''/\1/p'
+ zpool=
+ [[ -n '' ]]
+ unset zpool
+ wipefs --all -f /dev/sda2
+ cryptsetup luksClose /dev/mapper/cryptroot
+ wipefs --all -f /dev/mapper/cryptroot
wipefs: error: /dev/mapper/cryptroot: probing initialization failed: No such file or directory
+ wipefs --all -f /dev/sda3
/dev/sda3: 6 bytes were erased at offset 0x00000000 (crypto_LUKS): 4c 55 4b 53 ba be
/dev/sda3: 6 bytes were erased at offset 0x00004000 (crypto_LUKS): 53 4b 55 4c ba be
++ type zdb
++ zdb -l /dev/sda
++ sed -nr 's/ +name: '\''(.*)'\''/\1/p'
+ zpool=
+ [[ -n '' ]]
+ unset zpool
++ lsblk /dev/sda -l -p -o type,name
++ awk 'match($1,"raid.*") {print $2}'
+ md_dev=
+ [[ -n '' ]]
+ wipefs --all -f /dev/sda
/dev/sda: 8 bytes were erased at offset 0x00000200 (gpt): 45 46 49 20 50 41 52 54
/dev/sda: 8 bytes were erased at offset 0x13fffffe00 (gpt): 45 46 49 20 50 41 52 54
/dev/sda: 2 bytes were erased at offset 0x000001fe (PMBR): 55 aa
+ dd if=/dev/zero of=/dev/sda bs=440 count=1
1+0 records in
1+0 records out
440 bytes copied, 3.2521e-05 s, 13.5 MB/s
+ lsblk -a -f
NAME  FSTYPE   FSVER            LABEL                      UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
loop0 squashfs 4.0                                                                                    0   100% /nix/.ro-store
loop1
loop2
loop3
loop4
loop5
loop6
loop7
sda
sr0   iso9660  Joliet Extension nixos-minimal-26.05-x86_64 1980-01-01-00-00-00-00                     0   100% /iso
++ mktemp -d
+ disko_devices_dir=/tmp/tmp.YmHFshJMZT
+ trap 'rm -rf "$disko_devices_dir"' EXIT
+ mkdir -p /tmp/tmp.YmHFshJMZT
+ destroy=1
+ device=/dev/sda
+ imageName=main
+ imageSize=2G
+ name=main
+ type=disk
+ device=/dev/sda
+ efiGptPartitionFirst=1
+ type=gpt
+ blkid /dev/sda
+ sgdisk --clear /dev/sda
Creating new GPT entries in memory.
The operation has completed successfully.
+ sgdisk --align-end --new=1:0:+512M --partition-guid=1:R --change-name=1:disk-main-ESP --typecode=1:EF00 --attributes=1:=:0 /dev/sda
The operation has completed successfully.
+ partprobe /dev/sda
+ udevadm trigger --subsystem-match=block
+ udevadm settle --timeout 120
+ sgdisk --align-end --new=2:0:+8G --partition-guid=2:R --change-name=2:disk-main-swap --typecode=2:8200 --attributes=2:=:0 /dev/sda
The operation has completed successfully.
+ partprobe /dev/sda
+ udevadm trigger --subsystem-match=block
+ udevadm settle --timeout 120
+ sgdisk --align-end --new=3:0:-0 --partition-guid=3:R --change-name=3:disk-main-root --typecode=3:8300 --attributes=3:=:0 /dev/sda
The operation has completed successfully.
+ partprobe /dev/sda
+ udevadm trigger --subsystem-match=block
+ udevadm settle --timeout 120
+ device=/dev/disk/by-partlabel/disk-main-ESP
+ extraArgs=()
+ declare -a extraArgs
+ format=vfat
+ mountOptions=('defaults' 'umask=0077' 'noatime')
+ declare -a mountOptions
+ mountpoint=/boot
+ type=filesystem
+ blkid /dev/disk/by-partlabel/disk-main-ESP
+ grep -q TYPE=
+ mkfs.vfat /dev/disk/by-partlabel/disk-main-ESP
mkfs.fat 4.2 (2021-01-31)
+ device=/dev/disk/by-partlabel/disk-main-swap
+ discardPolicy=
+ extraArgs=()
+ declare -a extraArgs
+ mountOptions=('defaults')
+ declare -a mountOptions
+ priority=
+ randomEncryption=1
+ resumeDevice=
+ type=swap
+ additionalKeyFiles=()
+ declare -a additionalKeyFiles
+ askPassword=1
+ device=/dev/disk/by-partlabel/disk-main-root
+ enrollFido2=
+ enrollRecovery=
+ extraFido2EnrollArgs=()
+ declare -a extraFido2EnrollArgs
+ extraFormatArgs=()
+ declare -a extraFormatArgs
+ extraOpenArgs=()
+ declare -a extraOpenArgs
+ initrdUnlock=1
+ keyFile=
+ name=cryptroot
+ passwordFile=
+ settings=(['allowDiscards']='1')
+ declare -A settings
+ type=luks
+ blkid /dev/disk/by-partlabel/disk-main-root
+ cryptsetup isLuks /dev/disk/by-partlabel/disk-main-root
+ askPassword
+ '[' -z ']'
+ set +x
Enter password for /dev/disk/by-partlabel/disk-main-root:
Enter password for /dev/disk/by-partlabel/disk-main-root again to be safe:
+ cryptsetup -q luksFormat /dev/disk/by-partlabel/disk-main-root --key-file /dev/fd/63
++ set +x
+ cryptsetup open /dev/disk/by-partlabel/disk-main-root cryptroot --allow-discards --key-file /dev/fd/63 --persistent
++ set +x
+ cryptsetup status cryptroot
+ device=/dev/mapper/cryptroot
+ extraArgs=('-f' '--label' 'nixos')
+ declare -a extraArgs
+ mountOptions=('defaults')
+ declare -a mountOptions
+ mountpoint=
+ type=btrfs
+ blkid /dev/mapper/cryptroot -o export
+ grep -q '^TYPE='
+ mkfs.btrfs /dev/mapper/cryptroot -f --label nixos
btrfs-progs v7.0
See https://btrfs.readthedocs.io for more information.

Performing full device TRIM /dev/mapper/cryptroot (71.48GiB) ...
NOTE: default settings have changed in version 6.19 (supported since linux 6.1):
      - enable block-group-tree (-O bgt)

Label:              nixos
UUID:               9f366204-d3c6-420b-85ac-79f7d1c8ea00
Node size:          16384
Sector size:        4096	(CPU page size: 4096)
Filesystem size:    71.48GiB
Block group profiles:
  Data:             single            8.00MiB
  Metadata:         DUP               1.00GiB
  System:           DUP               8.00MiB
SSD detected:       yes
Zoned device:       no
Features:           extref, skinny-metadata, no-holes, free-space-tree, block-group-tree
Checksum:           crc32c
Number of devices:  1
Devices:
   ID        SIZE  PATH
    1    71.48GiB  /dev/mapper/cryptroot

+ blkid /dev/mapper/cryptroot -o export
+ grep -q '^TYPE=btrfs$'
++ mktemp -d
+ MNTPOINT=/tmp/tmp.4UU53fNQUj
+ mount /dev/mapper/cryptroot /tmp/tmp.4UU53fNQUj -o subvol=/
+ trap 'umount "$MNTPOINT"; rm -rf "$MNTPOINT"' EXIT
+ SUBVOL_ABS_PATH=/tmp/tmp.4UU53fNQUj//nix
++ dirname /tmp/tmp.4UU53fNQUj//nix
+ mkdir -p /tmp/tmp.4UU53fNQUj
+ btrfs subvolume show /tmp/tmp.4UU53fNQUj//nix
+ btrfs subvolume create /tmp/tmp.4UU53fNQUj//nix
Create subvolume '/tmp/tmp.4UU53fNQUj/nix'
++ umount /tmp/tmp.4UU53fNQUj
++ rm -rf /tmp/tmp.4UU53fNQUj
++ mktemp -d
+ MNTPOINT=/tmp/tmp.qSRPT0NC8H
+ mount /dev/mapper/cryptroot /tmp/tmp.qSRPT0NC8H -o subvol=/
+ trap 'umount "$MNTPOINT"; rm -rf "$MNTPOINT"' EXIT
+ SUBVOL_ABS_PATH=/tmp/tmp.qSRPT0NC8H//opt
++ dirname /tmp/tmp.qSRPT0NC8H//opt
+ mkdir -p /tmp/tmp.qSRPT0NC8H
+ btrfs subvolume show /tmp/tmp.qSRPT0NC8H//opt
+ btrfs subvolume create /tmp/tmp.qSRPT0NC8H//opt
Create subvolume '/tmp/tmp.qSRPT0NC8H/opt'
++ umount /tmp/tmp.qSRPT0NC8H
++ rm -rf /tmp/tmp.qSRPT0NC8H
++ mktemp -d
+ MNTPOINT=/tmp/tmp.D9gunjTyIB
+ mount /dev/mapper/cryptroot /tmp/tmp.D9gunjTyIB -o subvol=/
+ trap 'umount "$MNTPOINT"; rm -rf "$MNTPOINT"' EXIT
+ SUBVOL_ABS_PATH=/tmp/tmp.D9gunjTyIB//root
++ dirname /tmp/tmp.D9gunjTyIB//root
+ mkdir -p /tmp/tmp.D9gunjTyIB
+ btrfs subvolume show /tmp/tmp.D9gunjTyIB//root
+ btrfs subvolume create /tmp/tmp.D9gunjTyIB//root
Create subvolume '/tmp/tmp.D9gunjTyIB/root'
++ umount /tmp/tmp.D9gunjTyIB
++ rm -rf /tmp/tmp.D9gunjTyIB
++ mktemp -d
+ MNTPOINT=/tmp/tmp.tu8P5M0OkF
+ mount /dev/mapper/cryptroot /tmp/tmp.tu8P5M0OkF -o subvol=/
+ trap 'umount "$MNTPOINT"; rm -rf "$MNTPOINT"' EXIT
+ SUBVOL_ABS_PATH=/tmp/tmp.tu8P5M0OkF//tmp
++ dirname /tmp/tmp.tu8P5M0OkF//tmp
+ mkdir -p /tmp/tmp.tu8P5M0OkF
+ btrfs subvolume show /tmp/tmp.tu8P5M0OkF//tmp
+ btrfs subvolume create /tmp/tmp.tu8P5M0OkF//tmp
Create subvolume '/tmp/tmp.tu8P5M0OkF/tmp'
++ umount /tmp/tmp.tu8P5M0OkF
++ rm -rf /tmp/tmp.tu8P5M0OkF
++ mktemp -d
+ MNTPOINT=/tmp/tmp.H3PIPkX60u
+ mount /dev/mapper/cryptroot /tmp/tmp.H3PIPkX60u -o subvol=/
+ trap 'umount "$MNTPOINT"; rm -rf "$MNTPOINT"' EXIT
+ SUBVOL_ABS_PATH=/tmp/tmp.H3PIPkX60u//var
++ dirname /tmp/tmp.H3PIPkX60u//var
+ mkdir -p /tmp/tmp.H3PIPkX60u
+ btrfs subvolume show /tmp/tmp.H3PIPkX60u//var
+ btrfs subvolume create /tmp/tmp.H3PIPkX60u//var
Create subvolume '/tmp/tmp.H3PIPkX60u/var'
++ umount /tmp/tmp.H3PIPkX60u
++ rm -rf /tmp/tmp.H3PIPkX60u
+ set -efux
+ destroy=1
+ device=/dev/sda
+ imageName=main
+ imageSize=2G
+ name=main
+ type=disk
+ device=/dev/sda
+ efiGptPartitionFirst=1
+ type=gpt
+ additionalKeyFiles=()
+ declare -a additionalKeyFiles
+ askPassword=1
+ device=/dev/disk/by-partlabel/disk-main-root
+ enrollFido2=
+ enrollRecovery=
+ extraFido2EnrollArgs=()
+ declare -a extraFido2EnrollArgs
+ extraFormatArgs=()
+ declare -a extraFormatArgs
+ extraOpenArgs=()
+ declare -a extraOpenArgs
+ initrdUnlock=1
+ keyFile=
+ name=cryptroot
+ passwordFile=
+ settings=(['allowDiscards']='1')
+ declare -A settings
+ type=luks
+ cryptsetup status cryptroot
+ destroy=1
+ device=/dev/sda
+ imageName=main
+ imageSize=2G
+ name=main
+ type=disk
+ device=/dev/sda
+ efiGptPartitionFirst=1
+ type=gpt
+ additionalKeyFiles=()
+ declare -a additionalKeyFiles
+ askPassword=1
+ device=/dev/disk/by-partlabel/disk-main-root
+ enrollFido2=
+ enrollRecovery=
+ extraFido2EnrollArgs=()
+ declare -a extraFido2EnrollArgs
+ extraFormatArgs=()
+ declare -a extraFormatArgs
+ extraOpenArgs=()
+ declare -a extraOpenArgs
+ initrdUnlock=1
+ keyFile=
+ name=cryptroot
+ passwordFile=
+ settings=(['allowDiscards']='1')
+ declare -A settings
+ type=luks
+ device=/dev/mapper/cryptroot
+ extraArgs=('-f' '--label' 'nixos')
+ declare -a extraArgs
+ mountOptions=('defaults')
+ declare -a mountOptions
+ mountpoint=
+ type=btrfs
+ findmnt /dev/mapper/cryptroot /mnt/
+ mount /dev/mapper/cryptroot /mnt/ -o compress=zstd -o noatime -o subvol=/root -o X-mount.mkdir
+ destroy=1
+ device=/dev/sda
+ imageName=main
+ imageSize=2G
+ name=main
+ type=disk
+ device=/dev/sda
+ efiGptPartitionFirst=1
+ type=gpt
+ device=/dev/disk/by-partlabel/disk-main-ESP
+ extraArgs=()
+ declare -a extraArgs
+ format=vfat
+ mountOptions=('defaults' 'umask=0077' 'noatime')
+ declare -a mountOptions
+ mountpoint=/boot
+ type=filesystem
+ findmnt /dev/disk/by-partlabel/disk-main-ESP /mnt/boot
+ mount /dev/disk/by-partlabel/disk-main-ESP /mnt/boot -t vfat -o defaults -o umask=0077 -o noatime -o X-mount.mkdir
+ destroy=1
+ device=/dev/sda
+ imageName=main
+ imageSize=2G
+ name=main
+ type=disk
+ device=/dev/sda
+ efiGptPartitionFirst=1
+ type=gpt
+ additionalKeyFiles=()
+ declare -a additionalKeyFiles
+ askPassword=1
+ device=/dev/disk/by-partlabel/disk-main-root
+ enrollFido2=
+ enrollRecovery=
+ extraFido2EnrollArgs=()
+ declare -a extraFido2EnrollArgs
+ extraFormatArgs=()
+ declare -a extraFormatArgs
+ extraOpenArgs=()
+ declare -a extraOpenArgs
+ initrdUnlock=1
+ keyFile=
+ name=cryptroot
+ passwordFile=
+ settings=(['allowDiscards']='1')
+ declare -A settings
+ type=luks
+ device=/dev/mapper/cryptroot
+ extraArgs=('-f' '--label' 'nixos')
+ declare -a extraArgs
+ mountOptions=('defaults')
+ declare -a mountOptions
+ mountpoint=
+ type=btrfs
+ findmnt /dev/mapper/cryptroot /mnt/nix
+ mount /dev/mapper/cryptroot /mnt/nix -o compress=zstd -o noatime -o subvol=/nix -o X-mount.mkdir
+ destroy=1
+ device=/dev/sda
+ imageName=main
+ imageSize=2G
+ name=main
+ type=disk
+ device=/dev/sda
+ efiGptPartitionFirst=1
+ type=gpt
+ additionalKeyFiles=()
+ declare -a additionalKeyFiles
+ askPassword=1
+ device=/dev/disk/by-partlabel/disk-main-root
+ enrollFido2=
+ enrollRecovery=
+ extraFido2EnrollArgs=()
+ declare -a extraFido2EnrollArgs
+ extraFormatArgs=()
+ declare -a extraFormatArgs
+ extraOpenArgs=()
+ declare -a extraOpenArgs
+ initrdUnlock=1
+ keyFile=
+ name=cryptroot
+ passwordFile=
+ settings=(['allowDiscards']='1')
+ declare -A settings
+ type=luks
+ device=/dev/mapper/cryptroot
+ extraArgs=('-f' '--label' 'nixos')
+ declare -a extraArgs
+ mountOptions=('defaults')
+ declare -a mountOptions
+ mountpoint=
+ type=btrfs
+ findmnt /dev/mapper/cryptroot /mnt/opt
+ mount /dev/mapper/cryptroot /mnt/opt -o compress=zstd -o noatime -o subvol=/opt -o X-mount.mkdir
+ destroy=1
+ device=/dev/sda
+ imageName=main
+ imageSize=2G
+ name=main
+ type=disk
+ device=/dev/sda
+ efiGptPartitionFirst=1
+ type=gpt
+ additionalKeyFiles=()
+ declare -a additionalKeyFiles
+ askPassword=1
+ device=/dev/disk/by-partlabel/disk-main-root
+ enrollFido2=
+ enrollRecovery=
+ extraFido2EnrollArgs=()
+ declare -a extraFido2EnrollArgs
+ extraFormatArgs=()
+ declare -a extraFormatArgs
+ extraOpenArgs=()
+ declare -a extraOpenArgs
+ initrdUnlock=1
+ keyFile=
+ name=cryptroot
+ passwordFile=
+ settings=(['allowDiscards']='1')
+ declare -A settings
+ type=luks
+ device=/dev/mapper/cryptroot
+ extraArgs=('-f' '--label' 'nixos')
+ declare -a extraArgs
+ mountOptions=('defaults')
+ declare -a mountOptions
+ mountpoint=
+ type=btrfs
+ findmnt /dev/mapper/cryptroot /mnt/tmp
+ mount /dev/mapper/cryptroot /mnt/tmp -o compress=zstd -o noatime -o nosuid -o nodev -o noexec -o subvol=/tmp -o X-mount.mkdir
+ destroy=1
+ device=/dev/sda
+ imageName=main
+ imageSize=2G
+ name=main
+ type=disk
+ device=/dev/sda
+ efiGptPartitionFirst=1
+ type=gpt
+ additionalKeyFiles=()
+ declare -a additionalKeyFiles
+ askPassword=1
+ device=/dev/disk/by-partlabel/disk-main-root
+ enrollFido2=
+ enrollRecovery=
+ extraFido2EnrollArgs=()
+ declare -a extraFido2EnrollArgs
+ extraFormatArgs=()
+ declare -a extraFormatArgs
+ extraOpenArgs=()
+ declare -a extraOpenArgs
+ initrdUnlock=1
+ keyFile=
+ name=cryptroot
+ passwordFile=
+ settings=(['allowDiscards']='1')
+ declare -A settings
+ type=luks
+ device=/dev/mapper/cryptroot
+ extraArgs=('-f' '--label' 'nixos')
+ declare -a extraArgs
+ mountOptions=('defaults')
+ declare -a mountOptions
+ mountpoint=
+ type=btrfs
+ findmnt /dev/mapper/cryptroot /mnt/var
+ mount /dev/mapper/cryptroot /mnt/var -o compress=zstd -o noatime -o subvol=/var -o X-mount.mkdir
+ rm -rf /tmp/tmp.YmHFshJMZT
▶  Festplatte partitioniert und unter /mnt gemountet
▶  Passwort-Hash nach /mnt/etc/apphost-password-hash geschrieben
▶  Generiere nixos/hardware-configuration.nix...
▶  hardware-configuration.nix generiert
▶  Starte nixos-install ohne Bootloader (dieser Vorgang wird einen Moment dauern)...
copying channel...
building the flake in path:/home/nixos/LFM-Team-Blue/apphost?lastModified=1783952499&narHash=sha256-IyQ7FU3Ydz2wEu550mU24FAMPOmua/JWj6gIQxmvd7Q%3D...
installation finished!
NixOS erfolgreich installiert! :party:
Generiere Secure Boot Schlüssel...
setting up /etc...
old configuration detected. Please use `sbctl setup --migrate`
Created Owner UUID be4b8c33-407f-4743-bc02-d66a10bee97d
✓
Secure boot keys created!
Keys erfolgreich unter /etc/secureboot/keys
▶  Secure Boot Schlüssel erzeugt: /etc/secureboot
▶  Installiere Bootloader (lanzaboote signiert EFI-Binaries)...
setting up /etc...
Not checking switch inhibitors (action = boot)
Installing Lanzaboote to "/boot"...
Updating systemd-boot...
Error reading file /boot/EFI/BOOT/BOOTX64.EFI: No such file or directory
Can't open image /boot/EFI/BOOT/BOOTX64.EFI
systemd-boot is not signed. Replacing it with a signed binary...
Installing /boot/EFI/BOOT/BOOTX64.EFI
Installing /boot/EFI/systemd/systemd-bootx64.efi
Collecting garbage...
Successfully installed Lanzaboote.
▶  Bootloader installiert
▶  Kopiere Repo nach /mnt/opt/apphost...

  Konfiguration
  MQTT- und Ntfy-Passwörter werden automatisch generiert.
  Alle Werte können nach dem Neustart in /opt/apphost/.env geändert werden.

  Domain (z.B. example.com): lbaecker.de
  ACME E-Mail (Let's Encrypt): admin@lbaecker.de
  Cloudflare API Token:
  Authelia Admin-Nutzer [admin]:
  Authelia Admin-E-Mail [admin@lbaecker.de]:
  Authelia Admin-Passwort:
  Authelia Admin-Passwort (bestätigen):
▶  .env konfiguriert
▶  Generiere Secrets (lädt benötigte Nix-Pakete, dauert einen Moment...)
Generating RSA-4096 OIDC signing key...
⚠  update-secrets-authelia fehlgeschlagen – nach Neustart manuell ausführen:
⚠    bash /opt/apphost/scripts/update-secrets-authelia.sh
Hashing password for user 'homeassistant'...
these 18 paths will be fetched (99.2 MiB download, 315.7 MiB unpacked):
  /nix/store/39lyf5g2iz4jd2r6q4g5whk9vw09zglj-binutils-2.46
  /nix/store/y4h9ak6f3z22hvq97jwh90lmc4agx28c-binutils-2.46-lib
  /nix/store/z4zcd87nx2hrsdayd0vl2mx5ncj3ikd8-binutils-wrapper-2.46
  /nix/store/f055ibhb3if5qdvwfdqym4g90fjrdy62-cjson-1.7.19
  /nix/store/aagixdk8hcs7p107szv9z17p87mx33nb-expand-response-params
  /nix/store/sq0nrnfwhkc5ljvklnrk5ps4358g4nbj-gcc-15.2.0
  /nix/store/xcnqqnhw9hb4j5rjgds2yjryi8qki5f3-gcc-wrapper-15.2.0
  /nix/store/q5wv2ldpcv5w8yb2wmsngsygvlxb73fk-glibc-2.42-67-dev
  /nix/store/zkw0hl5pzwkmrvkrfvr1q5zlk28nv9v2-gmp-6.3.0
  /nix/store/9zgdw228zjfd4jzr901qzxhfcf43kz91-isl-0.20
  /nix/store/hvla3ggrfrl8rarcb0ps5kwdmfiajbf7-libargon2-20190702
  /nix/store/c0i98bjjwf0lcmrh97123qayrzchxz3d-libmpc-1.4.0
  /nix/store/1hrk7xhpm6h98n0lg1qixfrr2kb96zqs-linux-headers-6.18.7
  /nix/store/bkvyp9kqydixsfw8hbk29jgrxc31763g-mosquitto-2.1.2
  /nix/store/1hj55ilr76dggmpd99hvs21xai0p8046-mosquitto-2.1.2-dev
  /nix/store/x7j1z5lzbzfw28wq0vy406wq0w5n804r-mosquitto-2.1.2-lib
  /nix/store/wzigz21rnv9nj8g7r8ai8ldm84zqnhda-mpfr-4.2.2
  /nix/store/xknwpg5yjxxsffmwdmpys269543wpdy5-stdenv-linux
copying path '/nix/store/aagixdk8hcs7p107szv9z17p87mx33nb-expand-response-params' from 'https://cache.nixos.org'...
copying path '/nix/store/f055ibhb3if5qdvwfdqym4g90fjrdy62-cjson-1.7.19' from 'https://cache.nixos.org'...
copying path '/nix/store/1hrk7xhpm6h98n0lg1qixfrr2kb96zqs-linux-headers-6.18.7' from 'https://cache.nixos.org'...
copying path '/nix/store/hvla3ggrfrl8rarcb0ps5kwdmfiajbf7-libargon2-20190702' from 'https://cache.nixos.org'...
copying path '/nix/store/zkw0hl5pzwkmrvkrfvr1q5zlk28nv9v2-gmp-6.3.0' from 'https://cache.nixos.org'...
copying path '/nix/store/y4h9ak6f3z22hvq97jwh90lmc4agx28c-binutils-2.46-lib' from 'https://cache.nixos.org'...
copying path '/nix/store/x7j1z5lzbzfw28wq0vy406wq0w5n804r-mosquitto-2.1.2-lib' from 'https://cache.nixos.org'...
copying path '/nix/store/9zgdw228zjfd4jzr901qzxhfcf43kz91-isl-0.20' from 'https://cache.nixos.org'...
copying path '/nix/store/wzigz21rnv9nj8g7r8ai8ldm84zqnhda-mpfr-4.2.2' from 'https://cache.nixos.org'...
copying path '/nix/store/bkvyp9kqydixsfw8hbk29jgrxc31763g-mosquitto-2.1.2' from 'https://cache.nixos.org'...
copying path '/nix/store/39lyf5g2iz4jd2r6q4g5whk9vw09zglj-binutils-2.46' from 'https://cache.nixos.org'...
copying path '/nix/store/c0i98bjjwf0lcmrh97123qayrzchxz3d-libmpc-1.4.0' from 'https://cache.nixos.org'...
copying path '/nix/store/q5wv2ldpcv5w8yb2wmsngsygvlxb73fk-glibc-2.42-67-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/1hj55ilr76dggmpd99hvs21xai0p8046-mosquitto-2.1.2-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/sq0nrnfwhkc5ljvklnrk5ps4358g4nbj-gcc-15.2.0' from 'https://cache.nixos.org'...
copying path '/nix/store/z4zcd87nx2hrsdayd0vl2mx5ncj3ikd8-binutils-wrapper-2.46' from 'https://cache.nixos.org'...
copying path '/nix/store/xcnqqnhw9hb4j5rjgds2yjryi8qki5f3-gcc-wrapper-15.2.0' from 'https://cache.nixos.org'...
copying path '/nix/store/xknwpg5yjxxsffmwdmpys269543wpdy5-stdenv-linux' from 'https://cache.nixos.org'...
Error: Unable to open file /tmp/tmp.PCHMmxevz8 for writing. File exists.
⚠  update-secrets-mosquitto fehlgeschlagen – nach Neustart manuell ausführen:
⚠    bash /opt/apphost/scripts/update-secrets-mosquitto.sh
Hashing password for user 'admin'...
these 20 paths will be fetched (4.2 MiB download, 14.6 MiB unpacked):
  /nix/store/750mbixhamw6140rfavyvjpcp27mndmm-apache-httpd-2.4.68
  /nix/store/a4jhl1xmqazkjry9l9m8pazpzscb30gn-apache-httpd-2.4.68-dev
  /nix/store/03m5pz1b19721q4fcvz8fb1xj3mpijqw-apr-1.7.6
  /nix/store/cvxvwjm5ficvwv3gxk6pxnwwvqb3ycnf-apr-1.7.6-dev
  /nix/store/h94280pbv0bpr72fjd4bn2kcwikxv2if-apr-util-1.6.3
  /nix/store/cir6a6yzpk0b2b8lf2qcx452bqx7570k-apr-util-1.6.3-dev
  /nix/store/y574lyg1hs7zy43v5q255fz8xq0qp3wf-brotli-1.2.0
  /nix/store/z30fdafn9bykq5kdmq6lggi8fpjgkpw4-db-5.3.28-bin
  /nix/store/21mypl1fx5v7wh3gggzbq2irmc2338l2-db-5.3.28-dev
  /nix/store/aml37q1c80v4dpkjilvp3avqwqjxc4vb-expat-2.8.1-dev
  /nix/store/93bjlzpa0w7cg6fmpkgxa7494ac9rwf8-find-xml-catalogs-hook
  /nix/store/4rr29qx2avfs1xflg4m1wk35fcbhnjm9-glibc-iconv-2.42
  /nix/store/fmivqr7jkqz6qv0knm692d1998wc8in7-libxml2-2.15.3-bin
  /nix/store/35wfzwiy77ab9dhzjblb4kmdnckss40i-libxml2-2.15.3-dev
  /nix/store/lcygsmjgjv7y7n9ibr0jfw8kzpf708zx-lynx-2.9.2
  /nix/store/cy47yhhvklxhix57nkgbrnrq6dcsy3b7-openldap-2.6.13-dev
  /nix/store/i0jqva96qfgc76g8w7jbyiv6h3si07b9-openssl-3.6.2-dev
  /nix/store/a4pl6lig5byl15m4fpg4ypgsvly1byiy-pcre2-10.46-bin
  /nix/store/y5yv1kzvmppzdp0jkq3yf3apx563canv-pcre2-10.46-dev
  /nix/store/a9psmsc93llkravrd50rrv8k3dwdw60x-zlib-1.3.2-dev
copying path '/nix/store/93bjlzpa0w7cg6fmpkgxa7494ac9rwf8-find-xml-catalogs-hook' from 'https://cache.nixos.org'...
copying path '/nix/store/03m5pz1b19721q4fcvz8fb1xj3mpijqw-apr-1.7.6' from 'https://cache.nixos.org'...
copying path '/nix/store/y574lyg1hs7zy43v5q255fz8xq0qp3wf-brotli-1.2.0' from 'https://cache.nixos.org'...
copying path '/nix/store/i0jqva96qfgc76g8w7jbyiv6h3si07b9-openssl-3.6.2-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/a9psmsc93llkravrd50rrv8k3dwdw60x-zlib-1.3.2-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/aml37q1c80v4dpkjilvp3avqwqjxc4vb-expat-2.8.1-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/z30fdafn9bykq5kdmq6lggi8fpjgkpw4-db-5.3.28-bin' from 'https://cache.nixos.org'...
copying path '/nix/store/4rr29qx2avfs1xflg4m1wk35fcbhnjm9-glibc-iconv-2.42' from 'https://cache.nixos.org'...
copying path '/nix/store/lcygsmjgjv7y7n9ibr0jfw8kzpf708zx-lynx-2.9.2' from 'https://cache.nixos.org'...
copying path '/nix/store/fmivqr7jkqz6qv0knm692d1998wc8in7-libxml2-2.15.3-bin' from 'https://cache.nixos.org'...
copying path '/nix/store/cy47yhhvklxhix57nkgbrnrq6dcsy3b7-openldap-2.6.13-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/a4pl6lig5byl15m4fpg4ypgsvly1byiy-pcre2-10.46-bin' from 'https://cache.nixos.org'...
copying path '/nix/store/cvxvwjm5ficvwv3gxk6pxnwwvqb3ycnf-apr-1.7.6-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/h94280pbv0bpr72fjd4bn2kcwikxv2if-apr-util-1.6.3' from 'https://cache.nixos.org'...
copying path '/nix/store/35wfzwiy77ab9dhzjblb4kmdnckss40i-libxml2-2.15.3-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/21mypl1fx5v7wh3gggzbq2irmc2338l2-db-5.3.28-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/y5yv1kzvmppzdp0jkq3yf3apx563canv-pcre2-10.46-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/750mbixhamw6140rfavyvjpcp27mndmm-apache-httpd-2.4.68' from 'https://cache.nixos.org'...
copying path '/nix/store/cir6a6yzpk0b2b8lf2qcx452bqx7570k-apr-util-1.6.3-dev' from 'https://cache.nixos.org'...
copying path '/nix/store/a4jhl1xmqazkjry9l9m8pazpzscb30gn-apache-httpd-2.4.68-dev' from 'https://cache.nixos.org'...
Hashing password for user 'alertmanager'...
Hashing password for user 'hotwallet'...
Done. Written to /mnt/opt/apphost/secrets/ntfy.env
▶  update-secrets-ntfy ✓

NixOS-Installation erfolgreich abgeschlossen!

  Nach dem Neustart:

  1. SSH-Login:     ssh apphost@<IP-ADRESSE>
  2. Stack starten: cd /opt/apphost && docker compose up -d
  3. Tor-Adresse:   bash /opt/apphost/scripts/show-onion-address.sh
            TOR_DOMAIN in .env eintragen, danach: docker compose up -d

  Neustart in 1 Sekunden … (Strg+C zum Abbrechen)

Broadcast message from root@nixos on pts/1 (Mon 2026-07-13 14:27:21 UTC):

The system will reboot now!

Connection to 192.168.99.75 closed by remote host.
Connection to 192.168.99.75 closed.
```

```
~ ❯ ssh apphost@192.168.99.75
╔══════════════════════════════════════════════════════════════╗
║         AUTORISIERTER ZUGRIFF IST AUSSCHLIESSLICH            ║
║         FÜR BERECHTIGTE BENUTZER GESTATTET.                  ║
║         Alle Aktivitäten werden protokolliert.               ║
╚══════════════════════════════════════════════════════════════╝
[apphost@apphost:~]$
```
