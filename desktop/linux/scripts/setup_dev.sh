#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
python3 -m venv --system-site-packages .venv
mkdir -p "$HOME/.config/echoscribe"
if [ ! -f "$HOME/.config/echoscribe/config.toml" ]; then
  if [ -f "$HOME/.config/wispr/config.toml" ]; then
    cp "$HOME/.config/wispr/config.toml" "$HOME/.config/echoscribe/config.toml"
  else
    cp config.example.toml "$HOME/.config/echoscribe/config.toml"
  fi
fi
mkdir -p "$HOME/.config/echoscribe"
if [ ! -f "$HOME/.config/echoscribe/echoscribe.env" ] && [ -f "$HOME/.config/echoscribe/legacy-transcriber.env" ]; then
  cp "$HOME/.config/echoscribe/legacy-transcriber.env" "$HOME/.config/echoscribe/echoscribe.env"
  chmod 600 "$HOME/.config/echoscribe/echoscribe.env" 2>/dev/null || true
fi
echo "EchoScribe dev environment ready."
