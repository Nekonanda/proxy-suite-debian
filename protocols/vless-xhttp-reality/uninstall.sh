#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="xray-vless-xhttp-reality"
CONFIG_PATH="/usr/local/etc/xray/config.json"
STATE_DIR="/etc/${PROJECT_NAME}"
CLIENT_FILE="/root/xray-xhttp-reality-client.txt"
SYSCTL_FILE="/etc/sysctl.d/99-xray-xhttp-reality-performance.conf"
INBOUND_TAG="vless-xhttp-reality"
REMOVE_SYSCTL="0"

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '[+] %s\n' "$*"; }
die() { red "[ERROR] $*"; exit 1; }

usage() {
  cat <<USAGE
卸载 VLESS + XHTTP + REALITY 附加 inbound，不卸载 Xray，不影响已有 REALITY/HY2/SS2022。

用法：
  bash uninstall.sh
  bash uninstall.sh --remove-sysctl

参数：
  --remove-sysctl    同时删除本脚本写入的 /etc/sysctl.d/99-xray-xhttp-reality-performance.conf
  -h, --help         显示帮助
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-sysctl) REMOVE_SYSCTL="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "请用 root 用户运行。"
[[ -f "$CONFIG_PATH" ]] || die "未找到 $CONFIG_PATH"

backup="${CONFIG_PATH}.bak.${PROJECT_NAME}.uninstall.$(date +%Y%m%d-%H%M%S)"
cp -a "$CONFIG_PATH" "$backup"

export XRAY_CONFIG_PATH="$CONFIG_PATH"
export XRAY_INBOUND_TAG="$INBOUND_TAG"
python3 <<'PY'
import json, os
from pathlib import Path
p = Path(os.environ['XRAY_CONFIG_PATH'])
tag = os.environ['XRAY_INBOUND_TAG']
data = json.loads(p.read_text())
inbounds = data.get('inbounds', [])
if not isinstance(inbounds, list):
    raise SystemExit('inbounds 不是数组，无法安全卸载')
new_inbounds = [i for i in inbounds if not (isinstance(i, dict) and i.get('tag') == tag)]
removed = len(inbounds) - len(new_inbounds)
data['inbounds'] = new_inbounds
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
print(f'已移除 {removed} 个 inbound')
PY

if ! /usr/local/bin/xray run -test -config "$CONFIG_PATH"; then
  cp -a "$backup" "$CONFIG_PATH"
  die "卸载后的 Xray 配置测试失败，已回滚：$backup"
fi

if ! systemctl restart xray; then
  cp -a "$backup" "$CONFIG_PATH"
  systemctl restart xray || true
  die "Xray 重启失败，已回滚：$backup"
fi

rm -rf "$STATE_DIR"
rm -f "$CLIENT_FILE"
if [[ "$REMOVE_SYSCTL" == "1" ]]; then
  rm -f "$SYSCTL_FILE"
  sysctl --system >/dev/null || true
fi

green "[+] 已卸载 VLESS + XHTTP + REALITY inbound。"
yellow "未卸载 Xray，也未触碰已有 REALITY/HY2/SS2022。"
