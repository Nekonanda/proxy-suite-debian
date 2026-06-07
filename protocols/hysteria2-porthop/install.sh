#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="hysteria2-porthop-debian"
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
STATE_DIR="/etc/${PROJECT_NAME}"
INFO_FILE="/root/hysteria2-client.txt"
SYSCTL_FILE="/etc/sysctl.d/99-hysteria2-performance.conf"
SERVICE_NAME="hysteria-server.service"
WEB_ROOT_CANDIDATE_XRAY="/var/www/xray-reality/html"
WEB_ROOT_DEFAULT="/var/www/html"

DOMAIN=""
EMAIL=""
PUBLIC_ADDR=""
PORT_RANGE="20000-29999"
PASSWORD=""
OBFS_PASSWORD=""
OBFS_TYPE="salamander"
NO_OBFS="0"
MASQ_URL="https://www.bing.com/"
NODE_NAME=""
FORCE_FIREWALL_BACKEND=""
ENABLE_SUBSCRIPTION="1"
SHOW_ONLY="0"

log() { printf '\033[0;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Hysteria 2 + port hopping 一键安装脚本，适配 Debian 12/13。

用法：
  bash install.sh [选项]

常用：
  bash install.sh
  bash install.sh --domain hy2.example.com --email admin@example.com
  bash install.sh --port-range 20000-29999

选项：
  --domain DOMAIN            使用域名 + Let's Encrypt 证书。没有域名时自动使用自签证书。
  --email EMAIL              申请证书用邮箱，可选。
  --ip IP                    手动指定客户端连接地址；无域名时可用。
  --port-range START-END     UDP 端口跳跃范围，默认 20000-29999。
  --password PASSWORD        Hysteria 认证密码；默认自动生成。
  --obfs-password PASSWORD   Salamander 混淆密码；默认自动生成。
  --no-obfs                  不启用 Salamander 混淆，保留标准 HTTP/3 外观。
  --masq-url URL             伪装反代目标，默认 https://www.bing.com/。
  --firewall-backend BACKEND 强制端口跳跃防火墙后端：nftables 或 iptables。
  --name NAME                节点名称。
  --no-subscription          不生成 HTTP 订阅文件，只生成 /root/hysteria2-client.txt。
  --show                     显示已保存的客户端信息。
  -h, --help                 显示帮助。

说明：
  默认不会改动 Xray/REALITY，也不会占用 TCP 443。Hysteria2 使用 UDP 端口范围。
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --ip|--public-addr) PUBLIC_ADDR="${2:-}"; shift 2 ;;
    --port-range) PORT_RANGE="${2:-}"; shift 2 ;;
    --password) PASSWORD="${2:-}"; shift 2 ;;
    --obfs-password) OBFS_PASSWORD="${2:-}"; shift 2 ;;
    --no-obfs) NO_OBFS="1"; shift ;;
    --masq-url) MASQ_URL="${2:-}"; shift 2 ;;
    --firewall-backend) FORCE_FIREWALL_BACKEND="${2:-}"; shift 2 ;;
    --name) NODE_NAME="${2:-}"; shift 2 ;;
    --no-subscription) ENABLE_SUBSCRIPTION="0"; shift ;;
    --show) SHOW_ONLY="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1。使用 --help 查看帮助。" ;;
  esac
done

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请用 root 运行：sudo bash install.sh"
}

check_os() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "当前系统不是 Debian。检测到：${PRETTY_NAME:-unknown}"
  case "${VERSION_ID:-}" in
    12|13) log "检测到 ${PRETTY_NAME:-Debian ${VERSION_ID}}。" ;;
    *) warn "当前不是 Debian 12/13，而是 ${PRETTY_NAME:-unknown}；脚本仍会尝试安装。" ;;
  esac
  command -v systemctl >/dev/null 2>&1 || die "未检测到 systemd/systemctl。"
}

