# xray-reality-debian

当前版本：1.0.1，已兼容 Xray 新版 `xray x25519` 输出里的 `Password (PublicKey)` 格式。

Debian 12 / Debian 13 一键部署 **Xray VLESS + REALITY + Vision**，默认使用 `www.microsoft.com:443` 作为 REALITY 目标站点特征；不需要你自己准备证书或域名。有域名时可绑定域名作为客户端连接地址；没有域名时自动使用公网 IP，并可生成适配 Shadowrocket（小火箭）的 `vless://` 链接和 HTTP 订阅 URL。

> 仅用于合法网络访问、个人服务器加密连接和网络研究。请遵守你所在地区法律法规和服务商条款。

## 功能

- 支持 Debian 12 / Debian 13，要求 systemd。
- 使用 XTLS 官方 `Xray-install` 安装/更新 Xray-core。
- 自动生成 UUID、REALITY x25519 密钥、shortId、SpiderX。
- 默认协议：`VLESS + TCP + REALITY + XTLS Vision`。
- 默认 SNI/目标：`www.microsoft.com` / `www.microsoft.com:443`，可通过参数改。
- 自动开启 BBR，并把 sysctl 写入 `/etc/sysctl.d/99-xray-reality-performance.conf`，兼容 Debian 13。
- IPv6 友好：检测 IPv6 后使用 IPv6 监听，并对客户端 IPv6 地址自动加 `[]`。
- 可选安装 nginx：生成普通 HTTP 伪装页、随机高熵订阅路径、关闭访问日志、禁止搜索索引。
- 输出 Shadowrocket 可导入的 `vless://` 链接和订阅 URL。
- 不改 SSH、不强制安装防火墙，降低首次运行把自己锁外面的概率。

## 一键运行

```bash
sudo bash install.sh
```

有域名时：

```bash
sudo bash install.sh --domain node.example.com
```

指定端口和节点名：

```bash
sudo bash install.sh --domain node.example.com --port 8443 --name "My Reality Node"
```

只显示上次生成的客户端信息：

```bash
sudo bash install.sh --show
```

卸载：

```bash
sudo bash uninstall.sh
```

彻底删除 Xray 配置和日志：

```bash
sudo bash uninstall.sh --purge
```

## 参数

```text
--domain <域名>          可选。你的域名已解析到本机时填写；不填则自动使用公网 IP。
--ip <公网IP>            可选。自动检测失败或多 IP 机器时手动指定。
--port <端口>            默认 443。
--target <域名:端口>     REALITY 目标站点，默认 www.microsoft.com:443。
--sni <域名>             REALITY 客户端 SNI，默认 www.microsoft.com。
--uuid <UUID>            可选。自定义用户 UUID。
--short-id <hex>         可选。0-16 个十六进制字符，长度必须为偶数。
--name <节点名>          可选。小火箭里显示的节点名。
--no-http                不安装 HTTP 伪装页/订阅 URL，只输出 vless:// 链接。
--no-bbr                 不写入 BBR 与内核网络优化。
--force                  端口占用检查更宽松。
--show                   只显示上次生成的客户端信息。
```

## Shadowrocket / 小火箭导入

安装完成后脚本会输出并保存：

```text
/root/xray-reality-client.txt
```

你可以复制其中的：

1. `vless://...` 链接，直接在 Shadowrocket 中导入；或
2. `http://你的IP/assets/随机token.txt` 订阅 URL，在 Shadowrocket 的订阅里添加。

HTTP 订阅 URL 的内容是 base64 后的节点链接。由于没有域名和证书时只能提供 HTTP 订阅，订阅内容在传输路径上不是端到端加密的。脚本做了这些保护：随机 48 位十六进制路径、nginx 访问日志关闭、`X-Robots-Tag: noindex`、`Cache-Control: no-store`。但仍建议不要公开分享 HTTP 订阅 URL。

代理连接本身不是 HTTP 明文；节点使用的是 VLESS + REALITY + Vision。

## 关于“借用微软证书”

REALITY 的机制不是让你拥有 Microsoft 的证书，而是使用目标站点的 TLS 外观与握手特征作为伪装。默认目标是 `www.microsoft.com:443`，客户端 SNI 默认 `www.microsoft.com`。你也可以换成其它合适站点：

```bash
sudo bash install.sh --target www.example.com:443 --sni www.example.com
```

更换前建议确认目标站点支持 TLS 1.3 / HTTP/2，并且 SNI 与目标证书 SAN 匹配。

## 文件位置

- Xray 配置：`/usr/local/etc/xray/config.json`
- 客户端信息：`/root/xray-reality-client.txt`
- 状态文件：`/etc/xray-reality/client.env`
- 内核优化：`/etc/sysctl.d/99-xray-reality-performance.conf`
- BBR 模块加载：`/etc/modules-load.d/99-xray-reality-bbr.conf`
- nginx 站点：`/etc/nginx/sites-available/xray-reality-decoy`
- HTTP 伪装页/订阅：`/var/www/reality-decoy/`

## 常用检查命令

```bash
systemctl status xray --no-pager
journalctl -u xray -e --no-pager
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
ss -ltnp | grep -E ':443|:80'
```

## GitHub 发布建议

仓库结构可以直接这样放：

```text
.
├── install.sh
├── uninstall.sh
├── README.md
├── LICENSE
├── SECURITY.md
├── CHANGELOG.md
└── .gitignore
```

发布后用户可用：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/<你的用户名>/<你的仓库>/main/install.sh)
```

## 上游资料

- XTLS/Xray-core 官方仓库与文档
- XTLS/Xray-install 官方安装脚本
- Project X 官方 VLESS、REALITY 文档
- Debian 13 release notes：Debian 13 不再读取 `/etc/sysctl.conf`，本项目使用 `/etc/sysctl.d/*.conf`
- Linux kernel networking sysctl 文档
- Google BBR 文档仓库

## License

MIT
