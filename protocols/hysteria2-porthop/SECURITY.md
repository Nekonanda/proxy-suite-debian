# Security Policy

- 不要公开 `/root/hysteria2-client.txt`。
- 不要公开 `hysteria2://` 链接、认证密码、混淆密码或订阅 URL。
- 没有域名时脚本使用自签证书，并自动生成 `pinSHA256`，请不要删除该参数。
- 如果怀疑配置泄露，请重新运行 `bash install.sh` 生成新密码和新证书。
- 订阅 URL 是 HTTP 时，不要公开分享；代理连接本身走 HY2/TLS，但订阅文件的传输路径不是端到端加密。
