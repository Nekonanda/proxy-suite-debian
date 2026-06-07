#!/usr/bin/env bash
set -Eeuo pipefail

# TUIC v5 on Debian 12/13 using sing-box.
# Designed as an additive install: it does not modify Xray/Hysteria2/SS2022 services.

SCRIPT_VERSION="1.0.0"
SERVICE_NAME="sing-box-tuic"
USER_NAME="sing-tuic"
GROUP_NAME="sing-tuic"
CONFIG_DIR="/etc/sing-box-tuic"
CERT_DIR="${CONFIG_DIR}/certs"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATE_FILE="${CONFIG_DIR}/state.env"
CLIENT_FILE="/root/tuic5-client.txt"
CLIENT_JSON="${CONFIG_DIR}/client-outbound-tuic5.json"
SYSCTL_FILE="/etc/sysctl.d/99-tuic5-quic-performance.conf"
DEFAULT_PORT="10443"
DEFAULT_SNI="www.bing.com"
DEFAULT_CC="bbr"
DEFAULT_ALPN="h3"
PORT="${DEFAULT_PORT}"
SNI="${DEFAULT_SNI}"
CONGESTION_CONTROL="${DEFAULT_CC}"
FORCE_REGEN="0"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
TUIC v5 一键安装脚本 v${SCRIPT_VERSION}

用法:
  bash install.tuic5.sh [选项]

选项:
  --port <端口>              默认: ${DEFAULT_PORT}，UDP 端口
  --sni <域名>               默认: ${DEFAULT_SNI}，自签证书 SAN/SNI
  --congestion <算法>        默认: ${DEFAULT_CC}，可选: bbr/cubic/new_reno
  --regen                    重新生成 UUID/密码/证书
  -h, --help                 显示帮助

示例:
  bash install.tuic5.sh
  bash install.tuic5.sh --port 10443
  bash install.tuic5.sh --port 30443 --sni www.bing.com
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="${2:-}"; shift 2 ;;
    --sni)
      SNI="${2:-}"; shift 2 ;;
    --congestion)
      CONGESTION_CONTROL="${2:-}"; shift 2 ;;
    --regen)
      FORCE_REGEN="1"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "未知参数: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "请使用 root 运行。"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "端口必须是数字。"
(( PORT >= 1 && PORT <= 65535 )) || die "端口范围必须是 1-65535。"
case "$CONGESTION_CONTROL" in
  bbr|cubic|new_reno) ;;
  *) die "--congestion 只能是 bbr/cubic/new_reno。" ;;
esac

wait_apt_lock() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
  local waited=0
  while true; do
    local busy=0
    for f in "${locks[@]}"; do
      if command -v fuser >/dev/null 2>&1 && fuser "$f" >/dev/null 2>&1; then
        busy=1
      fi
    done
    [[ "$busy" == "0" ]] && break
    if (( waited >= 300 )); then
      die "apt/dpkg 锁等待超过 300 秒，请稍后重试。"
    fi
    warn "apt/dpkg 正在运行，等待 5 秒..."
    sleep 5
    waited=$(( waited + 5 ))
  done
}

detect_os() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck source=/dev/null
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "仅支持 Debian 12/13，当前: ${PRETTY_NAME:-unknown}。"
  case "${VERSION_ID:-}" in
    12|13) log "检测到 ${PRETTY_NAME}。" ;;
    *) die "仅支持 Debian 12/13，当前: ${PRETTY_NAME:-unknown}。" ;;
  esac
}

install_dependencies() {
  log "安装基础依赖：curl, ca-certificates, openssl, tar, gzip, python3, jq, iproute2, procps。"
  wait_apt_lock
  apt-get update
  wait_apt_lock
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl ca-certificates openssl tar gzip python3 jq iproute2 procps coreutils sed gawk
}

optimize_kernel() {
  log "写入 TUIC/QUIC 稳健型内核优化。"
  cat > "$SYSCTL_FILE" <<'SYSCTL'
# TUIC5 / QUIC performance tuning.
# Debian 13 uses /etc/sysctl.d/*.conf; do not rely on /etc/sysctl.conf.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.netdev_max_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv6.bindv6only = 0
SYSCTL
  sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || warn "部分 sysctl 参数可能在当前内核不可用，已跳过。"
}

