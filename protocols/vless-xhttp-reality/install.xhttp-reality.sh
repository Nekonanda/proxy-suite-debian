#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="xray-vless-xhttp-reality"
CONFIG_PATH="/usr/local/etc/xray/config.json"
STATE_DIR="/etc/${PROJECT_NAME}"
STATE_FILE="${STATE_DIR}/state.env"
CLIENT_FILE="/root/xray-xhttp-reality-client.txt"
COMBINED_FILE="/root/all-proxy-subscription.txt"
SYSCTL_FILE="/etc/sysctl.d/99-xray-xhttp-reality-performance.conf"
INBOUND_TAG="vless-xhttp-reality"
PORT="9443"
REALITY_SNI="www.microsoft.com"
REALITY_TARGET="www.microsoft.com:443"
NODE_NAME=""
XHTTP_PATH=""
UPDATE_XRAY="0"
KERNEL_TUNE="1"
PUBLIC_HOST=""
UUID=""
SHORT_ID=""
PRIVATE_KEY=""
PUBLIC_KEY=""
SPIDER_X=""

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '[+] %s\n' "$*"; }
warn() { yellow "[!] $*"; }
die() { red "[ERROR] $*"; exit 1; }

usage() {
  cat <<USAGE
${PROJECT_NAME} 一键附加安装脚本

用途：在现有 Xray 服务器上追加 VLESS + XHTTP + REALITY inbound，不覆盖已有 REALITY/HY2/SS2022。

默认参数：
  端口: ${PORT}/tcp
  REALITY SNI: ${REALITY_SNI}
  REALITY target: ${REALITY_TARGET}

用法：
  bash install.xhttp-reality.sh
  bash install.xhttp-reality.sh --port 9443
  bash install.xhttp-reality.sh --sni www.microsoft.com --target www.microsoft.com:443
  bash install.xhttp-reality.sh --update-xray

参数：
  --port <端口>              新 XHTTP REALITY 入站端口，默认 9443
  --sni <域名>               REALITY serverName / SNI，默认 www.microsoft.com
  --target <域名:端口>       REALITY fallback target，默认 www.microsoft.com:443
  --path <路径>              XHTTP path，默认随机，例如 /xhttp-abcd1234
  --node-name <名称>         客户端节点名称，默认自动生成
  --public-host <IP/域名>    手动指定客户端连接地址，默认自动探测公网 IP
  --uuid <UUID>              手动指定 VLESS UUID，默认自动生成
  --update-xray              即使已安装 Xray，也调用 XTLS 官方脚本更新
  --no-kernel-tune           不写入内核优化参数
  -h, --help                 显示帮助

安装后：
  cat /root/xray-xhttp-reality-client.txt

注意：
  需要在 VPS 服务商后台放行 TCP 端口，例如 TCP ${PORT}。
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    --sni) REALITY_SNI="${2:-}"; shift 2 ;;
    --target) REALITY_TARGET="${2:-}"; shift 2 ;;
    --path) XHTTP_PATH="${2:-}"; shift 2 ;;
    --node-name) NODE_NAME="${2:-}"; shift 2 ;;
    --public-host) PUBLIC_HOST="${2:-}"; shift 2 ;;
    --uuid) UUID="${2:-}"; shift 2 ;;
    --update-xray) UPDATE_XRAY="1"; shift ;;
    --no-kernel-tune) KERNEL_TUNE="0"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1。运行 --help 查看用法。" ;;
  esac
done

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请用 root 用户运行。"
}