wait_apt_lock() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
  local waited=0
  while fuser "${locks[@]}" >/dev/null 2>&1; do
    if (( waited == 0 )); then
      warn "apt/dpkg 正在被其他进程占用，等待锁释放。"
    fi
    sleep 5
    waited=$((waited + 5))
    if (( waited > 600 )); then
      die "等待 apt 锁超过 10 分钟。请执行 ps aux | grep -E 'apt|dpkg' 检查。"
    fi
  done
}

apt_install_base() {
  export DEBIAN_FRONTEND=noninteractive
  wait_apt_lock
  log "安装基础依赖：curl、openssl、nftables、iptables、python3、nginx 等。"
  apt-get update
  wait_apt_lock
  apt-get install -y --no-install-recommends \
    ca-certificates curl openssl iproute2 procps coreutils sed gawk grep \
    nftables iptables python3 nginx
}

validate_inputs() {
  if [[ -n "$DOMAIN" && ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
    die "域名格式不正确：$DOMAIN"
  fi
  if [[ ! "$PORT_RANGE" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]]; then
    die "端口范围格式不正确，应为 START-END，例如 20000-29999。"
  fi
  local start end
  start="${BASH_REMATCH[1]}"
  end="${BASH_REMATCH[2]}"
  if (( start < 1 || end > 65535 || start >= end )); then
    die "端口范围无效：$PORT_RANGE"
  fi
  if (( end - start < 9 )); then
    die "端口跳跃范围太小，至少建议 10 个 UDP 端口。当前：$PORT_RANGE"
  fi
  case "$FORCE_FIREWALL_BACKEND" in
    ""|nftables|nft|iptables|ipt) ;;
    *) die "--firewall-backend 只能是 nftables 或 iptables。" ;;
  esac
  case "$MASQ_URL" in
    http://*|https://*) ;;
    *) die "--masq-url 必须以 http:// 或 https:// 开头。" ;;
  esac
}

rand_hex() {
  openssl rand -hex "$1"
}

first_port() {
  printf '%s' "$PORT_RANGE" | cut -d- -f1
}

is_udp_port_in_use() {
  local port="$1"
  ss -H -lun 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[:.])${port}$"
}

check_udp_port() {
  local p
  p="$(first_port)"
  if is_udp_port_in_use "$p"; then
    ss -lunp | grep -E "(^|[:.])${p}[[:space:]]" || true
    die "UDP ${p} 已被占用。请改用 --port-range，例如 --port-range 30000-39999。"
  fi
  log "UDP 端口跳跃范围：${PORT_RANGE}。请在 VPS 服务商安全组放行 UDP ${PORT_RANGE}。"
}

apply_kernel_tuning() {
  log "写入 Hysteria2/QUIC 性能优化到 ${SYSCTL_FILE}。"
  cat > "$SYSCTL_FILE" <<'SYSCTL_EOF'
# Hysteria2 QUIC performance tuning.
# Debian 13/systemd-sysctl reads /etc/sysctl.d/*.conf; keep settings here.
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
SYSCTL_EOF
  sysctl --system >/dev/null || warn "部分 sysctl 参数可能未生效；请稍后用 sysctl -p ${SYSCTL_FILE} 检查。"
}

