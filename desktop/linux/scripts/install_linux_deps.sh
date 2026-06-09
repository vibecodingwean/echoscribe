#!/usr/bin/env bash
set -euo pipefail

target_user="${1:-${SUDO_USER:-$USER}}"

apt-get update
apt-get install -y \
  ffmpeg \
  alsa-utils \
  poppler-utils \
  python3-venv \
  python3-cairo \
  python3-gi \
  gir1.2-gtk-3.0 \
  wl-clipboard \
  wtype \
  ydotool \
  xdotool \
  xclip \
  udev

groupadd -f input
usermod -aG input "$target_user"
printf 'KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"\n' \
  >/etc/udev/rules.d/90-echoscribe-uinput.rules
modprobe uinput || true
udevadm control --reload-rules
udevadm trigger || true

echo "Installed dependencies. Log out and back in so group membership applies."

