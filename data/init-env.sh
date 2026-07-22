#!/usr/bin/env bash
# init-env.sh — run on the Ubuntu multipass VM after files are synced.
# Edit this script to change packages and other guest setup.
set -euo pipefail

log() { printf '==> %s\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive

log "Updating apt..."
sudo apt-get update -qq

log "Installing packages..."
sudo apt-get install -y \
  git \
  curl \
  tree \
  net-tools
# sudo apt-get install -y htop tmux

log "Installing Grok Build..."
curl -fsSL https://x.ai/cli/install.sh | bash

# Ensure grok is on PATH for login shells (install script may already do this).
if ! grep -q '\.grok/bin' "$HOME/.bashrc" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.grok/bin:$PATH"\n' >> "$HOME/.bashrc"
fi

log "Env init done."
