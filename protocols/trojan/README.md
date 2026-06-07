# Trojan for Debian 12/13

A conservative one-click Trojan installer for Debian 12/13, designed to coexist with other proxy services on the same VPS.

This project uses a dedicated `sing-box` instance and service:

- Service: `sing-box-trojan.service`
- Config: `/etc/sing-box-trojan/config.json`
- Client info: `/root/trojan-client.txt`
- Default port: `12443/tcp`

It does **not** modify Xray, Hysteria2, Shadowsocks 2022, TUIC5, or AnyTLS configs.

## Features

- Debian 12/13 support
- No domain required
- Self-signed TLS certificate
- Shadowrocket-friendly `trojan://` links
- Dedicated system user: `singbox-trojan`
- Dedicated sing-box binary: `/usr/local/bin/sing-box-trojan`
- Config check before service start
- Conservative TCP kernel tuning via `/etc/sysctl.d/`
- Re-runnable installer: password and port are reused unless changed

## Quick start

Upload `install.trojan.sh` to your VPS, then run as root:

```bash
cd /root
chmod +x install.trojan.sh
bash install.trojan.sh
```

Default port:

```text
TCP 12443
```

After installation:

```bash
cat /root/trojan-client.txt
```

Import one of the `trojan://` links into Shadowrocket. Since this no-domain mode uses a self-signed certificate, the client must allow insecure certificates / skip certificate verification.

## Custom port

```bash
bash install.trojan.sh --port 13443
```

Then make sure TCP `13443` is reachable.

## Custom host or SNI

```bash
bash install.trojan.sh --host 203.0.113.10 --sni www.bing.com
```

The default SNI is `www.bing.com`.

## Check service

```bash
systemctl status sing-box-trojan --no-pager
journalctl -u sing-box-trojan -e --no-pager
ss -ltnp | grep ':12443'
```

## Uninstall

```bash
bash uninstall.sh
```

Keep config while uninstalling:

```bash
bash uninstall.sh --keep-config
```

## Notes

Trojan is a TLS proxy. This script is optimized for the user's no-domain scenario, so it uses a self-signed certificate and client-side insecure mode. For a production domain-based deployment, use a valid TLS certificate and disable insecure verification on the client.
