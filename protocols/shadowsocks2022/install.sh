#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="shadowsocks2022-debian"
SERVICE_NAME="shadowsocks-rust-server"
SERVICE_USER="ss2022"
SERVICE_GROUP="ss2022"
CONFIG_DIR="/etc/shadowsocks-rust"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATE_FILE="${CONFIG_DIR}/ss2022.env"
CLIENT_FILE="/root/shadowsocks2022-client.txt"
COMBINED_FILE="/root/all-proxy-subscription.txt"
SUB_ROOT="/var/www/html/assets"
SYSCTL_FILE="/etc/sysctl.d/99-ss2022-performance.conf"
SS_BIN_DIR="/usr/local/bin"
INSTALL_MARKER="/usr/local/share/${PROJECT_NAME}/installed-by-this-script"

PORT="8388"
METHOD="2022-blake3-aes-256-gcm"
NODE_NAME="SS2022"
PUBLIC_HOST=""
SKIP_NGINX="0"
FORCE_REGEN="0"
NO_COMBINED="0"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

on_error() {
  local line="$1"
  printf '\033[1;31m[ERROR]\033[0m line %s: %s\n' "$line" "${BASH_COMMAND}" >&2
  journalctl -u "${SERVICE_NAME}" -n 80 --no-pager 2>/dev/null || true
}
trap 'on_error $LINENO' ERR

usage() {
  cat <<EOF
${PROJECT_NAME} installer

用法：
  bash install.sh [选项]

选项：
  --port <端口>              SS2022 监听端口，默认 8388，同时使用 TCP+UDP
  --method <方法>            默认 2022-blake3-aes-256-gcm
                            可选：2022-blake3-aes-128-gcm / 2022-blake3-aes-256-gcm / 2022-blake3-chacha20-poly1305
  --host <IP或域名>          客户端链接里使用的地址；不填则自动检测公网 IPv4，失败再检测 IPv6
  --name <节点名>            默认 SS2022
  --regen-key                强制重新生成 SS2022 PSK/密码
  --no-nginx                 不安装/不写入 HTTP 订阅文件，只生成本地客户端文件
  --no-combined              不生成整合订阅文件
  -h, --help                 显示帮助

示例：
  bash install.sh
  bash install.sh --port 8388
  bash install.sh --host 1.2.3.4 --port 18443
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        PORT="${2:-}"; shift 2 ;;
      --method)
        METHOD="${2:-}"; shift 2 ;;
      --host)
        PUBLIC_HOST="${2:-}"; shift 2 ;;
      --name)
        NODE_NAME="${2:-}"; shift 2 ;;
      --regen-key)
        FORCE_REGEN="1"; shift ;;
      --no-nginx)
        SKIP_NGINX="1"; shift ;;
      --no-combined)
        NO_COMBINED="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "未知参数：$1" ;;
    esac
  done
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "请使用 root 用户运行。"
}

validate_input() {
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "端口必须是数字。"
  (( PORT >= 1 && PORT <= 65535 )) || die "端口范围必须是 1-65535。"
  if (( PORT < 1024 )); then
    warn "你选择了低端口 ${PORT}，脚本会给 systemd 服务保留 CAP_NET_BIND_SERVICE，但不建议和现有 443/80 服务抢端口。"
  fi
  case "$METHOD" in
    2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) ;;
    *) die "不支持的 SS2022 method：${METHOD}" ;;
  esac
  [[ -n "$NODE_NAME" ]] || NODE_NAME="SS2022"
}

check_os() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "当前系统不是 Debian。"
  case "${VERSION_ID:-}" in
    12|13) log "检测到 Debian ${VERSION_ID}。" ;;
    *) warn "当前 Debian 版本为 ${VERSION_ID:-unknown}，脚本主要适配 Debian 12/13。" ;;
  esac
}

wait_for_apt() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
  local waited=0
  while true; do
    local busy=0
    for f in "${locks[@]}"; do
      if [[ -e "$f" ]] && fuser "$f" >/dev/null 2>&1; then
        busy=1
        break
      fi
    done
    if [[ "$busy" -eq 0 ]]; then
      break
    fi
    waited=$((waited + 5))
    if (( waited > 600 )); then
      die "apt/dpkg 锁等待超过 10 分钟，请检查是否有其它 apt 进程卡住。"
    fi
    warn "apt/dpkg 正在运行，等待 5 秒..."
    sleep 5
  done
}

