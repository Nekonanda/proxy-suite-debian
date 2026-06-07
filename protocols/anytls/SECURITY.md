# Security Policy

## Supported Versions

The latest version in this repository is supported.

## Notes

This installer creates a self-signed certificate by default for no-domain deployments. Clients must allow insecure certificates. For stronger authentication, use a real domain and trusted certificate, or manually pin certificate/public key information if your client supports it.

Do not publish generated passwords, client links, `/root/anytls-client.txt`, or `/etc/sing-box-anytls/state.env`.
