#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="hysteria2-porthop-debian"
STATE_DIR="/etc/${PROJECT_NAME}"
INFO_FILE="/root/hysteria2-client.txt"
SYSCTL_FILE="/etc/sysctl.d/99-hysteria2-performance.conf"
SERVICE_NAME="hysteria-server.service"

log() { printf '\033[0;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }

[[ "${EUID}" -eq 0 ]] || { echo "请用 root 运行：sudo bash uninstall.sh" >&2; exit 1; }

SUB_TOKEN=""
if [[ -f "${STATE_DIR}/client.env" ]]; then
  # shellcheck disable=SC1091
  . "${STATE_DIR}/client.env" || true
fi

log "停止并卸载 Hysteria2 官方服务。"
if command -v hysteria >/dev/null 2>&1 || [[ -f /etc/systemd/system/${SERVICE_NAME} ]]; then
  bash <(curl -fsSL https://get.hy2.sh/) --remove || warn "官方卸载脚本执行失败，请手动检查 hysteria-server 服务。"
fi

log "清理本脚本生成的配置、状态和 systemd drop-in。"
rm -rf /etc/hysteria
rm -rf "$STATE_DIR"
rm -f "$INFO_FILE"
rm -rf "/etc/systemd/system/${SERVICE_NAME}.d"
rm -f "$SYSCTL_FILE"

if [[ -n "${SUB_TOKEN:-}" ]]; then
  rm -f "/var/www/html/assets/${SUB_TOKEN}.txt"
  rm -f "/var/www/xray-reality/html/assets/${SUB_TOKEN}.txt"
fi

systemctl daemon-reload || true
sysctl --system >/dev/null 2>&1 || true

log "卸载完成。Xray/REALITY、nginx 主配置和已有订阅不会被删除。"
