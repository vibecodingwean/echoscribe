#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

repo_dir="$(pwd)"
package_root="$(cd .. && pwd)"
host_name="de.echoscribe.nativehost"
extension_uuid="echoscribe@wean.de"
config_dir="$HOME/.config/echoscribe"
config_file="$config_dir/config.toml"
secrets_file="${ECHOSCRIBE_ENV_FILE:-$config_dir/secrets.env}"
remove_gnome="no"
remove_browser_hosts="no"
remove_config="no"
remove_secrets="no"
remove_local_whisper="no"
remove_all_ollama_models="no"
uninstall_ollama="no"
remove_package="no"
non_interactive="no"
ollama_models=()

usage() {
  cat <<'USAGE'
Usage: ./uninstall.sh [options]

Interactive by default. In non-interactive mode, pass explicit removal flags.

Options:
  --all                    Remove core integration, browser hosts, runtime state, and installed code.
  --gnome                  Remove the EchoScribe GNOME Shell extension.
  --browser-hosts          Remove browser Native Messaging host manifests.
  --config                 Remove ~/.config/echoscribe.
  --secrets                Remove the EchoScribe secret env file.
  --local-whisper          Remove EchoScribe Local Whisper user service and files.
  --ollama-model <model>   Remove one Ollama model. Can be repeated; kept for automation.
  --all-ollama-models      Remove all local Ollama models.
  --uninstall-ollama       Try to uninstall the Ollama package itself.
  --remove-package         Remove the installed app directory. Refuses Git checkouts.
  --non-interactive        Do not prompt; use only selected flags.
  -h, --help               Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      remove_gnome="yes"
      remove_browser_hosts="yes"
      remove_package="yes"
      shift
      ;;
    --gnome)
      remove_gnome="yes"
      shift
      ;;
    --browser-hosts)
      remove_browser_hosts="yes"
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
    --ollama-model)
      ollama_models+=("$2")
      shift 2
      ;;
    --all-ollama-models)
      remove_all_ollama_models="yes"
      shift
      ;;
    --uninstall-ollama)
      uninstall_ollama="yes"
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

remove_browser_native_hosts() {
  local paths=(
    "$HOME/.config/google-chrome/NativeMessagingHosts/$host_name.json"
    "$HOME/.config/chromium/NativeMessagingHosts/$host_name.json"
    "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/$host_name.json"
    "$HOME/.config/microsoft-edge/NativeMessagingHosts/$host_name.json"
    "$HOME/.mozilla/native-messaging-hosts/$host_name.json"
    "$HOME/.librewolf/native-messaging-hosts/$host_name.json"
  )
  rm -f "${paths[@]}"
  echo "Removed browser Native Messaging host manifests."
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

remove_ollama_model_list() {
  if [ "${#ollama_models[@]}" -eq 0 ]; then
    echo "No Ollama models selected; skipping model removal."
    return
  fi
  for model in "${ollama_models[@]}"; do
    [ -n "$model" ] || continue
    echo "Removing Ollama model: $model"
    if command -v ollama >/dev/null 2>&1; then
      ollama rm "$model" || true
    else
      curl -fsS -X DELETE http://127.0.0.1:11434/api/delete \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"${model}\"}" >/dev/null || true
    fi
  done
}

remove_all_ollama_models() {
  local models=()
  if command -v ollama >/dev/null 2>&1; then
    mapfile -t models < <(ollama list 2>/dev/null | awk 'NR > 1 && $1 != "" { print $1 }')
  else
    if command -v python3 >/dev/null 2>&1; then
      mapfile -t models < <(python3 - <<'PY'
import json
import urllib.request

try:
    with urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=5) as response:
        payload = json.load(response)
except Exception:
    payload = {"models": []}

for item in payload.get("models", []):
    name = item.get("name")
    if name:
        print(name)
PY
)
    fi
  fi

  if [ "${#models[@]}" -eq 0 ]; then
    echo "No local Ollama models were found."
    return
  fi

  ollama_models=("${models[@]}")
  remove_ollama_model_list
}

uninstall_ollama_package() {
  if command -v apt-get >/dev/null 2>&1 && dpkg -s ollama >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1; then
      sudo apt-get remove -y ollama
    else
      echo "sudo is not installed. Run as root: apt-get remove -y ollama" >&2
      return 1
    fi
  else
    echo "Ollama was not detected as an apt package. Remove it manually if it was installed another way."
  fi
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
  ask_yes_no "Remove browser Native Messaging host manifests?" "y" && remove_browser_hosts="yes"
  ask_yes_no "Remove EchoScribe config in ~/.config/echoscribe?" "n" && remove_config="yes"
  ask_yes_no "Remove EchoScribe secret env file at $secrets_file?" "n" && remove_secrets="yes"
  ask_yes_no "Remove EchoScribe Local Whisper service, venv, and models?" "n" && remove_local_whisper="yes"
  ask_yes_no "Remove all local Ollama models? Only choose this if no other app needs them." "n" && remove_all_ollama_models="yes"
  ask_yes_no "Uninstall Ollama itself? Only choose this if no other app uses Ollama." "n" && uninstall_ollama="yes"
  ask_yes_no "Remove this installed app directory? Refuses Git checkouts." "y" && remove_package="yes"
  echo
  read -r -p "Press Enter to uninstall or type q to cancel " answer
  if [ "${answer,,}" = "q" ]; then
    echo "Uninstall canceled."
    exit 0
  fi
fi

[ "$remove_gnome" = "yes" ] && remove_gnome_extension
[ "$remove_browser_hosts" = "yes" ] && remove_browser_native_hosts
if [ "$remove_gnome" = "yes" ] || [ "$remove_package" = "yes" ]; then
  remove_obsolete_runtime_state
fi
[ "$remove_config" = "yes" ] && remove_config_files
[ "$remove_secrets" = "yes" ] && rm -f "$secrets_file" && echo "Removed secret env file: $secrets_file"
[ "$remove_local_whisper" = "yes" ] && remove_local_whisper_files
[ "${#ollama_models[@]}" -gt 0 ] && remove_ollama_model_list
[ "$remove_all_ollama_models" = "yes" ] && remove_all_ollama_models
[ "$uninstall_ollama" = "yes" ] && uninstall_ollama_package
[ "$remove_package" = "yes" ] && remove_package_directory

echo "EchoScribe uninstall finished."
