#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="trojan-debian"
SERVICE_NAME="sing-box-trojan"
SERVICE_USER="singbox-trojan"
SERVICE_GROUP="singbox-trojan"
CONFIG_DIR="/etc/sing-box-trojan"
CERT_DIR="${CONFIG_DIR}/certs"
STATE_FILE="${CONFIG_DIR}/state.env"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CLIENT_JSON="${CONFIG_DIR}/client-outbound-trojan.json"
LOG_DIR="/var/log/sing-box-trojan"
BIN_PATH="/usr/local/bin/sing-box-trojan"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SYSCTL_FILE="/etc/sysctl.d/99-trojan-performance.conf"
CLIENT_INFO="/root/trojan-client.txt"
ALL_SUB="/root/all-proxy-subscription.txt"
WEB_ASSETS_DIR="/var/www/html/assets"

DEFAULT_PORT="12443"
DEFAULT_SNI="www.bing.com"
PORT="$DEFAULT_PORT"
SNI="$DEFAULT_SNI"
PASSWORD=""
PUBLIC_HOST=""
FORCE_NEW_PASSWORD="0"
NO_WEB_SUB="0"
PORT_SET="0"
SNI_SET="0"
PASSWORD_SET="0"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { green "[+] $*"; }
warn() { yellow "[!] $*"; }
die() { red "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<USAGE
Trojan installer for Debian 12/13

Usage:
  bash install.trojan.sh [options]

Options:
  --port PORT              TCP port for Trojan. Default: ${DEFAULT_PORT}
  --sni DOMAIN             SNI used by client links. Default: ${DEFAULT_SNI}
  --password PASSWORD      Use a custom Trojan password.
  --host HOST              Public host/IP used in client links. Auto-detected by default.
  --force-new-password     Generate a new password even if state exists.
  --no-web-sub             Do not publish subscription files to /var/www/html/assets.
  -h, --help               Show this help.

Examples:
  bash install.trojan.sh
  bash install.trojan.sh --port 12443
  bash install.trojan.sh --host 203.0.113.10 --sni www.bing.com
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        [[ $# -ge 2 ]] || die "--port requires a value"
        PORT="$2"; PORT_SET="1"; shift 2 ;;
      --sni)
        [[ $# -ge 2 ]] || die "--sni requires a value"
        SNI="$2"; SNI_SET="1"; shift 2 ;;
      --password)
        [[ $# -ge 2 ]] || die "--password requires a value"
        PASSWORD="$2"; PASSWORD_SET="1"; shift 2 ;;
      --host)
        [[ $# -ge 2 ]] || die "--host requires a value"
        PUBLIC_HOST="$2"; shift 2 ;;
      --force-new-password)
        FORCE_NEW_PASSWORD="1"; shift ;;
      --no-web-sub)
        NO_WEB_SUB="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "Unknown option: $1" ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Please run as root."
}

validate_port() {
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "Invalid port: $PORT"
  (( PORT >= 1 && PORT <= 65535 )) || die "Port out of range: $PORT"
}

validate_sni() {
  [[ -n "$SNI" ]] || die "SNI cannot be empty."
  [[ "$SNI" != *" "* ]] || die "SNI must not contain spaces."
}

detect_debian() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "This installer is designed for Debian 12/13. Current ID=${ID:-unknown}"
  case "${VERSION_ID:-}" in
    12|13) info "Detected Debian ${VERSION_ID}." ;;
    *) warn "Current Debian version is ${VERSION_ID:-unknown}; script is tested for Debian 12/13." ;;
  esac
  command -v systemctl >/dev/null 2>&1 || die "systemd is required."
}

wait_apt_lock() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
  local waited=0
  while true; do
    local busy=0
    for lock in "${locks[@]}"; do
      if fuser "$lock" >/dev/null 2>&1; then
        busy=1
      fi
    done
    if [[ "$busy" -eq 0 ]]; then
      break
    fi
    warn "apt/dpkg is busy, waiting 5 seconds..."
    sleep 5
    waited=$((waited + 5))
    (( waited <= 600 )) || die "apt/dpkg lock did not clear after 10 minutes."
  done
}

