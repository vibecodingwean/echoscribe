"""Diagnostics for the supported EchoScribe Linux/GNOME runtime."""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

from .config import Config
from .recorder import build_record_command


EXTENSION_UUID = "echoscribe@wean.de"


def doctor(config: Config) -> list[str]:
    version = gnome_version()
    session = os.environ.get("XDG_SESSION_TYPE", "unknown").lower()
    findings: list[str] = [
        f"platform: linux / GNOME {version} ({gnome_support(version)})",
        f"session: {session} ({'supported' if session in {'wayland', 'x11', 'xorg'} else 'unsupported or unknown'})",
        f"python: {sys.executable} ({sys.version.split()[0]})",
        f"config: {config.path or 'defaults'}",
        f"secrets: {'present' if config.env_file.exists() else 'missing'} ({config.env_file})",
    ]
    findings.extend(provider_findings(config))
    findings.extend(recorder_findings(config))
    findings.extend(extension_findings())
    findings.extend(legacy_findings())
    return findings


def provider_findings(config: Config) -> list[str]:
    findings: list[str] = []
    for stage in ("transcription", "summary"):
        try:
            provider = config.active_provider(stage)
            suffix = ""
            if provider != "localai":
                suffix = f", key {'set' if config.provider_api_key(provider) else 'missing'}"
            findings.append(f"{stage} provider: {provider}{suffix}")
        except (KeyError, TypeError, ValueError) as exc:
            findings.append(f"{stage} provider: invalid ({exc})")
    local = config.data.get("localai", {})
    if isinstance(local, dict):
        findings.append(f"local AI LLM endpoint: {str(local.get('llm_url', '')).strip() or 'missing'}")
        findings.append(f"local AI STT endpoint: {str(local.get('whisper_url', '')).strip() or 'missing'}")
    return findings


def recorder_findings(config: Config) -> list[str]:
    recorder = config.data.get("recorder", {})
    if not isinstance(recorder, dict):
        return ["recorder: invalid configuration"]
    template = str(recorder.get("command", "")).strip()
    try:
        command = build_record_command(template, Path("/tmp/echoscribe-doctor.wav"))
    except RuntimeError as exc:
        return [f"recorder: missing ({exc})"]
    executable = command[0]
    resolved = shutil.which(executable) if "/" not in executable else executable
    label = shlex.join(command[: min(4, len(command))])
    return [f"recorder: {'ok' if resolved else 'missing'} ({label})"]


def extension_findings() -> list[str]:
    data_home = Path(os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser()
    extension = data_home / "gnome-shell/extensions" / EXTENSION_UUID
    schema = extension / "schemas/gschemas.compiled"
    return [
        f"GNOME extension files: {'ok' if (extension / 'extension.js').is_file() else 'missing'} ({extension})",
        f"GNOME extension schema: {'ok' if schema.is_file() else 'missing'}",
        f"GNOME extension state: {gnome_extension_state()}",
    ]


def legacy_findings() -> list[str]:
    state = Path(os.environ.get("XDG_STATE_HOME", "~/.local/state")).expanduser() / "echoscribe"
    candidates = [
        Path.home() / ".config/systemd/user/echoscribe.service",
        Path.home() / ".config/systemd/user/wispr.service",
        Path.home() / ".config/systemd/user/ydotool.service.d/override.conf",
        state / "sideband.pid",
        state / "sideband.mode",
        state / "focus-app-hint",
        Path("/etc/udev/rules.d/90-echoscribe-uinput.rules"),
    ]
    found = [str(path) for path in candidates if path.exists()]
    return [f"legacy remnants: {', '.join(found) if found else 'none'}"]


def gnome_version() -> str:
    if not shutil.which("gnome-shell"):
        return "missing"
    try:
        result = subprocess.run(
            ["gnome-shell", "--version"], text=True, capture_output=True, timeout=3, check=False
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return f"unknown ({exc})"
    return (result.stdout or result.stderr).strip().removeprefix("GNOME Shell ") or "unknown"


def gnome_support(version: str) -> str:
    try:
        major = int(version.split(".", 1)[0])
    except ValueError:
        return "not detected"
    return "supported" if 45 <= major <= 50 else "unsupported"


def gnome_extension_state() -> str:
    if not shutil.which("gnome-extensions"):
        return "gnome-extensions missing"
    try:
        result = subprocess.run(
            ["gnome-extensions", "info", EXTENSION_UUID],
            text=True,
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return f"unknown ({exc})"
    if result.returncode != 0:
        return "not recognized"
    for line in result.stdout.splitlines():
        if line.strip().startswith("State:"):
            return line.split(":", 1)[1].strip()
    return "recognized (state unknown)"
