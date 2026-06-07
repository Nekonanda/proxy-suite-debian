# Proxy Suite Debian Toolkit

A collection of Debian 12/13 one-click deployment scripts for multiple proxy protocols. The scripts are designed to run side-by-side on the same VPS with independent ports and services.

> This repository contains **installer source code only**. Do not upload generated client files from your VPS, because they contain passwords, UUIDs, private keys, subscription tokens, and server IPs.

## Included protocols

| Protocol | Default port | Transport | Installer |
|---|---:|---|---|
| VLESS + REALITY + Vision | TCP 443 | Xray | `protocols/vless-reality-vision/install.sh` |
| VLESS + XHTTP + REALITY | TCP 9443 | Xray | `protocols/vless-xhttp-reality/install.xhttp-reality.sh` |
| Hysteria2 with port hopping | UDP 20000-29999 | Hysteria2 | `protocols/hysteria2-porthop/install.sh` |
| Shadowsocks 2022 | TCP/UDP 8388 | shadowsocks-rust | `protocols/shadowsocks2022/install.ss2022.sh` |
| TUIC5 | UDP 10443 | sing-box | `protocols/tuic5/install.tuic5.sh` |
| AnyTLS | TCP 11443 | sing-box | `protocols/anytls/install.anytls.sh` |
| Trojan | TCP 12443 | sing-box | `protocols/trojan/install.trojan.sh` |

## Subscription manager

After installing any protocols, rebuild a unified subscription with:

```bash
bash tools/subscription-manager/update-subscription.sh
```

On a VPS where the file is copied to `/root/update-subscription.sh`:

```bash
bash /root/update-subscription.sh
```

It collects the generated client files under `/root/*client.txt`, creates raw and Base64 subscriptions, and exposes them through:

```text
http://SERVER_IP/sub/TOKEN-all.txt
http://SERVER_IP/sub/TOKEN-all.b64
```

For Shadowrocket, the Base64 URL is usually the safer choice.

## Recommended deployment order

```bash
# 1. VLESS REALITY Vision
bash protocols/vless-reality-vision/install.sh

# 2. Hysteria2
bash protocols/hysteria2-porthop/install.sh

# 3. Shadowsocks 2022
bash protocols/shadowsocks2022/install.ss2022.sh

# 4. VLESS XHTTP REALITY
bash protocols/vless-xhttp-reality/install.xhttp-reality.sh

# 5. TUIC5
bash protocols/tuic5/install.tuic5.sh

# 6. AnyTLS
bash protocols/anytls/install.anytls.sh

# 7. Trojan
bash protocols/trojan/install.trojan.sh

# 8. Unified subscription
bash tools/subscription-manager/update-subscription.sh
```

You can also install only the protocols you need.

## Important security notes

Never commit these generated files from your VPS:

```text
/root/*client.txt
/root/all-proxy-subscription.txt
/root/all-proxy-subscription.b64
/etc/proxy-subscription/token
/usr/local/etc/xray/config.json
/etc/sing-box-*/config.json
/etc/shadowsocks-rust/config.json
/etc/hysteria/config.yaml
/etc/*/certs/*
```

The `.gitignore` in this repository includes common secret patterns, but you should still review files before pushing.

## Debian support

The scripts target Debian 12 and Debian 13. Kernel/network tuning is written to `/etc/sysctl.d/` rather than `/etc/sysctl.conf`, so it works with Debian 13's current systemd-sysctl behavior.

## License

MIT License. See `LICENSE`.
