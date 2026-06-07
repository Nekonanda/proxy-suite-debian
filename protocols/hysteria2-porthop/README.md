# Hysteria2 Port Hopping for Debian 12/13

一个适合直接发 GitHub 的 Hysteria 2 一键安装项目，默认部署：

- Hysteria 2 / HY2
- UDP 端口跳跃 Port Hopping
- Debian 12 / Debian 13
- IPv4 / IPv6
- 自签证书无域名模式，或域名 + Let's Encrypt 模式
- Salamander 混淆，默认开启
- QUIC 性能优化
- Shadowrocket / 小火箭 `hysteria2://` 链接
- 随机 HTTP 订阅文件
- 与同机 Xray VLESS + REALITY + Vision 共存

> 默认不会修改 `/usr/local/etc/xray/config.json`，不会占用 TCP 443。Hysteria2 使用 UDP 端口范围，因此可以和已有的 Xray REALITY TCP 443 同机共存。

## 官方依据

- Hysteria 官方 Linux 安装脚本：`bash <(curl -fsSL https://get.hy2.sh/)`
- Hysteria 官方文档说明 `listen: :20000-50000` 支持 Linux 端口跳跃，服务端会监听范围内第一个端口，并通过 nftables/iptables 把其他端口重定向到第一个端口。
- 端口跳跃需要 Linux 上可用的 `nft` 或 `iptables`，并需要 root 或 `CAP_NET_ADMIN` 权限。
- Hysteria 官方性能文档建议 Linux UDP buffer 设置为 16 MB，并可调大 QUIC flow-control receive window。
- Hysteria URI 支持 `hysteria2://` / `hy2://`，并支持多端口格式、`obfs`、`obfs-password`、`insecure`、`pinSHA256`。

## 快速安装

root 用户执行：

```bash
cd /root
bash install.sh
```

没有域名时，脚本会：

- 自动检测 VPS 公网 IP
- 生成自签 TLS 证书
- 生成 `insecure=1` + `pinSHA256` 的客户端链接
- 默认使用 UDP `20000-29999` 端口跳跃

安装完成后查看节点：

```bash
cat /root/hysteria2-client.txt
```

## 有域名安装

先把域名解析到 VPS，Cloudflare 建议先用灰云 DNS only，然后运行：

```bash
bash install.sh --domain hy2.example.com --email admin@example.com
```

域名模式会使用 certbot 申请 Let's Encrypt 证书。若同机已有 nginx，脚本优先使用 webroot 方式，不会让 Hysteria 抢占 TCP 80/443。

## 端口跳跃

默认端口范围：

```text
UDP 20000-29999
```

自定义：

```bash
bash install.sh --port-range 30000-39999
```

必须到 VPS 服务商安全组/防火墙放行对应 UDP 范围，例如：

```text
UDP 20000-29999
```

只放行第一个端口是不够的，因为客户端会随机跳到范围内其他端口。

## 小火箭 / Shadowrocket

安装完成后复制：

```bash
cat /root/hysteria2-client.txt
```

优先导入里面的 `hysteria2://` 链接。若订阅 URL 不被小火箭识别，直接复制单条 `hysteria2://` 链接导入。

## 常用参数

```bash
# 指定端口范围
bash install.sh --port-range 20000-50000

# 指定域名
bash install.sh --domain hy2.example.com

# 不启用 Salamander 混淆，保留标准 HTTP/3 外观
bash install.sh --no-obfs

# 指定伪装站点
bash install.sh --masq-url https://www.microsoft.com/

# 强制端口跳跃防火墙后端
bash install.sh --firewall-backend nftables
bash install.sh --firewall-backend iptables

# 显示已生成的客户端信息
bash install.sh --show
```

## 检查服务

```bash
systemctl status hysteria-server --no-pager
journalctl -u hysteria-server -e --no-pager
ss -lunp | grep hysteria
```

检查内核参数：

```bash
sysctl net.core.rmem_max net.core.wmem_max
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
```

## 与 Xray REALITY 共存说明

这套 HY2 默认只使用 UDP 端口范围，例如 UDP `20000-29999`。你原来的 Xray REALITY 通常是 TCP `443`，二者协议层和端口层不冲突。

脚本会复用已有 nginx 来放一个随机订阅文件，但不会覆盖你之前的 Xray 配置。若你的 nginx 是之前那个 Xray 脚本安装的，HY2 订阅文件会优先放到：

```text
/var/www/xray-reality/html/assets/
```

否则放到：

```text
/var/www/html/assets/
```

## 卸载

```bash
bash uninstall.sh
```

卸载脚本会删除 Hysteria2 服务、`/etc/hysteria`、本项目状态文件和本项目生成的 sysctl 文件。不会删除 Xray/REALITY，也不会删除 nginx 主配置。

## 注意事项

1. HY2 是 UDP 协议，服务商安全组必须放行 UDP 端口范围。
2. 没域名时使用自签证书，客户端链接会包含 `insecure=1` 和 `pinSHA256`。
3. `insecure=1` 单独使用不推荐，所以脚本自动加证书指纹 pin。
4. 域名证书模式不默认 pin 指纹，因为证书续期后指纹会变化，可能导致客户端失效。
5. Salamander 混淆默认开启；如果你更想伪装成标准 HTTP/3，可使用 `--no-obfs`。
6. 若安装失败，先看日志：`journalctl -u hysteria-server -e --no-pager`。

## License

MIT
