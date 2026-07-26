#!/usr/bin/env bash
set -euo pipefail

# Hardware values are serialized as JSON numbers. Keep decimal parsing stable
# even when the desktop locale formats them with a comma.
export LC_NUMERIC=C

install_whisper="no"
pull_ollama="no"
install_ollama="auto"
whisper_model="whisper-large-v3"
whisper_port="8000"
whisper_device="auto"
ollama_model="qwen3.5:9b"
ollama_model_explicit="no"
ollama_host="127.0.0.1"
ollama_port="11434"
recommend_models="no"
use_canirun="yes"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --whisper)
      install_whisper="yes"
      shift
      ;;
    --no-whisper)
      install_whisper="no"
      shift
      ;;
    --pull-ollama)
      pull_ollama="yes"
      shift
      ;;
    --no-pull-ollama)
      pull_ollama="no"
      shift
      ;;
    --whisper-model)
      whisper_model="$2"
      shift 2
      ;;
    --whisper-port)
      whisper_port="$2"
      shift 2
      ;;
    --whisper-device)
      whisper_device="$2"
      shift 2
      ;;
    --ollama-model)
      ollama_model="$2"
      ollama_model_explicit="yes"
      shift 2
      ;;
    --recommend-models)
      recommend_models="yes"
      shift
      ;;
    --no-canirun)
      use_canirun="no"
      shift
      ;;
    --install-ollama)
      install_ollama="yes"
      shift
      ;;
    --no-install-ollama)
      install_ollama="no"
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: ./scripts/install-local-ai.sh [options]

Options:
  --whisper                  Install/start the local Faster-Whisper server.
  --pull-ollama              Pull/check the selected Ollama model.
  --install-ollama           Install Ollama if the ollama command is missing.
  --no-install-ollama        Do not install Ollama; fail if it is unavailable.
  --whisper-model <model>    Whisper model name, default whisper-large-v3.
  --whisper-port <port>      Local Whisper HTTP port, default 8000.
  --whisper-device <device>  Backend: auto, cuda, or cpu; default auto.
  --ollama-model <model>     Use this exact Ollama model and skip model selection.
  --recommend-models         Show hardware-based model recommendations without installing.
  --no-canirun               Use only EchoScribe's three built-in recommendations.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

case "$whisper_device" in
  auto|cuda|cpu) ;;
  *) echo "Invalid Whisper device: $whisper_device (expected auto, cuda, or cpu)" >&2; exit 2 ;;
esac

if [ "$install_whisper" != "yes" ] && [ "$pull_ollama" != "yes" ] && [ "$recommend_models" != "yes" ]; then
  echo "Local AI setup skipped."
  exit 0
fi

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
root="$data_home/echoscribe/local-ai"
venv="$root/.venv"
logs="$root/logs"
ollama_unit="ollama.service"
ollama_url="http://${ollama_host}:${ollama_port}"

step() {
  printf 'Local AI: %s\n' "$1"
}

hardware_ram_gb=""
hardware_cpu_name=""
hardware_gpu_name=""
hardware_vram_gb="0"
hardware_vram_source="not detected"
hardware_unified="no"
selected_ollama_model="$ollama_model"
api_model_tags=()
api_model_names=()
api_model_quants=()
api_model_grades=()
api_model_statuses=()

builtin_model_tags=(
  "gemma4:e2b-it-qat"
  "qwen3.5:9b"
  "qwen3.6:35b-a3b-mtp-q4_K_M"
)
builtin_model_names=(
  "Fast: Gemma 4 E2B IT QAT"
  "Recommended: Qwen 3.5 9B"
  "Maximum quality: Qwen 3.6 35B-A3B MTP"
)
builtin_model_vram_gb=(5 8 26)
builtin_model_ram_gb=(8 12 32)
builtin_model_notes=(
  "small and quick for lightweight summaries"
  "best default balance for multilingual summaries"
  "strongest option; longer cold start and much higher memory use"
)
builtin_canirun_ids=(
  "gemma4-e2b-it"
  "qwen3.5-9b"
  "qwen3.6-35b-a3b"
)

