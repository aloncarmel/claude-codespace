#!/bin/bash
set -e

# =============================================================================
# start-terminal.sh
# Starts ttyd terminal server and announces via Cloudflare Tunnel to Upstash
# =============================================================================

PORT=${TTYD_PORT:-7681}
SHELL_CMD=${TTYD_SHELL:-bash}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# =============================================================================
# Announce tunnel URL to Upstash Redis (FIXED - stores URL directly)
# =============================================================================
announce_tunnel() {
  local tunnel_url="$1"
  local codespace_name="${CODESPACE_NAME:-$(hostname)}"
  
  if [ -z "$UPSTASH_REDIS_REST_URL" ] || [ -z "$UPSTASH_REDIS_REST_TOKEN" ]; then
    log_warn "Upstash credentials not found in environment - skipping announcement"
    return 1
  fi
  
  log_info "Announcing tunnel to Upstash Redis..."
  
  local key="tunnel:${codespace_name}"
  
  # Store just the URL directly - no nested JSON!
  local response
  response=$(curl -s -X POST "${UPSTASH_REDIS_REST_URL}" \
    -H "Authorization: Bearer ${UPSTASH_REDIS_REST_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-raw "[\"SET\", \"${key}\", \"${tunnel_url}\", \"EX\", \"7200\"]" \
    --connect-timeout 10 \
    --max-time 15)
  
  if echo "$response" | grep -q '"result":"OK"'; then
    log_success "Tunnel announced: $tunnel_url"
    return 0
  else
    log_error "Failed to announce tunnel: $response"
    return 1
  fi
}

announce_with_retry() {
  local tunnel_url="$1"
  local max_attempts=5
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    if announce_tunnel "$tunnel_url"; then
      return 0
    fi
    log_warn "Announcement attempt $attempt/$max_attempts failed, retrying in ${attempt}s..."
    sleep $attempt
    attempt=$((attempt + 1))
  done
  
  log_error "All announcement attempts failed"
  return 1
}

# =============================================================================
# Cleanup function
# =============================================================================
cleanup() {
  log_info "Shutting down..."
  [ -n "$TTYD_PID" ] && kill $TTYD_PID 2>/dev/null || true
  [ -n "$TUNNEL_PID" ] && kill $TUNNEL_PID 2>/dev/null || true
  
  # Remove tunnel entry from Redis on shutdown
  if [ -n "$UPSTASH_REDIS_REST_URL" ] && [ -n "$UPSTASH_REDIS_REST_TOKEN" ]; then
    local codespace_name="${CODESPACE_NAME:-$(hostname)}"
    curl -s -X POST "${UPSTASH_REDIS_REST_URL}" \
      -H "Authorization: Bearer ${UPSTASH_REDIS_REST_TOKEN}" \
      -H "Content-Type: application/json" \
      --data-raw "[\"DEL\", \"tunnel:${codespace_name}\"]" >/dev/null 2>&1 || true
  fi
  
  exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# =============================================================================
# Main
# =============================================================================
log_info "Starting terminal server..."
log_info "Codespace: ${CODESPACE_NAME:-unknown}"
log_info "Port: $PORT"

# Check for required tools
if ! command -v ttyd &> /dev/null; then
  log_error "ttyd not found. Please install ttyd first."
  exit 1
fi

if ! command -v cloudflared &> /dev/null; then
  log_error "cloudflared not found. Please install cloudflared first."
  exit 1
fi

# Start ttyd in background
log_info "Starting ttyd server..."
ttyd -p $PORT -W $SHELL_CMD &
TTYD_PID=$!
log_success "ttyd started (PID: $TTYD_PID)"

# Wait for ttyd to be ready
sleep 2

# Verify ttyd is running
if ! kill -0 $TTYD_PID 2>/dev/null; then
  log_error "ttyd failed to start"
  exit 1
fi

# Start cloudflared tunnel and capture URL
log_info "Starting Cloudflare tunnel..."

# Start cloudflared and process output
cloudflared tunnel --url http://localhost:$PORT 2>&1 | while IFS= read -r line; do
  echo "$line"
  
  # Look for the tunnel URL in the output
  if echo "$line" | grep -qE 'https://[a-z0-9-]+\.trycloudflare\.com'; then
    TUNNEL_URL=$(echo "$line" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)
    if [ -n "$TUNNEL_URL" ]; then
      log_success "Tunnel URL: $TUNNEL_URL"
      
      # Announce to Upstash in background
      (announce_with_retry "$TUNNEL_URL") &
    fi
  fi
done &
TUNNEL_PID=$!

# Keep running
log_info "Terminal server running. Press Ctrl+C to stop."
wait $TUNNEL_PID