create_user_and_dirs() {
  if ! getent group "$GROUP_NAME" >/dev/null; then
    groupadd --system "$GROUP_NAME"
  fi
  if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin --gid "$GROUP_NAME" "$USER_NAME"
  fi

  install -d -m 0750 -o root -g "$GROUP_NAME" "$CONFIG_DIR" "$CERT_DIR"
}

arch_for_singbox() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    armv6l) echo "armv6" ;;
    i386|i686) echo "386" ;;
    *) die "暂不支持架构: $(uname -m)" ;;
  esac
}

install_sing_box() {
  local arch version url tmp
  arch="$(arch_for_singbox)"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  log "从 SagerNet/sing-box GitHub Releases 获取最新版。"
  version="$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"
  [[ -n "$version" ]] || die "无法获取 sing-box 最新版本。"

  if command -v /usr/local/bin/sing-box >/dev/null 2>&1; then
    log "检测到已有 sing-box: $(/usr/local/bin/sing-box version | head -n1 || true)"
  fi

  url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-${arch}.tar.gz"
  log "下载 sing-box ${version} (${arch})。"
  curl -fL --retry 3 --connect-timeout 15 -o "$tmp/sing-box.tar.gz" "$url"
  tar -xzf "$tmp/sing-box.tar.gz" -C "$tmp"
  local bin
  bin="$(find "$tmp" -type f -name sing-box | head -n1)"
  [[ -n "$bin" ]] || die "下载包里没有找到 sing-box 二进制。"
  install -m 0755 -o root -g root "$bin" /usr/local/bin/sing-box
  log "已安装 $(/usr/local/bin/sing-box version | head -n1)。"
}

port_available() {
  if ss -lunp 2>/dev/null | awk '{print $5}' | grep -Eq "(^|:|\\])${PORT}$"; then
    # If it is our own service, allow overwrite/restart.
    if ss -lunp 2>/dev/null | grep -E "(^|:)${PORT}($| )" | grep -q "sing-box"; then
      return 0
    fi
    return 1
  fi
  return 0
}

load_or_generate_state() {
  UUID=""
  PASSWORD=""
  CERT_FILE="${CERT_DIR}/server.crt"
  KEY_FILE="${CERT_DIR}/server.key"

  if [[ "$FORCE_REGEN" != "1" && -f "$STATE_FILE" ]]; then
    # shellcheck source=/dev/null
    . "$STATE_FILE" || true
  fi

  if [[ -z "${UUID:-}" ]]; then
    UUID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  fi
  if [[ -z "${PASSWORD:-}" ]]; then
    PASSWORD="$(openssl rand -base64 18 | tr -d '=+/[:space:]' | cut -c1-24)"
  fi

  if [[ "$FORCE_REGEN" == "1" || ! -s "$CERT_FILE" || ! -s "$KEY_FILE" ]]; then
    log "生成自签 TLS 证书：CN/SAN=${SNI}。"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -nodes -sha256 -days 3650 \
      -subj "/CN=${SNI}" \
      -addext "subjectAltName=DNS:${SNI}" \
      -keyout "$KEY_FILE" \
      -out "$CERT_FILE" >/dev/null 2>&1
  fi

  cat > "$STATE_FILE" <<STATE
UUID='${UUID}'
PASSWORD='${PASSWORD}'
PORT='${PORT}'
SNI='${SNI}'
CONGESTION_CONTROL='${CONGESTION_CONTROL}'
CERT_FILE='${CERT_FILE}'
KEY_FILE='${KEY_FILE}'
STATE
  chown root:"$GROUP_NAME" "$STATE_FILE" "$CERT_FILE" "$KEY_FILE"
  chmod 640 "$STATE_FILE" "$CERT_FILE" "$KEY_FILE"
}

