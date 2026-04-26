#!/bin/bash

# --- CONFIGURAZIONE ---
INTERFACE="eth0"
SERVER_IP="192.168.11.1"
TFTPROOT="/srv/tftp"
HTTPROOT="/srv/http"
LOGFILE="/var/log/http_pxe.log"

# 🔥 PERCORSO BUILD IPXE (ALLINEATO CORRETTAMENTE)
#IPXE_BUILD_DIR="$HOME/blobspace/pxe-direct-server/ipxe/src/bin-x86_64-efi"

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
# 2. SETUP IPXE (SAFE)
# =========================

echo "📦 Setup iPXE (SAFE MODE)"

sudo mkdir -p "$TFTPROOT"

copy_if_missing() {
    src="$1"
    dst="$2"

    if [ ! -f "$src" ]; then
        echo "⚠️ MANCANTE: $src"
        return
    fi

    if [ -f "$dst" ]; then
        echo "⏭️ ESISTE GIÀ: $dst (skip)"
    else
        echo "✔ COPIO: $src -> $dst"
        sudo cp "$src" "$dst"
    fi
}

# =========================
# CUSTOM BUILD
# =========================
if [ -f "$IPXE_BUILD_DIR/ipxe.efi" ]; then
    echo "✔ Uso build custom iPXE"

    copy_if_missing "$IPXE_BUILD_DIR/ipxe.efi" "$TFTPROOT/ipxe.efi"
    copy_if_missing "$HOME/blobspace/pxe-direct-server/ipxe/src/bin/undionly.kpxe" "$TFTPROOT/undionly.kpxe"
    copy_if_missing "$IPXE_BUILD_DIR/snponly.efi" "$TFTPROOT/snponly.efi"

# =========================
# SYSTEM DEFAULT
# =========================
else
    echo "✔ Uso iPXE di sistema"

    copy_if_missing "/usr/lib/ipxe/ipxe.efi" "$TFTPROOT/ipxe.efi"
    copy_if_missing "/usr/lib/ipxe/undionly.kpxe" "$TFTPROOT/undionly.kpxe"
    copy_if_missing "/usr/lib/ipxe/snponly.efi" "$TFTPROOT/snponly.efi"
fi

# =========================
# 3. MENU IPXE
# =========================

echo "📝 Creazione menu iPXE..."

sudo tee "$HTTPROOT/menu-locale.ipxe" > /dev/null << EOF
#!ipxe

set server_ip $SERVER_IP

console
console --x 1024 --y 768

:menu
menu PXE SERVER LOCALE - Arg0net
item sysresc        SystemRescue (RAM)
item sysresc-safe   SystemRescue SAFE
item kali           Kali GUI
item kali-text      Kali Text
item kali-forensic  Kali Forensic
item kali-persist   Kali NFS (emergency shell)
item alpine-linux   Alpine Linux (emergency shell)
item shell          iPXE Shell
item reboot         Reboot

choose target && goto \${target}


# =========================
# SYSTEMRESCUE
# =========================

:sysresc
kernel http://\${server_ip}:8080/sysresc/linux \
    archisobasedir=sysresccd \
    archiso_http_srv=http://\${server_ip}:8080/sysresc/ \
    ip=dhcp \
    copytoram
initrd http://\${server_ip}:8080/sysresc/initrd.img
boot || goto menu

:sysresc-safe
kernel http://\${server_ip}:8080/sysresc/linux \
    archisobasedir=sysresccd \
    archiso_http_srv=http://\${server_ip}:8080/sysresc/ \
    ip=dhcp \
    nomodeset noapic noacpi
initrd http://\${server_ip}:8080/sysresc/initrd.img
boot || goto menu

# =========================
# KALI
# =========================

:kali
kernel http://\${server_ip}:8080/kali/live/vmlinuz \
    boot=live \
    components \
    netboot=http \
    fetch=http://\${server_ip}:8080/kali/live/filesystem.squashfs \
    ip=dhcp
initrd http://\${server_ip}:8080/kali/live/initrd.img
boot || goto menu

:kali-text
kernel http://\${server_ip}:8080/kali/live/vmlinuz \
    boot=live \
    components \
    netboot=http \
    fetch=http://\${server_ip}:8080/kali/live/filesystem.squashfs \
    systemd.unit=multi-user.target \
    ip=dhcp
initrd http://\${server_ip}:8080/kali/live/initrd.img
boot || goto menu

:kali-forensic
kernel http://\${server_ip}:8080/kali/live/vmlinuz \
    boot=live \
    components \
    netboot=http \
    fetch=http://\${server_ip}:8080/kali/live/filesystem.squashfs \
    forensic \
    ip=dhcp
initrd http://\${server_ip}:8080/kali/live/initrd.img
boot || goto menu

:kali-persist
set base http://\${server_ip}:8080/kali

kernel \${base}/live/vmlinuz \
    boot=live \
    components \
    ip=dhcp \
    netboot=nfs \
    nfsroot=\${server_ip}:/srv/nfs/kali-root \
    init=/lib/live/mount/medium/live-config \
    persistent

initrd \${base}/live/initrd.img
boot || goto menu


# =========================
# ALPINE (FIXED)
# =========================

:alpine-linux
set base http://\${server_ip}:8080/alpine

kernel \${base}/boot/vmlinuz-lts ip=dhcp copytoram modloop=\${base}/boot/modloop-lts alpine_repo=http://192.168.11.1:8080/alpine/apks
initrd \${base}/boot/initramfs-lts
boot || goto menu
# =========================
# SHELL / REBOOT
# =========================

:shell
shell
goto menu

:reboot
reboot
EOF

# =========================
# 4. DNSMASQ
# =========================

echo "⚙️ Configurazione dnsmasq..."

sudo tee /etc/dnsmasq.d/pxe.conf > /dev/null << EOF
interface=$INTERFACE
bind-interfaces

dhcp-range=192.168.11.10,192.168.11.200,12h
dhcp-option=3,$SERVER_IP

dhcp-match=set:ipxe,175
dhcp-boot=tag:ipxe,http://$SERVER_IP:8080/menu-locale.ipxe

dhcp-match=set:efi-x64,option:client-arch,7
dhcp-boot=tag:efi-x64,tag:!ipxe,snponly.efi

dhcp-boot=tag:!efi-x64,tag:!ipxe,undionly.kpxe

enable-tftp
tftp-root=$TFTPROOT
log-dhcp
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