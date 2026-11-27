# Xray REALITY + Hysteria2 (Salamander) — руководство по собственному VPN

<p align="center"><a href="README.md">🇬🇧 English</a> &nbsp;|&nbsp; <a href="README.vi.md">🇻🇳 Tiếng Việt</a> &nbsp;|&nbsp; <a href="README.ru.md">🇷🇺 Русский</a></p>

---

Практический обзор того, как поднять собственный устойчивый к блокировкам VPN на Linux VPS с двумя протоколами:

| Протокол | Транспорт | Сильные стороны | Слабые стороны |
|---|---|---|---|
| **VLESS + REALITY** (Xray) | TCP 443 | Выглядит как настоящий TLS 1.3 визит на чужой сайт; не нужны домен и сертификат | Только TCP; медленнее на сетях с потерями |
| **Hysteria2 + Salamander** | UDP | Очень быстрый на плохих сетях с потерями; Salamander скрывает сигнатуру QUIC | UDP часто режут или блокируют в мобильных сетях |

Держите оба: когда один заблокирован, второй часто продолжает работать.

> Требования: VPS с root-доступом (Debian 12/13 или Ubuntu 22.04+), публичный IPv4.
> Скрипты можно запускать повторно: ключи сохраняются, поэтому ссылки в клиентах не меняются.

## 1. Подключение к серверу

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\vpn
type $env:USERPROFILE\.ssh\vpn.pub | ssh root@<IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh -i $env:USERPROFILE\.ssh\vpn root@<IP>
```

Скачайте скрипты на сервер:

```bash
git clone https://github.com/<you>/<this-repo>.git && cd <this-repo>/scripts
```

## 2. Xray VLESS + REALITY

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

## 3. Hysteria2 + Salamander + port hopping

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

## 4. Клиенты

| Платформа | VLESS REALITY | Hysteria2 |
|---|---|---|
| Windows | v2rayN (ядро Xray), Hiddify | v2rayN, Hiddify, Karing |
| Android | v2rayNG, Hiddify | v2rayNG, Hiddify, Karing |
| iOS / macOS | Streisand, V2Box, Hiddify | Streisand, Hiddify, Karing |

Импортируйте ссылку из буфера обмена. Используйте клиенты со свежим ядром: старое ядро sing-box/Xray может выдавать `reality verification failed` с новым сервером Xray.

## 5. Транзит через сервер внутри страны

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

## 6. Диагностика

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

## Безопасность

- Ссылки содержат секреты (UUID, ключи, пароли). Не публикуйте их.
- Сменить пароли Hysteria2: удалите `/etc/hysteria/config.yaml` и запустите скрипт заново. Для Xray: удалите `/usr/local/etc/xray/reality.env` (или `relay.env`) и запустите заново.
- Следите за точностью времени на сервере (`timedatectl`); REALITY не любит рассинхронизацию часов.

## Лицензия

MIT
