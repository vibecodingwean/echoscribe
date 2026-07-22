#!/usr/bin/env bash
set -euo pipefail

install_whisper="no"
pull_ollama="no"
install_ollama="auto"
whisper_model="whisper-large-v3"
whisper_port="8000"
whisper_device="auto"
ollama_model="qwen2.5:7b"
ollama_host="127.0.0.1"
ollama_port="11434"

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
      shift 2
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
  --ollama-model <model>     Ollama model name, default qwen2.5:7b.
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

if [ "$install_whisper" != "yes" ] && [ "$pull_ollama" != "yes" ]; then
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
  step "Pulling/checking Ollama model ${ollama_model}..."
  ollama pull "$ollama_model"
  echo "Ollama model ${ollama_model} is available."
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
