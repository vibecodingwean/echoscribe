"""Small process worker used by the EchoScribe GNOME Shell extension."""

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
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from .config import Config, default_api_key_env, load_config
from .recorder import build_record_command


LOG = logging.getLogger(__name__)
STATE_KEYS = (
    "state",
    "recording_id",
    "recorder_pid",
    "audio_file",
    "started_at",
    "reminder_seconds",
)


def state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", "~/.local/state")).expanduser() / "echoscribe"


def state_file() -> Path:
    return state_dir() / "gnome-state.json"


def lock_file() -> Path:
    return state_dir() / "gnome-worker.lock"


def log_file() -> Path:
    return state_dir() / "gnome-recorder.log"


def make_state(
    state: str = "idle",
    *,
    recording_id: str = "",
    recorder_pid: int = 0,
    audio_file: str = "",
    started_at: float = 0.0,
    reminder_seconds: int = 0,
) -> dict[str, Any]:
    return {
        "state": state,
        "recording_id": recording_id,
        "recorder_pid": recorder_pid,
        "audio_file": audio_file,
        "started_at": started_at,
        "reminder_seconds": reminder_seconds,
    }


def normalize_state(payload: object) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return make_state()
    try:
        return make_state(
            str(payload.get("state", "idle")),
            recording_id=str(payload.get("recording_id", "")),
            recorder_pid=int(payload.get("recorder_pid", 0) or 0),
            audio_file=str(payload.get("audio_file", "")),
            started_at=float(payload.get("started_at", 0.0) or 0.0),
            reminder_seconds=int(payload.get("reminder_seconds", payload.get("limit_seconds", 0)) or 0),
        )
    except (TypeError, ValueError):
        return make_state()


def read_state() -> dict[str, Any]:
    try:
        return normalize_state(json.loads(state_file().read_text(encoding="utf-8")))
    except (FileNotFoundError, OSError, ValueError):
        return make_state()


def write_state(payload: dict[str, Any]) -> dict[str, Any]:
    """Atomically persist only the documented recorder state fields."""
    state_dir().mkdir(parents=True, exist_ok=True)
    normalized = normalize_state(payload)
    fd, raw_tmp = tempfile.mkstemp(prefix=".gnome-state-", suffix=".tmp", dir=state_dir())
    tmp = Path(raw_tmp)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(normalized, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, state_file())
    finally:
        tmp.unlink(missing_ok=True)
    return normalized


@contextmanager
def worker_lock() -> Iterator[None]:
    state_dir().mkdir(parents=True, exist_ok=True)
    with lock_file().open("a", encoding="utf-8") as handle:
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


