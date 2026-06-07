# Changelog

## v1.0.0

- 新增 AnyTLS 一键安装脚本。
- 使用 sing-box 独立服务 `sing-box-anytls.service`。
- 支持 Debian 12 / Debian 13。
- 默认 TCP 11443。
- 自签证书 + 客户端 insecure 模式。
- 自动下载最新 sing-box Release，要求版本 >= 1.12.0。
- 自动生成 AnyTLS 客户端链接和 sing-box outbound JSON。
- 自动写入保守 TCP 内核优化。
