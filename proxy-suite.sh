#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/Nekonanda/proxy-suite-debian.git"
INSTALL_DIR="/opt/proxy-suite-debian"
REPO_DIR=""

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
blue() { printf '\033[36m%s\033[0m\n' "$*"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    red "请使用 root 用户运行。"
    echo "可以先执行：sudo -i"
    exit 1
  fi
}

detect_debian() {
  if [[ ! -r /etc/os-release ]]; then
    red "无法读取 /etc/os-release。"
    exit 1
  fi

  . /etc/os-release

  if [[ "${ID:-}" != "debian" ]]; then
    red "当前系统不是 Debian：${PRETTY_NAME:-unknown}"
    echo "本项目主要适配 Debian 12 / Debian 13。"
    exit 1
  fi

  case "${VERSION_ID:-}" in
    12|13)
      green "检测到 ${PRETTY_NAME:-Debian}。"
      ;;
    *)
      yellow "当前 Debian 版本是 ${VERSION_ID:-unknown}，本项目主要适配 Debian 12 / Debian 13。"
      read -r -p "是否继续？[y/N] " ans
      [[ "${ans,,}" == "y" ]] || exit 1
      ;;
  esac
}

wait_apt_lock() {
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    yellow "apt/dpkg 正在被其他进程占用，等待 5 秒..."
    sleep 5
  done
}

install_base_deps() {
  green "安装基础依赖：curl git unzip ca-certificates openssl 等。"
  wait_apt_lock
  apt-get update
  wait_apt_lock
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip openssl procps iproute2 coreutils sed gawk
}

find_or_clone_repo() {
  local script_dir=""
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P || true)"

  if [[ -d "$(pwd)/protocols" && -d "$(pwd)/tools" ]]; then
    REPO_DIR="$(pwd)"
    return 0
  fi

  if [[ -n "$script_dir" && -d "$script_dir/protocols" && -d "$script_dir/tools" ]]; then
    REPO_DIR="$script_dir"
    return 0
  fi

  green "没有检测到本地项目目录，准备克隆到 ${INSTALL_DIR}。"

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" pull --ff-only
  else
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi

  REPO_DIR="$INSTALL_DIR"
}

run_child_script() {
  local name="$1"
  shift
  local script="$1"
  shift || true

  if [[ ! -f "$script" ]]; then
    red "找不到脚本：$script"
    exit 1
  fi

  green "开始执行：$name"
  bash "$script" "$@"
}

update_subscription() {
  local script="$REPO_DIR/tools/subscription-manager/update-subscription.sh"

  green "准备生成 / 更新统一订阅。"

  wait_apt_lock
  if ! command -v nginx >/dev/null 2>&1; then
    yellow "未检测到 nginx，正在安装 nginx 用于提供 /sub/ 订阅链接。"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nginx
  fi

  install -d -m 755 /etc/nginx/conf.d
  run_child_script "统一订阅生成器" "$script"
}

ask_update_subscription() {
  echo
  read -r -p "是否现在生成/更新统一订阅？[Y/n] " ans
  case "${ans,,}" in
    n|no)
      yellow "已跳过统一订阅。"
      ;;
    *)
      update_subscription
      ;;
  esac
}

install_vless_reality() {
  run_child_script "VLESS + REALITY + Vision" "$REPO_DIR/protocols/vless-reality-vision/install.sh"
  ask_update_subscription
}

install_hy2() {
  local script="$REPO_DIR/protocols/hysteria2-porthop/install.hy2.sh"
  [[ -f "$script" ]] || script="$REPO_DIR/protocols/hysteria2-porthop/install.sh"
  run_child_script "Hysteria2 / HY2 端口跳跃" "$script"
  ask_update_subscription
}

install_ss2022() {
  local script="$REPO_DIR/protocols/shadowsocks2022/install.ss2022.sh"
  [[ -f "$script" ]] || script="$REPO_DIR/protocols/shadowsocks2022/install.sh"
  run_child_script "Shadowsocks 2022" "$script"
  ask_update_subscription
}

install_tuic5() {
  run_child_script "TUIC5" "$REPO_DIR/protocols/tuic5/install.tuic5.sh"
  ask_update_subscription
}

install_anytls() {
  run_child_script "AnyTLS" "$REPO_DIR/protocols/anytls/install.anytls.sh"
  ask_update_subscription
}

install_trojan() {
  run_child_script "Trojan" "$REPO_DIR/protocols/trojan/install.trojan.sh"
  ask_update_subscription
}

install_xhttp_reality() {
  run_child_script "VLESS + XHTTP + REALITY" "$REPO_DIR/protocols/vless-xhttp-reality/install.xhttp-reality.sh"
  ask_update_subscription
}

install_recommended() {
  green "将安装推荐组合：VLESS REALITY、HY2、SS2022、TUIC5、AnyTLS、Trojan。"
  yellow "VLESS + XHTTP + REALITY 比较新，推荐单独测试，所以不会包含在推荐组合里。"
  read -r -p "确认开始？[y/N] " ans
  [[ "${ans,,}" == "y" ]] || return 0

  run_child_script "VLESS + REALITY + Vision" "$REPO_DIR/protocols/vless-reality-vision/install.sh"

  local hy2_script="$REPO_DIR/protocols/hysteria2-porthop/install.hy2.sh"
  [[ -f "$hy2_script" ]] || hy2_script="$REPO_DIR/protocols/hysteria2-porthop/install.sh"
  run_child_script "Hysteria2 / HY2 端口跳跃" "$hy2_script"

  local ss_script="$REPO_DIR/protocols/shadowsocks2022/install.ss2022.sh"
  [[ -f "$ss_script" ]] || ss_script="$REPO_DIR/protocols/shadowsocks2022/install.sh"
  run_child_script "Shadowsocks 2022" "$ss_script"

  run_child_script "TUIC5" "$REPO_DIR/protocols/tuic5/install.tuic5.sh"
  run_child_script "AnyTLS" "$REPO_DIR/protocols/anytls/install.anytls.sh"
  run_child_script "Trojan" "$REPO_DIR/protocols/trojan/install.trojan.sh"

  update_subscription
}

