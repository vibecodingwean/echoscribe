"""EchoScribe application orchestration."""

from __future__ import annotations

import logging
import os
import sys
import threading
import time

from .config import Config, default_api_key_env
from .providers import create_provider

if not sys.platform.startswith("win32"):
    from .gnome_worker import write_state
else:
    write_state = None


class HeadlessOverlay:
    def __init__(self, *args: object, **kwargs: object) -> None:
        del args, kwargs
        self._stopped = threading.Event()

    def show_recording(self) -> None:
        pass

    def show_processing(self, text: str) -> None:
        del text

    def show_toast(self, text: str) -> None:
        del text

    def set_clipboard_text(self, text: str, timeout: float = 2.0) -> bool:
        del text, timeout
        return False

    def run(self) -> None:
        self._stopped.wait()

    def stop(self) -> None:
        self._stopped.set()


if sys.platform == "win32":
    from .windows import (  # type: ignore[assignment]
        Binding,
        WindowsAudioRecorder as AudioRecorder,
        WindowsClipboardPaster as ClipboardPaster,
        WindowsHotkeyListener as InputHotkeyListener,
        WindowsOverlay as Overlay,
        parse_combo_list,
        windows_doctor as platform_doctor,
    )
else:
    from .linux import (  # type: ignore[assignment]
        AudioRecorder,
        Binding,
        ClipboardPaster,
        InputHotkeyListener,
        Overlay,
        linux_doctor as platform_doctor,
        parse_combo_list,
    )


LOG = logging.getLogger(__name__)


class EchoScribeApp:
    def __init__(self, config: Config) -> None:
        self.config = config
        overlay_config = config.data["overlay"]
        overlay_cls = HeadlessOverlay if use_headless_overlay() else Overlay
        self.overlay = overlay_cls(
            icon_path=config.icon_path,
            icon_size=int(overlay_config["icon_size_px"]),
            margin=int(overlay_config["margin_px"]),
            top=int(overlay_config.get("top_px", overlay_config["margin_px"])),
            toast_ms=int(overlay_config["toast_ms"]),
        )
        paste_config = config.data["paste"]
        self.paster = ClipboardPaster(
            method=str(paste_config["method"]),
            shortcut=str(paste_config.get("shortcut", "ctrl+shift+v")),
            paste_delay_ms=int(paste_config["paste_delay_ms"]),
            gtk_clipboard_setter=getattr(self.overlay, "set_clipboard_text", None),
        )
        recorder_config = config.data["recorder"]
        self.recorder = AudioRecorder(
            command_template=str(recorder_config["command"]),
            minimum_bytes=int(recorder_config["minimum_bytes"]),
        )
        self.listener: InputHotkeyListener | None = None
        self.lock = threading.Lock()
        self.state = "idle"
        self.mode = ""
        self.recording_started_at = 0.0
        self.max_recording_seconds = int(recorder_config.get("max_seconds", 90))
        self.stop_requested_while_starting = False

    def run(self) -> None:
        hotkeys = self.config.data["hotkeys"]
        dictation_hold = os.environ.get("ECHOSCRIBE_DICTATION_HOLD") or hotkeys["dictation_hold"]
        bindings = [
            Binding(
                name="dictation",
                hotkeys=parse_combo_list(dictation_hold),
                on_start=self.start_recording,
                on_stop=self.stop_recording,
            ),
        ]
        self.listener = InputHotkeyListener(bindings)
        try:
            self.listener.start()
            LOG.info("EchoScribe is running")
            self.overlay.show_toast("EchoScribe ready")
            self.overlay.run()
        finally:
            if self.listener:
                self.listener.stop()
            self.recorder.abort()

    def start_recording(self) -> None:
        with self.lock:
            if self.state != "idle":
                return
            try:
                missing_keys = self._missing_provider_keys()
            except ValueError as exc:
                message = format_error(exc)
                self.overlay.show_toast(message)
                if write_state:
                    write_state({"state": "error", "message": message})
                return
            if missing_keys:
                message = format_error(f"{', '.join(missing_keys)} missing for selected provider")
                self.overlay.show_toast(message)
                if write_state:
                    write_state({"state": "error", "message": message})
                return
            self.state = "starting"
            self.mode = "dictation"
            self.recording_started_at = time.monotonic()
        try:
            self.recorder.start()
            with self.lock:
                if self.stop_requested_while_starting:
                    self.stop_requested_while_starting = False
                    self.state = "recording"
                    stop_after_start = True
                else:
                    self.state = "recording"
                    stop_after_start = False
            if stop_after_start:
                self.stop_recording()
            else:
                self.overlay.show_recording()
                if write_state:
                    write_state({"state": "recording", "message": "Recording"})
                threading.Thread(target=self._recording_watchdog, daemon=True).start()
        except Exception as exc:
            LOG.exception("Could not start recording")
            with self.lock:
                self.state = "idle"
                self.mode = ""
                self.recording_started_at = 0.0
                self.stop_requested_while_starting = False
            message = format_error(exc)
            self.overlay.show_toast(message)
            if write_state:
                write_state({"state": "error", "message": message})

    def stop_recording(self) -> None:
        with self.lock:
            if self.state == "starting":
                self.stop_requested_while_starting = True
                return
            if self.state != "recording":
                return
            self.state = "processing"
            self.recording_started_at = 0.0
        if write_state:
            write_state({"state": "processing", "message": "Transcribing"})
        try:
            path = self.recorder.stop()
        except Exception as exc:
            LOG.exception("Could not stop recording")
            try:
                self.recorder.abort()
            except Exception:
                LOG.exception("Could not abort recorder after stop failure")
            with self.lock:
                self.state = "idle"
                self.mode = ""
                self.recording_started_at = 0.0
                self.stop_requested_while_starting = False
            message = format_error(exc)
            self.overlay.show_toast(message)
            if write_state:
                write_state({"state": "error", "message": message})
            return
        self.overlay.show_processing("Transcribing...")
        threading.Thread(target=self._process_recording, args=(path,), daemon=True).start()

    def _recording_watchdog(self) -> None:
        while True:
            time.sleep(1)
            with self.lock:
                if self.state != "recording" or self.recording_started_at <= 0:
                    return
                elapsed = time.monotonic() - self.recording_started_at
                if elapsed < self.max_recording_seconds:
                    continue
            LOG.warning("Recording exceeded %s seconds; stopping automatically", self.max_recording_seconds)
            self.stop_recording()
            return

    def _process_recording(self, path) -> None:
        try:
            transcription_provider_name = self.config.active_provider("transcription")
            transcription_cfg = self.config.data[transcription_provider_name]
            api_key = "" if transcription_provider_name == "localai" else self.config.provider_api_key(transcription_provider_name)
            transcription_client = create_provider(
                transcription_provider_name,
                api_key,
            )
            raw = transcription_client.transcribe(
                path,
                model=str(transcription_cfg["transcription_model"]),
                language=str(transcription_cfg.get("target_language", "auto")),
                endpoint=str(transcription_cfg.get("whisper_url", "")),
                stt_format=as_bool(transcription_cfg.get("stt_format", False)),
                tag_audio_events=as_bool(transcription_cfg.get("tag_audio_events", False)),
            )
            self.overlay.show_processing("Pasting...")
            if write_state:
                write_state({"state": "pasting", "message": "Pasting"})
            self.paster.paste_text(raw)
            self.overlay.show_toast("Pasted")
            if write_state:
                write_state({"state": "idle", "message": "Ready"})
        except Exception as exc:
            LOG.exception("Dictation failed")
            message = format_error(exc)
            self.overlay.show_toast(message)
            if write_state:
                write_state({"state": "error", "message": message})
        finally:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
            with self.lock:
                self.state = "idle"
                self.mode = ""
                self.recording_started_at = 0.0
                self.stop_requested_while_starting = False

    def _missing_provider_keys(self) -> list[str]:
        providers = {self.config.active_provider("transcription")}
        return [
            default_api_key_env(provider)
            for provider in sorted(providers)
            if provider != "localai" and not self.config.provider_api_key(provider)
        ]