apt_install() {
  wait_for_apt
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  wait_for_apt
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

install_deps() {
  log "安装基础依赖：curl ca-certificates tar xz-utils openssl python3 iproute2 procps gawk。"
  apt_install ca-certificates curl tar xz-utils openssl python3 iproute2 procps gawk
}

apply_sysctl() {
  log "写入 SS2022/TCP/UDP 稳健型内核参数。"
  cat > "$SYSCTL_FILE" <<'EOF'
# Managed by shadowsocks2022-debian installer.
# Debian 13's systemd-sysctl no longer relies on /etc/sysctl.conf, so keep settings in /etc/sysctl.d/.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.somaxconn = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
# Keep IPv6 wildcard sockets dual-stack on typical Debian kernels.
net.ipv6.bindv6only = 0
EOF
  sysctl --system >/dev/null || warn "sysctl --system 部分参数可能因内核/容器限制未生效，可稍后用 sysctl 查看。"
}

arch_target() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64-unknown-linux-gnu' ;;
    aarch64|arm64) printf 'aarch64-unknown-linux-gnu' ;;
    *) die "暂不支持该 CPU 架构：$(uname -m)。仅自动支持 x86_64/amd64 和 aarch64/arm64。" ;;
  esac
}

install_shadowsocks_rust() {
  local target archive_url sha_url tmp archive extract_dir ssserver_path ssurl_path sslocal_path
  target="$(arch_target)"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  log "从 shadowsocks-rust GitHub Releases 下载最新 ${target} 预编译包。"
  local api_json
  api_json="$(curl -fsSL --connect-timeout 15 --retry 3 https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest)"
  archive_url="$(API_JSON="$api_json" python3 - "$target" <<'PY'
import json, os, sys
j = json.loads(os.environ.get('API_JSON', '{}'))
target = sys.argv[1]
for asset in j.get('assets', []):
    name = asset.get('name', '')
    url = asset.get('browser_download_url', '')
    if target in name and name.endswith('.tar.xz') and not name.endswith('.sha256'):
        print(url)
        break
else:
    raise SystemExit(1)
PY
)" || die "无法从 GitHub API 解析 shadowsocks-rust 最新下载地址。"

  archive="${tmp}/shadowsocks.tar.xz"
  sha_url="${archive_url}.sha256"
  curl -fL --retry 3 -o "$archive" "$archive_url"

  if curl -fsSL --retry 3 -o "${archive}.sha256" "$sha_url"; then
    local expected actual
    expected="$(grep -Eo '[A-Fa-f0-9]{64}' "${archive}.sha256" | head -n1 || true)"
    actual="$(sha256sum "$archive" | awk '{print $1}')"
    if [[ -n "$expected" && "${expected,,}" != "${actual,,}" ]]; then
      die "shadowsocks-rust 下载包 sha256 校验失败。"
    fi
    log "sha256 校验通过。"
  else
    warn "未能下载 .sha256 校验文件，继续安装。"
  fi

  extract_dir="${tmp}/extract"
  mkdir -p "$extract_dir"
  tar -xJf "$archive" -C "$extract_dir"
  ssserver_path="$(find "$extract_dir" -type f -name ssserver -perm /111 | head -n1 || true)"
  ssurl_path="$(find "$extract_dir" -type f -name ssurl -perm /111 | head -n1 || true)"
  sslocal_path="$(find "$extract_dir" -type f -name sslocal -perm /111 | head -n1 || true)"
  [[ -n "$ssserver_path" ]] || die "下载包里没有找到 ssserver。"

  install -m 0755 "$ssserver_path" "${SS_BIN_DIR}/ssserver"
  [[ -n "$ssurl_path" ]] && install -m 0755 "$ssurl_path" "${SS_BIN_DIR}/ssurl" || true
  [[ -n "$sslocal_path" ]] && install -m 0755 "$sslocal_path" "${SS_BIN_DIR}/sslocal" || true
  mkdir -p "$(dirname "$INSTALL_MARKER")"
  printf '%s\n' "$archive_url" > "$INSTALL_MARKER"
  log "已安装：$(/usr/local/bin/ssserver --version 2>/dev/null || echo ssserver)"
}

port_in_use() {
  local port="$1"
  ss -H -lntu | awk '{print $5}' | grep -Eq "(^|:|\])${port}$"
}

