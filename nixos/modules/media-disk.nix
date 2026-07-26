# Deklarativer Mount der 4-TB-Bulk-Platte (USB, btrfs) nach /mnt/media.
#
# Bewusst als committed Modul (NICHT in der gitignore-ten hardware-configuration.nix),
# damit eine Neuinstallation den Mount automatisch enthält und Immich/OpenCloud/
# Paperless/Jellyfin ihre Bulk-Daten wiederfinden – ohne manuelles Nachtragen.
#
# WICHTIG: Die UUID gehört zum btrfs auf der WD-Elements-4TB dieses Hosts. Bei einer
# Neu-Formatierung der Platte hier die neue UUID eintragen (in der VM: `blkid /dev/sdb`).
#
# nofail  -> die VM bootet auch durch, wenn die USB-Platte gerade nicht da ist,
#            statt im Notfall-Modus hängen zu bleiben.
# x-systemd.device-timeout -> nicht ewig auf ein fehlendes Gerät warten.
#
# Hinweis: Auf einem bereits laufenden System, das den /mnt/media-Mount noch manuell
# in hardware-configuration.nix stehen hat, muss dieser dortige Eintrag ENTFERNT
# werden, bevor rebuild läuft – sonst kollidieren zwei Definitionen desselben Mounts.
{ ... }:
{
  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-uuid/16c073c4-7251-4e65-9145-8643e053a767";
    fsType = "btrfs";
    options = [
      "nofail"
      "noatime"
      "compress=zstd"
      "x-systemd.device-timeout=15s"
    ];
  };
}
