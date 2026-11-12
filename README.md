# Cloudflare WARP Self-Hosted CDN Package (wrapcdn)

This repository serves as a dedicated, high-speed CDN for Cloudflare WARP deb packages and setup scripts across GitHub Actions runner shards.

## 📦 Files
- `pubkey.gpg` — Cloudflare Official APT Archive Signing Key
- `cloudflare-warp_jammy_amd64.deb` — Ubuntu 22.04 LTS (Jammy)
- `cloudflare-warp_noble_amd64.deb` — Ubuntu 24.04 LTS (Noble)
- `cloudflare-warp.deb` — Universal alias for fast fallback
- `install_warp.sh` — 1-step installer script with D-Bus startup + TUN / SOCKS fallback

---

## ⚡ 1-Step Workflow Integration

```yaml
- name: Setup Cloudflare WARP
  if: matrix.shard != 15
  timeout-minutes: 3
  continue-on-error: true
  run: curl -fsSL https://raw.githubusercontent.com/MintBox04/wrapcdn/main/install_warp.sh | bash
```
