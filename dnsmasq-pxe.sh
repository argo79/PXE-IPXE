#!/bin/bash
# =============================================================================
# DNSMASQ-MANAGER-ROUTER.SH - Con routing tra eth0 (PXE) e wlan0 (internet)
# =============================================================================

# CONFIGURAZIONE
CLIENT_IFACE="eth0"           # Scheda per i client PXE
WAN_IFACE="wlan0"             # Scheda per internet
SERVER_IP="192.168.11.1"
DHCP_START="192.168.11.11"
DHCP_END="192.168.11.111"
TFTPROOT="/srv/tftp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

enable_routing() {
    echo -e "${YELLOW}🔁 Abilito routing tra $CLIENT_IFACE e $WAN_IFACE...${NC}"
    
    # IP forwarding
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    
    # NAT masquerade
    sudo iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE 2>/dev/null
    
    # Forward tra interfacce
    sudo iptables -A FORWARD -i $CLIENT_IFACE -o $WAN_IFACE -j ACCEPT 2>/dev/null
    sudo iptables -A FORWARD -i $WAN_IFACE -o $CLIENT_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    
    echo -e "${GREEN}✅ Routing attivo (i client PXE hanno internet)${NC}"
}

disable_routing() {
    echo -e "${YELLOW}🔁 Disabilito routing...${NC}"
    sudo iptables -t nat -D POSTROUTING -o $WAN_IFACE -j MASQUERADE 2>/dev/null
    sudo iptables -D FORWARD -i $CLIENT_IFACE -o $WAN_IFACE -j ACCEPT 2>/dev/null
    sudo iptables -D FORWARD -i $WAN_IFACE -o $CLIENT_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    echo 0 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    echo -e "${GREEN}✅ Routing disabilitato${NC}"
}

case "$1" in
    start)
        echo -e "${GREEN}🚀 Avvio dnsmasq su $CLIENT_IFACE...${NC}"
        
        sudo ip addr add $SERVER_IP/24 dev $CLIENT_IFACE 2>/dev/null
        sudo ip link set $CLIENT_IFACE up
        
        sudo mkdir -p $TFTPROOT
        
        sudo tee /etc/dnsmasq.d/pxe.conf > /dev/null << EOF
interface=$CLIENT_IFACE
bind-interfaces
dhcp-range=$DHCP_START,$DHCP_END,12h
dhcp-option=3,$SERVER_IP
dhcp-option=6,8.8.8.8
enable-tftp
tftp-root=$TFTPROOT
log-dhcp
EOF
        
        sudo systemctl restart dnsmasq
        
        # Abilita routing se richiesto
        if [ "$2" = "--with-internet" ]; then
            enable_routing
        fi
        
        echo -e "${GREEN}✅ dnsmasq avviato${NC}"
        ;;
        
    stop)
        echo -e "${YELLOW}🛑 Fermo dnsmasq...${NC}"
        disable_routing
        sudo systemctl stop dnsmasq
        sudo rm -f /etc/dnsmasq.d/pxe.conf
        echo -e "${GREEN}✅ dnsmasq fermato${NC}"
        ;;
        
    status)
        if pgrep -x "dnsmasq" > /dev/null; then
            echo -e "${GREEN}✅ dnsmasq ATTIVO${NC}"
            echo ""
            echo "Routing:"
            cat /proc/sys/net/ipv4/ip_forward | grep -q 1 && echo "  IP forwarding: ATTIVO" || echo "  IP forwarding: DISATTIVO"
            sudo iptables -t nat -L POSTROUTING -v -n 2>/dev/null | grep -q MASQUERADE && echo "  NAT: ATTIVO" || echo "  NAT: DISATTIVO"
        else
            echo -e "${RED}❌ dnsmasq NON ATTIVO${NC}"
        fi
        ;;
        
    router|routing)
        if [ "$2" = "on" ]; then
            enable_routing
        elif [ "$2" = "off" ]; then
            disable_routing
        else
            echo "Uso: $0 router {on|off}"
        fi
        ;;
        
    *)
        echo "USO: $0 {start|stop|status|router} [opzioni]"
        echo ""
        echo "start --with-internet  - Avvia con routing internet"
        echo "router on/off         - Abilita/disabilita routing"
        ;;
esac