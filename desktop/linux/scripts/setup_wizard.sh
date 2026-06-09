#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

repo_dir="$(pwd)"
config_dir="$HOME/.config/echoscribe"
config_file="$config_dir/config.toml"
secrets_dir="$HOME/.secrets"
env_file="${ECHOSCRIBE_ENV_FILE:-$secrets_dir/echoscribe.env}"

if [ ! -t 0 ]; then
  echo "This setup wizard is interactive. Run it from a terminal." >&2
  exit 1
fi

ask_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
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

run_root_script() {
  local target_user="$1"
  if [ "$(id -u)" -eq 0 ]; then
    ./scripts/install_linux_deps.sh "$target_user"
  elif command -v sudo >/dev/null 2>&1; then
    sudo ./scripts/install_linux_deps.sh "$target_user"
  else
    echo "sudo is not installed. Run this manually as root:"
    echo "  ./scripts/install_linux_deps.sh \"$target_user\""
    return 1
  fi
}

write_env_value() {
  local key="$1"
  local value="$2"
  mkdir -p "$(dirname "$env_file")"
  touch "$env_file"
  chmod 600 "$env_file"
  if grep -q "^${key}=" "$env_file"; then
    python3 - "$env_file" "$key" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines()
out = []
for line in lines:
    if line.startswith(f"{key}="):
        out.append(f"{key}={value}")
    else:
        out.append(line)
path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
PY
  else
    printf '%s=%s\n' "$key" "$value" >>"$env_file"
  fi
}

configure_env_key() {
  local key="$1"
  local label="$2"
  local required="${3:-no}"
  local existing=""
  if [ -f "$env_file" ]; then
    existing="$(grep -E "^${key}=" "$env_file" | tail -n 1 | cut -d= -f2- || true)"
  fi

  if [ -n "$existing" ]; then
    if ! ask_yes_no "$label is already set. Replace it?" "n"; then
      return
    fi
  elif [ "$required" != "yes" ]; then
    if ! ask_yes_no "Set optional $label now?" "n"; then
      return
    fi
  fi

  local value=""
  while [ -z "$value" ]; do
    read -r -s -p "$label: " value
    echo
    if [ -z "$value" ] && [ "$required" = "yes" ]; then
      echo "$label is required for the selected provider setup."
    elif [ -z "$value" ]; then
      return
    fi
  done
  write_env_value "$key" "$value"
}

normalize_provider() {
  local provider="${1,,}"
  case "$provider" in
    gpt|chatgpt) provider="openai" ;;
    google) provider="gemini" ;;
    grok) provider="xai" ;;
    claude) provider="anthropic" ;;
    eleven|11labs) provider="elevenlabs" ;;
  esac
  case "$provider" in
    openai|gemini|anthropic|xai|elevenlabs) printf '%s' "$provider" ;;
    *) return 1 ;;
  esac
}

prompt_provider() {
  local prompt="$1"
  local default="$2"
  local answer normalized
  while true; do
    read -r -p "$prompt [$default] " answer
    answer="${answer:-$default}"
    if normalized="$(normalize_provider "$answer")"; then
      printf '%s' "$normalized"
      return
    fi
    echo "Supported providers: openai, gemini, anthropic, xai, elevenlabs" >&2
  done
}

choose_providers() {
  echo
  echo "Choose transcription provider:"
  echo "  openai = OpenAI audio transcriptions"
  echo "  gemini = Gemini audio understanding"
  echo "  xai    = xAI/Grok STT"
  echo "  elevenlabs = ElevenLabs Scribe STT"
  transcription_provider="$(prompt_provider "Transcription provider" "openai")"
  echo
  echo "Choose web summary provider:"
  echo "  openai    = OpenAI chat summaries"
  echo "  gemini    = Gemini text summaries"
  echo "  anthropic = Claude/Anthropic text summaries"
  echo "  xai       = xAI/Grok text summaries"
  while true; do
    summary_provider="$(prompt_provider "Summary provider" "openai")"
    case "$summary_provider" in
      openai|gemini|anthropic|xai) break ;;
      *) echo "Summary providers: openai, gemini, anthropic, xai" >&2 ;;
    esac
  done
}

show_api_key_links() {
  echo
  echo "API key pages:"
  echo "  OpenAI:     https://platform.openai.com/api-keys"
  echo "  Gemini:     https://aistudio.google.com/api-keys"
  echo "  Anthropic:  https://console.anthropic.com/settings/keys"
  echo "  xAI:        https://console.x.ai"
  echo "  ElevenLabs: https://elevenlabs.io/app/developers/api-keys"
}

