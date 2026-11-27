# Xray REALITY + Hysteria2 (Salamander)

[🇬🇧 English](#english) · [🇻🇳 Tiếng Việt](#tiếng-việt) · [🇷🇺 Русский](#русский)

---

## English

A practical overview of running your own censorship-resistant VPN on a Linux VPS with two protocols:

| Protocol | Transport | Strength | Weakness |
|---|---|---|---|
| **VLESS + REALITY** (Xray) | TCP 443 | Looks like a real TLS 1.3 visit to another website; no domain or certificate needed | TCP only; slower on lossy links |
| **Hysteria2 + Salamander** | UDP | Very fast on bad / lossy networks; Salamander hides the QUIC signature | UDP is often throttled or blocked on mobile networks |

Keep both: when one is blocked, the other often still works.

> Requirements: a VPS with root access (Debian 12/13 or Ubuntu 22.04+), a public IPv4.
> Scripts are idempotent: re-running keeps existing keys, so your client links stay valid.

### 1. Connect to the server

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\vpn
type $env:USERPROFILE\.ssh\vpn.pub | ssh root@<IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh -i $env:USERPROFILE\.ssh\vpn root@<IP>
```

Copy the scripts to the server:

```bash
git clone https://github.com/<you>/<this-repo>.git && cd <this-repo>/scripts
```

### 2. Xray VLESS + REALITY

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

### 3. Hysteria2 + Salamander + port hopping

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

### 4. Clients

| Platform | VLESS REALITY | Hysteria2 |
|---|---|---|
| Windows | v2rayN (Xray core), Hiddify | v2rayN, Hiddify, Karing |
| Android | v2rayNG, Hiddify | v2rayNG, Hiddify, Karing |
| iOS / macOS | Streisand, V2Box, Hiddify | Streisand, Hiddify, Karing |

Import the link from the clipboard. Prefer clients with an up-to-date core: an old sing-box/Xray core may fail with `reality verification failed` against a new Xray server.

### 5. Relay (chain) through a domestic server

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

### 6. Diagnostics

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

### Security notes

- Links contain secrets (UUID, keys, passwords). Do not post them publicly.
- To rotate Hysteria2 passwords: delete `/etc/hysteria/config.yaml` and re-run the script. For Xray: delete `/usr/local/etc/xray/reality.env` (or `relay.env`) and re-run.
- Keep server time in sync (`timedatectl`); REALITY dislikes clock drift.

### License

MIT

[↑ Top](#xray-reality--hysteria2-salamander)

---

## Tiếng Việt

Tổng quan thực hành về cách tự dựng VPN chống kiểm duyệt trên VPS Linux với hai giao thức:

| Giao thức | Kênh | Ưu điểm | Nhược điểm |
|---|---|---|---|
| **VLESS + REALITY** (Xray) | TCP 443 | Trông như một lượt truy cập TLS 1.3 thật tới trang web khác; không cần domain hay chứng chỉ | Chỉ TCP; chậm hơn khi mạng mất gói |
| **Hysteria2 + Salamander** | UDP | Rất nhanh trên mạng kém, mất gói; Salamander che dấu vết QUIC | UDP hay bị bóp hoặc chặn trên mạng di động |

Nên giữ cả hai: khi một giao thức bị chặn, giao thức kia thường vẫn chạy.

> Yêu cầu: VPS có quyền root (Debian 12/13 hoặc Ubuntu 22.04+), có IPv4 công khai.
> Các script chạy lại được: chạy lần nữa vẫn giữ khóa cũ, nên link trong app không đổi.

### 1. Vào server

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\vpn
type $env:USERPROFILE\.ssh\vpn.pub | ssh root@<IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh -i $env:USERPROFILE\.ssh\vpn root@<IP>
```

Lấy script về server:

```bash
git clone https://github.com/<you>/<this-repo>.git && cd <this-repo>/scripts
```

### 2. Xray VLESS + REALITY

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

### 3. Hysteria2 + Salamander + port hopping

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

### 4. Ứng dụng client

| Nền tảng | VLESS REALITY | Hysteria2 |
|---|---|---|
| Windows | v2rayN (lõi Xray), Hiddify | v2rayN, Hiddify, Karing |
| Android | v2rayNG, Hiddify | v2rayNG, Hiddify, Karing |
| iOS / macOS | Streisand, V2Box, Hiddify | Streisand, Hiddify, Karing |

Nhập link từ clipboard. Nên dùng app có lõi mới: lõi sing-box/Xray cũ có thể báo `reality verification failed` khi gặp server Xray bản mới.

### 5. Trung chuyển qua server trong nước

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

### 6. Chẩn đoán

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

### Lưu ý bảo mật

- Link chứa thông tin bí mật (UUID, khóa, mật khẩu). Đừng đăng công khai.
- Đổi mật khẩu Hysteria2: xóa `/etc/hysteria/config.yaml` rồi chạy lại script. Với Xray: xóa `/usr/local/etc/xray/reality.env` (hoặc `relay.env`) rồi chạy lại.
- Giữ giờ server chính xác (`timedatectl`); REALITY không ưa lệch giờ.

### Giấy phép

MIT

[↑ Lên đầu](#xray-reality--hysteria2-salamander)

---

## Русский

Практический обзор того, как поднять собственный устойчивый к блокировкам VPN на Linux VPS с двумя протоколами:

| Протокол | Транспорт | Сильные стороны | Слабые стороны |
|---|---|---|---|
| **VLESS + REALITY** (Xray) | TCP 443 | Выглядит как настоящий TLS 1.3 визит на чужой сайт; не нужны домен и сертификат | Только TCP; медленнее на сетях с потерями |
| **Hysteria2 + Salamander** | UDP | Очень быстрый на плохих сетях с потерями; Salamander скрывает сигнатуру QUIC | UDP часто режут или блокируют в мобильных сетях |

Держите оба: когда один заблокирован, второй часто продолжает работать.

> Требования: VPS с root-доступом (Debian 12/13 или Ubuntu 22.04+), публичный IPv4.
> Скрипты можно запускать повторно: ключи сохраняются, поэтому ссылки в клиентах не меняются.

### 1. Подключение к серверу

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\vpn
type $env:USERPROFILE\.ssh\vpn.pub | ssh root@<IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh -i $env:USERPROFILE\.ssh\vpn root@<IP>
```

Скачайте скрипты на сервер:

```bash
git clone https://github.com/<you>/<this-repo>.git && cd <this-repo>/scripts
```

### 2. Xray VLESS + REALITY

### 2.1 Выбор SNI (домена маскировки)
REALITY заимствует TLS-рукопожатие настоящего сайта. Лучший вариант — небольшой сайт **в той же подсети**, что и VPS, с поддержкой TLS 1.3 + HTTP/2. Найти его можно через RealiTLScanner:

```bash
cd /tmp
URL=$(curl -s https://api.github.com/repos/XTLS/RealiTLScanner/releases/latest | grep browser_download_url | grep -i linux | grep -Ei 'amd64|64' | grep -vi arm | head -1 | cut -d '"' -f 4)
wget -q "$URL" -O scanner && chmod +x scanner
./scanner -addr <IP> -port 443 -thread 10 -timeout 5 -out found.csv   # Ctrl+C примерно через минуту
cut -d, -f3 found.csv | sort -u
```

Избегайте: крупных брендов (google, yandex, sberbank… на IP хостинга выглядят подозрительно), имён, похожих на чужие VPN/прокси, самоподписанных сертификатов.

### 2.2 Установка

```bash
bash install-xray-reality.sh <SNI_домен>         # 2-й аргумент (необязательно): порт, по умолчанию 443
```

Скрипт проверяет TLS 1.3 + HTTP/2 у SNI, ставит Xray, генерирует UUID / ключи x25519 / shortId, пишет конфиг и выводит ссылку `vless://` (сохраняется в `/root/vless-link.txt`).

### 3. Hysteria2 + Salamander + port hopping

```bash
bash install-hysteria2.sh                          # необязательный аргумент: порт, по умолчанию 29443
```

- Самоподписанный сертификат (`CN=bing.com`), поэтому в клиенте `insecure=1`.
- **Salamander**: каждый пакет перемешивается общим паролем, DPI не видит QUIC.
- **Port hopping**: UDP 20000–28999 перенаправляется на основной порт; клиент постоянно меняет порт, что обходит ограничения по отдельным портам.

Выводятся две ссылки (сохраняются в `/root/hy2-links.txt`): `HY2` (один порт) и `HY2-Hop` (смена портов).

Для высокой скорости рекомендуется:

```bash
printf 'net.core.rmem_max=16777216\nnet.core.wmem_max=16777216\n' >> /etc/sysctl.conf
sysctl -p && systemctl restart hysteria-server
```

### 4. Клиенты

| Платформа | VLESS REALITY | Hysteria2 |
|---|---|---|
| Windows | v2rayN (ядро Xray), Hiddify | v2rayN, Hiddify, Karing |
| Android | v2rayNG, Hiddify | v2rayNG, Hiddify, Karing |
| iOS / macOS | Streisand, V2Box, Hiddify | Streisand, Hiddify, Karing |

Импортируйте ссылку из буфера обмена. Используйте клиенты со свежим ядром: старое ядро sing-box/Xray может выдавать `reality verification failed` с новым сервером Xray.

### 5. Транзит через сервер внутри страны

Если прямые подключения к зарубежным IP блокируются или замедляются, поставьте перед ними VPS **внутри страны**:

```
Устройство ──REALITY──► транзитный сервер (внутри страны) ──REALITY──► зарубежный выходной сервер ──► Интернет
```

Провайдер видит только подключение к отечественному IP; трафик между дата-центрами обычно фильтруется слабее.

**VLESS (цепочка Xray)** — на транзитном сервере, со ссылкой выходного сервера и SNI, найденным сканированием подсети транзитного сервера:

```bash
bash relay-xray.sh 'vless://...ссылка выходного сервера...' <SNI_для_транзита>
```

Скрипт показывает IP выхода через цепочку (должен быть IP выходного сервера) и новую ссылку `vless://`. Отечественные сайты (по умолчанию `geosite:category-ru` / `geoip:ru`) идут напрямую с транзитного сервера.

**Hysteria2 (проброс UDP)**:

```bash
bash relay-hysteria2-udp.sh <IP_ВЫХОДНОГО_СЕРВЕРА>
```

Используйте ссылки `hysteria2://` выходного сервера, заменив IP на IP транзитного.

### 6. Диагностика

С Windows:

```powershell
Test-NetConnection <IP> -Port 443      # True = TCP доступен
curl.exe ipinfo.io                     # ваш публичный IP / провайдер
```

- `True`, но VPN не работает → DPI или ошибка конфигурации, а не блокировка IP.
- `False` и на Wi-Fi, и на мобильной сети → IP заблокирован.

На сервере:

```bash
systemctl is-active xray hysteria-server hy2-hop
journalctl -u xray -f                  # смотреть во время подключения
journalctl -u hysteria-server -f       # "client connected" = сервер в порядке
iptables -t nat -L PREROUTING -n       # правила port hopping / транзита
```

Действительно ли трафик идёт через транзит?

```bash
ss -tn state established '( sport = :443 )'                               # клиенты VLESS на транзите
timeout 10 tcpdump -ni eth0 -q 'udp and (portrange 20000-28999 or port 29443)'   # пересылаемые пакеты HY2
```

Запасной вариант через SSH (когда DPI блокирует VPN, но SSH проходит):

```powershell
ssh -N -L 9443:127.0.0.1:443 root@<IP>
```

…затем в ссылке VLESS замените `@<IP>:443` на `@127.0.0.1:9443`.

### Безопасность

- Ссылки содержат секреты (UUID, ключи, пароли). Не публикуйте их.
- Сменить пароли Hysteria2: удалите `/etc/hysteria/config.yaml` и запустите скрипт заново. Для Xray: удалите `/usr/local/etc/xray/reality.env` (или `relay.env`) и запустите заново.
- Следите за точностью времени на сервере (`timedatectl`); REALITY не любит рассинхронизацию часов.

### Лицензия

MIT

[↑ Наверх](#xray-reality--hysteria2-salamander)
