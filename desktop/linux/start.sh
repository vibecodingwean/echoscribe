#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./scripts/setup_dev.sh
./scripts/install_gnome_extension.sh
./scripts/register_chrome_host.sh --no-open

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user enable --now pipewire.socket pipewire-pulse.socket >/dev/null 2>&1 || true
  systemctl --user enable --now wireplumber.service >/dev/null 2>&1 || true
fi

echo "EchoScribe GNOME extension installed."
echo "EchoScribe browser native host registered."
echo "PipeWire/Pulse user audio services enabled where available."
echo "If GNOME Shell does not list it yet, log out and back in, then run:"
echo "  gnome-extensions enable echoscribe@wean.de"