install_dependencies() {
  info "Installing required packages."
  wait_apt_lock
  apt-get update
  wait_apt_lock
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl openssl tar gzip coreutils procps iproute2 sed grep gawk python3
}

setup_user_dirs() {
  info "Creating dedicated user and directories."
  if ! getent group "$SERVICE_GROUP" >/dev/null; then
    groupadd --system "$SERVICE_GROUP"
  fi
  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir /nonexistent \
      --shell /usr/sbin/nologin --gid "$SERVICE_GROUP" "$SERVICE_USER"
  fi

  install -d -m 0750 -o root -g "$SERVICE_GROUP" "$CONFIG_DIR"
  install -d -m 0750 -o root -g "$SERVICE_GROUP" "$CERT_DIR"
  install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$LOG_DIR"
}

install_sing_box() {
  info "Downloading latest stable sing-box release from GitHub."
  local uname_arch asset_arch api_json download_url tmpdir archive bin version
  uname_arch="$(uname -m)"
  case "$uname_arch" in
    x86_64|amd64) asset_arch="linux-amd64" ;;
    aarch64|arm64) asset_arch="linux-arm64" ;;
    armv7l|armv7*) asset_arch="linux-armv7" ;;
    armv6l|armv6*) asset_arch="linux-armv6" ;;
    *) die "Unsupported architecture: $uname_arch" ;;
  esac

  api_json="$(curl -fsSL --retry 3 https://api.github.com/repos/SagerNet/sing-box/releases/latest)" || die "Failed to fetch sing-box release metadata."
  download_url="$(printf '%s' "$api_json" | grep -Eo '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+sing-box-[^"]+-'"$asset_arch"'\.tar\.gz"' | sed -E 's/^.*"([^"]+)"$/\1/' | head -n1)"
  [[ -n "$download_url" ]] || die "Could not find sing-box asset for ${asset_arch}."

  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/sing-box.tar.gz"
  curl -fL --retry 3 -o "$archive" "$download_url" || die "Failed to download sing-box archive."
  tar -xzf "$archive" -C "$tmpdir" || die "Failed to extract sing-box archive."
  bin="$(find "$tmpdir" -type f -name sing-box | head -n1)"
  [[ -n "$bin" ]] || die "sing-box binary not found in archive."
  install -m 0755 "$bin" "$BIN_PATH"
  rm -rf "$tmpdir"

  version="$($BIN_PATH version | head -n1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  [[ -n "$version" ]] || die "Unable to parse sing-box version."
  info "Installed sing-box ${version} to ${BIN_PATH}."
}

save_state() {
  {
    printf 'PORT=%q\n' "$PORT"
    printf 'SNI=%q\n' "$SNI"
    printf 'PASSWORD=%q\n' "$PASSWORD"
  } > "$STATE_FILE"
  chown root:"$SERVICE_GROUP" "$STATE_FILE"
  chmod 0640 "$STATE_FILE"
}

load_or_create_state() {
  local requested_port requested_sni requested_password stored_port stored_sni stored_password
  requested_port="$PORT"
  requested_sni="$SNI"
  requested_password="$PASSWORD"
  stored_port=""
  stored_sni=""
  stored_password=""

  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    stored_port="${PORT:-}"
    stored_sni="${SNI:-}"
    stored_password="${PASSWORD:-}"
  fi

  if [[ "$PORT_SET" == "1" ]]; then
    PORT="$requested_port"
  else
    PORT="${stored_port:-$DEFAULT_PORT}"
  fi

  if [[ "$SNI_SET" == "1" ]]; then
    SNI="$requested_sni"
  else
    SNI="${stored_sni:-$DEFAULT_SNI}"
  fi

  if [[ "$PASSWORD_SET" == "1" ]]; then
    PASSWORD="$requested_password"
  elif [[ "$FORCE_NEW_PASSWORD" == "1" || -z "$stored_password" ]]; then
    PASSWORD="$(openssl rand -hex 24)"
  else
    PASSWORD="$stored_password"
  fi

  save_state
}

get_public_host() {
  if [[ -n "$PUBLIC_HOST" ]]; then
    return
  fi
  local ip
  ip="$(curl -4fsS --max-time 6 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -6fsS --max-time 6 https://api64.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -n "$ip" ]] || die "Could not auto-detect public IP. Use --host HOST."
  PUBLIC_HOST="$ip"
}

make_self_signed_cert() {
  info "Generating self-signed TLS certificate."
  local cert key san_arg
  cert="${CERT_DIR}/cert.pem"
  key="${CERT_DIR}/private.key"

  rm -f "$cert" "$key"
  san_arg="DNS:${SNI}"
  if [[ "$PUBLIC_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    san_arg="${san_arg},IP:${PUBLIC_HOST}"
  elif [[ "$PUBLIC_HOST" == *:* ]]; then
    san_arg="${san_arg},IP:${PUBLIC_HOST}"
  elif [[ "$PUBLIC_HOST" == *.* ]]; then
    san_arg="${san_arg},DNS:${PUBLIC_HOST}"
  fi

  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$key" -out "$cert" \
    -subj "/CN=${SNI}" \
    -addext "subjectAltName=${san_arg}" >/dev/null 2>&1 || die "Failed to generate self-signed certificate."

  chown root:"$SERVICE_GROUP" "$cert" "$key"
  chmod 0644 "$cert"
  chmod 0640 "$key"
}

write_config() {
  info "Writing sing-box Trojan config."
  cat > "$CONFIG_FILE" <<JSON
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "name": "trojan-user",
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_DIR}/cert.pem",
        "key_path": "${CERT_DIR}/private.key",
        "min_version": "1.2"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "direct"
  }
}
JSON
  chown root:"$SERVICE_GROUP" "$CONFIG_FILE"
  chmod 0640 "$CONFIG_FILE"
}

