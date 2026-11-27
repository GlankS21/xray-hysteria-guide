#!/bin/bash
# Hysteria2 + Salamander obfuscation + UDP port hopping installer.
# Usage: bash install-hysteria2.sh [port]   (default 29443, hopping range 20000-28999)
# Re-running reuses the existing passwords.
set -e
PORT=${1:-29443}
HOP=20000:28999
CFG=/etc/hysteria/config.yaml
apt update -y >/dev/null && apt install -y curl openssl iptables >/dev/null
IP=$(curl -s4 https://ifconfig.me || hostname -I | cut -d' ' -f1)

if [ -f "$CFG" ] && grep -q salamander "$CFG"; then
  echo "== Hysteria2 already configured, reusing settings"
  PORT=$(grep -oP '^listen: :\K[0-9]+' "$CFG")
  PASS=$(awk '/^auth:/{f=1} f&&/password:/{print $2; exit}' "$CFG")
  OBFS=$(awk '/salamander:/{f=1} f&&/password:/{print $2; exit}' "$CFG")
else
  if ss -ulnp | grep -q ":$PORT "; then echo "ERROR: UDP $PORT in use"; exit 1; fi
  bash <(curl -fsSL https://get.hy2.sh/)
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
    -subj "/CN=bing.com" -days 36500 2>/dev/null
  chown hysteria:hysteria /etc/hysteria/server.key /etc/hysteria/server.crt
  PASS=$(openssl rand -hex 16)
  OBFS=$(openssl rand -hex 16)
  cat > "$CFG" <<EOF
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASS
obfs:
  type: salamander
  salamander:
    password: $OBFS
EOF
fi
systemctl enable hysteria-server >/dev/null 2>&1
systemctl restart hysteria-server

# Port hopping: UDP $HOP -> $PORT
IPT=$(command -v iptables)
cat > /etc/systemd/system/hy2-hop.service <<EOF
[Unit]
Description=Hysteria2 port hopping
After=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$IPT -t nat -A PREROUTING -p udp --dport $HOP -j REDIRECT --to-ports $PORT
ExecStop=$IPT -t nat -D PREROUTING -p udp --dport $HOP -j REDIRECT --to-ports $PORT
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable hy2-hop >/dev/null 2>&1
systemctl restart hy2-hop

echo "hysteria: $(systemctl is-active hysteria-server)  hop: $(systemctl is-active hy2-hop)"
{
echo "hysteria2://$PASS@$IP:$PORT/?obfs=salamander&obfs-password=$OBFS&sni=bing.com&insecure=1#HY2"
echo "hysteria2://$PASS@$IP:$PORT/?mport=${HOP/:/-}&obfs=salamander&obfs-password=$OBFS&sni=bing.com&insecure=1#HY2-Hop"
} | tee /root/hy2-links.txt
chmod 600 /root/hy2-links.txt
