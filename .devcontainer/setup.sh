#!/bin/bash
set -e

echo "🚀 Setting up Claude CLI environment..."

# Update packages
sudo apt-get update

# Install ttyd
echo "📦 Installing ttyd..."
sudo apt-get install -y ttyd

# Install cloudflared
echo "📦 Installing cloudflared..."
curl -L --output /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i /tmp/cloudflared.deb
rm /tmp/cloudflared.deb

# Install Claude CLI (Anthropic)
echo "📦 Installing Claude CLI..."
npm install -g @anthropic-ai/claude-code

# Verify installations
echo ""
echo "✅ Installation complete!"
echo "   - ttyd: $(ttyd --version 2>&1 | head -1)"
echo "   - cloudflared: $(cloudflared --version 2>&1 | head -1)"
echo "   - claude: $(which claude)"
echo ""