# Security Policy

请不要在公开 issue 中提交你的 UUID、REALITY privateKey、订阅 URL、服务器 IP 或其它敏感信息。

如果你发现脚本存在安全问题，建议先私下联系仓库维护者；公开报告时请尽量使用脱敏配置。

## 默认安全取舍

- 不修改 SSH 配置，避免把用户锁出服务器。
- 不强制启用防火墙，避免云厂商安全组和本机防火墙冲突。
- Xray 不写 access log；nginx 伪装页关闭 access log。
- HTTP 订阅 URL 使用随机高熵路径，但 HTTP 本身不是端到端加密，不应公开分享。