install_all() {
  green "将安装全部协议，包括 VLESS + XHTTP + REALITY。"
  yellow "全部安装会占用多个 TCP/UDP 端口，请确认 VPS 没有限制。"
  read -r -p "确认开始？[y/N] " ans
  [[ "${ans,,}" == "y" ]] || return 0

  run_child_script "VLESS + REALITY + Vision" "$REPO_DIR/protocols/vless-reality-vision/install.sh"

  local hy2_script="$REPO_DIR/protocols/hysteria2-porthop/install.hy2.sh"
  [[ -f "$hy2_script" ]] || hy2_script="$REPO_DIR/protocols/hysteria2-porthop/install.sh"
  run_child_script "Hysteria2 / HY2 端口跳跃" "$hy2_script"

  local ss_script="$REPO_DIR/protocols/shadowsocks2022/install.ss2022.sh"
  [[ -f "$ss_script" ]] || ss_script="$REPO_DIR/protocols/shadowsocks2022/install.sh"
  run_child_script "Shadowsocks 2022" "$ss_script"

  run_child_script "TUIC5" "$REPO_DIR/protocols/tuic5/install.tuic5.sh"
  run_child_script "AnyTLS" "$REPO_DIR/protocols/anytls/install.anytls.sh"
  run_child_script "Trojan" "$REPO_DIR/protocols/trojan/install.trojan.sh"
  run_child_script "VLESS + XHTTP + REALITY" "$REPO_DIR/protocols/vless-xhttp-reality/install.xhttp-reality.sh"

  update_subscription
}

show_status() {
  echo
  blue "常用服务状态："
  systemctl --no-pager --type=service --state=running | grep -E 'xray|hysteria|shadowsocks|sing-box' || true
  echo
  blue "常用客户端文件："
  ls -lah /root/*client.txt 2>/dev/null || true
  echo
}

show_menu() {
  echo
  blue "Proxy Suite Debian"
  echo "Debian 12/13 多协议代理一键部署工具"
  echo
  echo "请选择要执行的操作："
  echo "  1) 安装 VLESS + REALITY + Vision（新手推荐）"
  echo "  2) 安装 Hysteria2 / HY2 端口跳跃"
  echo "  3) 安装 Shadowsocks 2022"
  echo "  4) 安装 TUIC5"
  echo "  5) 安装 AnyTLS"
  echo "  6) 安装 Trojan"
  echo "  7) 安装 VLESS + XHTTP + REALITY（较新，建议单独测试）"
  echo "  8) 生成 / 更新统一订阅"
  echo "  9) 一键安装推荐组合（不含 XHTTP REALITY）"
  echo " 10) 一键安装全部协议"
  echo " 11) 查看相关服务状态"
  echo "  0) 退出"
  echo
}

main_menu() {
  while true; do
    show_menu
    read -r -p "请输入数字：" choice
    case "$choice" in
      1) install_vless_reality ;;
      2) install_hy2 ;;
      3) install_ss2022 ;;
      4) install_tuic5 ;;
      5) install_anytls ;;
      6) install_trojan ;;
      7) install_xhttp_reality ;;
      8) update_subscription ;;
      9) install_recommended ;;
      10) install_all ;;
      11) show_status ;;
      0) exit 0 ;;
      *) red "无效选择，请重新输入。" ;;
    esac
  done
}

usage() {
  cat <<EOF
用法：
  bash proxy-suite.sh
  bash proxy-suite.sh --recommended
  bash proxy-suite.sh --all
  bash proxy-suite.sh --vless-reality
  bash proxy-suite.sh --hy2
  bash proxy-suite.sh --ss2022
  bash proxy-suite.sh --tuic5
  bash proxy-suite.sh --anytls
  bash proxy-suite.sh --trojan
  bash proxy-suite.sh --xhttp-reality
  bash proxy-suite.sh --subscription

一键在线运行（仓库公开后可用）：
  bash <(curl -fsSL https://raw.githubusercontent.com/Nekonanda/proxy-suite-debian/main/proxy-suite.sh)
EOF
}

main() {
  need_root
  detect_debian
  install_base_deps
  find_or_clone_repo
  green "项目目录：$REPO_DIR"

  case "${1:-}" in
    --help|-h) usage ;;
    --vless-reality) install_vless_reality ;;
    --hy2) install_hy2 ;;
    --ss2022) install_ss2022 ;;
    --tuic5) install_tuic5 ;;
    --anytls) install_anytls ;;
    --trojan) install_trojan ;;
    --xhttp-reality) install_xhttp_reality ;;
    --subscription) update_subscription ;;
    --recommended) install_recommended ;;
    --all) install_all ;;
    "") main_menu ;;
    *) red "未知参数：$1"; usage; exit 1 ;;
  esac
}

main "$@"
