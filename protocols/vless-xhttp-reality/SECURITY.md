# Security Policy

## Supported Versions

Only the latest version in this repository is supported.

## Reporting a Vulnerability

Please open a GitHub issue without posting private keys, UUIDs, server IPs, or subscription URLs.

## Secret Handling

Do not commit generated files containing:

- REALITY private key
- UUID
- shortId
- subscription token
- server IP if you want to keep it private

Generated files such as `/root/xray-xhttp-reality-client.txt` are intentionally not included in this repository.
