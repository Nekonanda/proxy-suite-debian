#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="/etc/proxy-subscription"
WEB_DIR="/var/www/proxy-subscription"
TOKEN_FILE="$STATE_DIR/token"

apt update
apt install -y nginx curl openssl coreutils

mkdir -p "$STATE_DIR" "$WEB_DIR"

if [ ! -s "$TOKEN_FILE" ]; then
  openssl rand -hex 24 > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi

TOKEN="$(cat "$TOKEN_FILE")"
RAW_SUB="$WEB_DIR/${TOKEN}-all.txt"
B64_SUB="$WEB_DIR/${TOKEN}-all.b64"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

add_line() {
  local line="${1:-}"
  [ -n "$line" ] && printf '%s\n' "$line" >> "$TMP"
}

first_scheme() {
  local file="$1"
  local scheme="$2"
  local prefer="${3:-}"

  [ -f "$file" ] || return 0

  if [ -n "$prefer" ]; then
    grep -hE "^${scheme}://" "$file" | grep -Ei "$prefer" | head -n1 || true
  else
    grep -hE "^${scheme}://" "$file" | head -n1 || true
  fi
}

add_line "$(first_scheme /root/xray-reality-client.txt vless)"

HY2_LINE="$(first_scheme /root/hysteria2-client.txt hysteria2)"
[ -n "$HY2_LINE" ] || HY2_LINE="$(first_scheme /root/hysteria2-client.txt hy2)"
add_line "$HY2_LINE"

add_line "$(first_scheme /root/shadowsocks2022-client.txt ss)"
add_line "$(first_scheme /root/tuic5-client.txt tuic)"

ANYTLS_LINE="$(first_scheme /root/anytls-client.txt anytls 'insecure=1|allowInsecure=1|allow_insecure=1|skip')"
[ -n "$ANYTLS_LINE" ] || ANYTLS_LINE="$(first_scheme /root/anytls-client.txt anytls)"
add_line "$ANYTLS_LINE"

TROJAN_LINE="$(first_scheme /root/trojan-client.txt trojan 'insecure=1|allowInsecure=1|allow_insecure=1|skip')"
[ -n "$TROJAN_LINE" ] || TROJAN_LINE="$(first_scheme /root/trojan-client.txt trojan)"
add_line "$TROJAN_LINE"

# VLESS + XHTTP + REALITY
# 如果已经安装过 XHTTP，就自动加入统一订阅。
add_line "$(first_scheme /root/xray-xhttp-reality-client.txt vless)"

awk 'NF && !seen[$0]++' "$TMP" > "$RAW_SUB"

if [ ! -s "$RAW_SUB" ]; then
  echo "错误：没有收集到任何节点链接。"
  echo "请先安装至少一个协议。"
  ls -lah /root/*client.txt 2>/dev/null || true
  exit 1
fi

base64 -w0 "$RAW_SUB" > "$B64_SUB"
printf '\n' >> "$B64_SUB"
chmod 644 "$RAW_SUB" "$B64_SUB"

BACKUP_DIR="/root/nginx-backup-proxy-suite-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for f in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
  [ -e "$f" ] || continue
  [ "$f" = "/etc/nginx/conf.d/proxy-subscription.conf" ] && continue

  if grep -qE 'listen[[:space:]]+.*80.*default_server' "$f" 2>/dev/null; then
    echo "备份并停用冲突 nginx 配置：$f"
    mv "$f" "$BACKUP_DIR/$(basename "$f").bak"
  fi
done

cat > /etc/nginx/conf.d/proxy-subscription.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    access_log off;

    location ^~ /sub/ {
        alias /var/www/proxy-subscription/;
        default_type text/plain;
        add_header Cache-Control "no-store" always;
        add_header X-Content-Type-Options "nosniff" always;
    }

    location / {
        return 404;
    }
}
EOF

nginx -t
systemctl enable --now nginx
systemctl restart nginx

IP="$(curl -4fsS https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"

echo
echo "订阅生成好了："
echo
echo "原始订阅："
echo "http://${IP}/sub/${TOKEN}-all.txt"
echo
echo "Base64 订阅，小火箭优先用这个："
echo "http://${IP}/sub/${TOKEN}-all.b64"
echo
echo "当前订阅里包含："
awk -F '://' '{print $1}' "$RAW_SUB" | sort | uniq -c
echo
echo "本机检测："
curl -I "http://127.0.0.1/sub/${TOKEN}-all.b64" || true