def doctor(config: Config) -> list[str]:
    findings: list[str] = []
    findings.append(f"config: {config.path or 'defaults'}")
    findings.append(f"env file: {'ok' if config.env_file.exists() else 'missing'} ({config.env_file})")
    findings.append(f"icon: {'ok' if config.icon_path.exists() else 'missing'} ({config.icon_path})")
    try:
        transcription_provider = config.active_provider("transcription")
        findings.append(f"transcription provider: {transcription_provider}")
    except ValueError as exc:
        findings.append(f"provider config: {exc}")
    try:
        summary_provider = config.active_provider("summary")
        findings.append(f"summary provider: {summary_provider}")
    except ValueError as exc:
        findings.append(f"summary config: {exc}")
    for provider in ("openai", "gemini", "anthropic", "xai", "elevenlabs"):
        findings.append(f"{provider} key: {'ok' if config.provider_api_key(provider) else 'missing'}")
    localai = config.data.get("localai", {})
    if isinstance(localai, dict):
        findings.append(f"localai llm url: {'ok' if str(localai.get('llm_url', '')).strip() else 'missing'}")
        findings.append(f"localai whisper url: {'ok' if str(localai.get('whisper_url', '')).strip() else 'missing'}")
    findings.extend(platform_doctor(config))
    return findings


def use_headless_overlay() -> bool:
    return sys.platform.startswith("linux") and os.environ.get("ECHOSCRIBE_HEADLESS_OVERLAY") == "1"


def as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def format_error(error: object) -> str:
    text = str(error).strip()
    if text.startswith("[ECHOSCRIBE ERROR]"):
        return text
    return f"[ECHOSCRIBE ERROR] {text}"
