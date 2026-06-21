#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

repo_dir="$(pwd)"
config_dir="$HOME/.config/echoscribe"
config_file="$config_dir/config.toml"
env_file="${ECHOSCRIBE_ENV_FILE:-$config_dir/secrets.env}"
dry_run="no"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run="yes"
      shift
      ;;
    --help|-h)
      echo "Usage: ./install.sh [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  c_reset="$(printf '\033[0m')"
  c_blue="$(printf '\033[1;34m')"
  c_green="$(printf '\033[1;32m')"
  c_yellow="$(printf '\033[1;33m')"
  c_red="$(printf '\033[1;31m')"
  c_dim="$(printf '\033[2m')"
else
  c_reset=""
  c_blue=""
  c_green=""
  c_yellow=""
  c_red=""
  c_dim=""
fi

step_current=0
step_total=10
local_ai_host="127.0.0.1"
local_whisper_model="whisper-large-v3"
local_ollama_model="qwen2.5:7b"
install_local_whisper="no"
pull_local_ollama="no"

banner() {
  echo
  echo "${c_blue}EchoScribe Linux Setup${c_reset}"
  echo "${c_dim}======================${c_reset}"
  echo
}

step() {
  step_current=$((step_current + 1))
  printf '%s[%d/%d]%s %s\n' "$c_green" "$step_current" "$step_total" "$c_reset" "$1"
}

note() {
  printf '%s%s%s\n' "$c_yellow" "$1" "$c_reset"
}

fail() {
  printf '%s%s%s\n' "$c_red" "$1" "$c_reset" >&2
}

if [ "$dry_run" = "yes" ]; then
  banner
  step "Checking platform"
  if command -v apt-get >/dev/null 2>&1; then
    echo "Debian-based package manager: found"
  else
    note "apt-get not found; dependency installation may need a different command."
  fi
  step "Checking project files"
  test -f "$repo_dir/pyproject.toml" && echo "Python package: ok"
  test -f "$repo_dir/scripts/setup_dev.sh" && echo "Python setup script: ok"
  test -f "$repo_dir/scripts/register_chrome_host.sh" && echo "Browser native-host script: ok"
  test -d "$repo_dir/../browser-extension" && echo "Chromium extension: ok"
  test -d "$repo_dir/../firefox-extension" && echo "Firefox extension: ok"
  step "Checking optional tools"
  for tool in python3 gnome-shell gnome-extensions xdg-open google-chrome chromium microsoft-edge brave-browser firefox; do
    if command -v "$tool" >/dev/null 2>&1; then
      echo "$tool: found"
    else
      echo "$tool: missing"
    fi
  done
  note "Dry run only. No files, packages, secrets, extensions, or services were changed."
  exit 0
fi

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

detect_vram_gb() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    local mib
    mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -dc '0-9' || true)"
    if [ -n "$mib" ]; then
      awk -v mib="$mib" 'BEGIN { printf "%.0f", mib / 1024 }'
      return
    fi
  fi
  printf '0'
}

detect_ram_gb() {
  if command -v free >/dev/null 2>&1; then
    free -g | awk '/^Mem:/ { print $2; exit }'
    return
  fi
  awk '/MemTotal:/ { printf "%.0f", $2 / 1024 / 1024; exit }' /proc/meminfo 2>/dev/null || printf '0'
}

model_color() {
  local need_vram="$1"
  local need_ram="$2"
  local have_vram="$3"
  local have_ram="$4"
  if [ "$have_vram" -gt 0 ]; then
    if [ "$need_vram" -le "$have_vram" ] && [ "$need_ram" -le "$have_ram" ]; then
      printf 'green'
    elif [ "$need_vram" -le $((have_vram + 2)) ] && [ "$need_ram" -le $((have_ram + 4)) ]; then
      printf 'yellow'
    else
      printf 'red'
    fi
  elif [ "$need_ram" -le "$have_ram" ]; then
    printf 'yellow'
  else
    printf 'red'
  fi
}