install_hysteria() {
  log "使用 Hysteria 官方安装脚本安装/更新 Hysteria 2。"
  # HYSTERIA_USER=root 可以让服务读取 Let's Encrypt 私钥，并配合端口跳跃修改防火墙规则。
  HYSTERIA_USER=root bash <(curl -fsSL https://get.hy2.sh/)
  command -v hysteria >/dev/null 2>&1 || die "Hysteria 未安装成功。"
  hysteria version || true
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
  log "未指定域名，自动检测公网 IP。"
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

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_ipv6() {
  [[ "$1" == *:* ]]
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
  python3 - <<'PY' "$1"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
}

issue_cert_with_domain() {
  local webroot=""
  log "检测到域名模式：尝试通过 certbot webroot/standalone 申请 Let's Encrypt 证书。"
  wait_apt_lock
  apt-get install -y --no-install-recommends certbot

  if systemctl is-active --quiet nginx; then
    if [[ -d "$WEB_ROOT_CANDIDATE_XRAY" ]]; then
      webroot="$WEB_ROOT_CANDIDATE_XRAY"
    else
      webroot="$WEB_ROOT_DEFAULT"
    fi
    install -d -m 0755 "$webroot/.well-known/acme-challenge"
    log "nginx 已运行，使用 webroot：${webroot}"
    if [[ -n "$EMAIL" ]]; then
      certbot certonly --webroot -w "$webroot" -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --keep-until-expiring
    else
      certbot certonly --webroot -w "$webroot" -d "$DOMAIN" --register-unsafely-without-email --agree-tos --non-interactive --keep-until-expiring
    fi
  else
    log "nginx 未运行，使用 standalone HTTP-01 方式申请证书。"
    if [[ -n "$EMAIL" ]]; then
      certbot certonly --standalone -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --keep-until-expiring
    else
      certbot certonly --standalone -d "$DOMAIN" --register-unsafely-without-email --agree-tos --non-interactive --keep-until-expiring
    fi
  fi

  CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  KEY_FILE="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
  [[ -s "$CERT_FILE" && -s "$KEY_FILE" ]] || die "证书申请失败或证书文件不存在。请确认域名 DNS 解析到本机，且 80 端口可访问。"
  TLS_INSECURE="0"
  PIN_SHA256=""
  SNI_VALUE="$DOMAIN"
}

generate_self_signed_cert() {
  log "未指定域名：生成自签 TLS 证书，并在客户端链接中加入 insecure=1 + pinSHA256。"
  install -d -m 0700 "${CONFIG_DIR}/certs"
  CERT_FILE="${CONFIG_DIR}/certs/hysteria2-selfsigned.crt"
  KEY_FILE="${CONFIG_DIR}/certs/hysteria2-selfsigned.key"
  local cn san tmpconf
  cn="$SERVER_HOST"
  tmpconf="$(mktemp)"
  if is_ipv4 "$SERVER_HOST" || is_ipv6 "$SERVER_HOST"; then
    san="IP:${SERVER_HOST}"
  else
    san="DNS:${SERVER_HOST}"
  fi
  cat > "$tmpconf" <<CERTCONF_EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = ${cn}

[v3_req]
subjectAltName = ${san}
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
CERTCONF_EOF
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "$KEY_FILE" -out "$CERT_FILE" -config "$tmpconf" >/dev/null 2>&1
  rm -f "$tmpconf"
  chmod 0600 "$KEY_FILE"
  chmod 0644 "$CERT_FILE"
  TLS_INSECURE="1"
  PIN_SHA256="$(openssl x509 -noout -fingerprint -sha256 -in "$CERT_FILE" | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')"
  SNI_VALUE=""
}

prepare_tls() {
  if [[ -n "$DOMAIN" ]]; then
    issue_cert_with_domain
  else
    generate_self_signed_cert
  fi
}

generate_secrets() {
  [[ -n "$PASSWORD" ]] || PASSWORD="$(rand_hex 24)"
  [[ -n "$OBFS_PASSWORD" ]] || OBFS_PASSWORD="$(rand_hex 24)"
  SUB_TOKEN="$(rand_hex 24)"
  if [[ -z "$NODE_NAME" ]]; then
    NODE_NAME="HY2-${PORT_RANGE}"
  fi
}

write_hysteria_config() {
  log "写入 Hysteria2 配置：${CONFIG_FILE}"
  install -d -m 0755 "$CONFIG_DIR"
  if [[ -f "$CONFIG_FILE" ]]; then
    cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  local sni_guard="dns-san"
  [[ -z "$DOMAIN" ]] && sni_guard="disable"

  cat > "$CONFIG_FILE" <<CONFIG_HEAD_EOF
listen: :${PORT_RANGE}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}
  sniGuard: ${sni_guard}

auth:
  type: password
  password: ${PASSWORD}
CONFIG_HEAD_EOF

  if [[ "$NO_OBFS" != "1" ]]; then
    cat >> "$CONFIG_FILE" <<CONFIG_OBFS_EOF

obfs:
  type: ${OBFS_TYPE}
  ${OBFS_TYPE}:
    password: ${OBFS_PASSWORD}
CONFIG_OBFS_EOF
  fi

  cat >> "$CONFIG_FILE" <<CONFIG_TAIL_EOF

quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false

disableUDP: false
udpIdleTimeout: 60s

resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53
    timeout: 4s

masquerade:
  type: proxy
  proxy:
    url: ${MASQ_URL}
    rewriteHost: true
    insecure: false
    xForwarded: false
CONFIG_TAIL_EOF
  chmod 0644 "$CONFIG_FILE"
}

setup_systemd_env_and_start() {
  log "配置 systemd 环境并启动 Hysteria2。"
  install -d -m 0755 /etc/systemd/system/${SERVICE_NAME}.d
  local backend_line=""
  if [[ -n "$FORCE_FIREWALL_BACKEND" ]]; then
    case "$FORCE_FIREWALL_BACKEND" in
      nft) FORCE_FIREWALL_BACKEND="nftables" ;;
      ipt) FORCE_FIREWALL_BACKEND="iptables" ;;
    esac
    backend_line="Environment=HYSTERIA_FIREWALL_BACKEND=${FORCE_FIREWALL_BACKEND}"
  fi
  cat > "/etc/systemd/system/${SERVICE_NAME}.d/10-performance-and-porthop.conf" <<SYSTEMD_EOF
