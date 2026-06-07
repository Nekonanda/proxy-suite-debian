# TUIC v5 for Debian 12/13

一个保守的一键脚本，用 `sing-box` 在 Debian 12/13 上部署 TUIC v5。

设计目标：

- 不修改现有 Xray / Hysteria2 / Shadowsocks 服务
- 默认使用 UDP `10443`，避免和常见 TCP 443、HY2 端口跳跃、SS2022 端口冲突
- 支持无域名部署：自签证书 + `allow_insecure=1`
- 生成 Shadowrocket / 小火箭可尝试导入的 `tuic://` 链接
- 自动更新 `/root/all-proxy-subscription.txt` 整合订阅
- Debian 13 兼容：内核优化写入 `/etc/sysctl.d/*.conf`

## 快速开始

上传 `install.tuic5.sh` 到 VPS 的 `/root/install.tuic5.sh` 后执行：

```bash
cd /root
bash install.tuic5.sh
```

默认端口：

```text
UDP 10443
```

请确认 VPS 服务商后台和系统防火墙放行 UDP 10443。

## 自定义端口

```bash
bash install.tuic5.sh --port 30443
```

## 查看客户端链接

```bash
cat /root/tuic5-client.txt
```

## 检查服务

```bash
systemctl status sing-box-tuic --no-pager
journalctl -u sing-box-tuic -e --no-pager
ss -lunp | grep ':10443'
```

## 卸载

```bash
bash uninstall.sh
```

卸载脚本不会删除 `/usr/local/bin/sing-box`，避免影响其他可能使用 sing-box 的服务。

## 说明

TUIC v5 使用 UUID + password。脚本默认生成自签证书并设置 SNI 为 `www.bing.com`，客户端链接包含 `allow_insecure=1`。没有域名时，这是最容易跑通的方式。

## 文件

```text
install.tuic5.sh
uninstall.sh
examples/sing-box-tuic5-server.example.json
examples/sing-box-tuic5-client-outbound.example.json
```