choose_local_ai_summary_model() {
  local have_vram have_ram
  have_vram="$(detect_vram_gb)"
  have_ram="$(detect_ram_gb)"
  echo >&2
  echo "Local AI summary model:" >&2
  if [ "$have_vram" -gt 0 ]; then
    local gpu_name
    gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 || true)"
    echo " Hardware: NVIDIA ${gpu_name:-GPU}, ${have_vram} GB VRAM, ${have_ram} GB RAM" >&2
  else
    echo " Hardware: no NVIDIA GPU detected, ${have_ram} GB RAM" >&2
  fi
  echo " Green = comfortable, yellow = tight, red = likely too large/slow." >&2
  echo " With NVIDIA VRAM, VRAM and RAM are considered. Without it, RAM-only CPU use is estimated." >&2
  echo " The list goes from smaller/faster models to stronger/larger models." >&2
  echo >&2

  local models=(
    "llama3.1:8b|Llama 3.1 8B|6|10|Solid entry point for CPU-only systems or smaller GPUs"
    "qwen2.5:7b|Qwen2.5 7B|6|10|Recommended: very fast with strong summary quality"
    "gemma4:e4b|Gemma 4 E4B|4|8|Very small and fast Gemma option for lightweight summaries"
    "gemma4:12b|Gemma 4 12B|9|14|Good reasoning and summary quality"
    "qwen2.5:14b|Qwen2.5 14B|10|16|Stronger quality with good speed"
    "deepseek-r1:14b|DeepSeek R1 14B|10|16|Strong reasoning, may answer more verbosely"
    "gemma4:26b|Gemma 4 26B|18|24|High quality, noticeably heavier"
    "qwen2.5:32b|Qwen2.5 32B|22|32|Very strong, tight on 24 GB VRAM"
    "deepseek-r1:32b|DeepSeek R1 32B|22|32|Very strong reasoning, tight/slower"
    "gemma4:31b|Gemma 4 31B|24|32|Strongest Gemma 4 in this list, very tight"
    "mixtral:8x7b|Mixtral 8x7B|28|48|MoE model, good quality, high RAM demand"
    "llama3.3:70b|Llama 3.3 70B|48|64|Very strong, for systems with lots of RAM/VRAM"
    "qwen2.5:72b|Qwen2.5 72B|48|64|Strongest Qwen in this list, very high memory demand"
    "deepseek-r1:70b|DeepSeek R1 70B|48|64|Strongest reasoning in this list, very high memory demand"
  )

  local i=1
  for entry in "${models[@]}"; do
    IFS='|' read -r model label need_vram need_ram note <<<"$entry"
    local color marker
    color="$(model_color "$need_vram" "$need_ram" "$have_vram" "$have_ram")"
    marker=" "
    [ "$model" = "qwen2.5:7b" ] && marker="*"
    printf '%s %2d. %s [%s] needs about %s GB VRAM / %s GB RAM - %s\n' "$marker" "$i" "$model" "$color" "$need_vram" "$need_ram" "$note" >&2
    i=$((i + 1))
  done
  echo >&2

  local answer selected
  read -r -p "Choose summary model number or name [2] " answer
  answer="${answer:-2}"
  if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#models[@]}" ]; then
    selected="${models[$((answer - 1))]}"
    printf '%s' "${selected%%|*}"
    return
  fi
  printf '%s' "$answer"
}

configure_local_ai() {
  local default_whisper="n"
  local default_ollama="n"
  [ "$transcription_provider" = "localai" ] && default_whisper="y"
  [ "$summary_provider" = "localai" ] && default_ollama="y"

  echo
  step "Local AI"
  local have_vram
  have_vram="$(detect_vram_gb)"
  if [ "$have_vram" -gt 0 ]; then
    if ask_yes_no "Optional: install/start local Whisper Large (CUDA) and use it for dictation?" "$default_whisper"; then
      install_local_whisper="yes"
      transcription_provider="localai"
    fi
  else
    echo "Optional Local Whisper setup skipped: no NVIDIA GPU/VRAM was detected on this GNOME installation."
    echo "You can still configure an existing Local AI Whisper endpoint manually."
  fi

  if ask_yes_no "Optional: configure Local AI summaries with an existing Ollama service?" "$default_ollama"; then
    summary_provider="localai"
    local_ollama_model="$(choose_local_ai_summary_model)"
    pull_local_ollama="yes"
  fi

  if [ "$install_local_whisper" = "yes" ] || [ "$summary_provider" = "localai" ] || [ "$transcription_provider" = "localai" ]; then
    local_ai_host="$(prompt_default "Local AI host/IP for EchoScribe config" "$local_ai_host")"
  fi
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
    local|local-ai|local_ai) provider="localai" ;;
  esac
  case "$provider" in
    openai|gemini|anthropic|xai|elevenlabs|localai) printf '%s' "$provider" ;;
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
    echo "Supported providers: openai, gemini, anthropic, xai, elevenlabs, localai" >&2
  done
}

choose_providers() {
  echo
  echo "Choose transcription provider:"
  echo "  openai = OpenAI audio transcriptions"
  echo "  gemini = Gemini audio understanding"
  echo "  xai    = xAI/Grok STT"
  echo "  elevenlabs = ElevenLabs Scribe STT"
  echo "  localai = Local AI Whisper-compatible STT"
  transcription_provider="$(prompt_provider "Transcription provider" "openai")"
  echo
  echo "Choose web summary provider:"
  echo "  openai    = OpenAI chat summaries"
  echo "  gemini    = Gemini text summaries"
  echo "  anthropic = Claude/Anthropic text summaries"
  echo "  xai       = xAI/Grok text summaries"
  echo "  localai   = Local AI Ollama-compatible summaries"
  while true; do
    summary_provider="$(prompt_provider "Summary provider" "openai")"
    case "$summary_provider" in
      openai|gemini|anthropic|xai|localai) break ;;
      *) echo "Summary providers: openai, gemini, anthropic, xai, localai" >&2 ;;
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
  echo "  Local AI:   configure your own Ollama and Whisper-compatible endpoints"
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
  python3 - "$repo_dir/config.example.toml" "$config_file" "$dictation" "$paste_shortcut" "$transcription_provider" "$summary_provider" "$local_ai_host" "$local_whisper_model" "$local_ollama_model" <<'PY'