[Service]
Nice=-5
Environment=HYSTERIA_DISABLE_UPDATE_CHECK=1
${backend_line}
SYSTEMD_EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  if ! systemctl restart "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager >&2 || true
    die "Hysteria2 启动失败。已保留配置备份，请检查上方日志。"
  fi
  sleep 1
  systemctl is-active --quiet "$SERVICE_NAME" || {
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager >&2 || true
    die "Hysteria2 未保持运行状态。"
  }
  systemctl --no-pager --full status "$SERVICE_NAME" | sed -n '1,12p' || true
}

open_ufw_if_active() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    log "检测到 ufw 已启用，放行 UDP ${PORT_RANGE}。"
    ufw allow "${PORT_RANGE}/udp" || warn "ufw 放行失败，请手动放行 UDP ${PORT_RANGE}。"
  fi
}

build_client_links() {
  local h auth_enc name_enc query=""
  h="$(uri_host "$SERVER_HOST")"
  auth_enc="$(urlencode "$PASSWORD")"
  name_enc="$(urlencode "$NODE_NAME")"

  if [[ "$TLS_INSECURE" == "1" ]]; then
    query="insecure=1&pinSHA256=${PIN_SHA256}"
  else
    query="insecure=0&sni=$(urlencode "$SNI_VALUE")"
  fi

  if [[ "$NO_OBFS" != "1" ]]; then
    query="${query}&obfs=${OBFS_TYPE}&obfs-password=$(urlencode "$OBFS_PASSWORD")"
  fi

  HY2_LINK="hysteria2://${auth_enc}@${h}:${PORT_RANGE}/?${query}#${name_enc}"
  HY2_SHORT_LINK="hy2://${auth_enc}@${h}:${PORT_RANGE}/?${query}#${name_enc}"
  SUBSCRIPTION_B64="$(printf '%s\n' "$HY2_LINK" | base64 -w 0)"
}

