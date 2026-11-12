#!/usr/bin/env bash
set -euo pipefail

CDN_BASE_URL="${WARP_CDN_URL:-https://raw.githubusercontent.com/MintBox04/wrapcdn/main}"

echo "=================================================="
OLD_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || curl -s https://ifconfig.me || echo 'Unknown')
echo "📍 IP BEFORE WARP: $OLD_IP"
echo "=================================================="

# 1. Fallback DNS
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" | sudo tee -a /etc/resolv.conf >/dev/null 2>&1 || true

# 2. Download deb directly from user CDN
mkdir -p ~/.apt-warp-cache
WARP_DEB="$HOME/.apt-warp-cache/cloudflare-warp.deb"

if [ ! -s "$WARP_DEB" ]; then
  DISTRO=$(lsb_release -cs 2>/dev/null || echo "jammy")
  echo "📥 Downloading WARP deb for $DISTRO from custom CDN..."
  curl -fsSL --retry 3 --connect-timeout 15 "${CDN_BASE_URL}/cloudflare-warp_${DISTRO}_amd64.deb" -o "$WARP_DEB" 2>/dev/null \
    || curl -fsSL --retry 3 --connect-timeout 15 "${CDN_BASE_URL}/cloudflare-warp.deb" -o "$WARP_DEB" || true
fi

# 3. Direct install bypassing APT index & mirror dependencies
if [ -s "$WARP_DEB" ]; then
  echo "📦 Installing Cloudflare WARP package..."
  sudo dpkg -i --force-depends "$WARP_DEB" 2>/dev/null || true
  sudo dpkg --configure cloudflare-warp 2>/dev/null || true
else
  echo "⚠️ WARP deb package unavailable, skipping..."
  exit 0
fi

# 4. Start D-Bus & Daemon manually (compatible with headless containers & VMs)
echo "🚀 Initializing D-Bus and warp-svc..."
sudo mkdir -p /run/dbus
sudo dbus-daemon --system --fork 2>/dev/null || true
sleep 1

sudo warp-svc --accept-tos > /tmp/warp-svc.log 2>&1 &

# Wait for socket
for i in {1..15}; do
  if warp-cli --accept-tos status >/dev/null 2>&1 || warp-cli status >/dev/null 2>&1; then
    echo "✅ warp-svc is ready."
    break
  fi
  echo "⏳ Waiting for warp-svc... ($i/15)"
  sleep 1
done

# 5. Registration & Connection
echo "🔑 Registering client..."
warp-cli --accept-tos registration new 2>/dev/null || warp-cli registration new 2>/dev/null || warp-cli --accept-tos register 2>/dev/null || true
sleep 1

echo "🛡️ Connecting in full WARP mode..."
warp-cli --accept-tos mode warp 2>/dev/null || warp-cli mode warp 2>/dev/null || warp-cli --accept-tos set-mode warp 2>/dev/null || true
warp-cli --accept-tos connect 2>/dev/null || warp-cli connect 2>/dev/null || true

# Wait for connection
for i in {1..12}; do
  STATUS=$(warp-cli --accept-tos status 2>/dev/null || warp-cli status 2>/dev/null || echo "")
  if echo "$STATUS" | grep -qi "connected"; then
    echo "✅ WARP tunnel connected successfully ($i/12)!"
    break
  fi
  echo "⏳ Waiting for WARP tunnel... ($i/12)"
  sleep 1
done

# Fallback to proxy mode if TUN mode does not route on cloud VM
NEW_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "")
if [ -z "$NEW_IP" ] || [ "$NEW_IP" = "$OLD_IP" ]; then
  echo "⚠️ TUN mode not routing, switching to WARP SOCKS proxy mode..."
  warp-cli --accept-tos mode proxy 2>/dev/null || warp-cli mode proxy 2>/dev/null || true
  warp-cli --accept-tos connect 2>/dev/null || warp-cli connect 2>/dev/null || true
  sleep 2
  PROXY_IP=$(curl -s --socks5 127.0.0.1:40000 --connect-timeout 5 https://api.ipify.org || echo "")
  if [ -n "$PROXY_IP" ] && [ "$PROXY_IP" != "$OLD_IP" ]; then
    echo "✅ SOCKS5 proxy active on 127.0.0.1:40000 (IP: $PROXY_IP)"
    if [ -n "${GITHUB_ENV:-}" ]; then
      echo "HTTP_PROXY=socks5://127.0.0.1:40000" >> "$GITHUB_ENV"
      echo "HTTPS_PROXY=socks5://127.0.0.1:40000" >> "$GITHUB_ENV"
      echo "ALL_PROXY=socks5://127.0.0.1:40000" >> "$GITHUB_ENV"
    fi
  fi
fi

echo "=================================================="
echo "🚀 IP AFTER WARP: $(curl -s https://api.ipify.org || curl -s https://ifconfig.me || echo 'Unknown')"
echo "=================================================="