check_port() {
  systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
  if port_in_use "$PORT"; then
    ss -H -lntup | grep -E "(^|[:\]])${PORT}[[:space:]]" || true
    ss -H -lnu  | grep -E "(^|[:\]])${PORT}[[:space:]]" || true
    die "端口 ${PORT} 已被占用。请换端口：bash install.sh --port 其它端口"
  fi
}

key_bytes_for_method() {
  case "$METHOD" in
    2022-blake3-aes-128-gcm) printf '16' ;;
    2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) printf '32' ;;
  esac
}

prepare_runtime_user_and_dirs() {
  log "准备 SS2022 运行用户、配置目录和日志目录。"
  if ! getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
    groupadd --system "$SERVICE_GROUP"
  fi
  if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --gid "$SERVICE_GROUP" --home-dir /nonexistent --shell /usr/sbin/nologin --no-create-home "$SERVICE_USER"
  fi

  install -d -m 0750 -o root -g "$SERVICE_GROUP" "$CONFIG_DIR"
  install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_GROUP" /var/log/shadowsocks-rust
}

load_or_generate_state() {
  install -d -m 0750 -o root -g "$SERVICE_GROUP" "$CONFIG_DIR"
  local existing_password="" existing_sub_token="" existing_all_token="" existing_method="" existing_port=""
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE" || true
    existing_password="${SS2022_PASSWORD:-}"
    existing_sub_token="${SS2022_SUB_TOKEN:-}"
    existing_all_token="${SS2022_ALL_TOKEN:-}"
    existing_method="${SS2022_METHOD:-}"
    existing_port="${SS2022_PORT:-}"
  fi

  if [[ "$FORCE_REGEN" == "1" || -z "$existing_password" || "$existing_method" != "$METHOD" ]]; then
    SS2022_PASSWORD="$(openssl rand -base64 "$(key_bytes_for_method)")"
  else
    SS2022_PASSWORD="$existing_password"
  fi
  SS2022_PORT="$PORT"
  SS2022_METHOD="$METHOD"
  SS2022_NODE_NAME="$NODE_NAME"
  SS2022_SUB_TOKEN="${existing_sub_token:-$(openssl rand -hex 24)}"
  SS2022_ALL_TOKEN="${existing_all_token:-$(openssl rand -hex 24)}"

  umask 077
  cat > "$STATE_FILE" <<EOF
SS2022_PORT='${SS2022_PORT}'
SS2022_METHOD='${SS2022_METHOD}'
SS2022_PASSWORD='${SS2022_PASSWORD}'
SS2022_NODE_NAME='${SS2022_NODE_NAME}'
SS2022_SUB_TOKEN='${SS2022_SUB_TOKEN}'
SS2022_ALL_TOKEN='${SS2022_ALL_TOKEN}'
EOF
  chown root:"$SERVICE_GROUP" "$STATE_FILE" 2>/dev/null || true
  chmod 0640 "$STATE_FILE"
}

write_config() {
  log "写入 shadowsocks-rust SS2022 配置。"
  python3 - "$CONFIG_FILE" "$METHOD" "$SS2022_PASSWORD" "$PORT" <<'PY'
import json, sys
path, method, password, port = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
config = {
    "server": "::",
    "server_port": port,
    "password": password,
    "method": method,
    "timeout": 300,
    "mode": "tcp_and_udp",
    "nameserver": "1.1.1.1,8.8.8.8"
}
with open(path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write('\n')
PY
  chown root:"$SERVICE_GROUP" "$CONFIG_FILE" 2>/dev/null || true
  chmod 0640 "$CONFIG_FILE"
}

write_systemd() {
  log "写入 systemd 服务：${SERVICE_NAME}.service。"
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Shadowsocks Rust Server (SS2022)
Documentation=https://github.com/shadowsocks/shadowsocks-rust https://shadowsocks.org/doc/sip022.html
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
ExecStart=/usr/local/bin/ssserver -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=3s
LimitNOFILE=1000000
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadOnlyPaths=${CONFIG_DIR}
ReadWritePaths=/var/log/shadowsocks-rust

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

start_service() {
  log "启动 shadowsocks-rust SS2022 服务。"
  systemctl enable --now "${SERVICE_NAME}"
  sleep 1
  if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    systemctl status "${SERVICE_NAME}" --no-pager || true
    journalctl -u "${SERVICE_NAME}" -n 120 --no-pager || true
    die "${SERVICE_NAME} 启动失败。"
  fi
  systemctl status "${SERVICE_NAME}" --no-pager || true
}

open_local_firewall() {
  log "尝试放行本机防火墙端口 ${PORT}/tcp 与 ${PORT}/udp。"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
    ufw allow "${PORT}/tcp" || true
    ufw allow "${PORT}/udp" || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" || true
    firewall-cmd --permanent --add-port="${PORT}/udp" || true
    firewall-cmd --reload || true
  fi
}

detect_public_host() {
  if [[ -n "$PUBLIC_HOST" ]]; then
    printf '%s' "$PUBLIC_HOST"
    return 0
  fi
  local h=""
  h="$(curl -4fsS --connect-timeout 3 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$h" ]]; then
    h="$(curl -6fsS --connect-timeout 3 https://api64.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "$h" ]]; then
    h="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  fi
  [[ -n "$h" ]] || die "无法自动检测公网 IP，请用 --host 手动指定。"
  printf '%s' "$h"
}