write_config() {
  log "写入 sing-box TUIC v5 配置。"
  python3 - <<PY
import json
from pathlib import Path
cfg = {
  "log": {"disabled": False, "level": "info", "timestamp": True},
  "inbounds": [
    {
      "type": "tuic",
      "tag": "tuic5-in",
      "listen": "::",
      "listen_port": int(${PORT}),
      "users": [
        {"name": "tuic5", "uuid": "${UUID}", "password": "${PASSWORD}"}
      ],
      "congestion_control": "${CONGESTION_CONTROL}",
      "auth_timeout": "3s",
      "zero_rtt_handshake": False,
      "heartbeat": "10s",
      "tls": {
        "enabled": True,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}",
        "alpn": ["${DEFAULT_ALPN}"]
      }
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"final": "direct"}
}
Path("${CONFIG_FILE}").write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
PY
  chown root:"$GROUP_NAME" "$CONFIG_FILE"
  chmod 640 "$CONFIG_FILE"
}

write_service() {
  log "写入 systemd 服务：${SERVICE_NAME}.service。"
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SERVICE
[Unit]
Description=sing-box TUIC v5 Server
Documentation=https://sing-box.sagernet.org/configuration/inbound/tuic/
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${GROUP_NAME}
ExecStart=/usr/local/bin/sing-box run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
}

validate_and_start() {
  log "检查 sing-box 配置。"
  /usr/local/bin/sing-box check -c "$CONFIG_FILE" || die "sing-box 配置检查失败。"
  if ! port_available; then
    die "UDP ${PORT} 已被其他进程占用。请换端口：bash install.tuic5.sh --port <端口>"
  fi
  log "启动 ${SERVICE_NAME}。"
  systemctl enable --now "${SERVICE_NAME}.service"
  sleep 1
  systemctl is-active --quiet "${SERVICE_NAME}.service" || {
    journalctl -u "${SERVICE_NAME}" -e --no-pager || true
    die "${SERVICE_NAME} 启动失败。"
  }
}

get_public_ipv4() {
  curl -4fsS --max-time 6 https://api.ipify.org 2>/dev/null || \
  curl -4fsS --max-time 6 https://icanhazip.com 2>/dev/null | tr -d '[:space:]' || \
  hostname -I | awk '{print $1}'
}

get_public_ipv6() {
  curl -6fsS --max-time 6 https://api64.ipify.org 2>/dev/null || true
}

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

