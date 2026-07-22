#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
config_file="$HOME/.config/echoscribe/config.toml"
env_file="${ECHOSCRIBE_ENV_FILE:-$HOME/.config/echoscribe/secrets.env}"

[ -t 0 ] || { echo "Configuration requires an interactive terminal." >&2; exit 1; }
mkdir -p "$(dirname "$config_file")" "$(dirname "$env_file")"
[ -f "$config_file" ] || cp config.example.toml "$config_file"
touch "$env_file"
chmod 600 "$env_file"

read_default() {
  local prompt="$1" default="$2" answer
  read -r -p "$prompt [$default] " answer
  printf '%s' "${answer:-$default}"
}

current_transcription="$(python3 -m echoscribe config-get transcription-provider 2>/dev/null || printf 'openai')"
current_summary="$(python3 -m echoscribe config-get summary-provider 2>/dev/null || printf 'openai')"
transcription="$(read_default 'Transcription provider (openai/gemini/xai/elevenlabs/localai)' "$current_transcription")"
summary="$(read_default 'Summary provider (openai/gemini/anthropic/xai/localai)' "$current_summary")"
python3 -m echoscribe config-set transcription-provider "$transcription"
python3 -m echoscribe config-set summary-provider "$summary"

for item in "openai:OPENAI_API_KEY" "gemini:GEMINI_API_KEY" "anthropic:ANTHROPIC_API_KEY" "xai:XAI_API_KEY" "elevenlabs:ELEVENLABS_API_KEY"; do
  provider="${item%%:*}"
  env_name="${item#*:}"
  required="no"
  [ "$transcription" = "$provider" ] && required="yes"
  [ "$summary" = "$provider" ] && required="yes"
  answer=""
  if [ "$required" = "yes" ]; then answer="yes"; else read -r -p "Set optional $provider API key? [y/N] " answer; fi
  if [[ "${answer,,}" =~ ^(y|yes|j|ja)$ ]]; then
    read -r -s -p "$provider API key (leave empty to keep existing): " secret
    echo
    if [ -n "$secret" ]; then
      printf '%s\n' "$secret" | python3 -m echoscribe config-set api-key "$provider"
    elif ! grep -q "^${env_name}=" "$env_file" && [ "$required" = "yes" ]; then
      echo "$provider is selected but its API key is still missing." >&2
    fi
  fi
done

echo "GNOME shortcut and feedback are configured in Extension Preferences."
echo "Optional Local AI installer: ./scripts/install-local-ai.sh --help"
read -r -p "Register Chromium/Firefox native messaging hosts now? [y/N] " browser
if [[ "${browser,,}" =~ ^(y|yes|j|ja)$ ]]; then
  ./scripts/register_chrome_host.sh
fi
