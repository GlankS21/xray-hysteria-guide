#!/bin/bash
# Forward Hysteria2 UDP (main port + hopping range) from this relay to an upstream server.
# Usage: bash relay-hysteria2-udp.sh <UPSTREAM_IP> [port] [hop_range]
# Client link: same as the upstream link, only replace the IP with this relay's IP.
set -e
FOREIGN=${1:?usage: bash relay-hysteria2-udp.sh <UPSTREAM_IP> [port] [hop_range]}
PORT=${2:-29443}
HOP=${3:-20000:28999}
apt install -y iptables >/dev/null 2>&1
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-relay.conf && sysctl -p /etc/sysctl.d/99-relay.conf
IPT=$(command -v iptables)
cat > /etc/systemd/system/hy2-relay.service <<EOT
[Unit]
Description=Forward Hysteria2 UDP to $FOREIGN
After=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$IPT -t nat -A PREROUTING -p udp -m multiport --dports $HOP,$PORT -j DNAT --to-destination $FOREIGN
ExecStart=$IPT -t nat -A POSTROUTING -p udp -d $FOREIGN -j MASQUERADE
ExecStart=$IPT -I FORWARD -p udp -d $FOREIGN -j ACCEPT
ExecStart=$IPT -I FORWARD -p udp -s $FOREIGN -j ACCEPT
ExecStop=$IPT -t nat -D PREROUTING -p udp -m multiport --dports $HOP,$PORT -j DNAT --to-destination $FOREIGN
ExecStop=$IPT -t nat -D POSTROUTING -p udp -d $FOREIGN -j MASQUERADE
ExecStop=$IPT -D FORWARD -p udp -d $FOREIGN -j ACCEPT
ExecStop=$IPT -D FORWARD -p udp -s $FOREIGN -j ACCEPT
[Install]
WantedBy=multi-user.target
EOT
systemctl daemon-reload && systemctl enable hy2-relay >/dev/null 2>&1 && systemctl restart hy2-relay
echo "hy2-relay: $(systemctl is-active hy2-relay)"