write_systemd() {
  info "Writing systemd service."
  cat > "$SYSTEMD_FILE" <<SERVICE
[Unit]
Description=sing-box Trojan Service
Documentation=https://sing-box.sagernet.org/configuration/inbound/trojan/
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=${BIN_PATH} run -c ${CONFIG_FILE}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SERVICE
}

apply_sysctl() {
  info "Writing conservative TCP kernel tuning."
  cat > "$SYSCTL_FILE" <<SYSCTL
# Conservative network tuning for Trojan / TCP proxy workloads.
# Debian 13 uses systemd-sysctl with /etc/sysctl.d/*.conf.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
SYSCTL
  sysctl --system >/dev/null || warn "Some sysctl settings failed to apply; continuing."
}

check_port_available() {
  info "Checking TCP port ${PORT}."
  systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  if ss -H -ltn "sport = :${PORT}" | grep -q .; then
    ss -ltnp "sport = :${PORT}" || true
    die "TCP port ${PORT} is already in use. Use --port PORT to choose another port."
  fi
}

check_and_start() {
  info "Checking sing-box configuration."
  "$BIN_PATH" check -c "$CONFIG_FILE" || die "sing-box config check failed."

  check_port_available
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null
  systemctl restart "$SERVICE_NAME"
  sleep 1
  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -e --no-pager || true
    die "${SERVICE_NAME} failed to start."
  fi
}

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