is_ipv6_literal() {
  [[ "$1" == *:* && "$1" != \[*\] ]]
}

uri_host() {
  local h="$1"
  if is_ipv6_literal "$h"; then
    printf '[%s]' "$h"
  else
    printf '%s' "$h"
  fi
}

http_host() {
  uri_host "$1"
}

make_ss_uri() {
  local host="$1"
  python3 - "$METHOD" "$SS2022_PASSWORD" "$(uri_host "$host")" "$PORT" "$NODE_NAME" <<'PY'
import sys, urllib.parse
method, password, host, port, name = sys.argv[1:]
# SIP002: AEAD-2022 userinfo MUST NOT be Base64URL-encoded; method/password should be percent-encoded.
userinfo = urllib.parse.quote(method, safe='') + ':' + urllib.parse.quote(password, safe='')
tag = urllib.parse.quote(name, safe='')
print(f"ss://{userinfo}@{host}:{port}#{tag}")
PY
}

ensure_nginx_for_subscription() {
  [[ "$SKIP_NGINX" == "0" ]] || return 1
  install -d -m 0755 "$SUB_ROOT"
  if ! command -v nginx >/dev/null 2>&1; then
    if ss -H -ltn | awk '{print $4}' | grep -Eq '(^|:|\])80$'; then
      warn "80/TCP 已被其它程序占用，跳过 HTTP 订阅服务；本地订阅文件仍会生成。"
      return 1
    fi
    log "安装 nginx 用于随机路径订阅文件。"
    apt_install nginx
  fi
  systemctl enable --now nginx >/dev/null 2>&1 || warn "nginx 启动失败，订阅 URL 可能不可用。"
  return 0
}

