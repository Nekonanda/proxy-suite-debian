#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

INSTALL_SCRIPT_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
STATE_DIR="/etc/xray-reality"
SYSCTL_CONF="/etc/sysctl.d/99-xray-reality-performance.conf"
MODULES_CONF="/etc/modules-load.d/99-xray-reality-bbr.conf"
NGINX_SITE="/etc/nginx/sites-available/xray-reality-decoy"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/xray-reality-decoy"
WEB_ROOT="/var/www/reality-decoy"
INFO_FILE="/root/xray-reality-client.txt"

[[ "${EUID}" -eq 0 ]] || { echo "请用 root 运行：sudo bash uninstall.sh" >&2; exit 1; }

PURGE="0"
if [[ "${1:-}" == "--purge" ]]; then
  PURGE="1"
fi

echo "[+] 停止并移除 Xray 服务。"
tmpdir="$(mktemp -d)"
if curl -fsSL "$INSTALL_SCRIPT_URL" -o "${tmpdir}/install-release.sh"; then
  if [[ "$PURGE" == "1" ]]; then
    bash "${tmpdir}/install-release.sh" remove --purge || true
  else
    bash "${tmpdir}/install-release.sh" remove || true
  fi
else
  systemctl disable --now xray 2>/dev/null || true
fi
rm -rf "$tmpdir"

echo "[+] 移除本项目写入的 sysctl、订阅页和状态文件。"
rm -f "$SYSCTL_CONF" "$MODULES_CONF" "$NGINX_SITE_LINK" "$NGINX_SITE" "$INFO_FILE"
rm -rf "$STATE_DIR" "$WEB_ROOT"

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
fi

if command -v sysctl >/dev/null 2>&1; then
  sysctl --system >/dev/null 2>&1 || true
fi

echo "[+] 已完成。nginx 软件包本身不会自动卸载，避免误删你机器上的其它站点。"
