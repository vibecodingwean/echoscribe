"""Linux backend wiring for EchoScribe."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from .config import Config
from .input_events import Binding, InputHotkeyListener
from .keycodes import parse_combo_list
from .overlay import Overlay
from .paste import ClipboardPaster
from .recorder import AudioRecorder


def linux_doctor(config: Config) -> list[str]:
    del config
    findings: list[str] = []
    extension_dir = Path.home() / ".local/share/gnome-shell/extensions/echoscribe@wean.de"
    findings.append("linux trigger: GNOME Shell extension")
    findings.append(f"gnome extension files: {'ok' if (extension_dir / 'extension.js').exists() else 'missing'} ({extension_dir})")
    findings.append(f"gnome extension state: {gnome_extension_state()}")
    findings.append("legacy linux runner: disabled by default")
    findings.append(f"ffmpeg: {shutil.which('ffmpeg') or 'missing'}")
    findings.append(f"arecord: {shutil.which('arecord') or 'missing'}")
    paste_tools = [
        name
        for name in ("wl-copy", "xclip", "xsel", "ydotool", "xdotool", "wtype")
        if shutil.which(name)
    ]
    findings.append(f"paste tools: {', '.join(paste_tools) if paste_tools else 'none'}")
    ydotool_state = systemd_user_state("ydotool.service")
    findings.append(f"ydotool service: {ydotool_state}")
    direct_uinput = "ok" if os.access("/dev/uinput", os.W_OK) else "not writable"
    findings.append(f"direct uinput fallback: {direct_uinput}")
    return findings


def gnome_extension_state() -> str:
    if not shutil.which("gnome-extensions"):
        return "gnome-extensions missing"
    try:
        result = subprocess.run(
            ["gnome-extensions", "info", "echoscribe@wean.de"],
            text=True,
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return f"unknown ({exc})"
    if result.returncode != 0:
        return "not loaded"
    for line in result.stdout.splitlines():
        if line.strip().startswith("State:"):
            return line.split(":", 1)[1].strip()
    return "unknown"


def systemd_user_state(unit: str) -> str:
    if not shutil.which("systemctl"):
        return "systemctl missing"
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", unit],
            text=True,
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return f"unknown ({exc})"
    return (result.stdout or result.stderr).strip() or "unknown"

