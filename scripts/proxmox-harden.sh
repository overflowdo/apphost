#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Als root ausfuehren: sudo bash scripts/proxmox-harden.sh" >&2; exit 1; }

ERRORS=0

echo "=== Proxmox Hardening ==="
echo "PVE: $(pveversion 2>/dev/null || echo 'nicht erkannt')"
echo ""

# --- SSH Key prüfen ---
echo "[ SSH Key ]"

AUTH_KEYS="/root/.ssh/authorized_keys"
if [[ ! -f "$AUTH_KEYS" ]] || ! grep -qE "^(ssh-|ecdsa-|sk-)" "$AUTH_KEYS" 2>/dev/null; then
    echo "FEHLER: Kein SSH Public Key in $AUTH_KEYS gefunden." >&2
    echo "" >&2
    echo "Ohne hinterlegten Key wuerde die Deaktivierung der Passwort-Authentifizierung" >&2
    echo "den Remote-Zugriff dauerhaft sperren." >&2
    echo "" >&2
    echo "Key eintragen:" >&2
    echo "  ssh-copy-id root@<PROXMOX-IP>          # vom lokalen Rechner" >&2
    echo "  ssh -i <key> root@<PROXMOX-IP>          # danach testen!" >&2
    exit 1
fi

echo "$(grep -cE "^(ssh-|ecdsa-|sk-)" "$AUTH_KEYS") SSH Key(s) gefunden."

# --- SSH härten ---
echo ""
echo "[ SSH ]"

SSH_DROP_IN="/etc/ssh/sshd_config.d/99-hardening.conf"
mkdir -p /etc/ssh/sshd_config.d

if ! grep -qE "^Include\s+/etc/ssh/sshd_config\.d" /etc/ssh/sshd_config 2>/dev/null; then
    sed -i '1s|^|Include /etc/ssh/sshd_config.d/*.conf\n\n|' /etc/ssh/sshd_config
fi

cat > "$SSH_DROP_IN" << 'EOF'
# Proxmox Hardening - nicht manuell bearbeiten
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
EOF

if sshd -t 2>/dev/null; then
    systemctl restart sshd
    echo "SSH gehaertet und neu gestartet."
else
    echo "FEHLER: SSH-Konfiguration ungueltig, Datei wird entfernt." >&2
    rm -f "$SSH_DROP_IN"
    ERRORS=$((ERRORS + 1))
fi

# --- USB deaktivieren ---
echo ""
echo "[ USB ]"

cat > /etc/modprobe.d/99-disable-usb.conf << 'EOF'
blacklist usb-storage
blacklist uas
blacklist usbhid
EOF

echo "Aktualisiere initramfs..."
update-initramfs -u -k all 2>&1 | grep -E "^update-initramfs|^done" || true

for mod in usbhid usb_storage uas; do
    if lsmod | grep -q "^${mod}\b"; then
        modprobe -r "$mod" 2>/dev/null \
            && echo "Modul $mod entladen." \
            || echo "Modul $mod laeuft noch – wirkt nach Neustart."
    fi
done

echo "USB-Blacklist gesetzt (wirkt vollstaendig nach Neustart)."

# --- UEFI & Secure Boot ---
echo ""
echo "[ UEFI / Secure Boot ]"

if [[ -d /sys/firmware/efi ]]; then
    echo "UEFI-Modus aktiv."
else
    echo "WARNUNG: Legacy-BIOS erkannt – Secure Boot nicht moeglich." >&2
    ERRORS=$((ERRORS + 1))
fi

SB_VAR=$(find /sys/firmware/efi/efivars/ -name "SecureBoot-*" 2>/dev/null | head -1)
if [[ -n "$SB_VAR" ]]; then
    SB_BYTE=$(od -An -j4 -N1 -t u1 "$SB_VAR" 2>/dev/null | tr -d ' ')
    if [[ "$SB_BYTE" == "1" ]]; then
        echo "Secure Boot: aktiv."
    else
        echo "WARNUNG: Secure Boot deaktiviert – im Mainboard-UEFI aktivieren." >&2
        ERRORS=$((ERRORS + 1))
    fi
elif command -v mokutil &>/dev/null; then
    SB_OUT=$(mokutil --sb-state 2>/dev/null || echo "unbekannt")
    if echo "$SB_OUT" | grep -qi "enabled"; then
        echo "Secure Boot: aktiv."
    else
        echo "WARNUNG: Secure Boot – $SB_OUT" >&2
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "WARNUNG: Secure Boot Status nicht lesbar." >&2
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo "Fertig."
else
    echo "Fertig mit $ERRORS Warnung(en) – Details oben pruefen."
fi

echo ""
echo "Nächste Schritte:"
echo "  1. SSH-Login in neuem Terminal testen (bestehende Session offen lassen!)"
echo "     ssh -i <key> root@<PROXMOX-IP>"
echo "  2. Neustart: reboot"
echo "  3. Nach Neustart Secure Boot pruefen: Host -> Summary -> Boot Mode"
