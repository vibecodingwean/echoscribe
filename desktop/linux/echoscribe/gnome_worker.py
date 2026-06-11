"""GNOME extension worker for one-shot EchoScribe dictation."""

from __future__ import annotations

import argparse
import fcntl
import json
import logging
import os
import signal
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from .config import Config, default_api_key_env, load_config
from .paste import ClipboardPaster
from .providers import create_provider
from .recorder import build_record_command


LOG = logging.getLogger(__name__)


def state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", "~/.local/state")).expanduser() / "echoscribe"


def state_file() -> Path:
    return state_dir() / "gnome-state.json"


def lock_file() -> Path:
    return state_dir() / "gnome-worker.lock"


def log_file() -> Path:
    return state_dir() / "gnome-recorder.log"


def idle_state(message: str = "Ready") -> dict[str, Any]:
    return {
        "state": "idle",
        "message": message,
        "updated_at": time.time(),
    }


def read_state() -> dict[str, Any]:
    path = state_file()
    if not path.exists():
        return idle_state()
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return idle_state()
    return payload if isinstance(payload, dict) else idle_state()


def write_state(payload: dict[str, Any]) -> dict[str, Any]:
    state_dir().mkdir(parents=True, exist_ok=True)
    payload = {**payload, "updated_at": time.time()}
    tmp = state_file().with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    tmp.replace(state_file())
    return payload


@contextmanager
def worker_lock() -> Iterator[None]:
    state_dir().mkdir(parents=True, exist_ok=True)
    with lock_file().open("w", encoding="utf-8") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def process_is_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def provider_config(config: Config) -> tuple[str, dict[str, Any]]:
    provider_name = config.active_provider("transcription")
    section = config.data[provider_name]
    if not isinstance(section, dict):
        raise RuntimeError(f"Invalid provider config: {provider_name}")
    return provider_name, section


def missing_provider_key(config: Config) -> str:
    provider_name, _ = provider_config(config)
    if provider_name == "localai":
        return ""
    if config.provider_api_key(provider_name):
        return ""
    return default_api_key_env(provider_name)


def start_recording(config: Config) -> dict[str, Any]:
    with worker_lock():
        current = read_state()
        if current.get("state") == "recording" and process_is_alive(int(current.get("pid", 0))):
            return current
        if current.get("state") == "processing":
            return current

        missing = missing_provider_key(config)
        if missing:
            return write_state({"state": "error", "message": format_error(f"{missing} missing for selected provider")})

        recorder_cfg = config.data["recorder"]
        fd, raw_path = tempfile.mkstemp(prefix="echoscribe_gnome_", suffix=".wav")
        os.close(fd)
        path = Path(raw_path)
        max_seconds = int(recorder_cfg.get("max_seconds", 90))
        command = build_record_command(
            str(recorder_cfg.get("command", "")),
            path,
            max_seconds=max_seconds,
        )
        state_dir().mkdir(parents=True, exist_ok=True)
        err = log_file().open("ab")
        try:
            process = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=err,
                start_new_session=True,
            )
        except Exception:
            err.close()
            path.unlink(missing_ok=True)
            raise
        err.close()
        return write_state(
            {
                "state": "recording",
                "message": "Recording",
                "pid": process.pid,
                "pgid": process.pid,
                "path": str(path),
                "started_at": time.time(),
                "max_seconds": max_seconds,
                "command": command[0] if command else "",
            }
        )


