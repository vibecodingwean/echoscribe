#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
repo_dir="$(pwd)"
service_dir="$HOME/.config/systemd/user"
mkdir -p "$service_dir"
mkdir -p "$HOME/.config/echoscribe"
if [ ! -f "$HOME/.config/echoscribe/config.toml" ]; then
  cp config.example.toml "$HOME/.config/echoscribe/config.toml"
fi
if [ ! -x "$repo_dir/.venv/bin/python" ]; then
  ./scripts/setup_dev.sh
fi
mkdir -p "$service_dir/ydotool.service.d"
cat >"$service_dir/ydotool.service.d/override.conf" <<'SERVICE'
[Service]
ExecStart=
ExecStart=/usr/bin/sg input -c '/usr/bin/ydotoold'
SERVICE
if systemctl --user daemon-reload >/dev/null 2>&1; then
  systemctl --user enable --now ydotool.service >/dev/null 2>&1 || true
  systemctl --user disable --now echoscribe.service >/dev/null 2>&1 || true
  rm -f "$service_dir/echoscribe.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "Installed ydotool paste helper service."
  echo "EchoScribe's Linux dictation trigger is owned by the GNOME Shell extension."
else
  echo "Installed ydotool override at $service_dir/ydotool.service.d/override.conf."
  echo "Run after logging into the desktop: systemctl --user daemon-reload"
  echo "Then start ydotool with: systemctl --user enable --now ydotool.service"
  echo "Install EchoScribe itself with: ./scripts/install_gnome_extension.sh"
fi

