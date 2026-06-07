#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# xray-reality-debian: Debian 12/13 one-click VLESS + REALITY + Vision installer
set -Eeuo pipefail
umask 077

APP_NAME="xray-reality-debian"
STATE_DIR="/etc/xray-reality"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
INFO_FILE="/root/xray-reality-client.txt"
SYSCTL_CONF="/etc/sysctl.d/99-xray-reality-performance.conf"
MODULES_CONF="/etc/modules-load.d/99-xray-reality-bbr.conf"
NGINX_SITE="/etc/nginx/sites-available/xray-reality-decoy"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/xray-reality-decoy"
WEB_ROOT="/var/www/reality-decoy"
INSTALL_SCRIPT_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

PORT="443"
DOMAIN=""
PUBLIC_ADDR=""
REALITY_TARGET="www.microsoft.com:443"
REALITY_SNI="www.microsoft.com"
UUID=""
SHORT_ID=""
NODE_NAME=""
ENABLE_BBR="1"
ENABLE_HTTP="1"
FORCE="0"
SHOW_ONLY="0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

trap 'echo -e "${RED}[ERROR] line ${LINENO}: ${BASH_COMMAND}${NC}" >&2' ERR

log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
die() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $*"; }

usage() {
  cat <<'USAGE'
Debian 12/13 一键安装 Xray VLESS + REALITY + Vision，默认借用 Microsoft 站点特征。

用法：
  sudo bash install.sh [选项]

常用选项：
  --domain <域名>          可选。你的域名已解析到本机时填写；不填则自动使用公网 IP。
  --ip <公网IP>            可选。自动检测失败或多 IP 机器时手动指定。
  --port <端口>            默认 443。
  --target <域名:端口>     REALITY 目标站点，默认 www.microsoft.com:443。
  --sni <域名>             REALITY 客户端 SNI，默认 www.microsoft.com。
  --uuid <UUID>            可选。自定义用户 UUID。
  --short-id <hex>         可选。0-16 个十六进制字符，长度必须为偶数。
  --name <节点名>          可选。小火箭里显示的节点名。
  --no-http                不安装 HTTP 伪装页/小火箭订阅 URL，只输出 vless:// 链接。
  --no-bbr                 不写入 BBR 与内核网络优化。
  --force                  端口占用检查更宽松，适合你确认已有服务可被覆盖的场景。
  --show                   只显示上次生成的客户端信息。
  -h, --help               显示帮助。

示例：
  sudo bash install.sh
  sudo bash install.sh --domain node.example.com
  sudo bash install.sh --domain node.example.com --port 8443 --name "My Reality Node"
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --ip) PUBLIC_ADDR="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --target) REALITY_TARGET="${2:-}"; shift 2 ;;
    --sni) REALITY_SNI="${2:-}"; shift 2 ;;
    --uuid) UUID="${2:-}"; shift 2 ;;
    --short-id) SHORT_ID="${2:-}"; shift 2 ;;
    --name) NODE_NAME="${2:-}"; shift 2 ;;
    --no-http) ENABLE_HTTP="0"; shift ;;
    --no-bbr) ENABLE_BBR="0"; shift ;;
    --force) FORCE="1"; shift ;;
    --show) SHOW_ONLY="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1。运行 --help 查看用法。" ;;
  esac
done

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请用 root 运行：sudo bash install.sh"
}

