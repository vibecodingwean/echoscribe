#!/usr/bin/env bash
set -euo pipefail

install_whisper="no"
pull_ollama="no"
whisper_model="whisper-large-v3"
whisper_port="8000"
ollama_model="qwen2.5:7b"

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
    --ollama-model)
      ollama_model="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: ./scripts/install-local-ai.sh [options]

Options:
  --whisper                  Install/start the local Faster-Whisper server.
  --pull-ollama              Pull/check the selected Ollama model.
  --whisper-model <model>    Whisper model name, default whisper-large-v3.
  --whisper-port <port>      Local Whisper HTTP port, default 8000.
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

if [ "$install_whisper" != "yes" ] && [ "$pull_ollama" != "yes" ]; then
  echo "Local AI setup skipped."
  exit 0
fi

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
root="$data_home/echoscribe/local-ai"
venv="$root/.venv"
logs="$root/logs"

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

if [ "$install_whisper" = "yes" ]; then
  step "Preparing Python environment in $root..."
  mkdir -p "$root" "$logs"
  python3 -m venv "$venv"
  run_logged pip-bootstrap "$venv/bin/python" -m pip install --disable-pip-version-check --quiet --upgrade pip wheel setuptools
  run_logged pip-whisper "$venv/bin/python" -m pip install --disable-pip-version-check --quiet --upgrade \
    fastapi "uvicorn[standard]" python-multipart faster-whisper nvidia-cublas-cu12 nvidia-cudnn-cu12

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
    return WhisperModel(name, device="cuda", compute_type="float16")


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "backend": "faster-whisper",
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

CUDA_LIBS="$(find "$VENV/lib" -type d \( -path '*/site-packages/nvidia/cublas/lib' -o -path '*/site-packages/nvidia/cudnn/lib' \) -print | paste -sd: -)"
export LD_LIBRARY_PATH="${CUDA_LIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export ECHOSCRIBE_WHISPER_MODEL="$MODEL"
exec "$VENV/bin/python" -m uvicorn server:app --host 127.0.0.1 --port "$PORT" --app-dir "$ROOT"
SH
  chmod +x "$root/run-whisper.sh"

  cat >"$root/start-whisper.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODEL="${1:-whisper-large-v3}"
PORT="${2:-8000}"
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

nohup "$ROOT/run-whisper.sh" "$MODEL" "$PORT" >"$LOG_FILE" 2>&1 &
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
ExecStart=$root/run-whisper.sh $whisper_model $whisper_port
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
    if systemctl --user daemon-reload && systemctl --user enable --now echoscribe-local-whisper.service; then
      if curl -fsS "http://127.0.0.1:${whisper_port}/health" >/dev/null 2>&1; then
        echo "EchoScribe Local Whisper systemd service is running on port ${whisper_port}."
      else
        step "systemd service is not healthy yet; trying direct start helper..."
        "$root/start-whisper.sh" "$whisper_model" "$whisper_port"
      fi
    else
      step "User systemd is not available; starting Whisper in the background..."
      "$root/start-whisper.sh" "$whisper_model" "$whisper_port"
    fi
  else
    step "Starting Whisper in the background..."
    "$root/start-whisper.sh" "$whisper_model" "$whisper_port"
  fi
fi

if [ "$pull_ollama" = "yes" ]; then
  step "Checking Ollama model ${ollama_model}..."
  if command -v ollama >/dev/null 2>&1; then
    ollama pull "$ollama_model"
  else
    curl -fsS http://127.0.0.1:11434/api/pull \
      -H 'Content-Type: application/json' \
      -d "{\"name\":\"${ollama_model}\",\"stream\":false}" >/dev/null
  fi
  echo "Ollama model ${ollama_model} is available."
fi
