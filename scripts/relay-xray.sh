#!/bin/bash
# Relay (entry) server: VLESS REALITY in -> VLESS REALITY out to an upstream (exit) server.
# Usage: bash relay-xray.sh 'vless://...upstream link...' <SNI_for_entry_hop>
set -e
UP=${1:?usage: bash relay-xray.sh '<upstream vless link>' <SNI>}
SNI=${2:?usage: bash relay-xray.sh '<upstream vless link>' <SNI>}
PORT=443
CFG=/usr/local/etc/xray/config.json
ENV=/usr/local/etc/xray/relay.env

# Parse the upstream link
R=${UP#vless://}; R=${R%%#*}
UP_ID=${R%%@*}; R=${R#*@}
HP=${R%%\?*}; HP=${HP%/}; Q=${R#*\?}
UP_HOST=${HP%:*}; UP_PORT=${HP##*:}
p(){ echo "$Q" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1; }
UP_SNI=$(p sni); UP_PBK=$(p pbk); UP_SID=$(p sid); UP_FLOW=$(p flow); UP_FP=$(p fp); T=$(p type)
if [ "$(p security)" != reality ] || [ -z "$UP_PBK" ] || ! [[ "$T" =~ ^(tcp|raw|)$ ]]; then
  echo "ERROR: need a VLESS REALITY tcp link"; exit 1; fi

apt update -y >/dev/null && apt install -y curl openssl >/dev/null
timeout 5 bash -c "</dev/tcp/$UP_HOST/$UP_PORT" 2>/dev/null || { echo "ERROR: cannot reach $UP_HOST:$UP_PORT"; exit 1; }
[ "$(curl -s --tlsv1.3 --http2 -o /dev/null -w '%{http_version}' --max-time 8 https://$SNI)" = 2 ] || { echo "ERROR: $SNI lacks TLS1.3+H2, pick another"; exit 1; }
if ss -tlnp | grep ":$PORT " | grep -vq xray; then echo "ERROR: TCP $PORT in use"; exit 1; fi
command -v xray >/dev/null || bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Keys (reused on re-run so the client link stays the same)
if [ -f "$ENV" ]; then . "$ENV"; echo "== reusing existing keys"; else
  UUID=$(xray uuid); SID=$(openssl rand -hex 8); K=$(xray x25519)
  PRIV=$(echo "$K" | awk -F': ' 'NR==1{print $2}'); PUB=$(echo "$K" | awk -F': ' 'NR==2{print $2}')
  printf 'UUID=%s\nPRIV=%s\nPUB=%s\nSID=%s\n' "$UUID" "$PRIV" "$PUB" "$SID" > "$ENV"; chmod 600 "$ENV"
fi

[ -f "$CFG" ] && cp "$CFG" "$CFG.bak"
cat > "$CFG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "in", "port": $PORT, "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "dest": "$SNI:443", "serverNames": ["$SNI"], "privateKey": "$PRIV", "shortIds": ["$SID"] }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true }
    },
    { "tag": "test", "listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": { "udp": true } }
  ],
  "outbounds": [
    {
      "tag": "abroad", "protocol": "vless",
      "settings": { "vnext": [ { "address": "$UP_HOST", "port": $UP_PORT,
        "users": [ { "id": "$UP_ID", "encryption": "none", "flow": "$UP_FLOW" } ] } ] },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "serverName": "$UP_SNI", "publicKey": "$UP_PBK", "shortId": "$UP_SID", "fingerprint": "${UP_FP:-chrome}" }
      }
    },
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" },
      { "type": "field", "domain": ["geosite:category-ru"], "outboundTag": "direct" },
      { "type": "field", "ip": ["geoip:ru"], "outboundTag": "direct" }
    ]
  }
}
EOF
xray run -test -c "$CFG" || { echo "ERROR: bad config"; exit 1; }
systemctl enable xray >/dev/null 2>&1; systemctl restart xray; sleep 2
command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow $PORT/tcp >/dev/null

echo "xray: $(systemctl is-active xray)"
echo "exit IP (must be the upstream IP): $(curl -s4 --max-time 10 -x socks5h://127.0.0.1:10808 https://ipinfo.io/ip || echo FAIL)"
IP=$(curl -s4 --max-time 5 https://ifconfig.me || hostname -I | cut -d' ' -f1)
echo "vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUB&sid=$SID&type=tcp#RELAY-VLESS" | tee /root/relay-link.txt
chmod 600 /root/relay-link.txt
