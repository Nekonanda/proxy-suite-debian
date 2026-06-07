# Security Notes

This installer targets a no-domain VPS setup. It uses a self-signed TLS certificate so clients must allow insecure certificate verification.

Recommendations:

- Do not publish your Trojan password.
- Do not publish `/root/trojan-client.txt`.
- Prefer a real domain and trusted certificate when available.
- Keep Debian and sing-box updated.
- Use a non-default port if your environment needs it.
