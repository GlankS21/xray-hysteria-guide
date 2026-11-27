# Xray REALITY + Hysteria2 (Salamander) — hướng dẫn tự dựng VPN

[English](README.md) · **Tiếng Việt** · [Русский](README.ru.md)

Tổng quan thực hành về cách tự dựng VPN chống kiểm duyệt trên VPS Linux với hai giao thức:

| Giao thức | Kênh | Ưu điểm | Nhược điểm |
|---|---|---|---|
| **VLESS + REALITY** (Xray) | TCP 443 | Trông như một lượt truy cập TLS 1.3 thật tới trang web khác; không cần domain hay chứng chỉ | Chỉ TCP; chậm hơn khi mạng mất gói |
| **Hysteria2 + Salamander** | UDP | Rất nhanh trên mạng kém, mất gói; Salamander che dấu vết QUIC | UDP hay bị bóp hoặc chặn trên mạng di động |

Nên giữ cả hai: khi một giao thức bị chặn, giao thức kia thường vẫn chạy.

> Yêu cầu: VPS có quyền root (Debian 12/13 hoặc Ubuntu 22.04+), có IPv4 công khai.
> Các script chạy lại được: chạy lần nữa vẫn giữ khóa cũ, nên link trong app không đổi.

## 1. Vào server

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\vpn
type $env:USERPROFILE\.ssh\vpn.pub | ssh root@<IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh -i $env:USERPROFILE\.ssh\vpn root@<IP>
```

Lấy script về server:

```bash
git clone https://github.com/<you>/<this-repo>.git && cd <this-repo>/scripts
```

## 2. Xray VLESS + REALITY

### 2.1 Chọn SNI (domain ngụy trang)
REALITY mượn màn bắt tay TLS của một trang web thật. Tốt nhất là một trang nhỏ **nằm cùng dải IP** với VPS, có TLS 1.3 + HTTP/2. Tìm bằng RealiTLScanner:

```bash
cd /tmp
URL=$(curl -s https://api.github.com/repos/XTLS/RealiTLScanner/releases/latest | grep browser_download_url | grep -i linux | grep -Ei 'amd64|64' | grep -vi arm | head -1 | cut -d '"' -f 4)
wget -q "$URL" -O scanner && chmod +x scanner
./scanner -addr <IP> -port 443 -thread 10 -timeout 5 -out found.csv   # bấm Ctrl+C sau khoảng 1 phút
cut -d, -f3 found.csv | sort -u
```

Nên tránh: thương hiệu lớn (google, yandex, sberbank… mà nằm trên IP nhà cung cấp VPS là đáng ngờ), tên trông giống VPN/proxy của người khác, chứng chỉ tự ký.

### 2.2 Cài đặt

```bash
bash install-xray-reality.sh <domain_SNI>        # tham số thứ 2 (tùy chọn): port, mặc định 443
```

Script kiểm tra SNI có TLS 1.3 + HTTP/2, cài Xray, tạo UUID / khóa x25519 / shortId, ghi config và in ra link `vless://` (lưu ở `/root/vless-link.txt`).

## 3. Hysteria2 + Salamander + port hopping

```bash
bash install-hysteria2.sh                          # tham số tùy chọn: port, mặc định 29443
```

- Chứng chỉ tự ký (`CN=bing.com`), nên client dùng `insecure=1`.
- **Salamander**: mọi gói tin bị xáo trộn bằng một mật khẩu chung, nên DPI không nhận ra QUIC.
- **Port hopping**: UDP 20000–28999 được chuyển về port chính; client liên tục đổi port, né việc bóp băng thông theo từng port.

Script in ra hai link (lưu ở `/root/hy2-links.txt`): `HY2` (một port) và `HY2-Hop` (nhảy port).

Nên tăng bộ đệm UDP để đạt tốc độ cao:

```bash
printf 'net.core.rmem_max=16777216\nnet.core.wmem_max=16777216\n' >> /etc/sysctl.conf
sysctl -p && systemctl restart hysteria-server
```

## 4. Ứng dụng client

| Nền tảng | VLESS REALITY | Hysteria2 |
|---|---|---|
| Windows | v2rayN (lõi Xray), Hiddify | v2rayN, Hiddify, Karing |
| Android | v2rayNG, Hiddify | v2rayNG, Hiddify, Karing |
| iOS / macOS | Streisand, V2Box, Hiddify | Streisand, Hiddify, Karing |

Nhập link từ clipboard. Nên dùng app có lõi mới: lõi sing-box/Xray cũ có thể báo `reality verification failed` khi gặp server Xray bản mới.

## 5. Trung chuyển qua server trong nước

Nếu kết nối thẳng tới IP nước ngoài bị chặn hoặc bóp, đặt một VPS **trong nước** đứng trước:

```
Thiết bị ──REALITY──► server trung chuyển trong nước ──REALITY──► server thoát ở nước ngoài ──► Internet
```

Nhà mạng chỉ thấy bạn kết nối tới một IP trong nước; lưu lượng giữa các datacenter thường ít bị lọc hơn.

**VLESS (chuỗi Xray)**: chạy trên server trung chuyển, dùng link hiện có của server thoát và một SNI tìm được bằng cách quét dải IP của server trung chuyển:

```bash
bash relay-xray.sh 'vless://...link server thoát...' <SNI_cho_server_trung_chuyển>
```

Script in ra IP thoát ra khi đi qua chuỗi (phải là IP server thoát) và một link `vless://` mới. Trang trong nước (mặc định `geosite:category-ru` / `geoip:ru`, sửa theo nước của bạn) đi thẳng ra từ server trung chuyển.

**Hysteria2 (chuyển tiếp UDP)**:

```bash
bash relay-hysteria2-udp.sh <IP_SERVER_THOÁT>
```

Dùng các link `hysteria2://` của server thoát, chỉ đổi IP thành IP server trung chuyển.

## 6. Chẩn đoán

Trên Windows:

```powershell
Test-NetConnection <IP> -Port 443      # True = TCP vào được
curl.exe ipinfo.io                     # IP công khai / nhà mạng của bạn
```

- `True` mà VPN không chạy → do DPI hoặc cấu hình, không phải IP bị chặn.
- `False` trên cả Wi-Fi lẫn 4G → IP đã bị chặn.

Trên server:

```bash
systemctl is-active xray hysteria-server hy2-hop
journalctl -u xray -f                  # theo dõi khi kết nối
journalctl -u hysteria-server -f       # thấy "client connected" là server ổn
iptables -t nat -L PREROUTING -n       # rule port hopping / trung chuyển
```

Lưu lượng có thật sự đi qua server trung chuyển không?

```bash
ss -tn state established '( sport = :443 )'                               # client VLESS trên server trung chuyển
timeout 10 tcpdump -ni eth0 -q 'udp and (portrange 20000-28999 or port 29443)'   # gói HY2 được chuyển tiếp
```

Lối thoát chỉ cần SSH (khi DPI chặn VPN nhưng SSH vẫn vào được):

```powershell
ssh -N -L 9443:127.0.0.1:443 root@<IP>
```

…rồi trong link VLESS đổi `@<IP>:443` thành `@127.0.0.1:9443`.

## Lưu ý bảo mật

- Link chứa thông tin bí mật (UUID, khóa, mật khẩu). Đừng đăng công khai.
- Đổi mật khẩu Hysteria2: xóa `/etc/hysteria/config.yaml` rồi chạy lại script. Với Xray: xóa `/usr/local/etc/xray/reality.env` (hoặc `relay.env`) rồi chạy lại.
- Giữ giờ server chính xác (`timedatectl`); REALITY không ưa lệch giờ.

## Giấy phép

MIT
