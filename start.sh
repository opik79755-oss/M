#!/bin/bash
set -e

echo "[START] Initializing SSH & VPN Panel Container..."

# --- BBR Optimization ---
if [ "$ENABLE_BBR" = "true" ]; then
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true
fi

# --- Start Dropbear SSH Server ---
SSH_PORT="${SSH_PORT:-22}"
echo "[START] Starting Dropbear on port $SSH_PORT..."
mkdir -p /etc/dropbear
/usr/sbin/dropbear -p 0.0.0.0:$SSH_PORT -R -b /etc/dropbear_banner 2>/dev/null || true

# --- Start BadVPN UDPGW ---
UDPGW_PORT="${UDPGW_PORT:-7300}"
if [ -f /usr/local/bin/badvpn-udpgw ]; then
    echo "[START] Starting UDPGW on port $UDPGW_PORT..."
    nohup /usr/local/bin/badvpn-udpgw --listen-addr 0.0.0.0:$UDPGW_PORT --max-clients 1000 --max-connections-for-client 50 >/dev/null 2>&1 &
fi

# --- Start Node.js Server ---
echo "[START] Starting Node.js Server Engine..."
exec node server.js