detect_local_hardware() {
  hardware_ram_gb="${ECHOSCRIBE_HARDWARE_RAM_GB:-}"
  if [ -z "$hardware_ram_gb" ]; then
    hardware_ram_gb="$(LC_ALL=C awk '/^MemTotal:/ { printf "%.1f", $2 / 1024 / 1024 }' /proc/meminfo 2>/dev/null || true)"
  fi
  hardware_ram_gb="${hardware_ram_gb/,/.}"
  hardware_ram_gb="${hardware_ram_gb:-0}"

  hardware_cpu_name="${ECHOSCRIBE_HARDWARE_CPU_NAME:-}"
  if [ -z "$hardware_cpu_name" ] && [ -r /proc/cpuinfo ]; then
    hardware_cpu_name="$(LC_ALL=C awk -F: '
      /^model name[[:space:]]*:/ || /^Hardware[[:space:]]*:/ {
        sub(/^[[:space:]]+/, "", $2)
        print $2
        exit
      }
    ' /proc/cpuinfo 2>/dev/null || true)"
  fi
  if [ -z "$hardware_cpu_name" ] && command -v lscpu >/dev/null 2>&1; then
    hardware_cpu_name="$(LC_ALL=C lscpu 2>/dev/null | awk -F: '/^Model name/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }')"
  fi
  hardware_cpu_name="${hardware_cpu_name:-Unknown CPU}"

  hardware_gpu_name="${ECHOSCRIBE_HARDWARE_GPU_NAME:-}"
  hardware_vram_gb="${ECHOSCRIBE_HARDWARE_VRAM_GB:-0}"
  hardware_vram_gb="${hardware_vram_gb/,/.}"
  hardware_vram_source="${ECHOSCRIBE_HARDWARE_VRAM_SOURCE:-not detected}"
  hardware_unified="${ECHOSCRIBE_HARDWARE_UNIFIED:-no}"

  if [ -z "$hardware_gpu_name" ] && command -v nvidia-smi >/dev/null 2>&1; then
    local gpu_line
    gpu_line="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 || true)"
    if [[ "$gpu_line" =~ ^[[:space:]]*(.+),[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
      hardware_gpu_name="${BASH_REMATCH[1]}"
      hardware_vram_gb="$(awk -v mib="${BASH_REMATCH[2]}" 'BEGIN { printf "%.1f", mib / 1024 }')"
      hardware_vram_source="dedicated VRAM reported by nvidia-smi"
    fi
  fi

  if [ -z "$hardware_gpu_name" ] && command -v lspci >/dev/null 2>&1; then
    hardware_gpu_name="$(lspci 2>/dev/null | awk -F': ' 'tolower($1) ~ /vga|3d|display/ { print $2; exit }')"
  fi

  if [ -n "$hardware_gpu_name" ] \
    && { [[ "${hardware_gpu_name,,}" == *intel* ]] \
      || [[ "${hardware_gpu_name,,}" == *integrated* ]] \
      || [[ "${hardware_gpu_name,,}" == *"radeon graphics"* ]]; }; then
    hardware_unified="yes"
  fi

  if { [ "$hardware_vram_gb" = "0" ] || [ -z "$hardware_vram_gb" ]; } \
    && [ -n "$hardware_gpu_name" ] \
    && [ "$hardware_unified" = "yes" ]; then
    hardware_vram_gb="$(awk -v ram="$hardware_ram_gb" 'BEGIN { printf "%.1f", ram * 0.75 }')"
    hardware_vram_source="estimated upper bound from 75% of shared system RAM"
  fi

  hardware_gpu_name="${hardware_gpu_name:-No compatible GPU detected}"
}

is_builtin_canirun_id() {
  local candidate="$1" known
  for known in "${builtin_canirun_ids[@]}"; do
    [ "$candidate" != "$known" ] || return 0
  done
  return 1
}

is_known_model_tag() {
  local candidate="$1" known
  for known in "${builtin_model_tags[@]}" "${api_model_tags[@]}"; do
    [ "$candidate" != "$known" ] || return 0
  done
  return 1
}

json_field() {
  local field="$1"
  python3 -c '
import json
import sys
data = json.load(sys.stdin)
value = data
for part in sys.argv[1].split("."):
    value = value.get(part, {}) if isinstance(value, dict) else {}
print("" if value is None or isinstance(value, (dict, list)) else value)
' "$field"
}

fetch_canirun_recommendations() {
  [ "$use_canirun" = "yes" ] || return 0
  command -v curl >/dev/null 2>&1 || {
    echo "CanIRun.ai recommendations unavailable: curl is missing." >&2
    return 0
  }
  command -v python3 >/dev/null 2>&1 || {
    echo "CanIRun.ai recommendations unavailable: python3 is missing." >&2
    return 0
  }

  local api_base="${ECHOSCRIBE_CANIRUN_API_BASE:-https://www.canirun.ai}"
  local payload response ids model_id detail tag name quant grade status

  echo
  echo "CanIRun.ai request parameters"
  echo "=============================="
  echo "RAM:                 ${hardware_ram_gb} GB"
  echo "CPU (local only):    ${hardware_cpu_name}"
  echo "GPU name:            ${hardware_gpu_name}"
  echo "VRAM sent to API:    ${hardware_vram_gb} GB"
  echo "VRAM source:         ${hardware_vram_source}"
  echo "Use case:            chat"
  echo "Requested results:   10 (up to 3 unique suggestions are shown)"
  echo "Note: CanIRun.ai treats the transmitted VRAM value as available VRAM."
  echo "For iGPUs/unified or shared memory this is an estimate, not dedicated VRAM."
  echo "The CPU name is displayed locally but is not transmitted to CanIRun.ai."
  echo

  payload="$(python3 - "$hardware_ram_gb" "$hardware_gpu_name" "$hardware_vram_gb" <<'PY'
import json
import sys

ram, gpu, vram = sys.argv[1:]
hardware = {"ramGb": float(ram)}
if gpu and gpu != "No compatible GPU detected":
    hardware["gpu"] = {"name": gpu, "vramGb": float(vram)}
print(json.dumps({"hardware": hardware, "useCase": "chat", "limit": 10}))
PY
)"

  if ! response="$(curl -fsS --max-time 10 -X POST "${api_base}/api/recommend" \
    -H 'content-type: application/json' -d "$payload" 2>/dev/null)"; then
    echo "CanIRun.ai is unavailable; continuing with EchoScribe's built-in recommendations." >&2
    return 0
  fi

  if ! ids="$(printf '%s' "$response" | python3 -c '
import json
import sys
data = json.load(sys.stdin)
for item in data.get("recommendations", []):
    model_id = str(item.get("modelId", "")).strip()
    if model_id:
        print(model_id)
' 2>/dev/null)"; then
    echo "CanIRun.ai returned an unreadable response; using built-in recommendations." >&2
    return 0
  fi

  while IFS= read -r model_id; do
    [ -n "$model_id" ] || continue
    is_builtin_canirun_id "$model_id" && continue
    if ! detail="$(curl -fsS --max-time 6 "${api_base}/api/models/${model_id}" 2>/dev/null)"; then
      continue
    fi
    tag="$(printf '%s' "$detail" | json_field ollamaId 2>/dev/null || true)"
    name="$(printf '%s' "$detail" | json_field name 2>/dev/null || true)"
    [ -n "$tag" ] || continue
    is_known_model_tag "$tag" && continue
    quant="$(printf '%s' "$response" | python3 -c '
import json
import sys
model_id = sys.argv[1]
data = json.load(sys.stdin)
item = next((x for x in data.get("recommendations", []) if x.get("modelId") == model_id), {})
print(item.get("quantization", ""))
' "$model_id" 2>/dev/null || true)"
    grade="$(printf '%s' "$response" | python3 -c '
import json
import sys
model_id = sys.argv[1]
data = json.load(sys.stdin)
item = next((x for x in data.get("recommendations", []) if x.get("modelId") == model_id), {})
print(item.get("grade", ""))
' "$model_id" 2>/dev/null || true)"
    status="$(printf '%s' "$response" | python3 -c '
import json
import sys
model_id = sys.argv[1]
data = json.load(sys.stdin)
item = next((x for x in data.get("recommendations", []) if x.get("modelId") == model_id), {})
print(item.get("status", ""))
' "$model_id" 2>/dev/null || true)"
    api_model_tags+=("$tag")
    api_model_names+=("${name:-$model_id}")
    api_model_quants+=("${quant:-unspecified}")
    api_model_grades+=("${grade:-?}")
    api_model_statuses+=("${status:-unknown}")
    [ "${#api_model_tags[@]}" -ge 3 ] && break
  done <<<"$ids"
}

fit_label() {
  local required_vram="$1" required_ram="$2"
  local ratio
  if [ "$hardware_unified" = "no" ] && awk -v v="$hardware_vram_gb" 'BEGIN { exit !(v > 0) }'; then
    ratio="$(awk -v ram="$hardware_ram_gb" -v rr="$required_ram" -v vram="$hardware_vram_gb" -v vr="$required_vram" \
      'BEGIN { a=ram/rr; b=vram/vr; printf "%.3f", (a < b ? a : b) }')"
  else
    ratio="$(awk -v ram="$hardware_ram_gb" -v rr="$required_ram" 'BEGIN { printf "%.3f", ram/rr }')"
  fi
  if awk -v r="$ratio" 'BEGIN { exit !(r >= 1.25) }'; then
    printf 'green'
  elif awk -v r="$ratio" 'BEGIN { exit !(r >= 0.85) }'; then
    printf 'yellow'
  else
    printf 'red'
  fi
}

choose_summary_model() {
  detect_local_hardware
  api_model_tags=()
  api_model_names=()
  api_model_quants=()
  api_model_grades=()
  api_model_statuses=()
  fetch_canirun_recommendations

  local default_index=1
  if awk -v ram="$hardware_ram_gb" 'BEGIN { exit !(ram < 12) }'; then
    default_index=0
  fi

  echo
  echo "Local AI summary model"
  echo "======================"
  echo "Detected hardware: ${hardware_cpu_name}; ${hardware_gpu_name}; ${hardware_ram_gb} GB RAM"
  echo "EchoScribe built-in choices:"
  local i number marker fit
  for i in "${!builtin_model_tags[@]}"; do
    number=$((i + 1))
    marker=" "
    [ "$i" -ne "$default_index" ] || marker="*"
    fit="$(fit_label "${builtin_model_vram_gb[$i]}" "${builtin_model_ram_gb[$i]}")"
    printf '%s%2d. %-43s [%s]\n' "$marker" "$number" "${builtin_model_tags[$i]}" "$fit"
    printf '      %s — %s\n' "${builtin_model_names[$i]}" "${builtin_model_notes[$i]}"
  done

  if [ "${#api_model_tags[@]}" -gt 0 ]; then
    echo "CanIRun.ai choices:"
    for i in "${!api_model_tags[@]}"; do
      number=$((i + 1 + ${#builtin_model_tags[@]}))
      printf ' %2d. %-43s [grade %s, %s]\n' \
        "$number" "${api_model_tags[$i]}" "${api_model_grades[$i]}" "${api_model_statuses[$i]}"
      printf '      %s — CanIRun.ai estimates %s\n' "${api_model_names[$i]}" "${api_model_quants[$i]}"
    done
  else
    echo "No additional CanIRun.ai choices are available."
  fi
  echo "* = EchoScribe recommendation for this hardware and summary workload"

  selected_ollama_model="${builtin_model_tags[$default_index]}"
  if [ "$recommend_models" = "yes" ] && [ ! -t 0 ]; then
    echo "Recommended model: $selected_ollama_model"
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "Non-interactive selection: $selected_ollama_model"
    return 0
  fi

  local total=$(( ${#builtin_model_tags[@]} + ${#api_model_tags[@]} ))
  local answer selected_index
  while true; do
    read -r -p "Choose model number [$((default_index + 1))] " answer
    answer="${answer:-$((default_index + 1))}"
    if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "$total" ]; then
      selected_index=$((answer - 1))
      if [ "$selected_index" -lt "${#builtin_model_tags[@]}" ]; then
        selected_ollama_model="${builtin_model_tags[$selected_index]}"
      else
        selected_ollama_model="${api_model_tags[$((selected_index - ${#builtin_model_tags[@]}))]}"
      fi
      break
    fi
    echo "Please enter a number from 1 to ${total}." >&2
  done
  echo "Selected Ollama model: $selected_ollama_model"
}

run_logged() {
  local name="$1"
  shift
  mkdir -p "$logs"
  local log="$logs/$name.log"
  if "$@" >"$log" 2>&1; then
    return 0
  fi
  echo "Command failed: $*" >&2
  echo "Last log lines from $log:" >&2
  tail -n 80 "$log" >&2 || true
  return 1
}

if [ "$recommend_models" = "yes" ]; then
  choose_summary_model
  exit 0
fi

run_logged_retry() {
  local name="$1"
  local attempts="$2"
  shift 2
  local attempt
  for attempt in $(seq 1 "$attempts"); do
    if run_logged "$name" "$@"; then
      return 0
    fi
    if [ "$attempt" -lt "$attempts" ]; then
      step "Download failed (attempt ${attempt}/${attempts}); retrying in $((attempt * 3)) seconds..."
      sleep $((attempt * 3))
    fi
  done
  return 1
}

install_whisper_dependencies() {
  "$venv/bin/python" -m pip install --disable-pip-version-check --quiet \
    --retries 10 --timeout 60 --upgrade "$@" &&
    "$venv/bin/python" -c 'import fastapi, uvicorn, multipart, faster_whisper, ctranslate2'
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "sudo is not installed. Re-run as root or install sudo before enabling Ollama installation." >&2
    return 1
  fi
}

ollama_api_healthy() {
  curl -fsS --max-time 3 "$ollama_url/api/tags" >/dev/null 2>&1
}

wait_for_ollama() {
  local i
  for i in $(seq 1 30); do
    if ollama_api_healthy; then
      return 0
    fi
    sleep 1
  done
  return 1
}

install_ollama_package() {
  if command -v ollama >/dev/null 2>&1; then
    return 0
  fi
  if [ "$install_ollama" = "no" ]; then
    echo "Ollama is not installed and --no-install-ollama was set." >&2
    return 1
  fi
  step "Installing Ollama..."
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to install Ollama." >&2
    return 1
  fi
  curl -fsSL https://ollama.com/install.sh | run_as_root sh
}

start_ollama_service() {
  if ollama_api_healthy; then
    return 0
  fi
  step "Starting Ollama service..."
  if command -v systemctl >/dev/null 2>&1; then
    run_as_root systemctl enable --now "$ollama_unit" || true
  fi
  if ! wait_for_ollama; then
    echo "Ollama service did not become healthy at $ollama_url." >&2
    if command -v systemctl >/dev/null 2>&1; then
      run_as_root systemctl status "$ollama_unit" --no-pager || true
      run_as_root journalctl -u "$ollama_unit" -n 80 --no-pager || true
    fi
    return 1
  fi
}

if [ "$install_whisper" = "yes" ]; then
  step "Preparing Python environment in $root..."
  mkdir -p "$root" "$logs"
  python3 -m venv "$venv"
  run_logged_retry pip-bootstrap 3 \
    "$venv/bin/python" -m pip install --disable-pip-version-check --quiet \
    --retries 10 --timeout 60 --upgrade pip wheel setuptools
  whisper_packages=(fastapi "uvicorn[standard]" python-multipart faster-whisper)
  if [ "$whisper_device" = "cuda" ]; then
    whisper_packages+=(nvidia-cublas-cu12 nvidia-cudnn-cu12)
  fi
  run_logged_retry pip-whisper 3 install_whisper_dependencies "${whisper_packages[@]}"

  step "Downloading and validating Whisper model ${whisper_model}..."
  run_logged_retry model-download 3 env \
    HF_HUB_DOWNLOAD_TIMEOUT=120 \
    HF_HUB_ETAG_TIMEOUT=30 \
    ECHOSCRIBE_WHISPER_MODEL="$whisper_model" \
    ECHOSCRIBE_WHISPER_DEVICE="$whisper_device" \
    "$venv/bin/python" -c '
import os
import ctranslate2
from faster_whisper import WhisperModel

name = os.environ["ECHOSCRIBE_WHISPER_MODEL"]
if name.startswith("whisper-"):
    name = name.removeprefix("whisper-")
device = os.environ["ECHOSCRIBE_WHISPER_DEVICE"]
if device == "auto":
    device = "cuda" if ctranslate2.get_cuda_device_count() > 0 else "cpu"
compute_type = "float16" if device == "cuda" else "int8"
WhisperModel(name, device=device, compute_type=compute_type)
'

  step "Writing Whisper-compatible API server..."
  cat >"$root/server.py" <<'PY'
from __future__ import annotations

import os
import tempfile
from functools import lru_cache
from pathlib import Path

from fastapi import FastAPI, File, Form, UploadFile
from faster_whisper import WhisperModel

app = FastAPI(title="EchoScribe Local Whisper")


def normalize_model(name: str | None) -> str:
    value = (name or os.environ.get("ECHOSCRIBE_WHISPER_MODEL") or "whisper-large-v3").strip()
    lower = value.lower()
    if lower in {"whisper-1", "whisper-large", "whisper-large-v3", "large-v3"}:
        return "large-v3"
    if lower.startswith("whisper-"):
        return lower.removeprefix("whisper-")
    return value


@lru_cache(maxsize=4)
def get_model(name: str) -> WhisperModel:
    configured = os.environ.get("ECHOSCRIBE_WHISPER_DEVICE", "auto").lower()
    if configured == "auto":
        try:
            import ctranslate2
            device = "cuda" if ctranslate2.get_cuda_device_count() > 0 else "cpu"
        except Exception:
            device = "cpu"
    else:
        device = configured
    compute_type = "float16" if device == "cuda" else "int8"
    return WhisperModel(name, device=device, compute_type=compute_type)


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "backend": "faster-whisper",
        "device": os.environ.get("ECHOSCRIBE_WHISPER_DEVICE", "auto"),
        "defaultModel": os.environ.get("ECHOSCRIBE_WHISPER_MODEL", "whisper-large-v3"),
    }


@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model: str = Form("whisper-large-v3"),
    response_format: str = Form("json"),
    language: str | None = Form(None),
) -> dict[str, str]:
    model_name = normalize_model(model)
    suffix = Path(file.filename or "audio.wav").suffix or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name
    try:
        kwargs = {}
        if language and language.lower() != "auto":
            kwargs["language"] = language
        segments, _ = get_model(model_name).transcribe(
            tmp_path,
            beam_size=5,
            vad_filter=True,
            **kwargs,
        )
        text = "".join(segment.text for segment in segments).strip()
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
    return {"text": text}
PY

  step "Writing start helpers..."
  cat >"$root/run-whisper.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV="$ROOT/.venv"
MODEL="${1:-whisper-large-v3}"
PORT="${2:-8000}"
DEVICE="${3:-auto}"

CUDA_LIBS="$(find "$VENV/lib" -type d \( -path '*/site-packages/nvidia/cublas/lib' -o -path '*/site-packages/nvidia/cudnn/lib' \) -print | paste -sd: -)"
export LD_LIBRARY_PATH="${CUDA_LIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export ECHOSCRIBE_WHISPER_MODEL="$MODEL"
export ECHOSCRIBE_WHISPER_DEVICE="$DEVICE"
exec "$VENV/bin/python" -m uvicorn server:app --host 127.0.0.1 --port "$PORT" --app-dir "$ROOT"
SH
  chmod +x "$root/run-whisper.sh"

  cat >"$root/start-whisper.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODEL="${1:-whisper-large-v3}"
PORT="${2:-8000}"
DEVICE="${3:-auto}"
PID_FILE="$ROOT/whisper-server.pid"
LOG_FILE="$ROOT/logs/whisper-server.log"
mkdir -p "$ROOT/logs"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    echo "EchoScribe Local Whisper already running on port ${PORT}."
    exit 0
  fi
  kill "$(cat "$PID_FILE")" >/dev/null 2>&1 || true
fi

nohup "$ROOT/run-whisper.sh" "$MODEL" "$PORT" "$DEVICE" >"$LOG_FILE" 2>&1 &
echo "$!" >"$PID_FILE"

for _ in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    echo "EchoScribe Local Whisper started on port ${PORT} with model ${MODEL}."
    exit 0
  fi
  sleep 0.5
done

echo "EchoScribe Local Whisper did not become healthy. Last log lines:" >&2
tail -n 80 "$LOG_FILE" >&2 || true
exit 1
SH
  chmod +x "$root/start-whisper.sh"

  if command -v systemctl >/dev/null 2>&1 && systemctl --user --version >/dev/null 2>&1; then
    step "Installing user systemd service..."
    user_unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$user_unit_dir"
    cat >"$user_unit_dir/echoscribe-local-whisper.service" <<EOF
[Unit]
Description=EchoScribe Local Whisper API

[Service]
Type=simple
WorkingDirectory=$root
ExecStart=$root/run-whisper.sh $whisper_model $whisper_port $whisper_device
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
    if systemctl --user daemon-reload && systemctl --user enable --now echoscribe-local-whisper.service; then
      whisper_healthy="no"
      for _ in $(seq 1 30); do
        if curl -fsS --max-time 2 "http://127.0.0.1:${whisper_port}/health" >/dev/null 2>&1; then
          whisper_healthy="yes"
          break
        fi
        if ! systemctl --user is-active --quiet echoscribe-local-whisper.service; then
          break
        fi
        sleep 1
      done
      if [ "$whisper_healthy" = "yes" ]; then
        echo "EchoScribe Local Whisper systemd service is running on port ${whisper_port}."
      else
        echo "EchoScribe Local Whisper systemd service did not become healthy." >&2
        journalctl --user -u echoscribe-local-whisper.service -n 80 --no-pager >&2 || true
        exit 1
      fi
    else
      step "User systemd is not available; starting Whisper in the background..."
      "$root/start-whisper.sh" "$whisper_model" "$whisper_port" "$whisper_device"
    fi
  else
    step "Starting Whisper in the background..."
    "$root/start-whisper.sh" "$whisper_model" "$whisper_port" "$whisper_device"
  fi
fi

if [ "$pull_ollama" = "yes" ]; then
  install_ollama_package
  start_ollama_service
  if [ "$ollama_model_explicit" != "yes" ]; then
    choose_summary_model
    ollama_model="$selected_ollama_model"
  fi
  step "Pulling/checking Ollama model ${ollama_model}..."
  ollama pull "$ollama_model"
  echo "Ollama model ${ollama_model} is available."
  linux_root="$(cd "$(dirname "$0")/.." && pwd)"
  if [ -f "$linux_root/echoscribe/__main__.py" ]; then
    PYTHONPATH="$linux_root" python3 -m echoscribe config-set summary-model localai "$ollama_model"
    echo "EchoScribe Local AI summary model set to ${ollama_model}."
  fi
fi

echo
echo "Local AI installation summary"
echo "============================="
if [ "$install_whisper" = "yes" ]; then
  echo "Whisper server files: $root"
  echo "Whisper Python venv:  $venv"
  echo "Whisper logs:         $logs"
  echo "Whisper health URL:   http://127.0.0.1:${whisper_port}/health"
  echo "Start Whisper:        systemctl --user start echoscribe-local-whisper.service"
  echo "Stop Whisper:         systemctl --user stop echoscribe-local-whisper.service"
  echo "Whisper logs:         journalctl --user -u echoscribe-local-whisper.service -n 80"
fi
if [ "$pull_ollama" = "yes" ]; then
  echo "Ollama binary:        $(command -v ollama)"
  echo "Ollama service:       $ollama_unit"
  echo "Ollama API URL:       $ollama_url"
  echo "Ollama model:         $ollama_model"
  echo "Start Ollama:         sudo systemctl start $ollama_unit"
  echo "Stop Ollama:          sudo systemctl stop $ollama_unit"
  echo "Ollama logs:          sudo journalctl -u $ollama_unit -n 80"
  echo "Ollama model storage: managed by Ollama, usually /usr/share/ollama/.ollama/models for the system service"
fi
