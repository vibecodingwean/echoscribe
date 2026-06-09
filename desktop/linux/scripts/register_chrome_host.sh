#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

repo_dir="$(pwd)"
host_name="de.echoscribe.nativehost"
extension_dir="$(cd "$repo_dir/../browser-extension" && pwd)"
extension_manifest="$extension_dir/manifest.json"
firefox_extension_dir="$(cd "$repo_dir/../firefox-extension" && pwd)"
firefox_extension_manifest="$firefox_extension_dir/manifest.json"
firefox_extension_id="echoscribe@wean.de"
native_wrapper="$repo_dir/native-host/echoscribe-native-host"
open_after="yes"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-open)
      open_after="no"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$extension_manifest" ]; then
  echo "Chromium extension manifest not found: $extension_manifest" >&2
  exit 1
fi

if [ ! -f "$firefox_extension_manifest" ]; then
  echo "Firefox extension manifest not found: $firefox_extension_manifest" >&2
  exit 1
fi

if [ ! -x "$native_wrapper" ]; then
  chmod +x "$native_wrapper"
fi

if [ ! -x .venv/bin/python ]; then
  ./scripts/setup_dev.sh
fi

extension_id="$(python3 - "$extension_manifest" <<'PY'
import base64
import hashlib
import json
import sys

manifest = json.loads(open(sys.argv[1], encoding="utf-8").read())
public_key = base64.b64decode(manifest["key"])
digest = hashlib.sha256(public_key).digest()
chars = []
for byte in digest[:16]:
    chars.append(chr(ord("a") + ((byte >> 4) & 0x0F)))
    chars.append(chr(ord("a") + (byte & 0x0F)))
print("".join(chars))
PY
)"

write_chromium_manifest() {
  local directory="$1"
  mkdir -p "$directory"
  python3 - "$directory/$host_name.json" "$host_name" "$native_wrapper" "$extension_id" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "name": sys.argv[2],
    "description": "EchoScribe Web Summary Native Host",
    "path": sys.argv[3],
    "type": "stdio",
    "allowed_origins": [f"chrome-extension://{sys.argv[4]}/"],
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(path)
PY
}

write_firefox_manifest() {
  local directory="$1"
  mkdir -p "$directory"
  python3 - "$directory/$host_name.json" "$host_name" "$native_wrapper" "$firefox_extension_id" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "name": sys.argv[2],
    "description": "EchoScribe Web Summary Native Host",
    "path": sys.argv[3],
    "type": "stdio",
    "allowed_extensions": [sys.argv[4]],
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(path)
PY
}

open_browser_page() {
  local command="$1"
  local url="$2"
  if command -v "$command" >/dev/null 2>&1; then
    "$command" "$url" >/dev/null 2>&1 &
    echo "Opened $url with $command"
    return 0
  fi
  return 1
}

write_chromium_manifest "$HOME/.config/google-chrome/NativeMessagingHosts"
write_chromium_manifest "$HOME/.config/chromium/NativeMessagingHosts"
write_chromium_manifest "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
write_chromium_manifest "$HOME/.config/microsoft-edge/NativeMessagingHosts"
write_firefox_manifest "$HOME/.mozilla/native-messaging-hosts"
write_firefox_manifest "$HOME/.librewolf/native-messaging-hosts"

echo "EchoScribe Browser extension registered."
echo "Chromium extension ID: $extension_id"
echo "Chromium extension folder: $extension_dir"
echo "Firefox extension ID: $firefox_extension_id"
echo "Firefox extension manifest: $firefox_extension_manifest"
echo "Native host: $native_wrapper"
echo
echo "Chromium browsers: enable developer mode on the extensions page and load this folder:"
echo "  $extension_dir"
echo "Firefox: open about:debugging#/runtime/this-firefox and load this manifest as a temporary add-on:"
echo "  $firefox_extension_manifest"

if [ "$open_after" = "yes" ] && command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$extension_dir" >/dev/null 2>&1 || true
  xdg-open "$firefox_extension_dir" >/dev/null 2>&1 || true
  open_browser_page google-chrome chrome://extensions || true
  open_browser_page chromium chrome://extensions || true
  open_browser_page microsoft-edge edge://extensions || true
  open_browser_page brave-browser brave://extensions || true
  open_browser_page firefox about:debugging#/runtime/this-firefox || true
fi
