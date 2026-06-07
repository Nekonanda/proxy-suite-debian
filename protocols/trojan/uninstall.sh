#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="sing-box-trojan"
SERVICE_USER="singbox-trojan"
SERVICE_GROUP="singbox-trojan"
CONFIG_DIR="/etc/sing-box-trojan"
LOG_DIR="/var/log/sing-box-trojan"
BIN_PATH="/usr/local/bin/sing-box-trojan"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SYSCTL_FILE="/etc/sysctl.d/99-trojan-performance.conf"
CLIENT_INFO="/root/trojan-client.txt"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { green "[+] $*"; }
warn() { yellow "[!] $*"; }
die() { red "[ERROR] $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Please run as root."

KEEP_CONFIG="0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-config)
      KEEP_CONFIG="1"; shift ;;
    -h|--help)
      cat <<USAGE
Uninstall Trojan sing-box service.

Usage:
  bash uninstall.sh [--keep-config]
USAGE
      exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

info "Stopping and disabling ${SERVICE_NAME}."
systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
rm -f "$SYSTEMD_FILE"
systemctl daemon-reload
systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true

info "Removing binary and client info."
rm -f "$BIN_PATH"
rm -f "$CLIENT_INFO"

if [[ "$KEEP_CONFIG" == "0" ]]; then
  info "Removing config and log directories."
  rm -rf "$CONFIG_DIR" "$LOG_DIR"
else
  warn "Keeping ${CONFIG_DIR} and ${LOG_DIR}."
fi

info "Removing sysctl file."
rm -f "$SYSCTL_FILE"
sysctl --system >/dev/null 2>&1 || true

if id "$SERVICE_USER" >/dev/null 2>&1; then
  userdel "$SERVICE_USER" >/dev/null 2>&1 || true
fi
if getent group "$SERVICE_GROUP" >/dev/null; then
  groupdel "$SERVICE_GROUP" >/dev/null 2>&1 || true
fi

green "Trojan service uninstalled. Existing Xray/HY2/SS2022/TUIC/AnyTLS services were not touched."
