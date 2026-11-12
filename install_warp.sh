#!/usr/bin/env bash
# ==============================================================================
# Cloudflare WARP Fast Installer (Zero Live Downloads - Uses Local Repo Files)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTRO=$(lsb_release -cs 2>/dev/null || echo "jammy")

echo "=================================================="
OLD_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || curl -s https://ifconfig.me || echo 'Unknown')
echo "📍 IP BEFORE WARP: $OLD_IP"
echo "=================================================="

# 1. Fallback DNS
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf >/dev/null 2>&1 || true
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf >/dev/null 2>&1 || true

# 2. Locate local deb package (ZERO LIVE DOWNLOADS)
WARP_DEB=""
if [ -s "$SCRIPT_DIR/cloudflare-warp_${DISTRO}_amd64.deb" ]; then
  WARP_DEB="$SCRIPT_DIR/cloudflare-warp_${DISTRO}_amd64.deb"
elif [ -s "$SCRIPT_DIR/cloudflare-warp.deb" ]; then
  WARP_DEB="$SCRIPT_DIR/cloudflare-warp.deb"
elif [ -s "/tmp/wrapcdn/cloudflare-warp_${DISTRO}_amd64.deb" ]; then
  WARP_DEB="/tmp/wrapcdn/cloudflare-warp_${DISTRO}_amd64.deb"
elif [ -s "/tmp/wrapcdn/cloudflare-warp.deb" ]; then
  WARP_DEB="/tmp/wrapcdn/cloudflare-warp.deb"
fi
echo "📦 Using local package: $WARP_DEB"

# 3. Direct install packages including TSS2 dependencies
if [ -d "$SCRIPT_DIR" ]; then
  sudo dpkg -i --force-depends "$SCRIPT_DIR"/libtss2*.deb "$WARP_DEB" 2>/dev/null || sudo dpkg -i --force-depends "$WARP_DEB" 2>/dev/null || true
elif [ -d "/tmp/wrapcdn" ]; then
  sudo dpkg -i --force-depends /tmp/wrapcdn/libtss2*.deb "$WARP_DEB" 2>/dev/null || sudo dpkg -i --force-depends "$WARP_DEB" 2>/dev/null || true
fi
sudo dpkg --configure cloudflare-warp 2>/dev/null || true
sudo ldconfig 2>/dev/null || true

# 4. Start D-Bus & Daemon manually
sudo mkdir -p /run/dbus /var/lib/cloudflare-warp /etc/cloudflare-warp
sudo dbus-uuidgen --ensure 2>/dev/null || true
sudo dbus-daemon --system --fork 2>/dev/null || sudo service dbus start 2>/dev/null || true
sleep 1

sudo systemctl start warp-svc 2>/dev/null || sudo service warp-svc start 2>/dev/null || true
if ! pgrep -x warp-svc >/dev/null 2>&1; then
  sudo /bin/warp-svc > /tmp/warp-svc.log 2>&1 &
fi

for i in {1..15}; do
  if pgrep -x warp-svc >/dev/null 2>&1 || warp-cli --accept-tos status 2>&1 | grep -qE "Status|Registration|Connected|Disconnected"; then
    echo "✅ warp-svc is ready ($i/15)."
    break
  fi
  sleep 1
done

if ! pgrep -x warp-svc >/dev/null 2>&1; then
  echo "❌ warp-svc failed to start! Debug logs:"
  cat /tmp/warp-svc.log 2>/dev/null || true
  sudo journalctl -u warp-svc -n 20 --no-pager 2>/dev/null || true
fi

# 5. Registration & Connection
warp-cli --accept-tos registration new 2>/dev/null || warp-cli registration new 2>/dev/null || warp-cli --accept-tos register 2>/dev/null || warp-cli register 2>/dev/null || true
sleep 1
warp-cli --accept-tos mode warp 2>/dev/null || warp-cli mode warp 2>/dev/null || warp-cli --accept-tos set-mode warp 2>/dev/null || warp-cli set-mode warp 2>/dev/null || true
warp-cli --accept-tos connect 2>/dev/null || warp-cli connect 2>/dev/null || true

for i in {1..12}; do
  STATUS=$(warp-cli --accept-tos status 2>/dev/null || warp-cli status 2>/dev/null || echo "")
  if echo "$STATUS" | grep -qi "connected"; then
    echo "✅ WARP tunnel connected successfully ($i/12)!"
    break
  fi
  sleep 1
done

# 6. SOCKS Proxy fallback if TUN mode doesn't route on Azure VM
NEW_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "")
if [ -z "$NEW_IP" ] || [ "$NEW_IP" = "$OLD_IP" ]; then
  echo "⚠️ TUN mode not routing, switching to WARP SOCKS proxy mode..."
  warp-cli --accept-tos mode proxy 2>/dev/null || warp-cli mode proxy 2>/dev/null || warp-cli --accept-tos set-mode proxy 2>/dev/null || warp-cli set-mode proxy 2>/dev/null || true
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
    export HTTP_PROXY="socks5://127.0.0.1:40000"
    export HTTPS_PROXY="socks5://127.0.0.1:40000"
    export ALL_PROXY="socks5://127.0.0.1:40000"
  else
    echo "⚠️ SOCKS5 proxy check: PROXY_IP='$PROXY_IP'"
  fi
fi

FINAL_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || curl -s https://ifconfig.me || echo "$OLD_IP")
echo "=================================================="
echo "🚀 IP AFTER WARP: $FINAL_IP"
echo "=================================================="
