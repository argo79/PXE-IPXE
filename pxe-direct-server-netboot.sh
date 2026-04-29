#!/bin/bash
# ======================================================================
# pxe-direct-server-netboot.sh - PXE
# ======================================================================

set -e

INTERFACE="${1:-eth0}"
SERVER_IP="${2:-192.168.11.1}"
DHCP_RANGE="192.168.11.50,192.168.11.150"

TFTPROOT="/srv/tftp"
HTTPROOT="/srv/http"
CACHEDIR="/var/cache/netbootxyz"

echo "======================================"
echo " NETBOOT.XYZ PXE - ARG0 mod"
echo "======================================"

# =========================
# 1. PREP DIR
# =========================
sudo mkdir -p "$TFTPROOT" "$HTTPROOT" "$CACHEDIR"

# =========================
# 2. PACKAGES
# =========================
sudo apt update
sudo apt install -y dnsmasq wget

# =========================
# 3. DOWNLOAD iPXE BOOT FILES
# =========================

echo "📦 Download bootloader..."

cd "$TFTPROOT"

wget -q -O netboot.xyz.kpxe https://boot.netboot.xyz/ipxe/netboot.xyz.kpxe
wget -q -O netboot.xyz.efi  https://boot.netboot.xyz/ipxe/netboot.xyz.efi

wget -q -O snponly.efi https://boot.ipxe.org/snponly.efi

# =========================
# 4. AUTOEXEC
# =========================

sudo tee "$HTTPROOT/autoexec.ipxe" > /dev/null <<EOF
#!ipxe

set server_ip $SERVER_IP

console --x 1024 --y 768

menu NETBOOT XYZ STABLE - ARG0 mod
item netboot https://boot.netboot.xyz/menu.ipxe
item shell   iPXE shell
item reboot  reboot
choose target && goto \${target}

:netboot
chain https://boot.netboot.xyz/menu.ipxe
goto menu

:shell
shell

:reboot
reboot
EOF

# =========================
# 5. DNSMASQ
# =========================

sudo tee /etc/dnsmasq.d/netbootxyz.conf > /dev/null <<EOF
interface=$INTERFACE
bind-interfaces

dhcp-range=$DHCP_RANGE,12h
dhcp-option=3,$SERVER_IP

# PXE detection
dhcp-match=set:ipxe,175
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:bios,option:client-arch,0

dhcp-boot=tag:ipxe,http://$SERVER_IP:8080/autoexec.ipxe

dhcp-boot=tag:efi64,tag:!ipxe,snponly.efi
dhcp-boot=tag:bios,tag:!ipxe,netboot.xyz.kpxe

enable-tftp
tftp-root=$TFTPROOT
log-dhcp
EOF

# =========================
# 6. HTTP SERVER
# =========================

cd "$HTTPROOT"
nohup python3 -m http.server 8080 --bind 0.0.0.0 > /tmp/http_pxe.log 2>&1 &

# =========================
# 7. RESTART DNSMASQ
# =========================

sudo systemctl restart dnsmasq

# =========================
# DONE
# =========================

echo ""
echo "======================================"
echo "✅ PXE NETBOOT.XYZ STABILE ATTIVO"
echo "IP: $SERVER_IP"
echo "HTTP: http://$SERVER_IP:8080/autoexec.ipxe"
echo "======================================"