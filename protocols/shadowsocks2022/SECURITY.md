# Security Policy

## Reporting

Please open a GitHub issue if you find a script bug that may expose credentials, break existing services, or generate invalid client links.

## Notes

- The generated Shadowsocks 2022 PSK/password is stored in `/etc/shadowsocks-rust/ss2022.env` and `/root/shadowsocks2022-client.txt`.
- Do not publish your generated client files or screenshots containing the PSK/password.
- HTTP subscription links are not end-to-end encrypted. Keep the random URL private.
- If the link was exposed, run `bash install.sh --regen-key` and re-import the new client link.
