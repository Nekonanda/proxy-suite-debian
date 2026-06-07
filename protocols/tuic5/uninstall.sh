#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="sing-box-tuic"
CONFIG_DIR="/etc/sing-box-tuic"
SYSCTL_FILE="/etc/sysctl.d/99-tuic5-quic-performance.conf"
CLIENT_FILE="/root/tuic5-client.txt"
RAW_SUB="/root/all-proxy-subscription.txt"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }

systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
systemctl reset-failed "${SERVICE_NAME}.service" 2>/dev/null || true

rm -rf "$CONFIG_DIR"
rm -f "$SYSCTL_FILE" "$CLIENT_FILE"

# 从整合订阅里移除 tuic:// 行，保留其他协议。
if [[ -f "$RAW_SUB" ]]; then
  grep -vE '^tuic://' "$RAW_SUB" > "${RAW_SUB}.tmp" || true
  mv "${RAW_SUB}.tmp" "$RAW_SUB"
fi

log "已卸载 TUIC v5 服务。"
warn "未删除 /usr/local/bin/sing-box，避免影响其他可能使用 sing-box 的服务。"
