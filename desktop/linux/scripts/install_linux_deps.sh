#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "install_linux_deps.sh must run as root" >&2
  exit 1
fi

apt-get update
apt-get install -y \
  python3 \
  ffmpeg \
  alsa-utils \
  poppler-utils \
  libglib2.0-bin \
  gnome-shell-extension-prefs

rm -f /etc/udev/rules.d/90-echoscribe-uinput.rules
echo "Installed EchoScribe GNOME runtime dependencies."
