proxy-suite-debian

Debian 12 / Debian 13 多协议代理一键部署脚本合集。

这个项目主要是给中文 VPS 用户用的。
目标很简单：少折腾一点配置文件，尽量复制一条命令就能把常见协议跑起来。

目前更适合个人 VPS 自用，不是面板，也不是多用户管理系统。

⸻

一键启动菜单

复制下面这条命令到 VPS 里执行：

bash <(curl -fsSL https://raw.githubusercontent.com/Nekonanda/proxy-suite-debian/main/proxy-suite.sh)

执行后会出现中文菜单，按数字选择要安装的协议。

菜单大概是这样：

1) 安装 VLESS + REALITY + Vision（新手推荐）
2) 安装 Hysteria2 / HY2 端口跳跃
3) 安装 Shadowsocks 2022
4) 安装 TUIC5
5) 安装 AnyTLS
6) 安装 Trojan
7) 安装 VLESS + XHTTP + REALITY（较新，建议单独测试）
8) 生成 / 更新统一订阅
9) 一键安装推荐组合
10) 一键安装全部协议
11) 查看相关服务状态
0) 退出

第一次使用建议先选：

1

也就是先安装 VLESS + REALITY + Vision。
这个不需要域名，也不需要自己的证书，比较适合新手先跑通。

⸻

手动安装方式

不想用一键菜单的话，也可以手动下载项目。

先登录 VPS：

ssh root@你的VPS_IP

安装基础工具：

apt update
apt install -y git curl unzip

下载项目：

git clone https://github.com/Nekonanda/proxy-suite-debian.git
cd proxy-suite-debian

启动中文菜单：

bash proxy-suite.sh

⸻

当前支持的协议

目前已经整理了这些协议：

* VLESS + REALITY + Vision
* VLESS + XHTTP + REALITY
* Hysteria2 / HY2 + 端口跳跃
* Shadowsocks 2022
* TUIC5
* AnyTLS
* Trojan
* 统一订阅生成器

各协议尽量保持独立安装、独立卸载，避免互相影响。

⸻

推荐安装顺序

新手可以按这个顺序来：

1. VLESS + REALITY + Vision
2. Hysteria2 / HY2 端口跳跃
3. Shadowsocks 2022
4. TUIC5
5. AnyTLS
6. Trojan
7. VLESS + XHTTP + REALITY
8. 生成统一订阅

VLESS + XHTTP + REALITY 比较新，对客户端版本会更挑一些，建议放到后面单独测试。

⸻

各协议单独安装

VLESS + REALITY + Vision

cd protocols/vless-reality-vision
bash install.sh

查看节点：

cat /root/xray-reality-client.txt

⸻

Hysteria2 / HY2 端口跳跃

cd protocols/hysteria2-porthop
bash install.hy2.sh

默认端口范围：

UDP 20000-29999

查看节点：

cat /root/hysteria2-client.txt

⸻

Shadowsocks 2022

cd protocols/shadowsocks2022
bash install.ss2022.sh

默认端口：

TCP 8388
UDP 8388

查看节点：

cat /root/shadowsocks2022-client.txt

⸻

TUIC5

cd protocols/tuic5
bash install.tuic5.sh

默认端口：

UDP 10443

查看节点：

cat /root/tuic5-client.txt

⸻

AnyTLS

cd protocols/anytls
bash install.anytls.sh

默认端口：

TCP 11443

查看节点：

cat /root/anytls-client.txt

⸻

Trojan

cd protocols/trojan
bash install.trojan.sh

默认端口：

TCP 12443

查看节点：

cat /root/trojan-client.txt

⸻

VLESS + XHTTP + REALITY

cd protocols/vless-xhttp-reality
bash install.xhttp-reality.sh

默认端口：

TCP 9443

查看节点：

cat /root/xray-xhttp-reality-client.txt

⸻

统一订阅

装完多个协议后，可以生成一个统一订阅。

cd tools/subscription-manager
bash update-subscription.sh

脚本会输出类似：

http://你的VPS_IP/sub/随机字符串-all.txt
http://你的VPS_IP/sub/随机字符串-all.b64

小火箭 / Shadowrocket 建议优先使用 .b64 结尾的订阅。

⸻

系统要求

目前主要适配：

* Debian 12
* Debian 13

建议使用干净的 Debian VPS，并且使用 root 用户运行。

需要的基础环境：

* systemd
* curl
* git
* unzip
* 可用的公网 IPv4 或 IPv6

⸻

关于域名

大部分协议可以无域名运行。

有域名的话，可以把域名解析到 VPS，再根据具体协议使用域名参数。
目前域名模式还没有完全统一，后面会继续补。

无域名模式下，部分协议会使用自签证书，客户端需要允许不安全证书。

⸻

目录结构

proxy-suite-debian/
├── proxy-suite.sh
├── protocols/
│   ├── vless-reality-vision/
│   ├── vless-xhttp-reality/
│   ├── hysteria2-porthop/
│   ├── shadowsocks2022/
│   ├── tuic5/
│   ├── anytls/
│   └── trojan/
├── tools/
│   └── subscription-manager/
├── docs/
├── README.md
├── LICENSE
├── SECURITY.md
└── CHANGELOG.md

⸻

一点安全提醒

仓库里只应该放脚本，不要把你服务器上生成的真实节点信息传上来。

尤其是这些东西，里面通常会有真实 IP、密码、UUID、私钥或者订阅 token：

/root/*client.txt
/root/all-proxy-subscription.txt
/root/all-proxy-subscription.b64
/etc/proxy-subscription/token
/usr/local/etc/xray/config.json
/etc/sing-box-*/config.json
/etc/shadowsocks-rust/config.json

简单说就是：
脚本可以公开，自己服务器生成的节点信息不要公开。

⸻

目前还不完美的地方

这个项目还在早期整理阶段，不是那种特别成熟的面板项目。

目前已知的问题：

* 域名模式还没有完全统一。
* 主要按 Shadowrocket / 小火箭测试。
* 不同 VPS 商家的系统镜像可能会有差异。
* 统一订阅目前以简单可用为主，格式兼容性后面还可以继续优化。
* 脚本更适合个人 VPS 自用，不适合拿来做多用户管理。
* 部分协议在无域名模式下需要客户端允许不安全证书。

⸻

后面准备做什么

后续如果反馈还可以，会继续补这些东西：

* 支持更多 VLESS 相关组合
* 补齐所有协议的域名模式
* 增加更完整的证书申请和续期逻辑
* 增加一键更新、卸载、回滚
* 增加 VPS 迁移脚本
* 增加服务状态检查和故障诊断
* 优化统一订阅格式
* 增加更多客户端配置示例
* 支持更多代理客户端
* 支持更多系统，比如 Ubuntu、AlmaLinux、Rocky Linux 等

目前先把 Debian 12 / 13 这条线做好，后面再慢慢扩。

⸻

免责声明

本项目仅用于个人学习、网络测试和自用 VPS 部署。
请遵守当地法律法规、VPS 服务商条款以及相关网络使用规定。
使用本项目造成的任何问题，由使用者自行承担。
