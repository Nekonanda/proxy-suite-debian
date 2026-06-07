# AnyTLS 一键安装脚本（Debian 12/13）

这是一个保守的 AnyTLS 一键安装项目，目标是在已经运行多个代理协议的同一台 VPS 上新增 AnyTLS，并尽量不破坏现有服务。

默认新增：

```text
AnyTLS：TCP 11443
核心：sing-box
证书：自签证书
客户端：Shadowrocket / 小火箭可尝试 anytls:// 链接
```

它不会修改你现有的：

```text
Xray / VLESS REALITY
Hysteria2 / HY2
Shadowsocks 2022
TUIC5
VLESS XHTTP REALITY
```

## 官方依据

- sing-box 从 1.12.0 开始支持 AnyTLS inbound/outbound。
- AnyTLS inbound 的核心字段包括 `users`、`padding_scheme` 和 `tls`。
- AnyTLS outbound 的核心字段包括 `server`、`server_port`、`password`、`idle_session_*` 和 `tls`。
- anytls-go 是 AnyTLS 参考实现，README 给出 `anytls://password@host:port` URI 示例，并说明 Shadowrocket 2.2.65+ 已实现 AnyTLS 客户端。

## 安装

上传 `install.anytls.sh` 到 VPS，例如：

```bash
/root/install.anytls.sh
```

执行：

```bash
cd /root
chmod +x install.anytls.sh
bash install.anytls.sh
```

默认端口：

```text
TCP 11443
```

如果想改端口：

```bash
bash install.anytls.sh --port 21443
```

指定客户端显示的服务器地址：

```bash
bash install.anytls.sh --host 你的VPS_IP
```

## 查看节点

```bash
cat /root/anytls-client.txt
```

里面会有：

```text
anytls://...
```

如果小火箭直接导入简洁链接不通，再尝试脚本输出的 `insecure=1` / `allowInsecure=1` 版本，或者在小火箭节点编辑里手动允许不安全证书。

## 防火墙

请确认 TCP 端口可访问：

```text
TCP 11443
```

如果你指定了其他端口，请放行对应 TCP 端口。

## 服务检查

```bash
systemctl status sing-box-anytls --no-pager
journalctl -u sing-box-anytls -e --no-pager
ss -ltnp | grep ':11443'
```

## 配置位置

```text
/etc/sing-box-anytls/config.json
/etc/sing-box-anytls/client-outbound-anytls.json
/root/anytls-client.txt
```

## 重新运行

重复运行脚本会复用已有密码，避免客户端链接无故改变。

如果想强制换密码：

```bash
bash install.anytls.sh --force-new-password
```

## 卸载

```bash
bash uninstall.sh
```

卸载只删除 AnyTLS 独立服务和配置，不会动其他协议。

## 注意

本项目默认使用自签证书，适合没有域名的场景。客户端需要允许不安全证书 / skip-cert-verify / insecure。

HTTP 订阅整合只是附加输出，若订阅导入不稳定，优先单独复制 `/root/anytls-client.txt` 里的链接导入。
