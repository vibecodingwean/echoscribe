#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
config_file="$HOME/.config/echoscribe/config.toml"
env_file="${ECHOSCRIBE_ENV_FILE:-$HOME/.config/echoscribe/secrets.env}"
local_ai_installer="${ECHOSCRIBE_LOCAL_AI_INSTALLER:-./scripts/install-local-ai.sh}"

[ -t 0 ] || { echo "Configuration requires an interactive terminal." >&2; exit 1; }
mkdir -p "$(dirname "$config_file")" "$(dirname "$env_file")"
[ -f "$config_file" ] || cp config.example.toml "$config_file"
touch "$env_file"
chmod 600 "$env_file"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  color_reset=$'\033[0m'
  color_bold=$'\033[1m'
  color_cyan=$'\033[1;36m'
  color_green=$'\033[1;32m'
  color_yellow=$'\033[1;33m'
  color_dim=$'\033[2m'
else
  color_reset=""
  color_bold=""
  color_cyan=""
  color_green=""
  color_yellow=""
  color_dim=""
fi

section() {
  local title="$1"
  printf '\n%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$color_cyan" "$color_reset"
  printf '%b  %s%b\n' "$color_cyan" "$title" "$color_reset"
  printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n\n' "$color_cyan" "$color_reset"
}

success_notice() {
  printf '\n%b✓ %s%b\n' "$color_green" "$1" "$color_reset"
}

warning_notice() {
  printf '\n%b⚠ %s%b\n' "$color_yellow" "$1" "$color_reset"
}

read_default() {
  local prompt="$1" default="$2" answer
  read -r -p "${color_bold}${prompt}${color_reset} [${default}] " answer
  printf '%s' "${answer:-$default}"
}

printf '\n%bEchoScribe configuration%b\n' "$color_bold" "$color_reset"
printf '%bProvider setup, Local AI models, and browser integration%b\n' "$color_dim" "$color_reset"

section "1 / 4  Providers"
current_transcription="$(python3 -m echoscribe config-get transcription-provider 2>/dev/null || printf 'openai')"
current_summary="$(python3 -m echoscribe config-get summary-provider 2>/dev/null || printf 'openai')"
transcription="$(read_default 'Transcription provider (openai/gemini/xai/elevenlabs/localai)' "$current_transcription")"
summary="$(read_default 'Summary provider (openai/gemini/anthropic/xai/localai)' "$current_summary")"
python3 -m echoscribe config-set transcription-provider "$transcription"
python3 -m echoscribe config-set summary-provider "$summary"

section "2 / 4  Cloud credentials"
printf '%bLocal AI does not require an API key. Cloud credentials remain optional unless their provider is selected.%b\n\n' \
  "$color_dim" "$color_reset"
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

section "3 / 4  Local AI"
local_ai_args=()
local_ai_features=()
if [ "$transcription" = "localai" ]; then
  local_ai_args+=(--whisper)
  local_ai_features+=("local speech-to-text with Whisper")
fi
if [ "$summary" = "localai" ]; then
  local_ai_args+=(--pull-ollama)
  local_ai_features+=("local summaries with Ollama")
fi

if [ "${#local_ai_args[@]}" -gt 0 ]; then
  warning_notice "Local AI was selected and needs an additional model setup."
  printf '\nThe following components will be prepared:\n'
  for feature in "${local_ai_features[@]}"; do
    printf '  • %s\n' "$feature"
  done
  printf '\n%bCommand:%b\n  %s' "$color_bold" "$color_reset" "$local_ai_installer"
  printf ' %q' "${local_ai_args[@]}"
  printf '\n\n'
  read -r -p "${color_bold}Run Local AI setup now?${color_reset} [Y/n] " local_ai_answer
  if [[ ! "${local_ai_answer,,}" =~ ^(n|no|nein)$ ]]; then
    if "$local_ai_installer" "${local_ai_args[@]}"; then
      success_notice "Local AI setup completed."
    else
      warning_notice "Local AI setup did not complete. EchoScribe core setup will continue."
      printf 'Retry later with:\n  %s' "$local_ai_installer"
      printf ' %q' "${local_ai_args[@]}"
      printf '\n'
    fi
  else
    warning_notice "Local AI is selected but its models have not been configured yet."
    printf 'Run this command later:\n  %s' "$local_ai_installer"
    printf ' %q' "${local_ai_args[@]}"
    printf '\n'
  fi
else
  printf 'Local AI is not selected for transcription or summaries.\n'
  printf 'You can configure it later with:\n  %s --help\n' "$local_ai_installer"
fi

section "4 / 4  Desktop and browser integration"
echo "GNOME shortcut and feedback are configured in Extension Preferences."
read -r -p "${color_bold}Register Chromium/Firefox native messaging hosts now?${color_reset} [y/N] " browser
if [[ "${browser,,}" =~ ^(y|yes|j|ja)$ ]]; then
  ./scripts/register_chrome_host.sh
fi

success_notice "EchoScribe configuration completed."
