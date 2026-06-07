# Shadowsocks 2022 一键安装脚本（Debian 12 / Debian 13）

一个面向 Debian 12 / Debian 13 的 **Shadowsocks 2022 / shadowsocks-rust** 一键安装脚本。

默认使用：

- 实现：`shadowsocks-rust`
- 协议：Shadowsocks 2022 / AEAD-2022
- 加密：`2022-blake3-aes-256-gcm`
- 端口：`8388`
- 传输：TCP + UDP
- IPv6：服务端默认监听 `::`，并尝试保持 IPv4/IPv6 双栈
- 订阅：生成 `ss://`、原始文本订阅、Base64 订阅
- 共存：不会修改 Xray REALITY 或 Hysteria2/HY2 配置

> 注意：SS2022 不需要域名，也不需要 TLS 证书。它和你已有的 VLESS REALITY、HY2 可以在同一台 VPS 上共存，只要端口不冲突。

## 快速安装

root 用户执行：

```bash
bash install.sh
```

如果你在同一台 VPS 上已经有 `/root/install.sh` 用于 Xray REALITY，建议把本脚本命名为：

```bash
/root/install.ss2022.sh
```

然后执行：

```bash
cd /root
chmod +x install.ss2022.sh
bash install.ss2022.sh
```

## 指定端口

```bash
bash install.sh --port 8388
```

服务商后台安全组需要放行：

```text
TCP 8388
UDP 8388
```

## 指定客户端地址

自动检测公网 IP 失败时，可以手动指定：

```bash
bash install.sh --host 1.2.3.4
```

使用 IPv6：

```bash
bash install.sh --host 2001:db8::1234
```

脚本会在 `ss://` URI 中自动给 IPv6 地址加方括号。

## 更换加密方式

默认推荐：

```bash
2022-blake3-aes-256-gcm
```

可选：

```bash
bash install.sh --method 2022-blake3-aes-128-gcm
bash install.sh --method 2022-blake3-aes-256-gcm
bash install.sh --method 2022-blake3-chacha20-poly1305
```

## 强制换密钥

```bash
bash install.sh --regen-key
```

## 安装完成后查看链接

```bash
cat /root/shadowsocks2022-client.txt
```

里面会包含：

- `ss://` 单节点链接
- 原始文本订阅 URL
- Base64 订阅 URL
- 如果服务器已有 `/root/xray-reality-client.txt` 和 `/root/hysteria2-client.txt`，还会生成整合订阅

## 整合订阅

脚本会安装一个工具：

```bash
update-proxy-subscription
```

它会自动读取：

```text
/root/xray-reality-client.txt
/root/hysteria2-client.txt
/root/shadowsocks2022-client.txt
```

然后生成：

```text
/root/all-proxy-subscription.txt
```

如果 nginx 可用，还会生成随机路径 HTTP 订阅文件。

## 检查服务

```bash
systemctl status shadowsocks-rust-server --no-pager
journalctl -u shadowsocks-rust-server -e --no-pager
ss -lntup | grep ':8388'
ss -lnu | grep ':8388'
```

## 卸载

```bash
bash uninstall.sh
```

卸载脚本只处理 SS2022，不会删除：

- Xray / REALITY
- Hysteria2 / HY2
- nginx 本身
- `/root/xray-reality-client.txt`
- `/root/hysteria2-client.txt`

## 官方资料

- shadowsocks-rust: https://github.com/shadowsocks/shadowsocks-rust
- SIP022 AEAD-2022: https://shadowsocks.org/doc/sip022.html
- SIP002 URI Scheme: https://shadowsocks.org/doc/sip002.html


## v2 修复说明

本版本修复了 systemd 以非 root 用户运行时可能无法读取 `/etc/shadowsocks-rust/config.json` 的问题：安装脚本会创建专用系统用户 `ss2022`，并正确设置 `/etc/shadowsocks-rust` 与 `/var/log/shadowsocks-rust` 的权限。