from pathlib import Path
import sys
import re

from echoscribe.setup_config import render_config_template

template = Path(sys.argv[1]).read_text(encoding="utf-8")
out = Path(sys.argv[2])
dictation = sys.argv[3]
paste_shortcut = sys.argv[4]
transcription_provider = sys.argv[5]
summary_provider = sys.argv[6]
local_ai_host = sys.argv[7].strip() or "127.0.0.1"
local_whisper_model = sys.argv[8].strip() or "whisper-large-v3"
local_ollama_model = sys.argv[9].strip() or "qwen2.5:7b"

text = render_config_template(
    template,
    dictation_hold=dictation,
    transcription_provider=transcription_provider,
    paste_shortcut=paste_shortcut,
)
text = text.replace('summary = "openai"', f'summary = "{summary_provider}"')
text = re.sub(r'(?m)^llm_url = "[^"]+"', f'llm_url = "http://{local_ai_host}:11434/api/chat"', text)
text = re.sub(r'(?m)^summary_model = "qwen2\.5:7b"', f'summary_model = "{local_ollama_model}"', text)
text = re.sub(r'(?m)^whisper_url = "[^"]+"', f'whisper_url = "http://{local_ai_host}:8000/v1/audio/transcriptions"', text)
text = re.sub(r'(?m)^transcription_model = "whisper-1"', f'transcription_model = "{local_whisper_model}"', text)
out.write_text(text, encoding="utf-8")
PY
}

banner
echo "Repository: $repo_dir"
echo

step "System dependencies"
if ask_yes_no "Install/update Linux packages and input/uinput permissions?" "y"; then
  run_root_script "$USER" || true
fi

echo
step "Python environment"
echo "Setting up Python environment..."
./scripts/setup_dev.sh

mkdir -p "$config_dir" "$secrets_dir"
if [ ! -f "$env_file" ] && [ -f "$secrets_dir/wispr.env" ]; then
  cp "$secrets_dir/wispr.env" "$env_file"
  chmod 600 "$env_file" 2>/dev/null || true
fi

echo
step "Providers"
choose_providers
show_api_key_links
echo
step "API keys"
configure_env_key "OPENAI_API_KEY" "OpenAI API key" "$(provider_required_flag openai)"
configure_env_key "GEMINI_API_KEY" "Gemini API key" "$(provider_required_flag gemini)"
configure_env_key "ANTHROPIC_API_KEY" "Anthropic API key" "$(provider_required_flag anthropic)"
configure_env_key "XAI_API_KEY" "xAI/Grok API key" "$(provider_required_flag xai)"
configure_env_key "ELEVENLABS_API_KEY" "ElevenLabs API key" "$(provider_required_flag elevenlabs)"
chmod 600 "$env_file" 2>/dev/null || true

configure_local_ai

step "Hotkeys"
choose_hotkeys
echo
paste_shortcut="$(prompt_default "Paste shortcut (auto, ctrl+v, ctrl+shift+v)" "auto")"
write_config

if [ "$install_local_whisper" = "yes" ] || [ "$pull_local_ollama" = "yes" ]; then
  ./scripts/install-local-ai.sh \
    $( [ "$install_local_whisper" = "yes" ] && printf '%s' "--whisper" || printf '%s' "--no-whisper" ) \
    $( [ "$pull_local_ollama" = "yes" ] && printf '%s' "--pull-ollama" || printf '%s' "--no-pull-ollama" ) \
    --whisper-model "$local_whisper_model" \
    --ollama-model "$local_ollama_model"
fi

echo
step "Desktop integration"
if command -v gnome-shell >/dev/null 2>&1; then
  echo "Installing GNOME Shell extension..."
  ./scripts/install_gnome_extension.sh
elif ask_yes_no "Install ydotool paste helper service for manual worker use?" "n"; then
  ./scripts/install_user_service.sh
fi

echo
step "Browser extension"
if ask_yes_no "Register EchoScribe browser extensions/native hosts?" "y"; then
  ./scripts/register_chrome_host.sh
fi

echo
step "Doctor"
echo "Running doctor..."
if command -v sg >/dev/null 2>&1 && getent group input >/dev/null 2>&1; then
  sg input -c "$repo_dir/.venv/bin/python -m echoscribe doctor" || "$repo_dir/.venv/bin/python" -m echoscribe doctor
else
  "$repo_dir/.venv/bin/python" -m echoscribe doctor
fi

echo
step "Done"
echo "Config: $config_file"
echo "Env:    $env_file"
echo "If the GNOME extension is not visible yet, log out and back in once, then run:"
echo "  gnome-extensions enable echoscribe@wean.de"