validate_args() {
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "端口必须是数字。"
  (( PORT >= 1 && PORT <= 65535 )) || die "端口范围必须是 1-65535。"
  [[ -n "$REALITY_SNI" ]] || die "--sni 不能为空。"
  [[ -n "$REALITY_TARGET" && "$REALITY_TARGET" == *:* ]] || die "--target 必须类似 www.microsoft.com:443。"
  if [[ -n "$XHTTP_PATH" ]]; then
    [[ "$XHTTP_PATH" == /* ]] || XHTTP_PATH="/${XHTTP_PATH}"
    [[ "$XHTTP_PATH" =~ ^/[A-Za-z0-9._~/-]+$ ]] || die "XHTTP path 只能包含常见 URL path 字符。"
  fi
}

check_debian() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "当前系统不是 Debian。"
  case "${VERSION_ID:-}" in
    12|13) green "[+] 检测到 Debian ${VERSION_ID}。" ;;
    *) die "仅支持 Debian 12/13，当前 VERSION_ID=${VERSION_ID:-unknown}。" ;;
  esac
  command -v systemctl >/dev/null 2>&1 || die "未检测到 systemd，脚本需要 systemd 管理 Xray。"
}

wait_for_apt_lock() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
  local waited=0
  while true; do
    local busy=0
    for lock in "${locks[@]}"; do
      if command -v fuser >/dev/null 2>&1 && fuser "$lock" >/dev/null 2>&1; then
        busy=1
        break
      fi
    done
    if [[ "$busy" -eq 0 ]]; then
      break
    fi
    if (( waited >= 300 )); then
      die "apt/dpkg 锁等待超过 5 分钟，请稍后重试或检查 apt 进程。"
    fi
    info "apt/dpkg 正在运行，等待 5 秒..."
    sleep 5
    waited=$((waited + 5))
  done
}

install_deps() {
  info "安装基础依赖：curl、openssl、python3、iproute2、procps 等。"
  wait_for_apt_lock
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl openssl python3 iproute2 procps coreutils sed gawk
}

tune_kernel() {
  [[ "$KERNEL_TUNE" == "1" ]] || { warn "已跳过内核优化。"; return; }
  info "写入 Debian 12/13 兼容的稳健型内核优化。"
  modprobe tcp_bbr 2>/dev/null || true
  cat > "$SYSCTL_FILE" <<'SYSCTL'
# Managed by xray-vless-xhttp-reality-debian.
# Debian 13 no longer honors /etc/sysctl.conf at boot; keep local settings in /etc/sysctl.d/*.conf.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_max_syn_backlog = 65535
net.core.somaxconn = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
SYSCTL
  sysctl --system >/dev/null || warn "部分 sysctl 参数应用失败，脚本会继续；请稍后用 sysctl --system 检查。"
}

install_or_update_xray() {
  if command -v /usr/local/bin/xray >/dev/null 2>&1; then
    green "[+] 检测到已安装 Xray：$(/usr/local/bin/xray version | head -n1 || true)"
    if [[ "$UPDATE_XRAY" == "1" ]]; then
      info "使用 XTLS 官方安装脚本更新 Xray-core。"
      bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    else
      warn "为避免影响现有节点，默认不更新 Xray；如果需要更新，重新运行时加 --update-xray。"
    fi
  else
    info "未检测到 Xray，使用 XTLS 官方安装脚本安装 Xray-core。"
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  fi
  [[ -x /usr/local/bin/xray ]] || die "Xray 安装失败。"
  install -d -m 0755 "$(dirname "$CONFIG_PATH")"
  if [[ ! -f "$CONFIG_PATH" ]]; then
    cat > "$CONFIG_PATH" <<'JSON'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
JSON
  fi
}

parse_x25519() {
  local key_output
  key_output="$(/usr/local/bin/xray x25519)"
  PRIVATE_KEY="$(printf '%s\n' "$key_output" | sed -nE 's/^[[:space:]]*(Private[[:space:]]*key|PrivateKey)[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\2/Ip' | head -n1)"
  PUBLIC_KEY="$(printf '%s\n' "$key_output" | sed -nE 's/^[[:space:]]*(Public[[:space:]]*key|PublicKey|Password.*)[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\2/Ip' | head -n1)"
  if [[ -z "${PRIVATE_KEY:-}" || -z "${PUBLIC_KEY:-}" ]]; then
    printf '%s\n' "$key_output" >&2
    die "生成 REALITY x25519 密钥失败：无法解析 xray x25519 输出。"
  fi
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    [[ -n "${SAVED_UUID:-}" && -z "$UUID" ]] && UUID="$SAVED_UUID"
    [[ -n "${SAVED_SHORT_ID:-}" ]] && SHORT_ID="$SAVED_SHORT_ID"
    [[ -n "${SAVED_PRIVATE_KEY:-}" ]] && PRIVATE_KEY="$SAVED_PRIVATE_KEY"
    [[ -n "${SAVED_PUBLIC_KEY:-}" ]] && PUBLIC_KEY="$SAVED_PUBLIC_KEY"
    [[ -n "${SAVED_XHTTP_PATH:-}" && -z "$XHTTP_PATH" ]] && XHTTP_PATH="$SAVED_XHTTP_PATH"
    [[ -n "${SAVED_SPIDER_X:-}" ]] && SPIDER_X="$SAVED_SPIDER_X"
    green "[+] 已读取既有 XHTTP REALITY 身份参数，重复运行不会无故换链接。"
  fi
}

save_state() {
  install -d -m 0700 "$STATE_DIR"
  {
    printf 'SAVED_UUID=%q
' "$UUID"
    printf 'SAVED_SHORT_ID=%q
' "$SHORT_ID"
    printf 'SAVED_PRIVATE_KEY=%q
' "$PRIVATE_KEY"
    printf 'SAVED_PUBLIC_KEY=%q
' "$PUBLIC_KEY"
    printf 'SAVED_XHTTP_PATH=%q
' "$XHTTP_PATH"
    printf 'SAVED_SPIDER_X=%q
' "$SPIDER_X"
  } > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

generate_identity() {
  install -d -m 0700 "$STATE_DIR"
  load_state
  if [[ -z "$UUID" ]]; then
    UUID="$(/usr/local/bin/xray uuid)"
  fi
  if [[ -z "$SHORT_ID" ]]; then
    SHORT_ID="$(openssl rand -hex 8)"
  fi
  if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    parse_x25519
  fi
  if [[ -z "$XHTTP_PATH" ]]; then
    XHTTP_PATH="/xhttp-$(openssl rand -hex 8)"
  fi
  if [[ -z "$SPIDER_X" ]]; then
    SPIDER_X="/$(openssl rand -hex 4)"
  fi
  if [[ -z "$NODE_NAME" ]]; then
    NODE_NAME="XHTTP-REALITY-${REALITY_SNI}-${PORT}"
  fi
  save_state
}

detect_public_host() {
  if [[ -n "$PUBLIC_HOST" ]]; then
    return
  fi
  info "自动检测公网 IP。"
  PUBLIC_HOST="$(curl -4fsS --max-time 6 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$PUBLIC_HOST" ]]; then
    PUBLIC_HOST="$(curl -4fsS --max-time 6 https://icanhazip.com 2>/dev/null | tr -d '[:space:]' || true)"
  fi
  if [[ -z "$PUBLIC_HOST" ]]; then
    PUBLIC_HOST="$(curl -6fsS --max-time 6 https://api64.ipify.org 2>/dev/null || true)"
  fi
  [[ -n "$PUBLIC_HOST" ]] || die "无法自动检测公网 IP，请用 --public-host 手动指定。"
  green "[+] 公网地址：$PUBLIC_HOST"
}

port_already_declared_by_us() {
  python3 - "$CONFIG_PATH" "$INBOUND_TAG" "$PORT" <<'PY'
import json, sys
p, tag, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    data = json.load(open(p))
except Exception:
    sys.exit(1)
for inbound in data.get("inbounds", []):
    if inbound.get("tag") == tag and inbound.get("port") == port:
        sys.exit(0)
sys.exit(1)
PY
}

check_port() {
  if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:|\])${PORT}$"; then
    if port_already_declared_by_us; then
      warn "端口 ${PORT}/tcp 已由当前 XHTTP REALITY 配置使用，将进行覆盖更新。"
    else
      die "端口 ${PORT}/tcp 已被占用。请换端口：bash install.xhttp-reality.sh --port 9444"
    fi
  fi
}

patch_xray_config() {
  info "备份并追加/更新 Xray XHTTP + REALITY inbound。"
  local ts backup
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="${CONFIG_PATH}.bak.${PROJECT_NAME}.${ts}"
  cp -a "$CONFIG_PATH" "$backup"

  export XRAY_CONFIG_PATH="$CONFIG_PATH"
  export XRAY_INBOUND_TAG="$INBOUND_TAG"
  export XRAY_PORT="$PORT"
  export XRAY_UUID="$UUID"
  export XRAY_SNI="$REALITY_SNI"
  export XRAY_TARGET="$REALITY_TARGET"
  export XRAY_PRIVATE_KEY="$PRIVATE_KEY"
  export XRAY_SHORT_ID="$SHORT_ID"
  export XRAY_XHTTP_PATH="$XHTTP_PATH"

  if ! python3 <<'PY'
import json
import os
from pathlib import Path

p = Path(os.environ["XRAY_CONFIG_PATH"])
tag = os.environ["XRAY_INBOUND_TAG"]
port = int(os.environ["XRAY_PORT"])
uuid = os.environ["XRAY_UUID"]
sni = os.environ["XRAY_SNI"]
target = os.environ["XRAY_TARGET"]
private_key = os.environ["XRAY_PRIVATE_KEY"]
short_id = os.environ["XRAY_SHORT_ID"]
path = os.environ["XRAY_XHTTP_PATH"]

try:
    data = json.loads(p.read_text())
except Exception as e:
    raise SystemExit(f"无法解析 Xray JSON 配置：{e}")

if not isinstance(data, dict):
    raise SystemExit("Xray 配置顶层必须是 JSON object")

data.setdefault("log", {"loglevel": "warning"})
data.setdefault("inbounds", [])
data.setdefault("outbounds", [])
if not isinstance(data["inbounds"], list):
    raise SystemExit("inbounds 必须是数组")
if not isinstance(data["outbounds"], list):
    raise SystemExit("outbounds 必须是数组")

if not any(o.get("tag") == "direct" for o in data["outbounds"] if isinstance(o, dict)):
    data["outbounds"].append({"tag": "direct", "protocol": "freedom"})
if not any(o.get("tag") == "block" for o in data["outbounds"] if isinstance(o, dict)):
    data["outbounds"].append({"tag": "block", "protocol": "blackhole"})

inbound = {
    "tag": tag,
    "port": port,
    "protocol": "vless",
    "settings": {
        "clients": [
            {
                "id": uuid,
                "level": 0,
                "email": "xhttp-reality@local",
                "flow": ""
            }
        ],
        "decryption": "none"
    },
    "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
            "path": path
        },
        "realitySettings": {
            "show": False,
            "target": target,
            "xver": 0,
            "serverNames": [sni],
            "privateKey": private_key,
            "shortIds": [short_id]
        }
    },
    "sniffing": {
        "enabled": True,
        "destOverride": ["http", "tls", "quic"]
    }
}

data["inbounds"] = [i for i in data["inbounds"] if not (isinstance(i, dict) and i.get("tag") == tag)]
data["inbounds"].append(inbound)

p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
  then
    cp -a "$backup" "$CONFIG_PATH"
    die "修改 Xray 配置失败，已回滚。"
  fi

  info "测试 Xray 配置。"
  if ! /usr/local/bin/xray run -test -config "$CONFIG_PATH"; then
    warn "settings.clients 测试未通过，尝试回退到 settings.users 兼容字段。"
    export XRAY_CONFIG_PATH="$CONFIG_PATH"
    export XRAY_INBOUND_TAG="$INBOUND_TAG"
    python3 <<'PY_XRAY_USERS_FALLBACK'
import json, os
from pathlib import Path
p = Path(os.environ["XRAY_CONFIG_PATH"])
tag = os.environ["XRAY_INBOUND_TAG"]
data = json.loads(p.read_text())
for inbound in data.get("inbounds", []):
    if isinstance(inbound, dict) and inbound.get("tag") == tag:
        st = inbound.get("settings", {})
        if "clients" in st:
            st["users"] = st.pop("clients")
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY_XRAY_USERS_FALLBACK
    if ! /usr/local/bin/xray run -test -config "$CONFIG_PATH"; then
      cp -a "$backup" "$CONFIG_PATH"
      die "xray run -test 未通过，已回滚配置：$backup"
    fi
    warn "当前 Xray 回退到 settings.users 通过测试；如果客户端提示 invalid request user id，请优先升级 Xray 或改回 settings.clients。"
  fi

  info "重启 Xray。"
  systemctl daemon-reload
  if ! systemctl restart xray; then
    cp -a "$backup" "$CONFIG_PATH"
    systemctl restart xray || true
    die "Xray 重启失败，已回滚配置：$backup。请查看 journalctl -u xray -e --no-pager"
  fi
  systemctl enable xray >/dev/null 2>&1 || true
  green "[+] Xray 已重启，XHTTP REALITY 入站已追加。"
}

urlencode() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
}

uri_host() {
  if [[ "$PUBLIC_HOST" == *:* && "$PUBLIC_HOST" != \[*\] ]]; then
    printf '[%s]' "$PUBLIC_HOST"
  else
    printf '%s' "$PUBLIC_HOST"
  fi
}

write_client_files() {
  local host_enc name_enc path_enc spx_enc uri client_json
  host_enc="$(uri_host)"
  name_enc="$(urlencode "$NODE_NAME")"
  path_enc="$(urlencode "$XHTTP_PATH")"
  spx_enc="$(urlencode "$SPIDER_X")"
  uri="vless://${UUID}@${host_enc}:${PORT}?encryption=none&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=${spx_enc}&type=xhttp&path=${path_enc}&mode=auto#${name_enc}"
  client_json="${STATE_DIR}/client-outbound-xhttp-reality.json"

  cat > "$client_json" <<JSON
{
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${PUBLIC_HOST}",
            "port": ${PORT},
            "users": [
              {
                "id": "${UUID}",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "${XHTTP_PATH}"
        },
        "realitySettings": {
          "serverName": "${REALITY_SNI}",
          "fingerprint": "chrome",
          "password": "${PUBLIC_KEY}",
          "shortId": "${SHORT_ID}",
          "spiderX": "${SPIDER_X}"
        }
      }
    }
  ]
}
JSON
  chmod 600 "$client_json"

  cat > "$CLIENT_FILE" <<EOF_CLIENT
VLESS + XHTTP + REALITY 节点信息

协议：VLESS
传输：XHTTP
安全：REALITY
端口：${PORT}/tcp
地址：${PUBLIC_HOST}
UUID：${UUID}
SNI：${REALITY_SNI}
REALITY PublicKey / pbk：${PUBLIC_KEY}
shortId / sid：${SHORT_ID}
spiderX：${SPIDER_X}
XHTTP path：${XHTTP_PATH}
flow：空，不使用 xtls-rprx-vision

Shadowrocket / 小火箭可尝试导入 vless:// 链接：
${uri}

如果小火箭暂时不识别 XHTTP 参数，请保留下面这个 Xray 客户端 JSON 参考：
${client_json}

服务检查：
systemctl status xray --no-pager
journalctl -u xray -e --no-pager
ss -ltnp | grep ':${PORT}'

防火墙提醒：
请在 VPS 服务商后台放行 TCP ${PORT}。
EOF_CLIENT
  chmod 600 "$CLIENT_FILE"
  green "[+] 已生成客户端信息：$CLIENT_FILE"
}

update_combined_subscription() {
  info "生成/更新本机整合订阅文件。"
  python3 - <<'PY'
from pathlib import Path
import base64

sources = [
    Path('/root/xray-reality-client.txt'),
    Path('/root/hysteria2-client.txt'),
    Path('/root/shadowsocks2022-client.txt'),
    Path('/root/xray-xhttp-reality-client.txt'),
]
links = []
seen = set()
for p in sources:
    if not p.exists():
        continue
    for line in p.read_text(errors='ignore').splitlines():
        s = line.strip()
        if s.startswith(('vless://', 'hysteria2://', 'hy2://', 'ss://')) and s not in seen:
            seen.add(s)
            links.append(s)
text = '\n'.join(links) + ('\n' if links else '')
Path('/root/all-proxy-subscription.txt').write_text(text)
Path('/root/all-proxy-subscription.b64').write_text(base64.b64encode(text.encode()).decode() + '\n')
print(f'已写入 {len(links)} 条链接到 /root/all-proxy-subscription.txt')
PY

  if [[ -d /var/www/html ]]; then
    local token host url
    install -d -m 0755 /var/www/html/assets
    token="$(openssl rand -hex 16)"
    cp -f /root/all-proxy-subscription.txt "/var/www/html/assets/${token}-all.txt"
    cp -f /root/all-proxy-subscription.b64 "/var/www/html/assets/${token}-all.b64"
    chmod 644 "/var/www/html/assets/${token}-all.txt" "/var/www/html/assets/${token}-all.b64"
    host="$(uri_host)"
    url="http://${host}/assets/${token}-all.txt"
    cat >> "$CLIENT_FILE" <<EOF_SUB

整合订阅 URL，包含当前可识别的 vless/hysteria2/hy2/ss 链接：
${url}

Base64 整合订阅：
http://${host}/assets/${token}-all.b64
EOF_SUB
    green "[+] 已写入 Nginx assets 整合订阅：$url"
  else
    warn "未发现 /var/www/html，仅生成 /root/all-proxy-subscription.txt。"
  fi
}

print_summary() {
  green "------------------------------------------------------------"
  green "VLESS + XHTTP + REALITY 附加安装完成。"
  green "客户端信息：cat $CLIENT_FILE"
  green "整合订阅：cat $COMBINED_FILE"
  green "服务状态：systemctl status xray --no-pager"
  yellow "请确认 VPS 服务商后台已放行 TCP ${PORT}。"
  green "------------------------------------------------------------"
}

main() {
  require_root
  validate_args
  check_debian
  install_deps
  tune_kernel
  install_or_update_xray
  generate_identity
  detect_public_host
  check_port
  patch_xray_config
  write_client_files
  update_combined_subscription
  print_summary
}

main "$@"