def stop_recording(config: Config, paste: bool = True) -> dict[str, Any]:
    with worker_lock():
        current = read_state()
        if current.get("state") != "recording":
            return write_state(idle_state())
        pid = int(current.get("pid", 0))
        pgid = int(current.get("pgid", pid))
        raw_path = str(current.get("path", ""))
        path = Path(raw_path) if raw_path else Path()
        was_running = process_is_alive(pid)
        if was_running:
            stop_process_group(pgid or pid)
        minimum_bytes = int(config.data["recorder"].get("minimum_bytes", 2048))
        if not raw_path or not path.exists() or path.stat().st_size < minimum_bytes:
            if not was_running:
                return write_state(idle_state())
            return write_state(
                {
                    "state": "error",
                    "message": format_error("Recording failed or was too short"),
                    "path": str(path),
                }
            )
        write_state({"state": "processing", "message": "Transcribing", "path": str(path)})

    try:
        text = transcribe(config, path)
        if paste:
            write_state({"state": "pasting", "message": "Pasting", "path": str(path)})
            paste_text(config, text)
        return write_state(
            {
                "state": "done",
                "message": "Pasted" if paste else "Transcribed",
                "transcript": text,
            }
        )
    except Exception as exc:
        LOG.exception("GNOME worker failed")
        return write_state({"state": "error", "message": format_error(exc)})
    finally:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass


def stop_process_group(pgid: int) -> None:
    if pgid <= 0:
        return
    for sig, timeout in ((signal.SIGINT, 5.0), (signal.SIGTERM, 2.0), (signal.SIGKILL, 0.0)):
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            return
        except OSError:
            return
        if timeout <= 0:
            return
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not process_group_is_alive(pgid):
                return
            time.sleep(0.05)


def process_group_is_alive(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def transcribe(config: Config, path: Path) -> str:
    provider_name, transcription_cfg = provider_config(config)
    api_key = "" if provider_name == "localai" else config.provider_api_key(provider_name)
    client = create_provider(provider_name, api_key)
    text = client.transcribe(
        path,
        model=str(transcription_cfg["transcription_model"]),
        language=str(transcription_cfg.get("target_language", "auto")),
        endpoint=str(transcription_cfg.get("whisper_url", "")),
        stt_format=as_bool(transcription_cfg.get("stt_format", False)),
        tag_audio_events=as_bool(transcription_cfg.get("tag_audio_events", False)),
    )
    if not text.strip():
        raise RuntimeError("Transcription returned empty text")
    return text


def paste_text(config: Config, text: str) -> None:
    paste_cfg = config.data["paste"]
    ClipboardPaster(
        method=str(paste_cfg.get("method", "auto")),
        shortcut=str(paste_cfg.get("shortcut", "auto")),
        paste_delay_ms=int(paste_cfg.get("paste_delay_ms", 120)),
    ).paste_text(text)


def toggle(config: Config) -> dict[str, Any]:
    current = read_state()
    if current.get("state") == "recording" and process_is_alive(int(current.get("pid", 0))):
        return stop_recording(config)
    if current.get("state") == "processing":
        return current
    return start_recording(config)


def cancel() -> dict[str, Any]:
    with worker_lock():
        current = read_state()
        if current.get("state") == "recording":
            stop_process_group(int(current.get("pgid", current.get("pid", 0))))
            raw_path = str(current.get("path", ""))
            if raw_path:
                path = Path(raw_path)
                path.unlink(missing_ok=True)
        return write_state(idle_state("Canceled"))


def as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def print_result(payload: dict[str, Any], as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, ensure_ascii=False))
    else:
        print(f"{payload.get('state', 'unknown')}: {payload.get('message', '')}")


def format_error(error: object) -> str:
    text = str(error).strip()
    if text.startswith("[ECHOSCRIBE ERROR]"):
        return text
    return f"[ECHOSCRIBE ERROR] {text}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="echoscribe gnome-worker")
    parser.add_argument("action", choices=["status", "start", "stop", "toggle", "cancel"])
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--no-paste", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    project_dir = Path(__file__).resolve().parents[1]
    config = load_config(project_dir)
    try:
        if args.action == "status":
            payload = read_state()
        elif args.action == "start":
            payload = start_recording(config)
        elif args.action == "stop":
            payload = stop_recording(config, paste=not args.no_paste)
        elif args.action == "toggle":
            payload = toggle(config)
        else:
            payload = cancel()
    except Exception as exc:
        LOG.exception("GNOME worker command failed")
        try:
            payload = write_state({"state": "error", "message": format_error(exc)})
        except OSError:
            payload = {"state": "error", "message": format_error(exc), "updated_at": time.time()}
    print_result(payload, args.json)
    return 0 if payload.get("state") != "error" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
