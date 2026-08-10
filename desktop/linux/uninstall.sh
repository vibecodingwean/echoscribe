#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

repo_dir="$(pwd)"
package_root="$(cd .. && pwd)"
extension_uuid="echoscribe@wean.de"
config_dir="$HOME/.config/echoscribe"
config_file="$config_dir/config.toml"
secrets_file="${ECHOSCRIBE_ENV_FILE:-$config_dir/secrets.env}"
remove_gnome="no"
remove_config="no"
remove_secrets="no"
remove_local_whisper="no"
remove_package="no"
non_interactive="no"

usage() {
  cat <<'USAGE'
Usage: ./uninstall.sh [options]

Interactive by default. In non-interactive mode, pass explicit removal flags.

Options:
  --all                    Remove core integration, runtime state, and installed code.
  --gnome                  Remove the EchoScribe GNOME Shell extension.
  --config                 Remove ~/.config/echoscribe.
  --secrets                Remove the EchoScribe secret env file.
  --local-whisper          Remove EchoScribe Local Whisper user service and files.
  --remove-package         Remove the installed app directory. Refuses Git checkouts.
  --non-interactive        Do not prompt; use only selected flags.
  -h, --help               Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      remove_gnome="yes"
      remove_package="yes"
      shift
      ;;
    --gnome)
      remove_gnome="yes"
      shift
      ;;

    --config)
      remove_config="yes"
      shift
      ;;
    --secrets)
      remove_secrets="yes"
      shift
      ;;
    --local-whisper)
      remove_local_whisper="yes"
      shift
      ;;
    --remove-package)
      remove_package="yes"
      shift
      ;;
    --non-interactive)
      non_interactive="yes"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

"$repo_dir/scripts/cleanup_legacy_browser_integration.sh"

ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local suffix="[y/N]"
  if [ "$default" = "y" ]; then
    suffix="[Y/n]"
  fi
  local answer
  read -r -p "$prompt $suffix " answer
  answer="${answer:-$default}"
  case "${answer,,}" in
    y|yes|j|ja) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local answer
  read -r -p "$prompt [$default] " answer
  printf '%s' "${answer:-$default}"
}

remove_gnome_extension() {
  local target_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$extension_uuid"
  if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions disable "$extension_uuid" >/dev/null 2>&1 || true
  fi
  rm -rf "$target_dir"
  echo "Removed GNOME extension: $target_dir"
}


remove_local_whisper_files() {
  local root="${XDG_DATA_HOME:-$HOME/.local/share}/echoscribe/local-ai"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now echoscribe-local-whisper.service >/dev/null 2>&1 || true
    rm -f "$HOME/.config/systemd/user/echoscribe-local-whisper.service"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi
  if [ -f "$root/whisper-server.pid" ] && kill -0 "$(cat "$root/whisper-server.pid")" 2>/dev/null; then
    kill "$(cat "$root/whisper-server.pid")" 2>/dev/null || true
  fi
  pkill -f 'uvicorn server:app.*echoscribe/local-ai' 2>/dev/null || true
  rm -rf "$root"
  echo "Removed Local Whisper files: $root"
}

remove_obsolete_runtime_state() {
  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}/echoscribe"
  if [ -f "$repo_dir/echoscribe/gnome_worker.py" ] && command -v python3 >/dev/null 2>&1; then
    PYTHONPATH="$repo_dir" python3 -m echoscribe gnome-worker cancel --json >/dev/null 2>&1 || true
  fi
  pkill -f 'python .* -m echoscribe run' 2>/dev/null || true
  pkill -f 'python .* -m echoscribe sideband' 2>/dev/null || true
  rm -f \
    "$state_root/sideband.pid" \
    "$state_root/sideband.log" \
    "$state_root/sideband.mode" \
    "$state_root/sideband.shortcut" \
    "$state_root/focus-app-hint" \
    "$state_root/gnome-state.json" \
    "$state_root/gnome-worker.lock" \
    "$state_root/gnome-recorder.log" \
    "$state_root/install-state"
  echo "Removed obsolete EchoScribe runtime state."
}

remove_config_files() {
  rm -f "$config_file" "$config_file".bak.*
  rmdir "$config_dir" 2>/dev/null || true
  echo "Removed config files; secrets were retained unless --secrets was selected."
}

remove_package_directory() {
  if [ -d "$package_root/.git" ] || [ -d "$repo_dir/.git" ]; then
    echo "Refusing to remove a Git checkout: $package_root" >&2
    return 1
  fi
  case "$package_root" in
    "$HOME"|"."|"/"|"/tmp"|"/var"|"/usr"|"/home")
      echo "Refusing to remove suspicious package path: $package_root" >&2
      return 1
      ;;
  esac
  rm -rf "$package_root"
  echo "Removed package directory: $package_root"
}

if [ "$non_interactive" != "yes" ]; then
  echo
  echo "EchoScribe Linux/GNOME Uninstall"
  echo "================================="
  echo "Package folder: $package_root"
  echo
  ask_yes_no "Remove EchoScribe GNOME Shell extension?" "y" && remove_gnome="yes"
  ask_yes_no "Remove EchoScribe config in ~/.config/echoscribe?" "n" && remove_config="yes"
  ask_yes_no "Remove EchoScribe secret env file at $secrets_file?" "n" && remove_secrets="yes"
  ask_yes_no "Remove EchoScribe Local Whisper service, venv, and models?" "n" && remove_local_whisper="yes"
  ask_yes_no "Remove this installed app directory? Refuses Git checkouts." "y" && remove_package="yes"
  echo
  read -r -p "Press Enter to uninstall or type q to cancel " answer
  if [ "${answer,,}" = "q" ]; then
    echo "Uninstall canceled."
    exit 0
  fi
fi

[ "$remove_gnome" = "yes" ] && remove_gnome_extension
if [ "$remove_gnome" = "yes" ] || [ "$remove_package" = "yes" ]; then
  remove_obsolete_runtime_state
fi
[ "$remove_config" = "yes" ] && remove_config_files
[ "$remove_secrets" = "yes" ] && rm -f "$secrets_file" && echo "Removed secret env file: $secrets_file"
[ "$remove_local_whisper" = "yes" ] && remove_local_whisper_files
[ "$remove_package" = "yes" ] && remove_package_directory

echo "EchoScribe uninstall finished."