write_subscription_file() {
  SUBSCRIPTION_URL=""
  [[ "$ENABLE_SUBSCRIPTION" == "1" ]] || return 0

  local webroot="$WEB_ROOT_DEFAULT"
  if [[ -d "$WEB_ROOT_CANDIDATE_XRAY" ]]; then
    webroot="$WEB_ROOT_CANDIDATE_XRAY"
  fi
  install -d -m 0755 "$webroot/assets"
  printf '%s\n' "$SUBSCRIPTION_B64" > "$webroot/assets/${SUB_TOKEN}.txt"
  chmod 0644 "$webroot/assets/${SUB_TOKEN}.txt"

  if ! systemctl is-active --quiet nginx; then
    log "启动 nginx 用于随机订阅路径。"
    cat > /etc/nginx/sites-available/hysteria2-porthop-sub.conf <<NGINX_EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;
    access_log off;
    error_log /var/log/nginx/error.log crit;
    server_tokens off;
    root ${webroot};
    location / { try_files \$uri \$uri/ =404; }
}
NGINX_EOF
    ln -sfn /etc/nginx/sites-available/hysteria2-porthop-sub.conf /etc/nginx/sites-enabled/hysteria2-porthop-sub.conf
    nginx -t && systemctl enable --now nginx || warn "nginx 启动失败，订阅 URL 可能不可用；客户端信息文件仍可用。"
  else
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi

  local h
  h="$(uri_host "$SERVER_HOST")"
  SUBSCRIPTION_URL="http://${h}/assets/${SUB_TOKEN}.txt"
}

save_state_and_print() {
  install -d -m 0700 "$STATE_DIR"
  cat > "${STATE_DIR}/client.env" <<STATE_EOF
SERVER_HOST='${SERVER_HOST}'
PORT_RANGE='${PORT_RANGE}'
DOMAIN='${DOMAIN}'
PASSWORD='${PASSWORD}'
NO_OBFS='${NO_OBFS}'
OBFS_TYPE='${OBFS_TYPE}'
OBFS_PASSWORD='${OBFS_PASSWORD}'
TLS_INSECURE='${TLS_INSECURE}'
PIN_SHA256='${PIN_SHA256}'
SNI_VALUE='${SNI_VALUE}'
CERT_FILE='${CERT_FILE}'
KEY_FILE='${KEY_FILE}'
NODE_NAME='${NODE_NAME}'
HY2_LINK='${HY2_LINK}'
HY2_SHORT_LINK='${HY2_SHORT_LINK}'
SUBSCRIPTION_URL='${SUBSCRIPTION_URL}'
SUB_TOKEN='${SUB_TOKEN}'
STATE_EOF
  chmod 0600 "${STATE_DIR}/client.env"

  cat > "$INFO_FILE" <<INFO_EOF
Hysteria2 + UDP Port Hopping 安装完成
生成时间：$(date -Is)

服务器地址：${SERVER_HOST}
UDP 端口跳跃范围：${PORT_RANGE}
认证密码：${PASSWORD}
TLS 模式：$([[ -n "$DOMAIN" ]] && echo "域名证书" || echo "自签证书 + insecure=1 + pinSHA256")
SNI：${SNI_VALUE:-无}
证书指纹 pinSHA256：${PIN_SHA256:-域名证书模式未启用 pin，避免证书续期后失效}
混淆：$([[ "$NO_OBFS" == "1" ]] && echo "未启用" || echo "${OBFS_TYPE}")
混淆密码：$([[ "$NO_OBFS" == "1" ]] && echo "无" || echo "${OBFS_PASSWORD}")
伪装目标：${MASQ_URL}

Shadowrocket / 小火箭可导入 hysteria2:// 链接：
${HY2_LINK}

备用 hy2:// 链接：
${HY2_SHORT_LINK}

订阅 URL：
${SUBSCRIPTION_URL:-未生成}

iOS/小火箭提醒：
1. VPS 服务商安全组必须放行 UDP ${PORT_RANGE}。
2. 没有域名时使用自签证书，链接里已经包含 insecure=1 和 pinSHA256。
3. 如果小火箭不识别订阅，就直接复制 hysteria2:// 链接导入。

服务检查：
  systemctl status hysteria-server --no-pager
  journalctl -u hysteria-server -e --no-pager
  ss -lunp | grep hysteria
INFO_EOF
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
    echo "${HY2_LINK:-}"
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
  check_udp_port
  apply_kernel_tuning
  install_hysteria
  detect_public_host
  generate_secrets
  prepare_tls
  write_hysteria_config
  setup_systemd_env_and_start
  open_ufw_if_active
  build_client_links
  write_subscription_file
  save_state_and_print
}

main "$@"
