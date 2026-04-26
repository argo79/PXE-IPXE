#!/bin/bash

# --- CONFIGURAZIONE ---
INTERFACE="eth0"
SERVER_IP="192.168.11.1"
TFTPROOT="/srv/tftp"
HTTPROOT="/srv/http"
LOGFILE="/var/log/http_pxe.log"

# 🔥 PERCORSO BUILD IPXE
IPXE_BUILD_DIR="$HOME/blobspace/pxe-direct-server/ipxe/src/bin-x86_64-efi"

echo "======================================"
echo "   PXE SERVER LOCALE (STABLE FIX v2)"
echo "======================================"

# =========================
# 1. CLEAN
# =========================

echo "🧹 Pulizia servizi..."

sudo systemctl stop dnsmasq 2>/dev/null
sudo pkill -f "python3 -m http.server" 2>/dev/null

sudo mkdir -p "$TFTPROOT" "$HTTPROOT"

# pulizia TFTP
sudo rm -rf "$TFTPROOT"/*

# pulizia vecchi log
sudo rm -f "$LOGFILE"

# =========================
# 2. SETUP IPXE
# =========================

echo "📦 Setup iPXE..."

if [ -f "$IPXE_BUILD_DIR/ipxe.efi" ]; then
    echo "✔ Uso build custom iPXE"
    sudo cp "$IPXE_BUILD_DIR/ipxe.efi" "$TFTPROOT/ipxe.efi"
    [ -f "$IPXE_BUILD_DIR/undionly.kpxe" ] && sudo cp "$IPXE_BUILD_DIR/undionly.kpxe" "$TFTPROOT/"
    [ -f "$IPXE_BUILD_DIR/snponly.efi" ] && sudo cp "$IPXE_BUILD_DIR/snponly.efi" "$TFTPROOT/"
else
    echo "✔ Uso iPXE di sistema"
    sudo cp /usr/lib/ipxe/ipxe.efi "$TFTPROOT/" 2>/dev/null
    sudo cp /usr/lib/ipxe/undionly.kpxe "$TFTPROOT/" 2>/dev/null
    sudo cp /usr/lib/ipxe/snponly.efi "$TFTPROOT/" 2>/dev/null
fi

# =========================
# 3. MENU IPXE
# =========================

echo "📝 Creazione menu iPXE..."

sudo tee "$HTTPROOT/menu-locale.ipxe" > /dev/null << EOF
#!ipxe

set server_ip 192.168.11.1

:menu
menu PXE SERVER LOCALE
item sysresc        SystemRescue (RAM)
item sysresc-safe   SystemRescue SAFE
item kali           Kali GUI
item kali-text      Kali Text
item kali-forensic  Kali Forensic
item shell          iPXE Shell
item reboot         Reboot

choose target || goto menu
goto ${target}

# =========================
# SYSTEMRESCUE
# =========================

:sysresc
kernel http://${server_ip}:8080/sysresc/linux \
    archisobasedir=sysresccd \
    archiso_http_srv=http://${server_ip}:8080/sysresc/ \
    ip=dhcp \
    copytoram
initrd http://${server_ip}:8080/sysresc/initrd.img
boot || goto menu

:sysresc-safe
kernel http://${server_ip}:8080/sysresc/linux \
    archisobasedir=sysresccd \
    archiso_http_srv=http://${server_ip}:8080/sysresc/ \
    ip=dhcp \
    nomodeset noapic noacpi
initrd http://${server_ip}:8080/sysresc/initrd.img
boot || goto menu

# =========================
# KALI
# =========================

:kali
kernel http://${server_ip}:8080/kali/live/vmlinuz \
    boot=live \
    components \
    netboot=http \
    fetch=http://${server_ip}:8080/kali/live/filesystem.squashfs \
    ip=dhcp
initrd http://${server_ip}:8080/kali/live/initrd.img
boot || goto menu

:kali-text
kernel http://${server_ip}:8080/kali/live/vmlinuz \
    boot=live \
    components \
    netboot=http \
    fetch=http://${server_ip}:8080/kali/live/filesystem.squashfs \
    systemd.unit=multi-user.target \
    ip=dhcp
initrd http://${server_ip}:8080/kali/live/initrd.img
boot || goto menu

:kali-forensic
kernel http://${server_ip}:8080/kali/live/vmlinuz \
    boot=live \
    components \
    netboot=http \
    fetch=http://${server_ip}:8080/kali/live/filesystem.squashfs \
    forensic \
    ip=dhcp
initrd http://${server_ip}:8080/kali/live/initrd.img
boot || goto menu

# =========================
# SHELL
# =========================

:shell
shell

:reboot
reboot
EOF

# =========================
# 5. HTTP SERVER
# =========================

echo "🌐 Avvio HTTP server..."

sudo touch "$LOGFILE"
sudo chmod 666 "$LOGFILE"

cd "$HTTPROOT"

sudo nohup python3 -m http.server 8080 --bind 0.0.0.0 > "$LOGFILE" 2>&1 &

sleep 2

if ! ss -tulnp | grep -q ":8080"; then
    echo "❌ HTTP server NON attivo"
    exit 1
fi

# =========================
# 6. START DNSMASQ
# =========================

echo "🔄 Avvio dnsmasq..."
sudo systemctl restart dnsmasq

# =========================
# DONE
# =========================

echo ""
echo "======================================"
echo "✅ PXE SERVER ATTIVO"
echo "IP: $SERVER_IP"
echo "TFTP: $TFTPROOT"
echo "HTTP: http://$SERVER_IP:8080"
echo "======================================"