#!/bin/bash

# CONFIG - Update with your server URL
SERVER_URL="${NODEBAY_SERVER_URL:-https://your-server.com}"

echo "=== Starting Claude Code Terminal ==="
echo "Codespace: $CODESPACE_NAME"

# Kill existing processes
pkill ttyd 2>/dev/null || true
pkill cloudflared 2>/dev/null || true
sleep 1

# Start ttyd with Claude Code
echo "Starting ttyd with Claude..."
nohup ttyd -p 7681 -W claude > /tmp/ttyd.log 2>&1 &
sleep 2

if ! pgrep ttyd > /dev/null; then
  echo "✗ ttyd failed to start"
  cat /tmp/ttyd.log
  exit 1
fi

# Start cloudflared tunnel
echo "Starting tunnel..."
nohup cloudflared tunnel --url http://localhost:7681 > /tmp/cloudflared.log 2>&1 &
sleep 5

# Get tunnel URL
TUNNEL_URL=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)

if [ -z "$TUNNEL_URL" ]; then
  echo "✗ Failed to get tunnel URL"
  exit 1
fi

echo "✓ Tunnel: $TUNNEL_URL"

# Announce to server
curl -s -X POST "$SERVER_URL/api/announce" \
  -H "Content-Type: application/json" \
  -d "{\"codespace\": \"$CODESPACE_NAME\", \"url\": \"$TUNNEL_URL\"}" || true

echo "✓ Claude Code ready!"