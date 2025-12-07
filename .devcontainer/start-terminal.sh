#!/bin/bash

echo "=== Starting Claude Code Terminal ==="
echo "Codespace: $CODESPACE_NAME"

# Kill existing processes
pkill ttyd 2>/dev/null || true
pkill cloudflared 2>/dev/null || true
sleep 1

# Start ttyd with Claude Code
echo "Starting ttyd with Claude..."
ttyd -p 7681 -W claude > /tmp/ttyd.log 2>&1 &
sleep 2

if ! pgrep ttyd > /dev/null; then
  echo "✗ ttyd failed to start"
  cat /tmp/ttyd.log
  exit 1
fi

echo "✓ ttyd started"

# Start cloudflared tunnel
echo "Starting tunnel..."
cloudflared tunnel --url http://localhost:7681 > /tmp/cloudflared.log 2>&1 &
sleep 3

# Wait for tunnel URL
echo "Waiting for tunnel..."
TUNNEL_URL=""
for i in {1..20}; do
  TUNNEL_URL=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)
  if [ -n "$TUNNEL_URL" ]; then
    break
  fi
  sleep 2
done

if [ -z "$TUNNEL_URL" ]; then
  echo "✗ Failed to get tunnel URL"
  cat /tmp/cloudflared.log
  exit 1
fi

echo "✓ Tunnel: $TUNNEL_URL"

# Announce to Upstash
if [ -n "$UPSTASH_REDIS_REST_URL" ] && [ -n "$UPSTASH_REDIS_REST_TOKEN" ]; then
  curl -s -X POST "${UPSTASH_REDIS_REST_URL}" \
    -H "Authorization: Bearer ${UPSTASH_REDIS_REST_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-raw "[\"SET\", \"tunnel:${CODESPACE_NAME}\", \"${TUNNEL_URL}\", \"EX\", \"7200\"]" \
    && echo "✓ Announced to Upstash" \
    || echo "✗ Failed to announce"
else
  echo "⚠ Upstash not configured"
fi

echo "✓ Claude Code ready!"

# Keep script running so processes stay alive
while pgrep ttyd > /dev/null && pgrep cloudflared > /dev/null; do
  sleep 60
done