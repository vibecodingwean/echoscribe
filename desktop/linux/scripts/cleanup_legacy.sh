#!/usr/bin/env bash
set -euo pipefail

state_root="${XDG_STATE_HOME:-$HOME/.local/state}/echoscribe"
user_units="$HOME/.config/systemd/user"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now wispr.service echoscribe.service >/dev/null 2>&1 || true
fi
rm -f "$user_units/wispr.service" "$user_units/echoscribe.service"

override="$user_units/ydotool.service.d/override.conf"
if [ -f "$override" ] && grep -Eq 'EchoScribe|/usr/bin/sg input.*ydotoold' "$override"; then
  rm -f "$override"
  rmdir "$(dirname "$override")" 2>/dev/null || true
fi

rm -f \
  "$state_root/sideband.pid" \
  "$state_root/sideband.log" \
  "$state_root/sideband.mode" \
  "$state_root/sideband.shortcut" \
  "$state_root/focus-app-hint"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
