# Publishing checklist

1. Use only this repository source folder, not `/root` from your VPS.
2. Search for secrets before publishing:

```bash
grep -RInE 'vless://|hysteria2://|hy2://|ss://|tuic://|anytls://|trojan://|PrivateKey|password|passwd|uuid|154\.16\.|subscription|token' . || true
```

3. Confirm no generated client files exist:

```bash
find . -type f \( -name '*client.txt' -o -name '*subscription*' -o -name '*.key' -o -name '*.pem' \)
```

4. Commit and push.
