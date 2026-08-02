# Einzige Quelle der Wahrheit für die userns-remap-Basis.
#
# Docker läuft mit "userns-remap": default (nixos/modules/docker.nix). Container-UID
# N entspricht auf dem Host also remapBase + N. Der Wert stand vorher mehrfach im
# Baum (docker.nix, local-ca.nix, media-dirs.nix, Kommentare in den Skripten) und
# musste bei einer Änderung überall nachgezogen werden.
#
# Shell-Skripte lesen den Wert NICHT von hier, sondern zur Laufzeit aus /etc/subuid
# (Feld "dockremap") – das ist dort die verlässlichere Quelle, weil sie das
# widerspiegelt, was auf dem laufenden System tatsächlich gilt. Dieser Wert hier
# definiert, was in /etc/subuid landet.
{
  remapBase = 100000;
  remapCount = 65536;
}
