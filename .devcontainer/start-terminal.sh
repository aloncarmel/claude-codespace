#!/bin/bash

# Log everything to a file
exec > /tmp/startup.log 2>&1
set -x  # Print every command

# CONFIG - Update with your server URL
SERVER_URL="https://57325b28d992.ngrok-free.app"

echo "=== Starting Claude Code Terminal ==="
echo "Time: $(date)"
echo "Codespace: $CODESPACE_NAME"
echo "Server URL: $SERVER_URL"

# Kill existing processes
echo "Killing existing processes..."
pkill ttyd 2>/dev/null || true
pkill cloudflared 2>/dev/null || true
sleep 1

# Start ttyd with Claude Code
echo "Starting ttyd with Claude..."
nohup ttyd -p 7681 -W claude > /tmp/ttyd.log 2>&1 &
TTYD_PID=$!
echo "ttyd PID: $TTYD_PID"
sleep 2

if ! pgrep ttyd > /dev/null; then
  echo "✗ ttyd failed to start"
  echo "ttyd.log contents:"
  cat /tmp/ttyd.log
  exit 1
fi
echo "✓ ttyd is running"

# Start cloudflared tunnel
echo "Starting cloudflared tunnel..."
nohup cloudflared tunnel --url http://localhost:7681 > /tmp/cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!
echo "cloudflared PID: $CLOUDFLARED_PID"

echo "Waiting for tunnel URL..."
sleep 5

# Show cloudflared log
echo "cloudflared.log contents:"
cat /tmp/cloudflared.log

# Get tunnel URL
TUNNEL_URL=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)
echo "Extracted TUNNEL_URL: '$TUNNEL_URL'"

if [ -z "$TUNNEL_URL" ]; then
  echo "✗ Failed to get tunnel URL"
  echo "Waiting 5 more seconds and trying again..."
  sleep 5
  cat /tmp/cloudflared.log
  TUNNEL_URL=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)
  echo "Second attempt TUNNEL_URL: '$TUNNEL_URL'"
  if [ -z "$TUNNEL_URL" ]; then
    echo "Still no tunnel URL, exiting"
    exit 1
  fi
fi

echo "✓ Tunnel: $TUNNEL_URL"

# Announce to server
echo "Announcing to server..."
echo "POST to: $SERVER_URL/api/announce"
echo "Payload: {\"codespace\": \"$CODESPACE_NAME\", \"url\": \"$TUNNEL_URL\"}"

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$SERVER_URL/api/announce" \
  -H "Content-Type: application/json" \
  -d "{\"codespace\": \"$CODESPACE_NAME\", \"url\": \"$TUNNEL_URL\"}")

echo "Curl response: $RESPONSE"

echo "✓ Claude Code ready!"
echo "=== Startup complete at $(date) ==="