validate_inputs() {
  [[ "$PORT" =~ ^[0-9]{1,5}$ ]] || die "端口必须是 1-65535 的数字。"
  (( PORT >= 1 && PORT <= 65535 )) || die "端口必须是 1-65535。"
  [[ "$REALITY_TARGET" =~ ^[A-Za-z0-9._-]+:[0-9]{1,5}$ ]] || die "--target 格式应为 域名:端口，例如 www.microsoft.com:443。"
  [[ "$REALITY_SNI" =~ ^[A-Za-z0-9._-]+$ ]] || die "--sni 只能包含域名常用字符。"
  if [[ -n "$DOMAIN" ]]; then
    [[ "$DOMAIN" =~ ^[A-Za-z0-9._-]+$ ]] || die "--domain 只能填写普通域名，不要带 http:// 或路径。"
  fi
  if [[ -n "$UUID" ]]; then
    [[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die "--uuid 格式不正确。"
  fi
  if [[ -n "$SHORT_ID" ]]; then
    [[ "$SHORT_ID" =~ ^[0-9a-fA-F]*$ ]] || die "--short-id 必须是十六进制。"
    (( ${#SHORT_ID} <= 16 )) || die "--short-id 最长 16 个十六进制字符。"
    (( ${#SHORT_ID} % 2 == 0 )) || die "--short-id 长度必须为偶数。"
    SHORT_ID="$(echo "$SHORT_ID" | tr 'A-F' 'a-f')"
  fi
}

check_os() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "仅适配 Debian 12/13；当前 ID=${ID:-unknown}。"
  local ver="${VERSION_ID:-}"
  case "$ver" in
    12*|13*) ;;
    *) die "仅适配 Debian 12/13；当前 VERSION_ID=${ver:-unknown}。" ;;
  esac
  command -v systemctl >/dev/null 2>&1 || die "需要 systemd 环境。"
  log "检测到 Debian ${ver}，systemd 可用。"
}

apt_install_base() {
  export DEBIAN_FRONTEND=noninteractive
  log "安装基础依赖：curl、openssl、iproute2、procps 等。"
  apt-get update -y
  apt-get install -y --no-install-recommends ca-certificates curl openssl iproute2 procps coreutils sed gawk
}

is_tcp_port_in_use() {
  local port="$1"
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:|\])${port}$"
}

port_in_use_by_xray() {
  local port="$1"
  ss -H -ltnp 2>/dev/null | grep -E "(^|:|\])${port}[[:space:]]" | grep -qi 'xray'
}

check_ports() {
  if is_tcp_port_in_use "$PORT" && ! port_in_use_by_xray "$PORT"; then
    if [[ "$FORCE" == "1" ]]; then
      warn "端口 ${PORT} 已被占用，但已指定 --force，继续执行。"
    else
      ss -ltnp | grep -E "(^|:|\])${PORT}[[:space:]]" || true
      die "端口 ${PORT} 已被占用。换端口可用：--port 8443；或确认后加 --force。"
    fi
  fi
}

sysctl_key_exists() {
  local key="$1"
  [[ -e "/proc/sys/${key//./\/}" ]]
}

add_sysctl() {
  local key="$1" value="$2"
  if sysctl_key_exists "$key"; then
    printf '%s = %s\n' "$key" "$value" >> "$SYSCTL_CONF"
    if ! sysctl -w "${key}=${value}" >/dev/null 2>&1; then
      warn "运行时写入 ${key}=${value} 失败，已保留到 ${SYSCTL_CONF}，重启后可能生效。"
    fi
  else
    warn "内核不支持 ${key}，跳过。"
  fi
}

ipv6_enabled() {
  [[ -r /proc/net/if_inet6 ]] || return 1
  local disabled
  disabled="$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 1)"
  [[ "$disabled" != "1" ]]
}

apply_bbr_and_kernel_tuning() {
  [[ "$ENABLE_BBR" == "1" ]] || { warn "已按参数跳过 BBR/内核优化。"; return 0; }

  log "开启 BBR 并写入稳健型网络内核优化。"
  install -d -m 0755 /etc/sysctl.d /etc/modules-load.d
  : > "$SYSCTL_CONF"
  cat > "$MODULES_CONF" <<'EOF'
tcp_bbr
EOF

  modprobe tcp_bbr 2>/dev/null || warn "modprobe tcp_bbr 失败；如果内核内置 BBR 或不支持模块，这条可忽略。"
  local available_cc
  available_cc="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  if grep -qw bbr <<<"$available_cc"; then
    add_sysctl net.core.default_qdisc fq
    add_sysctl net.ipv4.tcp_congestion_control bbr
  else
    warn "当前内核未显示 bbr：${available_cc:-empty}。脚本保留其它优化，但不会强行换内核。"
  fi

  add_sysctl net.core.somaxconn 65535
  add_sysctl net.core.netdev_max_backlog 250000
  add_sysctl net.core.rmem_max 134217728
  add_sysctl net.core.wmem_max 134217728
  add_sysctl net.ipv4.tcp_rmem "4096 87380 67108864"
  add_sysctl net.ipv4.tcp_wmem "4096 65536 67108864"
  add_sysctl net.ipv4.tcp_fastopen 3
  add_sysctl net.ipv4.tcp_mtu_probing 1
  add_sysctl net.ipv4.tcp_slow_start_after_idle 0
  add_sysctl net.ipv4.tcp_max_syn_backlog 8192
  add_sysctl net.ipv4.tcp_fin_timeout 15
  add_sysctl net.ipv4.tcp_keepalive_time 600
  add_sysctl net.ipv4.tcp_keepalive_intvl 30
  add_sysctl net.ipv4.tcp_keepalive_probes 5
  add_sysctl net.ipv4.tcp_syncookies 1
  add_sysctl net.ipv4.ip_local_port_range "1024 65535"
  add_sysctl net.ipv4.conf.all.forwarding 0
  add_sysctl net.ipv4.conf.default.forwarding 0
  if ipv6_enabled; then
    add_sysctl net.ipv6.bindv6only 0
    add_sysctl net.ipv6.conf.all.forwarding 0
    add_sysctl net.ipv6.conf.default.forwarding 0
  fi

  chmod 0644 "$SYSCTL_CONF" "$MODULES_CONF"
  log "内核优化已写入 ${SYSCTL_CONF}。"
}

install_xray() {
  log "使用 XTLS 官方安装脚本安装/更新 Xray-core。"
  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL "$INSTALL_SCRIPT_URL" -o "${tmpdir}/install-release.sh"
  bash "${tmpdir}/install-release.sh" install
  rm -rf "$tmpdir"
  command -v /usr/local/bin/xray >/dev/null 2>&1 || die "Xray 安装失败：未找到 /usr/local/bin/xray。"
  /usr/local/bin/xray version | head -n 1 || true
}

generate_identity() {
  install -d -m 0700 "$STATE_DIR"
  if [[ -z "$UUID" ]]; then
    UUID="$(/usr/local/bin/xray uuid)"
  fi
  if [[ -z "$SHORT_ID" ]]; then
    SHORT_ID="$(openssl rand -hex 8)"
  fi

  local key_output
  key_output="$(/usr/local/bin/xray x25519)"
  # 兼容 Xray 新旧输出格式：
  #   Private key: ... / Public key: ...
  #   PrivateKey: ... / Password: ...
  #   PrivateKey: ... / Password (PublicKey): ...
  # 新版 Password/Password (PublicKey) 就是客户端 pbk 要用的 public key。
  PRIVATE_KEY="$(printf '%s\n' "$key_output" | sed -nE 's/^[[:space:]]*(Private[[:space:]]*key|PrivateKey)[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\2/Ip' | head -n1)"
  PUBLIC_KEY="$(printf '%s\n' "$key_output" | sed -nE 's/^[[:space:]]*(Public[[:space:]]*key|PublicKey|Password.*)[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\2/Ip' | head -n1)"
  if [[ -z "${PRIVATE_KEY:-}" || -z "${PUBLIC_KEY:-}" ]]; then
    printf '%s\n' "$key_output" >&2
    die "生成 REALITY x25519 密钥失败：无法解析 xray x25519 输出。"
  fi

  SPIDER_X="/$(openssl rand -hex 4)"
  SUB_TOKEN="$(openssl rand -hex 24)"
  if [[ -z "$NODE_NAME" ]]; then
    NODE_NAME="Reality-${REALITY_SNI}-${PORT}"
  fi
}

detect_public_host() {
  if [[ -n "$DOMAIN" ]]; then
    SERVER_HOST="$DOMAIN"
    return 0
  fi
  if [[ -n "$PUBLIC_ADDR" ]]; then
    SERVER_HOST="$PUBLIC_ADDR"
    return 0
  fi

  info "未指定域名，自动检测公网 IP。"
  local v4="" v6=""
  v4="$(curl -4fsSL --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$v4" ]]; then
    v6="$(curl -6fsSL --max-time 8 https://api64.ipify.org 2>/dev/null || true)"
  fi
  SERVER_HOST="${v4:-$v6}"
  if [[ -z "$SERVER_HOST" ]]; then
    SERVER_HOST="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    warn "公网 IP 自动检测失败，临时使用本机地址：${SERVER_HOST:-unknown}。如不对，请重跑时加 --ip。"
  fi
  [[ -n "$SERVER_HOST" ]] || die "无法确定客户端连接地址；请用 --domain 或 --ip 指定。"
}

uri_host() {
  local host="$1"
  if [[ "$host" == *:* && "$host" != \[*\] ]]; then
    printf '[%s]' "$host"
  else
    printf '%s' "$host"
  fi
}

urlencode() {
  local LC_ALL=C
  local s="$1" i c
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
      *) printf '%%%02X' "'$c" ;;
    esac
  done
}