write_subscription_files() {
  local host="$1" ss_uri="$2"
  install -d -m 0755 "$(dirname "$CLIENT_FILE")"
  local sub_url=""
  local sub_b64_url=""
  if ensure_nginx_for_subscription; then
    printf '%s\n' "$ss_uri" > "${SUB_ROOT}/${SS2022_SUB_TOKEN}.txt"
    printf '%s\n' "$ss_uri" | base64 -w0 > "${SUB_ROOT}/${SS2022_SUB_TOKEN}.b64"
    printf '\n' >> "${SUB_ROOT}/${SS2022_SUB_TOKEN}.b64"
    chmod 0644 "${SUB_ROOT}/${SS2022_SUB_TOKEN}.txt" "${SUB_ROOT}/${SS2022_SUB_TOKEN}.b64"
    sub_url="http://$(http_host "$host")/assets/${SS2022_SUB_TOKEN}.txt"
    sub_b64_url="http://$(http_host "$host")/assets/${SS2022_SUB_TOKEN}.b64"
  fi

  umask 077
  cat > "$CLIENT_FILE" <<EOF
Shadowsocks 2022 / shadowsocks-rust 已安装

地址: ${host}
端口: ${PORT}
传输: TCP + UDP
加密方法: ${METHOD}
PSK/密码: ${SS2022_PASSWORD}
节点名: ${NODE_NAME}

Shadowrocket / 小火箭可导入 ss:// 链接：
${ss_uri}

订阅 URL（原始文本，每行一个节点）：
${sub_url:-未启用 HTTP 订阅，可直接导入上面的 ss:// 链接}

订阅 URL（Base64 兼容版）：
${sub_b64_url:-未启用 HTTP 订阅}

提醒：
1. VPS 服务商后台安全组必须放行 TCP ${PORT} 和 UDP ${PORT}。
2. SS2022 的 URI 按 SIP002/SIP022 生成，AEAD-2022 userinfo 不使用 Base64URL。
3. 这不会修改你的 Xray REALITY 或 Hysteria2 配置。

服务检查：
  systemctl status ${SERVICE_NAME} --no-pager
  journalctl -u ${SERVICE_NAME} -e --no-pager
  ss -lntup | grep ':${PORT}'
  ss -lnu   | grep ':${PORT}'
EOF
  chmod 0600 "$CLIENT_FILE"
}

write_combined_updater() {
  [[ "$NO_COMBINED" == "0" ]] || return 0
  cat > /usr/local/bin/update-proxy-subscription <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE_FILE="/etc/shadowsocks-rust/ss2022.env"
SUB_ROOT="/var/www/html/assets"
OUT="/root/all-proxy-subscription.txt"
[[ -f "$STATE_FILE" ]] && source "$STATE_FILE" || true
ALL_TOKEN="${SS2022_ALL_TOKEN:-}"
collect_first() {
  local pattern="$1" file="$2"
  [[ -f "$file" ]] || return 0
  grep -aEo "$pattern" "$file" | head -n1 || true
}
{
  collect_first 'vless://[^[:space:]]+' /root/xray-reality-client.txt
  collect_first 'hysteria2://[^[:space:]]+' /root/hysteria2-client.txt
  collect_first 'ss://[^[:space:]]+' /root/shadowsocks2022-client.txt
} | awk 'NF && !seen[$0]++' > "$OUT"
chmod 0600 "$OUT"
if [[ -n "$ALL_TOKEN" && -d "$SUB_ROOT" ]]; then
  cp "$OUT" "${SUB_ROOT}/${ALL_TOKEN}-all.txt"
  base64 -w0 "$OUT" > "${SUB_ROOT}/${ALL_TOKEN}-all.b64"
  printf '\n' >> "${SUB_ROOT}/${ALL_TOKEN}-all.b64"
  chmod 0644 "${SUB_ROOT}/${ALL_TOKEN}-all.txt" "${SUB_ROOT}/${ALL_TOKEN}-all.b64"
fi
EOF
  chmod 0755 /usr/local/bin/update-proxy-subscription
}

update_combined_subscription() {
  [[ "$NO_COMBINED" == "0" ]] || return 0
  local host="$1"
  write_combined_updater
  /usr/local/bin/update-proxy-subscription || warn "整合订阅生成失败，可稍后手动运行 update-proxy-subscription。"
  if [[ -s "$COMBINED_FILE" && -d "$SUB_ROOT" ]]; then
    cat >> "$CLIENT_FILE" <<EOF

整合订阅 URL（如果本机已有 REALITY/HY2/SS2022，会自动合成多节点）：
http://$(http_host "$host")/assets/${SS2022_ALL_TOKEN}-all.txt

整合订阅 Base64 兼容版：
http://$(http_host "$host")/assets/${SS2022_ALL_TOKEN}-all.b64
EOF
  fi
}

print_result() {
  local host="$1"
  log "SS2022 安装完成。"
  cat <<EOF
------------------------------------------------------------
客户端信息已保存：
  ${CLIENT_FILE}

查看链接：
  cat ${CLIENT_FILE}

服务状态：
  systemctl status ${SERVICE_NAME} --no-pager

请在 VPS 服务商后台安全组放行：
  TCP ${PORT}
  UDP ${PORT}

当前地址：${host}
当前端口：${PORT}
------------------------------------------------------------
EOF
}

main() {
  parse_args "$@"
  need_root
  validate_input
  check_os
  install_deps
  apply_sysctl
  install_shadowsocks_rust
  check_port
  prepare_runtime_user_and_dirs
  load_or_generate_state
  write_config
  write_systemd
  start_service
  open_local_firewall

  local host ss_uri
  host="$(detect_public_host)"
  ss_uri="$(make_ss_uri "$host")"
  write_subscription_files "$host" "$ss_uri"
  update_combined_subscription "$host"
  print_result "$host"
}

main "$@"