write_client_files() {
  local ip4 ip6 name primary_url compat_url b64_url sub_token web_dir raw_sub cert_fingerprint_b64
  ip4="$(get_public_ipv4 || true)"
  ip6="$(get_public_ipv6 || true)"
  [[ -n "$ip4" ]] || ip4="你的VPS_IP"
  name="TUIC5-${ip4}-${PORT}"
  cert_fingerprint_b64="$(openssl x509 -in "$CERT_FILE" -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64 | tr -d '\n')"

  primary_url="tuic://${UUID}:$(urlencode "$PASSWORD")@${ip4}:${PORT}?congestion_control=${CONGESTION_CONTROL}&udp_relay_mode=native&alpn=${DEFAULT_ALPN}&sni=$(urlencode "$SNI")&allow_insecure=1#$(urlencode "$name")"
  compat_url="tuic://${UUID}:$(urlencode "$PASSWORD")@${ip4}:${PORT}?congestion-control=${CONGESTION_CONTROL}&udp-relay-mode=native&alpn=${DEFAULT_ALPN}&sni=$(urlencode "$SNI")&allow-insecure=1#$(urlencode "${name}-compat")"

  cat > "$CLIENT_FILE" <<CLIENT
TUIC v5 节点信息

协议：TUIC v5
核心：sing-box
端口：${PORT}/udp
地址：${ip4}
UUID：${UUID}
密码：${PASSWORD}
SNI：${SNI}
ALPN：${DEFAULT_ALPN}
拥塞控制：${CONGESTION_CONTROL}
UDP relay mode：native
TLS：自签证书 + allow_insecure=1
证书公钥 SHA256：${cert_fingerprint_b64}

Shadowrocket / 小火箭优先导入链接：
${primary_url}

兼容字段备用链接：
${compat_url}
CLIENT

  if [[ -n "$ip6" ]]; then
    local name6 url6
    name6="TUIC5-IPv6-${PORT}"
    url6="tuic://${UUID}:$(urlencode "$PASSWORD")@[${ip6}]:${PORT}?congestion_control=${CONGESTION_CONTROL}&udp_relay_mode=native&alpn=${DEFAULT_ALPN}&sni=$(urlencode "$SNI")&allow_insecure=1#$(urlencode "$name6")"
    cat >> "$CLIENT_FILE" <<CLIENT

IPv6 链接：
${url6}
CLIENT
  fi

  cat > "$CLIENT_JSON" <<CLIENTJSON
{
  "type": "tuic",
  "tag": "tuic5-out",
  "server": "${ip4}",
  "server_port": ${PORT},
  "uuid": "${UUID}",
  "password": "${PASSWORD}",
  "congestion_control": "${CONGESTION_CONTROL}",
  "udp_relay_mode": "native",
  "zero_rtt_handshake": false,
  "heartbeat": "10s",
  "tls": {
    "enabled": true,
    "server_name": "${SNI}",
    "insecure": true,
    "alpn": ["${DEFAULT_ALPN}"],
    "certificate_public_key_sha256": ["${cert_fingerprint_b64}"]
  }
}
CLIENTJSON

  chmod 600 "$CLIENT_FILE"
  chmod 640 "$CLIENT_JSON"
  chown root:"$GROUP_NAME" "$CLIENT_JSON"

  raw_sub="/root/all-proxy-subscription.txt"
  {
    grep -hE '^vless://' /root/xray-reality-client.txt 2>/dev/null || true
    grep -hE '^hysteria2://' /root/hysteria2-client.txt 2>/dev/null || true
    grep -hE '^hy2://' /root/hysteria2-client.txt 2>/dev/null || true
    grep -hE '^ss://' /root/shadowsocks2022-client.txt 2>/dev/null || true
    grep -hE '^vless://' /root/xray-xhttp-reality-client.txt 2>/dev/null || true
    grep -hE '^tuic://' "$CLIENT_FILE" 2>/dev/null || true
  } | awk 'NF && !seen[$0]++' > "$raw_sub"

  if [[ -d /var/www/html || -d /usr/share/nginx/html ]]; then
    if [[ -d /var/www/html ]]; then
      web_dir="/var/www/html/assets"
    else
      web_dir="/usr/share/nginx/html/assets"
    fi
    install -d -m 0755 "$web_dir"
    sub_token="$(openssl rand -hex 16)"
    cp "$raw_sub" "$web_dir/${sub_token}-all.txt"
    base64 -w0 "$raw_sub" > "$web_dir/${sub_token}-all.b64"
    chmod 644 "$web_dir/${sub_token}-all.txt" "$web_dir/${sub_token}-all.b64"
    cat >> "$CLIENT_FILE" <<CLIENT

整合订阅 URL：
http://${ip4}/assets/${sub_token}-all.txt

Base64 整合订阅：
http://${ip4}/assets/${sub_token}-all.b64
CLIENT
  fi
}

print_result() {
  echo
  echo "------------------------------------------------------------"
  log "TUIC v5 安装完成。"
  echo "客户端信息：cat ${CLIENT_FILE}"
  echo "服务状态：systemctl status ${SERVICE_NAME} --no-pager"
  echo "日志查看：journalctl -u ${SERVICE_NAME} -e --no-pager"
  echo "监听检查：ss -lunp | grep ':${PORT}'"
  echo
  cat "$CLIENT_FILE"
  echo
  warn "请确认 VPS 服务商后台/系统防火墙已放行 UDP ${PORT}。"
  echo "------------------------------------------------------------"
}

main() {
  detect_os
  install_dependencies
  optimize_kernel
  create_user_and_dirs
  install_sing_box
  load_or_generate_state
  write_config
  write_service
  validate_and_start
  write_client_files
  print_result
}

main "$@"
