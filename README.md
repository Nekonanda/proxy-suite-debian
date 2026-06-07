proxy-suite-debian

Debian 12 / Debian 13 多协议代理一键部署工具。

面向中文 VPS 用户，尽量让不太会写代码的人，也能把常见协议跑起来。
目前主要适合个人 VPS 自用，不是面板，也不是多用户管理系统。

⸻

新手快速开始

先登录你的 VPS，确保你是 root 用户。

ssh root@你的VPS_IP

安装基础工具：

apt update
apt install -y git curl unzip

下载本项目：

git clone https://github.com/Nekonanda/proxy-suite-debian.git
cd proxy-suite-debian

然后按需要安装协议。

⸻

推荐先装这个：VLESS + REALITY + Vision

这是最推荐的新手入门协议，不需要域名，也不需要自己的证书。

cd protocols/vless-reality-vision
bash install.sh

安装完成后查看小火箭链接：

cat /root/xray-reality-client.txt

复制里面的 vless:// 链接，导入 Shadowrocket / 小火箭。

⸻

安装 HY2 / Hysteria2 端口跳跃

cd ~/proxy-suite-debian/protocols/hysteria2-porthop
bash install.hy2.sh

默认使用 UDP 端口范围：

20000-29999

如果你的 VPS 服务商有安全组，请放行：

UDP 20000-29999

查看节点：

cat /root/hysteria2-client.txt

⸻

安装 Shadowsocks 2022

cd ~/proxy-suite-debian/protocols/shadowsocks2022
bash install.ss2022.sh

默认端口：

TCP 8388
UDP 8388

查看节点：

cat /root/shadowsocks2022-client.txt

⸻

安装 TUIC5

cd ~/proxy-suite-debian/protocols/tuic5
bash install.tuic5.sh

默认端口：

UDP 10443

查看节点：

cat /root/tuic5-client.txt

⸻

安装 AnyTLS

cd ~/proxy-suite-debian/protocols/anytls
bash install.anytls.sh

默认端口：

TCP 11443

查看节点：

cat /root/anytls-client.txt

⸻

安装 Trojan

cd ~/proxy-suite-debian/protocols/trojan
bash install.trojan.sh

默认端口：

TCP 12443

查看节点：

cat /root/trojan-client.txt

⸻

安装 VLESS + XHTTP + REALITY

这个协议比较新，建议放在最后测试。

cd ~/proxy-suite-debian/protocols/vless-xhttp-reality
bash install.xhttp-reality.sh

默认端口：

TCP 9443

查看节点：

cat /root/xray-xhttp-reality-client.txt

⸻

生成统一订阅

如果你已经安装了多个协议，可以生成一个统一订阅链接。

cd ~/proxy-suite-debian/tools/subscription-manager
bash update-subscription.sh

脚本会输出类似：

http://你的VPS_IP/sub/随机字符串-all.txt
http://你的VPS_IP/sub/随机字符串-all.b64

小火箭建议优先使用 .b64 结尾的 Base64 订阅。

⸻

当前支持的协议

* VLESS + REALITY + Vision
* VLESS + XHTTP + REALITY
* Hysteria2 / HY2 + 端口跳跃
* Shadowsocks 2022
* TUIC5
* AnyTLS
* Trojan
* 统一订阅生成器

⸻

系统要求

建议使用干净的 VPS。

目前主要适配：

* Debian 12
* Debian 13

需要：

* root 权限
* curl
* git
* systemd
* 可用的公网 IPv4 或 IPv6

⸻

目录结构

proxy-suite-debian/
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

关于域名

大部分协议可以无域名运行。

如果你有域名，可以把域名解析到 VPS，然后根据具体协议使用对应参数。
目前域名模式还没有完全统一，后续会继续整理。

无域名模式下，部分协议会使用自签证书，客户端需要允许不安全证书。

⸻

不要上传这些文件

下面这些文件可能包含真实 IP、UUID、密码、私钥或订阅 token，不要上传到 GitHub：

/root/*client.txt
/root/all-proxy-subscription.txt
/root/all-proxy-subscription.b64
/etc/proxy-subscription/token
/usr/local/etc/xray/config.json
/etc/sing-box-*/config.json
/etc/shadowsocks-rust/config.json

⸻

已知不足

* 目前没有统一总安装菜单。
* 域名模式还没有完全统一到所有协议。
* 主要按 Shadowrocket / 小火箭测试。
* 不同 VPS 商家的系统镜像和网络环境可能会有差异。
* 当前更适合个人 VPS 自用，不适合作为多用户面板。
* 部分协议在无域名模式下需要客户端允许不安全证书。
* 统一订阅目前偏向简单可用，后续还可以继续优化。

⸻

后续计划

* 增加根目录一键安装入口
* 增加中文交互式安装菜单
* 补齐所有协议的域名模式
* 增加自动健康检查
* 增加一键更新和回滚
* 增加迁移脚本
* 优化统一订阅管理
* 增加更多客户端示例

⸻

免责声明

本项目仅用于个人学习、网络测试和自用 VPS 部署。
请遵守当地法律法规、VPS 服务商条款以及相关网络使用规定。
使用本项目造成的任何问题，由使用者自行承担。
