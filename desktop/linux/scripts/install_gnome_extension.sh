#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

uuid="echoscribe@wean.de"
old_uuid="wispr@wean.de"
repo_dir="$(pwd)"
source_dir="$repo_dir/gnome-extension/$uuid"
target_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$uuid"
old_target_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$old_uuid"
skip_enable="no"
skip_settings="no"
skip_legacy_service="no"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-dir)
      target_dir="$2"
      shift 2
      ;;
    --repo-dir)
      repo_dir="$(cd "$2" && pwd)"
      source_dir="$repo_dir/gnome-extension/$uuid"
      shift 2
      ;;
    --skip-enable)
      skip_enable="yes"
      shift
      ;;
    --skip-settings)
      skip_settings="yes"
      shift
      ;;
    --skip-legacy-service)
      skip_legacy_service="yes"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$source_dir/metadata.json" ]; then
  echo "Extension source missing: $source_dir" >&2
  exit 1
fi

if command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions disable "$old_uuid" >/dev/null 2>&1 || true
fi
rm -rf "$old_target_dir"

mkdir -p "$target_dir"
find "$target_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "$source_dir"/. "$target_dir"/
glib-compile-schemas "$target_dir/schemas"

python_path="$repo_dir/.venv/bin/python"
if [ ! -x "$python_path" ]; then
  python_path="$(command -v python3)"
fi

if [ "$skip_settings" != "yes" ] && command -v gsettings >/dev/null 2>&1; then
  gsettings --schemadir "$target_dir/schemas" set org.gnome.shell.extensions.echoscribe repo-path "$repo_dir" || true
  gsettings --schemadir "$target_dir/schemas" set org.gnome.shell.extensions.echoscribe python-path "$python_path" || true
fi

if [ "$skip_enable" != "yes" ] && command -v gnome-extensions >/dev/null 2>&1; then
  if ! gnome-extensions enable "$uuid"; then
    current_enabled="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || printf '[]')"
    updated_enabled="$(python3 - "$current_enabled" "$uuid" <<'PY'
import ast
import sys

try:
    values = ast.literal_eval(sys.argv[1])
except Exception:
    values = []
uuid = sys.argv[2]
if not isinstance(values, list):
    values = []
if uuid not in values:
    values.append(uuid)
print("[" + ", ".join(repr(str(value)) for value in values) + "]")
PY
)"
    gsettings set org.gnome.shell enabled-extensions "$updated_enabled" || true
    echo "GNOME Shell does not see $uuid yet. Log out and back in, then run: gnome-extensions enable $uuid"
  fi
fi

echo "Installed $uuid to $target_dir"
echo "Repository: $repo_dir"
echo "Python: $python_path"

if [ "$skip_legacy_service" != "yes" ] && command -v systemctl >/dev/null 2>&1; then
  if systemctl --user list-unit-files wispr.service >/dev/null 2>&1; then
    systemctl --user disable --now wispr.service >/dev/null 2>&1 || true
  fi
  if systemctl --user list-unit-files echoscribe.service >/dev/null 2>&1; then
    systemctl --user disable --now echoscribe.service >/dev/null 2>&1 || true
  fi
  rm -f "$HOME/.config/systemd/user/wispr.service"
  rm -f "$HOME/.config/systemd/user/echoscribe.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "Removed legacy Wispr/EchoScribe user services; GNOME Shell owns the Linux dictation trigger now."
fi

