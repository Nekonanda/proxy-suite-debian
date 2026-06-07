# Changelog

## 1.0.1

- 修复 Xray 新版 `xray x25519` 输出格式解析：兼容 `PrivateKey`、`Password`、`Password (PublicKey)`。
- 保留对旧版 `Private key` / `Public key` 输出的兼容。
- 对 Debian 13 使用 `/etc/sysctl.d/*.conf` 写入内核参数，避免 `/etc/sysctl.conf` 不再被 systemd-sysctl 读取的问题。
- 增加安装后的 Shadowrocket 链接与 HTTP 订阅文件输出说明。
