#!/bin/bash
# Xray VLESS + REALITY (Vision) server installer.
# Usage: bash install-xray-reality.sh <SNI_domain> [port]
#   SNI_domain: a neighbour site with TLS 1.3 + HTTP/2 (find it with RealiTLScanner)
# Re-running keeps the same UUID/keys, so client links stay valid.
set -e
SNI=${1:?usage: bash install-xray-reality.sh <SNI_domain> [port]}
PORT=${2:-443}
CFG=/usr/local/etc/xray/config.json
ENV=/usr/local/etc/xray/reality.env

apt update -y >/dev/null && apt install -y curl openssl >/dev/null
[ "$(curl -s --tlsv1.3 --http2 -o /dev/null -w '%{http_version}' --max-time 8 "https://$SNI")" = 2 ] \
  || { echo "ERROR: $SNI does not offer TLS 1.3 + HTTP/2, pick another domain"; exit 1; }
if ss -tlnp | grep ":$PORT " | grep -vq xray; then echo "ERROR: TCP $PORT in use"; exit 1; fi
command -v xray >/dev/null || bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

if [ -f "$ENV" ]; then . "$ENV"; echo "== reusing existing keys"; else
  UUID=$(xray uuid); SID=$(openssl rand -hex 8); K=$(xray x25519)
  # Works with both old ("Private key:/Public key:") and new ("PrivateKey:/Password:") output
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
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "rules": [ { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" } ]
  }
}
EOF
xray run -test -c "$CFG" || { echo "ERROR: bad config"; exit 1; }
systemctl enable xray >/dev/null 2>&1; systemctl restart xray
command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow "$PORT/tcp" >/dev/null

IP=$(curl -s4 --max-time 5 https://ifconfig.me || hostname -I | cut -d' ' -f1)
echo "xray: $(systemctl is-active xray)"
echo "vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUB&sid=$SID&type=tcp#VLESS-REALITY" | tee /root/vless-link.txt
chmod 600 /root/vless-link.txt
