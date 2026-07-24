# GPT + EFI + zufällig-verschlüsselter Swap + Btrfs
# Root-Partition optional zusätzlich LUKS2-verschlüsselt, siehe disk-encryption.nix
#
# Subvolume-Struktur:
#   /    -> root – System
#   /nix -> nix  – Nix Store
#   /var -> var  – Logs, Datenbanken, Container-State
#   /opt -> opt  – AppHost-Repo, Docker-Daten
#   /tmp -> tmp  – Temporäre Dateien
{ ... }:
let
  # Optionale Festplattenverschlüsselung, standardmäßig aus (siehe disk-encryption.nix).
  diskEncryption = import ./disk-encryption.nix;

  rootFilesystem = {
    type      = "btrfs";
    extraArgs = [ "-f" "--label" "nixos" ];

    subvolumes = {

      # System-Root
      "/root" = {
        mountpoint   = "/";
        mountOptions = [ "compress=zstd" "noatime" ];
      };

      # Nix Store
      "/nix" = {
        mountpoint   = "/nix";
        mountOptions = [ "compress=zstd" "noatime" ];
      };

      # Systemdaten
      "/var" = {
        mountpoint   = "/var";
        mountOptions = [ "compress=zstd" "noatime" ];
      };

      # AppHost-Daten
      "/opt" = {
        mountpoint   = "/opt";
        mountOptions = [ "compress=zstd" "noatime" ];
      };

      # Temporäre Dateien nicht ausführbar (Sicherheit)
      "/tmp" = {
        mountpoint   = "/tmp";
        mountOptions = [
          "compress=zstd" "noatime"
          "nosuid" "nodev" "noexec"
        ];
      };
    };
  };

  # Bei aktivierter Verschlüsselung wird Btrfs in einen LUKS2-Container gelegt.
  # Ohne settings.keyFile/passwordFile fragt disko die Passphrase bei der
  # Formatierung interaktiv ab, und systemd fragt sie danach bei jedem Boot
  # erneut über die Konsole ab.
  rootContent =
    if diskEncryption then {
      type    = "luks";
      name    = "cryptroot";
      settings.allowDiscards = true; # TRIM-Unterstützung für SSDs
      content = rootFilesystem;
    } else rootFilesystem;
in
{
  disko.devices = {
    disk = {
      main = {
        type   = "disk";
        device = "/dev/sda"; # Müsste in Proxmox mit VirtIO SCSI immer gleich sein

        content = {
          type = "gpt";
          partitions = {

            # EFI System Partition (systemd-boot)
            ESP = {
              size    = "512M";
              type    = "EF00";   # EFI System Partition
              content = {
                type         = "filesystem";
                format       = "vfat";
                mountpoint   = "/boot";
                mountOptions = [ "defaults" "umask=0077" "noatime" ];
              };
            };

            # Swap verschlüsselt
            swap = {
              size    = "8G";
              content = {
                type             = "swap";
                randomEncryption = true;
              };
            };

            # Root-Partition via Btrfs mit Subvolumes
            root = {
              size    = "100%";
              content = rootContent;
            };
          };
        };
      };
    };
  };
}
