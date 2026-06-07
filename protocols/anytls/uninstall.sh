#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="sing-box-anytls"
SERVICE_USER="singbox-anytls"
SERVICE_GROUP="singbox-anytls"
CONFIG_DIR="/etc/sing-box-anytls"
LOG_DIR="/var/log/sing-box-anytls"
BIN_PATH="/usr/local/bin/sing-box-anytls"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SYSCTL_FILE="/etc/sysctl.d/99-anytls-performance.conf"
CLIENT_INFO="/root/anytls-client.txt"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
warn() { yellow "[!] $*"; }
info() { green "[+] $*"; }
die() { red "[ERROR] $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Please run as root."

read -r -p "This will remove AnyTLS service and files. Continue? [y/N] " ans
case "${ans:-}" in
  y|Y|yes|YES) ;;
  *) echo "Cancelled."; exit 0 ;;
esac

info "Stopping service."
systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
rm -f "$SYSTEMD_FILE"
systemctl daemon-reload
systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true

info "Removing files."
rm -f "$BIN_PATH"
rm -rf "$CONFIG_DIR" "$LOG_DIR"
rm -f "$SYSCTL_FILE"
rm -f "$CLIENT_INFO"

if id "$SERVICE_USER" >/dev/null 2>&1; then
  userdel "$SERVICE_USER" >/dev/null 2>&1 || warn "Failed to remove user ${SERVICE_USER}."
fi
if getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
  groupdel "$SERVICE_GROUP" >/dev/null 2>&1 || true
fi

sysctl --system >/dev/null 2>&1 || true

green "AnyTLS has been removed. Other protocols and services were not touched."
