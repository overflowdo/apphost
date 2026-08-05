# Deklarativer Mount der 4-TB-Bulk-Platte (USB, btrfs) nach /mnt/media.
#
# Bewusst als committed Modul (NICHT in der gitignore-ten hardware-configuration.nix),
# damit eine Neuinstallation den Mount automatisch enthält und Immich/OpenCloud/
# Paperless/Jellyfin ihre Bulk-Daten wiederfinden – ohne manuelles Nachtragen.
#
# device = der QEMU-Durchreich-Datenträger an scsi1 (`qm set 100 -scsi1 …`). Dieser
# by-id-Pfad ist stabil, deterministisch (solange die Platte an scsi1 hängt) und
# überlebt ein Neuformatieren der Platte (anders als eine btrfs-UUID, die man dann
# nachziehen müsste). Hängst du die Platte an einen anderen scsi-Slot, hier anpassen.
#
# nofail  -> die VM bootet auch durch, wenn die USB-Platte gerade nicht da ist.
# x-systemd.device-timeout -> nicht ewig auf ein fehlendes Gerät warten.
#
# ACHTUNG: Auf einem laufenden System, das den /mnt/media-Mount noch manuell in
# hardware-configuration.nix stehen hat, muss dieser dortige Eintrag ENTFERNT werden,
# bevor `nixos-rebuild` läuft – sonst kollidieren zwei Definitionen desselben Mounts.
{ ... }:
{
  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-id/usb-WD_Elements_25A3_575833324433333030524C30-0:0";
    fsType = "btrfs";
    options = [
      "nofail"
      "noatime"
      "compress=zstd"
      "x-systemd.device-timeout=15s"
    ];
  };
}
