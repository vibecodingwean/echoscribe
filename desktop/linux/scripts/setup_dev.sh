#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
python3 -m compileall -q echoscribe
glib-compile-schemas --strict gnome-extension/echoscribe@wean.de/schemas
echo "EchoScribe uses the system Python: $(command -v python3)"
