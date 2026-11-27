# Xray REALITY + Hysteria2 (Salamander) — self-hosted VPN guide

<p align="center"><a href="README.md">🇬🇧 English</a> &nbsp;|&nbsp; <a href="README.vi.md">🇻🇳 Tiếng Việt</a> &nbsp;|&nbsp; <a href="README.ru.md">🇷🇺 Русский</a></p>

---

A practical overview of running your own censorship-resistant VPN on a Linux VPS with two protocols:

| Protocol | Transport | Strength | Weakness |
|---|---|---|---|
| **VLESS + REALITY** (Xray) | TCP 443 | Looks like a real TLS 1.3 visit to another website; no domain or certificate needed | TCP only; slower on lossy links |
| **Hysteria2 + Salamander** | UDP | Very fast on bad / lossy networks; Salamander hides the QUIC signature | UDP is often throttled or blocked on mobile networks |

Keep both: when one is blocked, the other often still works.

> Requirements: a VPS with root access (Debian 12/13 or Ubuntu 22.04+), a public IPv4.
> Scripts are idempotent: re-running keeps existing keys, so your client links stay valid.

## 1. Connect to the server

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\vpn
type $env:USERPROFILE\.ssh\vpn.pub | ssh root@<IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh -i $env:USERPROFILE\.ssh\vpn root@<IP>
```

Copy the scripts to the server:

```bash
git clone https://github.com/<you>/<this-repo>.git && cd <this-repo>/scripts
```

## 2. Xray VLESS + REALITY

### 2.1 Choose an SNI (camouflage domain)
REALITY borrows the TLS handshake of a real website. Best choice: a small site **hosted in the same subnet** as your VPS, supporting TLS 1.3 + HTTP/2. Find one with RealiTLScanner:

```bash
cd /tmp
URL=$(curl -s https://api.github.com/repos/XTLS/RealiTLScanner/releases/latest | grep browser_download_url | grep -i linux | grep -Ei 'amd64|64' | grep -vi arm | head -1 | cut -d '"' -f 4)
wget -q "$URL" -O scanner && chmod +x scanner
./scanner -addr <IP> -port 443 -thread 10 -timeout 5 -out found.csv   # Ctrl+C after ~1 minute
cut -d, -f3 found.csv | sort -u
```

Avoid: big brands (google, yandex, sberbank… on a hosting IP is suspicious), names that look like other VPNs/proxies, self-signed certificates.

### 2.2 Install

```bash
bash install-xray-reality.sh <SNI_domain>        # optional 2nd arg: port (default 443)
```

The script checks TLS 1.3 + HTTP/2 of the SNI, installs Xray, generates UUID / x25519 keys / shortId, writes the config and prints a `vless://` link (also saved to `/root/vless-link.txt`).

## 3. Hysteria2 + Salamander + port hopping

```bash
bash install-hysteria2.sh                          # optional arg: port (default 29443)
```

- Self-signed certificate (`CN=bing.com`), so clients use `insecure=1`.
- **Salamander** obfuscation: every packet is scrambled with a shared password, so DPI cannot see QUIC.
- **Port hopping**: UDP 20000–28999 is redirected to the main port; the client keeps switching ports, which defeats per-port throttling.

Two links are printed (saved to `/root/hy2-links.txt`): `HY2` (single port) and `HY2-Hop` (port hopping).

Recommended for high speed:

```bash
printf 'net.core.rmem_max=16777216\nnet.core.wmem_max=16777216\n' >> /etc/sysctl.conf
sysctl -p && systemctl restart hysteria-server
```

## 4. Clients

| Platform | VLESS REALITY | Hysteria2 |
|---|---|---|
| Windows | v2rayN (Xray core), Hiddify | v2rayN, Hiddify, Karing |
| Android | v2rayNG, Hiddify | v2rayNG, Hiddify, Karing |
| iOS / macOS | Streisand, V2Box, Hiddify | Streisand, Hiddify, Karing |

Import the link from the clipboard. Prefer clients with an up-to-date core: an old sing-box/Xray core may fail with `reality verification failed` against a new Xray server.

## 5. Relay (chain) through a domestic server

If direct connections to foreign IPs are blocked or throttled, put a VPS **inside your country** in front:

```
Device ──REALITY──► domestic relay ──REALITY──► foreign exit server ──► Internet
```

The ISP only sees a connection to a domestic IP; traffic between data centers is usually filtered less.

**VLESS (Xray chain)** — on the relay, with the exit server's existing link and an SNI found by scanning the relay's subnet:

```bash
bash relay-xray.sh 'vless://...exit server link...' <SNI_for_relay>
```

The script prints the exit IP seen through the chain (must be the exit server) and a new `vless://` link. Domestic sites (`geosite:category-ru` / `geoip:ru` by default — edit for your country) leave directly from the relay.

**Hysteria2 (UDP forwarding)**:

```bash
bash relay-hysteria2-udp.sh <EXIT_SERVER_IP>
```

Use the exit server's `hysteria2://` links with the IP replaced by the relay IP.

## 6. Diagnostics

From Windows:

```powershell
Test-NetConnection <IP> -Port 443      # True = TCP reachable
curl.exe ipinfo.io                     # your public IP / ISP
```

- `True` but the VPN does not work → DPI or configuration issue, not an IP block.
- `False` on both Wi-Fi and mobile → the IP is blocked.

On the server:

```bash
systemctl is-active xray hysteria-server hy2-hop
journalctl -u xray -f                  # watch while connecting
journalctl -u hysteria-server -f       # "client connected" = server OK
iptables -t nat -L PREROUTING -n       # port hopping / relay rules
```

Is traffic really going through the relay?

```bash
ss -tn state established '( sport = :443 )'                               # VLESS clients on the relay
timeout 10 tcpdump -ni eth0 -q 'udp and (portrange 20000-28999 or port 29443)'   # HY2 forwarded packets
```

SSH-only escape hatch (when DPI blocks the VPN but SSH works):

```powershell
ssh -N -L 9443:127.0.0.1:443 root@<IP>
```

…then replace `@<IP>:443` with `@127.0.0.1:9443` in the VLESS link.

## Security notes

- Links contain secrets (UUID, keys, passwords). Do not post them publicly.
- To rotate Hysteria2 passwords: delete `/etc/hysteria/config.yaml` and re-run the script. For Xray: delete `/usr/local/etc/xray/reality.env` (or `relay.env`) and re-run.
- Keep server time in sync (`timedatectl`); REALITY dislikes clock drift.

## License

MIT
