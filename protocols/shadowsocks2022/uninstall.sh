#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="shadowsocks-rust-server"
CONFIG_DIR="/etc/shadowsocks-rust"
STATE_FILE="${CONFIG_DIR}/ss2022.env"
CLIENT_FILE="/root/shadowsocks2022-client.txt"
SYSCTL_FILE="/etc/sysctl.d/99-ss2022-performance.conf"
INSTALL_MARKER="/usr/local/share/shadowsocks2022-debian/installed-by-this-script"
SUB_ROOT="/var/www/html/assets"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

[[ "${EUID}" -eq 0 ]] || { echo "请使用 root 用户运行。" >&2; exit 1; }

SS2022_SUB_TOKEN=""
SS2022_ALL_TOKEN=""
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" || true
fi

log "停止并禁用 ${SERVICE_NAME}。"
systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload || true

log "删除 SS2022 配置和客户端文件。"
rm -rf "$CONFIG_DIR"
rm -f "$CLIENT_FILE"
rm -f "$SYSCTL_FILE"

if [[ -n "${SS2022_SUB_TOKEN:-}" && -d "$SUB_ROOT" ]]; then
  rm -f "${SUB_ROOT}/${SS2022_SUB_TOKEN}.txt" "${SUB_ROOT}/${SS2022_SUB_TOKEN}.b64"
fi

if [[ -n "${SS2022_ALL_TOKEN:-}" && -d "$SUB_ROOT" ]]; then
  rm -f "${SUB_ROOT}/${SS2022_ALL_TOKEN}-all.txt" "${SUB_ROOT}/${SS2022_ALL_TOKEN}-all.b64"
fi

if [[ -f "$INSTALL_MARKER" ]]; then
  log "删除本脚本安装的 shadowsocks-rust 二进制文件。"
  rm -f /usr/local/bin/ssserver /usr/local/bin/ssurl /usr/local/bin/sslocal
  rm -rf "$(dirname "$INSTALL_MARKER")"
else
  warn "未找到安装标记，保留 /usr/local/bin/ssserver/ssurl/sslocal，避免误删你手动安装的文件。"
fi

if [[ -x /usr/local/bin/update-proxy-subscription ]]; then
  log "刷新整合订阅，移除 SS2022 节点。"
  /usr/local/bin/update-proxy-subscription || true
fi

sysctl --system >/dev/null 2>&1 || true

cat <<EOF
卸载完成。

未触碰：
  Xray / REALITY
  Hysteria2 / HY2
  nginx 本身
  /root/xray-reality-client.txt
  /root/hysteria2-client.txt
EOF
