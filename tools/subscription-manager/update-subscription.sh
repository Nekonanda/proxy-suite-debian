#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="/etc/proxy-subscription"
WEB_DIR="/var/www/proxy-subscription"
TOKEN_FILE="$STATE_DIR/token"

install -d -m 700 "$STATE_DIR"
install -d -m 755 "$WEB_DIR"

if [[ ! -s "$TOKEN_FILE" ]]; then
  openssl rand -hex 24 > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi

TOKEN="$(cat "$TOKEN_FILE")"
RAW_SUB="$WEB_DIR/${TOKEN}-all.txt"
B64_SUB="$WEB_DIR/${TOKEN}-all.b64"
ROOT_RAW="/root/all-proxy-subscription.txt"
ROOT_B64="/root/all-proxy-subscription.b64"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

add_line() {
  local line="${1:-}"
  [[ -n "$line" ]] && printf '%s\n' "$line" >> "$TMP"
}

first_scheme() {
  local file="$1"
  local scheme="$2"
  local prefer="${3:-}"

  [[ -f "$file" ]] || return 0

  if [[ -n "$prefer" ]]; then
    grep -hE "^${scheme}://" "$file" | grep -Ei "$prefer" | head -n1 || true
  else
    grep -hE "^${scheme}://" "$file" | head -n1 || true
  fi
}

# VLESS REALITY Vision
add_line "$(first_scheme /root/xray-reality-client.txt vless)"

# VLESS XHTTP REALITY
add_line "$(first_scheme /root/xray-xhttp-reality-client.txt vless)"

# Hysteria2: prefer hysteria2://, fallback to hy2://
HY2_LINE="$(first_scheme /root/hysteria2-client.txt hysteria2)"
[[ -n "$HY2_LINE" ]] || HY2_LINE="$(first_scheme /root/hysteria2-client.txt hy2)"
add_line "$HY2_LINE"

# Shadowsocks 2022
add_line "$(first_scheme /root/shadowsocks2022-client.txt ss)"

# TUIC5
add_line "$(first_scheme /root/tuic5-client.txt tuic)"

# AnyTLS: prefer self-signed friendly links
ANYTLS_LINE="$(first_scheme /root/anytls-client.txt anytls 'insecure=1|allowInsecure=1|skip')"
[[ -n "$ANYTLS_LINE" ]] || ANYTLS_LINE="$(first_scheme /root/anytls-client.txt anytls)"
add_line "$ANYTLS_LINE"

# Trojan: prefer self-signed friendly links
TROJAN_LINE="$(first_scheme /root/trojan-client.txt trojan 'insecure=1|allowInsecure=1|skip')"
[[ -n "$TROJAN_LINE" ]] || TROJAN_LINE="$(first_scheme /root/trojan-client.txt trojan)"
add_line "$TROJAN_LINE"

awk 'NF && !seen[$0]++' "$TMP" > "$RAW_SUB"

if [[ ! -s "$RAW_SUB" ]]; then
  echo "错误：没有收集到任何节点链接。请检查 /root/*client.txt 是否存在。" >&2
  exit 1
fi

base64 -w0 "$RAW_SUB" > "$B64_SUB"
printf '\n' >> "$B64_SUB"
cp "$RAW_SUB" "$ROOT_RAW"
cp "$B64_SUB" "$ROOT_B64"
chmod 644 "$RAW_SUB" "$B64_SUB" "$ROOT_RAW" "$ROOT_B64"

PUBLIC_IP="$(curl -4fsS https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"

cat > /etc/nginx/conf.d/proxy-subscription.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${PUBLIC_IP};

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

if command -v nginx >/dev/null 2>&1; then
  nginx -t
  systemctl reload nginx
else
  echo "警告：nginx 未安装，已生成订阅文件但未配置 HTTP 服务。" >&2
fi

echo
echo "订阅已生成："
echo "原始文本订阅： http://${PUBLIC_IP}/sub/${TOKEN}-all.txt"
echo "Base64 订阅：   http://${PUBLIC_IP}/sub/${TOKEN}-all.b64"
echo
echo "当前收集到的协议："
awk -F '://' '{print $1}' "$RAW_SUB" | sort | uniq -c
