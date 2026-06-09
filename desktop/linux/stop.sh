#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -x .venv/bin/python ]; then
  .venv/bin/python -m echoscribe gnome-worker cancel --json || true
fi

if [ "${ECHOSCRIBE_FORCE_STOP:-0}" = "1" ] && command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions disable echoscribe@wean.de || true
  echo "EchoScribe GNOME extension disabled."
else
  echo "Canceled any active EchoScribe recording. Extension remains installed."
  echo "For maintenance only: ECHOSCRIBE_FORCE_STOP=1 ./stop.sh"
fi

