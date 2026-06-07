# Security Notes

- The default no-domain mode uses a self-signed certificate and `allow_insecure=1` for client compatibility.
- Keep `/root/tuic5-client.txt` private. It contains UUID and password.
- If you later own a domain, prefer a valid certificate and remove insecure client settings.
- Open only the UDP port you actually use.
