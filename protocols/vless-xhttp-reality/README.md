# Xray VLESS + XHTTP + REALITY for Debian 12/13

一个保守型一键脚本，用于在 Debian 12/13 VPS 上追加安装 **VLESS + XHTTP + REALITY**。

这个项目默认面向“同一台服务器已经运行其它节点”的场景，例如：

- VLESS + REALITY + Vision：TCP 443
- Hysteria2 / HY2：UDP 20000-29999
- Shadowsocks 2022：TCP/UDP 8388
- 本项目新增：VLESS + XHTTP + REALITY：默认 TCP 9443

脚本不会覆盖已有 Xray 配置，而是备份 `/usr/local/etc/xray/config.json` 后追加一个新的 inbound。配置测试通过后才会重启 Xray；如果测试或重启失败，会自动回滚。

## 特性

- 适配 Debian 12 / Debian 13
- 不需要自己的域名或证书
- 默认借用 `www.microsoft.com:443` 的 REALITY 外观
- 默认新增 TCP `9443`，不占用你现有的 TCP `443`
- 支持 IPv4 / IPv6 地址输出
- 写入 `/etc/sysctl.d/*.conf`，兼容 Debian 13
- 自动启用 BBR + fq 和稳健型 TCP 参数
- 自动生成 Shadowrocket 可尝试导入的 `vless://` 链接
- 同时生成 Xray 客户端 JSON 参考配置
- 自动合并 `/root/xray-reality-client.txt`、`/root/hysteria2-client.txt`、`/root/shadowsocks2022-client.txt` 和本节点到 `/root/all-proxy-subscription.txt`
- 如果已存在 `/var/www/html`，会自动创建 `/var/www/html/assets` 并生成 HTTP 订阅文件
- v2 修复：XHTTP inbound 默认使用 `settings.clients`，避免实际连接时出现 `invalid request user id`

## 快速安装

把 `install.xhttp-reality.sh` 上传到 VPS 的 `/root/`，然后执行：

```bash
cd /root
chmod +x install.xhttp-reality.sh
bash install.xhttp-reality.sh
```

安装完成后查看客户端信息：

```bash
cat /root/xray-xhttp-reality-client.txt
```

查看整合订阅：

```bash
cat /root/all-proxy-subscription.txt
```

## 防火墙 / 安全组

默认需要在 VPS 服务商后台放行：

```text
TCP 9443
```

如果你自定义端口，例如：

```bash
bash install.xhttp-reality.sh --port 9444
```

就放行：

```text
TCP 9444
```

## 常用参数

```bash
# 使用默认端口 9443
bash install.xhttp-reality.sh

# 指定端口
bash install.xhttp-reality.sh --port 9444

# 指定连接地址，例如手动指定 IPv4、IPv6 或域名
bash install.xhttp-reality.sh --public-host 1.2.3.4

# 指定 REALITY 伪装目标
bash install.xhttp-reality.sh --sni www.microsoft.com --target www.microsoft.com:443

# 更新 Xray 后再安装
bash install.xhttp-reality.sh --update-xray

# 跳过内核优化
bash install.xhttp-reality.sh --no-kernel-tune
```

## 为什么不使用 Vision flow

这个项目是 **VLESS + XHTTP + REALITY**，不是 **VLESS + RAW/TCP + REALITY + Vision**。

为了保守和兼容，脚本不会给 XHTTP inbound 设置 `flow=xtls-rprx-vision`。如果你已经有一个 TCP 443 的 Vision 节点，本项目会保持它不变。

## 文件位置

| 文件 | 说明 |
|---|---|
| `/usr/local/etc/xray/config.json` | Xray 主配置 |
| `/usr/local/etc/xray/config.json.bak.xray-vless-xhttp-reality.*` | 自动备份 |
| `/etc/xray-vless-xhttp-reality/client-outbound-xhttp-reality.json` | 客户端 JSON 参考 |
| `/root/xray-xhttp-reality-client.txt` | 本节点客户端信息 |
| `/root/all-proxy-subscription.txt` | 整合订阅，原始文本 |
| `/root/all-proxy-subscription.b64` | 整合订阅，Base64 |
| `/etc/sysctl.d/99-xray-xhttp-reality-performance.conf` | 内核优化参数 |

## 检查服务

```bash
systemctl status xray --no-pager
journalctl -u xray -e --no-pager
ss -ltnp | grep ':9443'
```

检查 BBR：

```bash
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
```

正常应类似：

```text
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
```


## v2 修复说明

旧版曾使用 `settings.users` 写入 XHTTP inbound；在部分新版 Xray 上配置测试可以通过，但实际连接会出现：

```text
rejected proxy/vless/encoding: invalid request user id
```

v2 已改为默认写入 `settings.clients`，并在安装时覆盖更新同 tag 的旧 inbound。已经安装过旧版的服务器可以直接重新运行 v2 脚本修复，不会影响其它 REALITY/HY2/SS2022 节点。

## 卸载

```bash
bash uninstall.sh
```

这只会移除本项目追加的 `vless-xhttp-reality` inbound，不卸载 Xray，不删除你已有的 REALITY/HY2/SS2022。

同时删除本项目的 sysctl 参数：

```bash
bash uninstall.sh --remove-sysctl
```

## 兼容性说明

服务端配置采用保守字段。v2 默认使用实测可用的 `settings.clients`，避免配置测试通过但运行时拒绝 UUID 的问题：

- `protocol: vless`
- `settings.clients`
- `decryption: none`
- `streamSettings.network: xhttp`
- `streamSettings.security: reality`
- `xhttpSettings.path`
- `realitySettings.target/serverNames/privateKey/shortIds`

XHTTP 仍是较新的传输方式。部分 iOS 客户端对 `vless://` 的 `type=xhttp` 参数可能存在导入兼容差异，所以脚本同时输出完整 Xray 客户端 JSON 参考配置。

## 免责声明

请遵守你所在地法律法规和 VPS 服务商服务条款。项目仅用于网络安全研究、个人加密连接和自有设备之间的安全访问。
