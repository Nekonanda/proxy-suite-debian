# Changelog

## v2

- Fix XHTTP REALITY inbound user field: default to `settings.clients` instead of `settings.users`.
- This resolves the runtime error `rejected proxy/vless/encoding: invalid request user id` observed with Xray v26.3.27 even when `xray run -test` passed.
- Keep a test-time fallback to `settings.users` only if `settings.clients` is rejected by the installed Xray build.
- Create `/var/www/html/assets` automatically when `/var/www/html` exists, so generated subscription URLs do not 404 due to a missing assets directory.

## v1

- Initial conservative add-on installer for VLESS + XHTTP + REALITY on Debian 12/13.