def response(
    snapshot: dict[str, Any],
    *,
    ok: bool,
    message: str,
    transcript: str | None = None,
    paste_shortcut: str | None = None,
    paste_delay_ms: int | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {"ok": ok, **normalize_state(snapshot), "message": message}
    if transcript is not None:
        payload["transcript"] = transcript
    if paste_shortcut is not None:
        payload["paste_shortcut"] = paste_shortcut
    if paste_delay_ms is not None:
        payload["paste_delay_ms"] = paste_delay_ms
    return payload


def error_response(snapshot: dict[str, Any], message: object) -> dict[str, Any]:
    return response(snapshot, ok=False, message=format_error(message))


def start_recording(config: Config) -> dict[str, Any]:
    """Start the recorder only; provider modules are deliberately not loaded here."""
    with worker_lock():
        current = read_state()
        if current["state"] in {"recording", "processing"}:
            if current["state"] == "processing" or process_is_alive(current["recorder_pid"]):
                return error_response(current, "A recording is already active")
            if current["audio_file"]:
                Path(current["audio_file"]).unlink(missing_ok=True)

        recorder_cfg = config.data["recorder"]
        fd, raw_path = tempfile.mkstemp(prefix="echoscribe_", suffix=".wav")
        os.close(fd)
        audio_path = Path(raw_path)
        reminder_seconds = max(0, int(recorder_cfg.get("reminder_seconds", 90)))
        command = build_record_command(
            str(recorder_cfg.get("command", "")),
            audio_path,
        )
        state_dir().mkdir(parents=True, exist_ok=True)
        with log_file().open("ab") as recorder_log:
            try:
                process = subprocess.Popen(
                    command,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=recorder_log,
                    start_new_session=True,
                )
            except Exception:
                audio_path.unlink(missing_ok=True)
                raise

        snapshot = write_state(
            make_state(
                "recording",
                recording_id=uuid.uuid4().hex,
                recorder_pid=process.pid,
                audio_file=str(audio_path),
                started_at=time.time(),
                reminder_seconds=reminder_seconds,
            )
        )
        return response(snapshot, ok=True, message="Recording")


def validate_recording_id(current: dict[str, Any], recording_id: str) -> dict[str, Any] | None:
    if recording_id and recording_id != current["recording_id"]:
        return error_response(current, "Stale recording_id; active recording was not changed")
    return None


def stop_recording(config: Config, recording_id: str = "") -> dict[str, Any]:
    with worker_lock():
        current = read_state()
        stale = validate_recording_id(current, recording_id)
        if stale:
            return stale
        if current["state"] == "processing":
            return error_response(current, "Recording is already being processed")
        if current["state"] != "recording":
            return error_response(current, "No active recording")

        audio_path = Path(current["audio_file"])
        recorder_was_alive = process_is_alive(current["recorder_pid"])
        if recorder_was_alive:
            stop_process_group(current["recorder_pid"])

        if not recorder_was_alive:
            audio_path.unlink(missing_ok=True)
            failed = write_state(make_state("error", recording_id=current["recording_id"]))
            return error_response(failed, "Recorder exited unexpectedly")

        minimum_bytes = int(config.data["recorder"].get("minimum_bytes", 2048))
        if not audio_path.is_file() or audio_path.stat().st_size < minimum_bytes:
            audio_path.unlink(missing_ok=True)
            failed = write_state(make_state("error", recording_id=current["recording_id"]))
            detail = "Recording failed or was too short"
            if not recorder_was_alive:
                detail = "Recorder exited without usable audio"
            return error_response(failed, detail)

        processing = write_state(
            make_state(
                "processing",
                recording_id=current["recording_id"],
                audio_file=current["audio_file"],
                started_at=current["started_at"],
                reminder_seconds=current["reminder_seconds"],
            )
        )

    try:
        transcript = transcribe(config, audio_path)
        with worker_lock():
            latest = read_state()
            if latest["state"] != "processing" or latest["recording_id"] != processing["recording_id"]:
                return error_response(latest, "Recording was canceled or superseded")
            completed = write_state(make_state(recording_id=processing["recording_id"]))
        paste_cfg = config.data["paste"]
        return response(
            completed,
            ok=True,
            message="Transcribed",
            transcript=transcript,
            paste_shortcut=str(paste_cfg.get("shortcut", "auto")),
            paste_delay_ms=int(paste_cfg.get("paste_delay_ms", 120)),
        )
    except Exception as exc:
        LOG.exception("GNOME transcription failed")
        with worker_lock():
            latest = read_state()
            if latest["state"] == "processing" and latest["recording_id"] == processing["recording_id"]:
                latest = write_state(make_state("error", recording_id=processing["recording_id"]))
                return error_response(latest, exc)
            return error_response(latest, "Recording was canceled or superseded")
    finally:
        audio_path.unlink(missing_ok=True)


def cancel(recording_id: str = "") -> dict[str, Any]:
    with worker_lock():
        current = read_state()
        stale = validate_recording_id(current, recording_id)
        if stale:
            return stale
        if current["state"] == "error":
            raw_path = current["audio_file"]
            if raw_path:
                Path(raw_path).unlink(missing_ok=True)
            idle = write_state(make_state(recording_id=current["recording_id"]))
            return response(idle, ok=True, message="Error state cleared")
        if current["state"] not in {"recording", "processing"}:
            return response(current, ok=True, message="Nothing to cancel")
        if current["state"] == "recording":
            stop_process_group(current["recorder_pid"])
        raw_path = current["audio_file"]
        if raw_path:
            Path(raw_path).unlink(missing_ok=True)
        idle = write_state(make_state(recording_id=current["recording_id"]))
        return response(idle, ok=True, message="Canceled")


def status() -> dict[str, Any]:
    with worker_lock():
        current = read_state()
        if current["state"] == "recording" and not process_is_alive(current["recorder_pid"]):
            audio = Path(current["audio_file"])
            audio.unlink(missing_ok=True)
            current = write_state(make_state("error", recording_id=current["recording_id"]))
            return error_response(current, "Recorder exited unexpectedly")
        messages = {
            "idle": "Ready",
            "recording": "Recording",
            "processing": "Transcribing",
            "error": "Error",
        }
        return response(current, ok=current["state"] != "error", message=messages.get(current["state"], current["state"]))


def provider_config(config: Config) -> tuple[str, dict[str, Any]]:
    provider_name = config.active_provider("transcription")
    section = config.data[provider_name]
    if not isinstance(section, dict):
        raise RuntimeError(f"Invalid provider config: {provider_name}")
    return provider_name, section


def transcribe(config: Config, path: Path) -> str:
    # Importing providers can be relatively expensive. Keep it off the shortcut start path.
    from .providers import create_provider

    provider_name, transcription_cfg = provider_config(config)
    api_key = "" if provider_name == "localai" else config.provider_api_key(provider_name)
    if provider_name != "localai" and not api_key:
        raise RuntimeError(f"{default_api_key_env(provider_name)} missing for selected provider")
    client = create_provider(provider_name, api_key)
    text = client.transcribe(
        path,
        model=str(transcription_cfg["transcription_model"]),
        language=str(transcription_cfg.get("target_language", "auto")),
        endpoint=str(transcription_cfg.get("whisper_url", "")),
        stt_format=as_bool(transcription_cfg.get("stt_format", False)),
        tag_audio_events=as_bool(transcription_cfg.get("tag_audio_events", False)),
    )
    text = str(text).strip()
    if not text:
        raise RuntimeError("Transcription returned empty text")
    return text


def stop_process_group(pgid: int) -> None:
    if pgid <= 0:
        return
    for sig, timeout in ((signal.SIGINT, 3.0), (signal.SIGTERM, 1.0), (signal.SIGKILL, 0.0)):
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            return
        except OSError:
            return
        deadline = time.monotonic() + timeout
        while timeout > 0 and time.monotonic() < deadline:
            if not process_group_is_alive(pgid):
                return
            time.sleep(0.025)


def process_group_is_alive(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def format_error(error: object) -> str:
    text = str(error).strip() or "Unknown error"
    if text.startswith("[ECHOSCRIBE ERROR]"):
        return text
    return f"[ECHOSCRIBE ERROR] {text}"


def print_result(payload: dict[str, Any], as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    else:
        print(f"{payload['state']}: {payload['message']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="echoscribe gnome-worker")
    parser.add_argument("action", choices=["status", "start", "stop", "cancel"])
    parser.add_argument("--recording-id", default="")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        if args.action == "status":
            payload = status()
        elif args.action == "cancel":
            payload = cancel(args.recording_id)
        elif args.action == "start":
            config = load_config(Path(__file__).resolve().parents[1])
            payload = start_recording(config)
        else:
            config = load_config(Path(__file__).resolve().parents[1])
            payload = stop_recording(config, args.recording_id)
    except Exception as exc:
        LOG.exception("GNOME worker command failed")
        payload = error_response(read_state(), exc)
    print_result(payload, args.json)
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