build_client_links() {
  local h sni_enc spx_enc name_enc
  h="$(uri_host "$SERVER_HOST")"
  sni_enc="$(urlencode "$REALITY_SNI")"
  spx_enc="$(urlencode "$SPIDER_X")"
  name_enc="$(urlencode "$NODE_NAME")"
  VLESS_LINK="vless://${UUID}@${h}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni_enc}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=${spx_enc}&type=tcp&headerType=none#${name_enc}"
  SUBSCRIPTION_B64="$(printf '%s' "$VLESS_LINK" | base64 -w 0)"
}

write_xray_config() {
  log "写入 Xray VLESS + REALITY + Vision 配置。"
  install -d -m 0755 /usr/local/etc/xray
  if [[ -f "$XRAY_CONFIG" ]]; then
    cp -a "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  local listen_addr="0.0.0.0"
  if ipv6_enabled; then
    listen_addr="::"
  fi

  cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-vision",
      "listen": "${listen_addr}",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision",
            "email": "user-${SHORT_ID}@reality.local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "tcpSettings": {
          "acceptProxyProtocol": false
        },
        "realitySettings": {
          "show": false,
          "target": "${REALITY_TARGET}",
          "xver": 0,
          "serverNames": [
            "${REALITY_SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        },
        "sockopt": {
          "tcpFastOpen": true
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF
  chmod 0644 "$XRAY_CONFIG"
  /usr/local/bin/xray run -test -config "$XRAY_CONFIG" >/dev/null
  systemctl daemon-reload
  systemctl enable --now xray
  systemctl restart xray
  systemctl --no-pager --full status xray | sed -n '1,12p' || true
}

setup_http_decoy_and_subscription() {
  SUBSCRIPTION_URL=""
  [[ "$ENABLE_HTTP" == "1" ]] || { warn "已按参数跳过 HTTP 伪装页/订阅 URL。"; return 0; }

  if is_tcp_port_in_use 80 && ! ss -H -ltnp 2>/dev/null | grep -E '(^|:|\])80[[:space:]]' | grep -qi 'nginx'; then
    warn "80 端口已被非 nginx 服务占用，跳过 HTTP 伪装页和订阅 URL。"
    return 0
  fi

  log "安装 nginx，生成无访问日志的 HTTP 伪装页和随机订阅路径。"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y --no-install-recommends nginx

  install -d -m 0755 "${WEB_ROOT}/html" "${WEB_ROOT}/sub"
  cat > "${WEB_ROOT}/html/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="robots" content="noindex,nofollow,noarchive">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OK</title>
</head>
<body>
  <main style="font-family: system-ui, sans-serif; max-width: 680px; margin: 12vh auto; line-height: 1.6;">
    <h1>OK</h1>
    <p>Service is running.</p>
  </main>
</body>
</html>
EOF
  printf '%s\n' "$SUBSCRIPTION_B64" > "${WEB_ROOT}/sub/${SUB_TOKEN}.txt"
  chmod -R go+rX "$WEB_ROOT"

  local server_name="_"
  [[ -n "$DOMAIN" ]] && server_name="$DOMAIN _"
  local ipv6_listen=""
  if ipv6_enabled; then
    ipv6_listen="    listen [::]:80;"
  fi

  cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
${ipv6_listen}
    server_name ${server_name};

    access_log off;
    error_log /var/log/nginx/error.log crit;
    server_tokens off;

    root ${WEB_ROOT}/html;
    index index.html;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Robots-Tag "noindex, nofollow, noarchive" always;

    location = /assets/${SUB_TOKEN}.txt {
        alias ${WEB_ROOT}/sub/${SUB_TOKEN}.txt;
        default_type text/plain;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header Pragma "no-cache" always;
        add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\\. {
        deny all;
    }
}
EOF

  rm -f /etc/nginx/sites-enabled/default
  ln -sfn "$NGINX_SITE" "$NGINX_SITE_LINK"
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx

  local h
  h="$(uri_host "$SERVER_HOST")"
  SUBSCRIPTION_URL="http://${h}/assets/${SUB_TOKEN}.txt"
}

save_state_and_print() {
  install -d -m 0700 "$STATE_DIR"
  cat > "${STATE_DIR}/client.env" <<EOF
PORT='${PORT}'
DOMAIN='${DOMAIN}'
SERVER_HOST='${SERVER_HOST}'
REALITY_TARGET='${REALITY_TARGET}'
REALITY_SNI='${REALITY_SNI}'
UUID='${UUID}'
SHORT_ID='${SHORT_ID}'
PUBLIC_KEY='${PUBLIC_KEY}'
SPIDER_X='${SPIDER_X}'
NODE_NAME='${NODE_NAME}'
VLESS_LINK='${VLESS_LINK}'
SUBSCRIPTION_URL='${SUBSCRIPTION_URL}'
XRAY_CONFIG='${XRAY_CONFIG}'
EOF
  chmod 0600 "${STATE_DIR}/client.env"

  cat > "$INFO_FILE" <<EOF
Xray VLESS + REALITY + Vision 安装完成
生成时间：$(date -Is)

服务器地址：${SERVER_HOST}
端口：${PORT}
REALITY 目标：${REALITY_TARGET}
SNI：${REALITY_SNI}
UUID：${UUID}
Flow：xtls-rprx-vision
PublicKey/password：${PUBLIC_KEY}
ShortId：${SHORT_ID}
SpiderX：${SPIDER_X}
Fingerprint：chrome
传输：tcp

小火箭/Shadowrocket 可直接导入的 vless:// 链接：
${VLESS_LINK}

小火箭订阅 URL：
${SUBSCRIPTION_URL:-未启用或 80 端口被占用}

重要提示：如果订阅 URL 是 http://，订阅内容在传输路径上不是端到端加密的；脚本已使用高熵随机路径、关闭 nginx 访问日志并禁止索引，但不要公开分享该 URL。代理连接本身使用 REALITY，不走明文 HTTP。

服务检查：
  systemctl status xray --no-pager
  journalctl -u xray -e --no-pager
  sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
EOF
  chmod 0600 "$INFO_FILE"

  echo
  log "安装完成。客户端信息已保存：${INFO_FILE}"
  echo "------------------------------------------------------------"
  cat "$INFO_FILE"
  echo "------------------------------------------------------------"
}

show_previous() {
  require_root
  if [[ -f "$INFO_FILE" ]]; then
    cat "$INFO_FILE"
  elif [[ -f "${STATE_DIR}/client.env" ]]; then
    # shellcheck disable=SC1091
    . "${STATE_DIR}/client.env"
    echo "vless:// 链接：${VLESS_LINK:-}"
    echo "订阅 URL：${SUBSCRIPTION_URL:-}"
  else
    die "没有找到历史客户端信息。"
  fi
}

main() {
  if [[ "$SHOW_ONLY" == "1" ]]; then
    show_previous
    exit 0
  fi
  require_root
  validate_inputs
  check_os
  apt_install_base
  check_ports
  apply_bbr_and_kernel_tuning
  install_xray
  generate_identity
  detect_public_host
  build_client_links
  write_xray_config
  setup_http_decoy_and_subscription
  save_state_and_print
}

main "$@"
