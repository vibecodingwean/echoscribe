#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
package_root="$(cd "$script_dir/.." && pwd)"
install_root="${ECHOSCRIBE_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/echoscribe/app}"
installed_linux="$install_root/linux"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/echoscribe"
install_state_file="$state_dir/install-state"
config_dir="$HOME/.config/echoscribe"
config_file="$config_dir/config.toml"
dry_run="no"
reconfigure="no"
skip_deps="no"

usage() { echo "Usage: ./install.sh [--dry-run] [--reconfigure] [--skip-deps]"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run="yes"; shift ;;
    --reconfigure) reconfigure="yes"; shift ;;
    --skip-deps) skip_deps="yes"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

validate_tree() {
  local root="$1"
  local required=(
    "linux/pyproject.toml"
    "linux/echoscribe/gnome_worker.py"
    "linux/gnome-extension/echoscribe@wean.de/metadata.json"
    "linux/gnome-extension/echoscribe@wean.de/extension.js"
  )
  for item in "${required[@]}"; do
    [ -f "$root/$item" ] || { echo "Incomplete EchoScribe package: missing $item" >&2; return 1; }
  done
}

validate_tree "$package_root"

had_install="no"
if [ -f "$installed_linux/echoscribe/gnome_worker.py" ]; then
  had_install="yes"
fi
install_phase=""
if [ -f "$install_state_file" ]; then
  install_phase="$(tr -d '\r\n' <"$install_state_file")"
fi
if [ -z "$install_phase" ] \
  && [ "$had_install" = "yes" ] \
  && [ -f "$config_file" ] \
  && cmp -s "$config_file" "$installed_linux/config.example.toml" \
  && [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/echoscribe@wean.de/extension.js" ] \
  && { ! command -v gnome-extensions >/dev/null 2>&1 || ! gnome-extensions info echoscribe@wean.de >/dev/null 2>&1; }; then
  # Compatibility recovery for installs interrupted before install-state existed.
  install_phase="configuring"
fi

if [ "$dry_run" = "yes" ]; then
  echo "EchoScribe dry run"
  echo "Source: $package_root"
  echo "Target: $install_root"
  for tool in python3 ffmpeg arecord glib-compile-schemas gnome-shell gnome-extensions; do
    printf '%s: %s\n' "$tool" "$(command -v "$tool" 2>/dev/null || echo missing)"
  done
  echo "No files, packages, settings, or services were changed."
  exit 0
fi

mkdir -p "$state_dir"
if [ -z "$install_phase" ] && [ "$had_install" = "no" ]; then
  install_phase="configuring"
fi
if [ -n "$install_phase" ] && [ ! -f "$install_state_file" ]; then
  printf '%s\n' "$install_phase" >"$install_state_file"
fi

if [ "$skip_deps" != "yes" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    "$script_dir/scripts/install_linux_deps.sh"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$script_dir/scripts/install_linux_deps.sh"
  else
    echo "sudo is unavailable; rerun with --skip-deps after installing dependencies." >&2
    exit 1
  fi
fi

parent="$(dirname "$install_root")"
stage="$parent/.echoscribe-app.stage.$$"
backup="$parent/.echoscribe-app.old.$$"
mkdir -p "$parent"
rm -rf "$stage" "$backup"
mkdir -p "$stage"
(cd "$package_root" && tar \
  --exclude='./.git' \
  --exclude='*/__pycache__' \
  --exclude='*.pyc' \
  --exclude='./linux/.venv' \
  --exclude='./windows' \
  -cf - .) | (cd "$stage" && tar -xf -)

validate_tree "$stage"
PYTHONPYCACHEPREFIX="$stage/.validation-pycache" python3 -m compileall -q "$stage/linux/echoscribe"
rm -rf "$stage/.validation-pycache"
glib-compile-schemas --strict "$stage/linux/gnome-extension/echoscribe@wean.de/schemas"
if command -v node >/dev/null 2>&1; then
  node --check "$stage/linux/gnome-extension/echoscribe@wean.de/extension.js"
  node --check "$stage/linux/gnome-extension/echoscribe@wean.de/prefs.js"
  node --check "$stage/linux/gnome-extension/echoscribe@wean.de/logic.js"
fi
for script in "$stage/linux"/*.sh "$stage/linux/scripts"/*.sh; do
  bash -n "$script"
done

if [ "$script_dir" != "$installed_linux" ]; then
  if [ -e "$install_root" ]; then
    mv "$install_root" "$backup"
  fi
  if ! mv "$stage" "$install_root"; then
    [ ! -e "$backup" ] || mv "$backup" "$install_root"
    exit 1
  fi
  rm -rf "$backup"
else
  rm -rf "$stage"
fi

mkdir -p "$config_dir"
first_install="no"
if [ ! -f "$config_file" ]; then
  cp "$installed_linux/config.example.toml" "$config_file"
  chmod 600 "$config_file"
  first_install="yes"
fi
if [ "$reconfigure" = "yes" ]; then
  cp "$config_file" "$config_file.bak.$(date +%Y%m%d-%H%M%S)"
fi
if [ "$first_install" = "yes" ] || [ "$reconfigure" = "yes" ] || [ "$install_phase" = "configuring" ]; then
  if [ -t 0 ]; then
    "$installed_linux/scripts/setup_wizard.sh"
  else
    echo "Non-interactive install: kept configuration in $config_file"
  fi
fi

chmod 600 "$config_file"
install_phase="integrating"
printf '%s\n' "$install_phase" >"$install_state_file"

"$installed_linux/scripts/cleanup_legacy.sh"
"$installed_linux/scripts/cleanup_legacy_browser_integration.sh"
"$installed_linux/scripts/install_gnome_extension.sh"
rm -f "$install_state_file"

echo "EchoScribe installed successfully."
echo "App: $install_root"
echo "Config and secrets were preserved in: $config_dir"
echo
echo "Optional Local Whisper setup or model change:"
echo "  $installed_linux/scripts/install-local-ai.sh --whisper"