write_client_info() {
  local enc_pass enc_name enc_sni host_for_url simple_url insecure_url slash_insecure_url allow_url skip_url
  enc_pass="$(urlencode "$PASSWORD")"
  enc_name="$(urlencode "Trojan-${PUBLIC_HOST}-${PORT}")"
  enc_sni="$(urlencode "$SNI")"

  host_for_url="$PUBLIC_HOST"
  if [[ "$host_for_url" == *:* && "$host_for_url" != \[*\] ]]; then
    host_for_url="[${host_for_url}]"
  fi

  simple_url="trojan://${enc_pass}@${host_for_url}:${PORT}#${enc_name}"
  insecure_url="trojan://${enc_pass}@${host_for_url}:${PORT}?security=tls&type=tcp&sni=${enc_sni}&insecure=1#${enc_name}"
  slash_insecure_url="trojan://${enc_pass}@${host_for_url}:${PORT}/?security=tls&type=tcp&sni=${enc_sni}&insecure=1#${enc_name}"
  allow_url="trojan://${enc_pass}@${host_for_url}:${PORT}?security=tls&type=tcp&sni=${enc_sni}&allowInsecure=1#${enc_name}"
  skip_url="trojan://${enc_pass}@${host_for_url}:${PORT}?security=tls&type=tcp&sni=${enc_sni}&skip-cert-verify=1#${enc_name}"

  cat > "$CLIENT_JSON" <<JSON
{
  "type": "trojan",
  "tag": "trojan-out",
  "server": "${PUBLIC_HOST}",
  "server_port": ${PORT},
  "password": "${PASSWORD}",
  "tls": {
    "enabled": true,
    "server_name": "${SNI}",
    "insecure": true
  }
}
JSON
  chown root:"$SERVICE_GROUP" "$CLIENT_JSON"
  chmod 0640 "$CLIENT_JSON"

  cat > "$CLIENT_INFO" <<INFO
Trojan 节点信息

协议：Trojan
核心：sing-box
地址：${PUBLIC_HOST}
端口：${PORT}/tcp
SNI：${SNI}
密码：${PASSWORD}
TLS 模式：自签证书；客户端需允许不安全证书 / insecure / skip-cert-verify

Shadowrocket / 小火箭优先尝试：
${insecure_url}

如果导入器不识别，依次尝试：
${allow_url}
${skip_url}
${slash_insecure_url}
${simple_url}

sing-box 客户端 JSON 参考：
${CLIENT_JSON}

服务检查：
systemctl status ${SERVICE_NAME} --no-pager
journalctl -u ${SERVICE_NAME} -e --no-pager
ss -ltnp | grep ':${PORT}'

防火墙提醒：
请确保 TCP ${PORT} 可访问。
INFO
  chmod 0600 "$CLIENT_INFO"
}

update_subscriptions() {
  info "Updating local combined subscription files."
  {
    grep -hE '^vless://' /root/xray-reality-client.txt 2>/dev/null || true
    grep -hE '^hysteria2://' /root/hysteria2-client.txt 2>/dev/null || true
    grep -hE '^hy2://' /root/hysteria2-client.txt 2>/dev/null || true
    grep -hE '^ss://' /root/shadowsocks2022-client.txt 2>/dev/null || true
    grep -hE '^vless://' /root/xray-xhttp-reality-client.txt 2>/dev/null || true
    grep -hE '^tuic://' /root/tuic5-client.txt 2>/dev/null || true
    grep -hE '^anytls://' /root/anytls-client.txt 2>/dev/null | head -n1 || true
    grep -hE '^trojan://' "$CLIENT_INFO" 2>/dev/null | head -n1 || true
  } | awk 'NF && !seen[$0]++' > "$ALL_SUB"
  chmod 0600 "$ALL_SUB"

  if [[ "$NO_WEB_SUB" == "1" ]]; then
    return
  fi

  if [[ -d /var/www/html ]]; then
    install -d -m 0755 "$WEB_ASSETS_DIR"
    local token raw_path b64_path
    token="$(openssl rand -hex 16)"
    raw_path="${WEB_ASSETS_DIR}/${token}-all.txt"
    b64_path="${WEB_ASSETS_DIR}/${token}-all.b64"
    cp "$ALL_SUB" "$raw_path"
    base64 -w0 "$ALL_SUB" > "$b64_path"
    chmod 0644 "$raw_path" "$b64_path"
    {
      echo
      echo "整合订阅 URL："
      echo "http://${PUBLIC_HOST}/assets/${token}-all.txt"
      echo
      echo "Base64 整合订阅："
      echo "http://${PUBLIC_HOST}/assets/${token}-all.b64"
    } >> "$CLIENT_INFO"
  fi
}

print_summary() {
  echo
  green "------------------------------------------------------------"
  green "Trojan 安装完成。"
  green "------------------------------------------------------------"
  cat "$CLIENT_INFO"
  echo
  green "------------------------------------------------------------"
}

main() {
  parse_args "$@"
  require_root
  validate_port
  validate_sni
  detect_debian
  install_dependencies
  get_public_host
  setup_user_dirs
  install_sing_box
  load_or_create_state
  validate_port
  validate_sni
  make_self_signed_cert
  write_config
  write_systemd
  apply_sysctl
  check_and_start
  write_client_info
  update_subscriptions
  print_summary
}

main "$@"
