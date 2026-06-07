#!/usr/bin/env bash
set -Eeuo pipefail

apt update
apt install -y nginx curl openssl coreutils

STATE_DIR="/etc/proxy-subscription"
WEB_DIR="/var/www/proxy-subscription"
TOKEN_FILE="$STATE_DIR/token"

mkdir -p "$STATE_DIR" "$WEB_DIR"

if [ ! -s "$TOKEN_FILE" ]; then
  openssl rand -hex 24 > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi

TOKEN="$(cat "$TOKEN_FILE")"
RAW_SUB="$WEB_DIR/${TOKEN}-all.txt"
B64_SUB="$WEB_DIR/${TOKEN}-all.b64"

grep -hEo '(vless|hysteria2|hy2|ss|tuic|anytls|trojan)://[^[:space:]]+' /root/*client.txt 2>/dev/null \
  | awk 'NF && !seen[$0]++' > "$RAW_SUB"

if [ ! -s "$RAW_SUB" ]; then
  echo "没有收集到节点链接。"
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

  if grep -qE 'listen .*80.*default_server' "$f" 2>/dev/null; then
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