provider_required_flag() {
  local provider="$1"
  if [ "$transcription_provider" = "$provider" ] || [ "${summary_provider:-}" = "$provider" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

choose_hotkeys() {
  echo
  echo "Choose hotkeys:"
  echo "  1) Super+Alt+A / Super+Alt+S (GNOME-safe recommendation)"
  echo "  2) Ctrl+Alt+A / Ctrl+Alt+S"
  echo "  3) AltGr+A / AltGr+S (rightalt)"
  echo "  4) Fn+A / Fn+S (only if your laptop emits KEY_FN)"
  echo "  5) Custom"
  local choice
  read -r -p "Selection [1] " choice
  choice="${choice:-1}"
  case "$choice" in
    1) dictation="leftmeta+leftalt+a" ;;
    2) dictation="leftctrl+leftalt+a" ;;
    3) dictation="rightalt+a" ;;
    4) dictation="fn+a" ;;
    5)
      dictation="$(prompt_default "Dictation hold hotkey" "leftmeta+leftalt+a")"
      ;;
    *)
      dictation="leftmeta+leftalt+a"
      ;;
  esac
}

write_config() {
  mkdir -p "$config_dir"
  if [ -f "$config_file" ]; then
    cp "$config_file" "$config_file.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  python3 - "$repo_dir/config.example.toml" "$config_file" "$dictation" "$paste_shortcut" "$transcription_provider" "$summary_provider" <<'PY'
from pathlib import Path
import sys

from echoscribe.setup_config import render_config_template

template = Path(sys.argv[1]).read_text(encoding="utf-8")
out = Path(sys.argv[2])
dictation = sys.argv[3]
paste_shortcut = sys.argv[4]
transcription_provider = sys.argv[5]
summary_provider = sys.argv[6]

text = render_config_template(
    template,
    dictation_hold=dictation,
    transcription_provider=transcription_provider,
    paste_shortcut=paste_shortcut,
)
text = text.replace('summary = "openai"', f'summary = "{summary_provider}"')
out.write_text(text, encoding="utf-8")
PY
}

echo "EchoScribe setup wizard"
echo "Repository: $repo_dir"
echo

if ask_yes_no "Install/update Linux packages and input/uinput permissions?" "y"; then
  run_root_script "$USER" || true
fi

echo
echo "Setting up Python environment..."
./scripts/setup_dev.sh

mkdir -p "$config_dir" "$secrets_dir"
if [ ! -f "$env_file" ] && [ -f "$secrets_dir/wispr.env" ]; then
  cp "$secrets_dir/wispr.env" "$env_file"
  chmod 600 "$env_file" 2>/dev/null || true
fi

echo
choose_providers
show_api_key_links
echo
configure_env_key "OPENAI_API_KEY" "OpenAI API key" "$(provider_required_flag openai)"
configure_env_key "GEMINI_API_KEY" "Gemini API key" "$(provider_required_flag gemini)"
configure_env_key "ANTHROPIC_API_KEY" "Anthropic API key" "$(provider_required_flag anthropic)"
configure_env_key "XAI_API_KEY" "xAI/Grok API key" "$(provider_required_flag xai)"
configure_env_key "ELEVENLABS_API_KEY" "ElevenLabs API key" "$(provider_required_flag elevenlabs)"
chmod 600 "$env_file" 2>/dev/null || true

choose_hotkeys
echo
paste_shortcut="$(prompt_default "Paste shortcut (auto, ctrl+v, ctrl+shift+v)" "auto")"
write_config

echo
if command -v gnome-shell >/dev/null 2>&1; then
  echo "Installing GNOME Shell extension..."
  ./scripts/install_gnome_extension.sh
elif ask_yes_no "Install ydotool paste helper service for manual worker use?" "n"; then
  ./scripts/install_user_service.sh
fi

echo
if ask_yes_no "Register the EchoScribe Chrome browser plugin/native host?" "y"; then
  ./scripts/register_chrome_host.sh
fi

echo
echo "Running doctor..."
if command -v sg >/dev/null 2>&1 && getent group input >/dev/null 2>&1; then
  sg input -c "$repo_dir/.venv/bin/python -m echoscribe doctor" || "$repo_dir/.venv/bin/python" -m echoscribe doctor
else
  "$repo_dir/.venv/bin/python" -m echoscribe doctor
fi

echo
echo "Config: $config_file"
echo "Env:    $env_file"
echo "If the GNOME extension is not visible yet, log out and back in once, then run:"
echo "  gnome-extensions enable echoscribe@wean.de"
