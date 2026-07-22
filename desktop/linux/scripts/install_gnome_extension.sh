#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

uuid="echoscribe@wean.de"
old_uuid="wispr@wean.de"
app_dir="$(pwd)"
source_dir="$app_dir/gnome-extension/$uuid"
target_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$uuid"
skip_enable="no"
skip_settings="no"
toggle_shortcut=""
extension_changed="no"
was_active="no"
was_loaded="no"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-dir) target_dir="$2"; shift 2 ;;
    --repo-dir) app_dir="$(cd "$2" && pwd)"; source_dir="$app_dir/gnome-extension/$uuid"; shift 2 ;;
    --skip-enable) skip_enable="yes"; shift ;;
    --skip-settings) skip_settings="yes"; shift ;;
    --toggle-shortcut) toggle_shortcut="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -f "$source_dir/metadata.json" ] || { echo "Extension source missing: $source_dir" >&2; exit 1; }
[ -f "$source_dir/extension.js" ] || { echo "Extension.js missing: $source_dir" >&2; exit 1; }

if [ -d "$target_dir" ] && ! diff -qr --exclude=gschemas.compiled "$source_dir" "$target_dir" >/dev/null 2>&1; then
  extension_changed="yes"
fi
if command -v gnome-extensions >/dev/null 2>&1; then
  previous_info="$(gnome-extensions info "$uuid" 2>/dev/null || true)"
  previous_state="$(awk -F': ' '/^[[:space:]]*State:/ {print toupper($2); exit}' <<<"$previous_info")"
  case "$previous_state" in
    ACTIVE|ENABLED) was_active="yes"; was_loaded="yes" ;;
    ERROR) was_loaded="yes" ;;
  esac
fi

target_parent="$(dirname "$target_dir")"
stage="$target_parent/.${uuid}.stage.$$"
backup="$target_parent/.${uuid}.old.$$"
mkdir -p "$target_parent"
rm -rf "$stage" "$backup"
cp -a "$source_dir" "$stage"
glib-compile-schemas --strict "$stage/schemas"
test -s "$stage/schemas/gschemas.compiled"

if [ "$skip_enable" != "yes" ] \
  && command -v gnome-extensions >/dev/null 2>&1 \
  && ! { [ "$extension_changed" = "yes" ] && [ "$was_active" = "yes" ]; }; then
  gnome-extensions disable "$uuid" >/dev/null 2>&1 || true
fi

if [ -e "$target_dir" ]; then
  mv "$target_dir" "$backup"
fi
if ! mv "$stage" "$target_dir"; then
  [ ! -e "$backup" ] || mv "$backup" "$target_dir"
  exit 1
fi
rm -rf "$backup"

if command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions disable "$old_uuid" >/dev/null 2>&1 || true
fi
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$old_uuid"

python_path="$(command -v python3)"
if [ "$skip_settings" != "yes" ] && command -v gsettings >/dev/null 2>&1; then
  gsettings --schemadir "$target_dir/schemas" set org.gnome.shell.extensions.echoscribe install-path "$app_dir"
  gsettings --schemadir "$target_dir/schemas" set org.gnome.shell.extensions.echoscribe python-path "$python_path"
  if [ -n "$toggle_shortcut" ]; then
    gsettings --schemadir "$target_dir/schemas" set org.gnome.shell.extensions.echoscribe toggle-shortcut "['$toggle_shortcut']"
    gsettings --schemadir "$target_dir/schemas" set org.gnome.shell.extensions.echoscribe echoscribe-toggle-shortcut "['$toggle_shortcut']"
    gsettings --schemadir "$target_dir/schemas" set org.gnome.shell.extensions.echoscribe echoscribe-ptt-shortcut "['$toggle_shortcut']"
  fi
fi

if [ "$skip_enable" != "yes" ]; then
  if ! command -v gnome-extensions >/dev/null 2>&1; then
    echo "GNOME cannot verify the extension because gnome-extensions is missing." >&2
    exit 1
  fi
  if ! gnome-extensions info "$uuid" >/dev/null 2>&1; then
    echo "GNOME Shell has not recognized $uuid yet." >&2
    echo "Log out and back in, then run: gnome-extensions enable $uuid" >&2
    exit 3
  fi
  if ! { [ "$extension_changed" = "yes" ] && [ "$was_active" = "yes" ]; }; then
    gnome-extensions enable "$uuid" >/dev/null 2>&1 || {
      echo "GNOME recognized the extension but could not enable it." >&2
      echo "Log out and back in, then run: gnome-extensions enable $uuid" >&2
      exit 3
    }
  fi
  info="$(gnome-extensions info "$uuid" 2>/dev/null || true)"
  state="$(awk -F': ' '/^[[:space:]]*State:/ {print toupper($2); exit}' <<<"$info")"
  case "$state" in
    ACTIVE|ENABLED) ;;
    *)
      echo "GNOME reports extension state ${state:-unknown}, not active." >&2
      echo "Log out and back in, then run: gnome-extensions enable $uuid" >&2
      exit 3
      ;;
  esac
  if [ "$extension_changed" = "yes" ] && [ "$was_loaded" = "yes" ]; then
    echo "GNOME still has the previous EchoScribe JavaScript module cached." >&2
    echo "Log out and back in once to activate the updated extension code." >&2
    exit 3
  fi
fi

echo "Installed and validated $uuid at $target_dir"
