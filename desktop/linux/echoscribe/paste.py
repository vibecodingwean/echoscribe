"""Clipboard and paste helpers."""

from __future__ import annotations

import logging
import os
import shutil
import struct
import subprocess
import time
from collections.abc import Callable
from pathlib import Path


LOG = logging.getLogger(__name__)

EV_SYN = 0
EV_KEY = 1
SYN_REPORT = 0
KEY_LEFTCTRL = 29
KEY_LEFTSHIFT = 42
KEY_V = 47
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
BUS_USB = 0x03
EVENT_STRUCT = struct.Struct("llHHi")


class ClipboardPaster:
    def __init__(
        self,
        method: str = "auto",
        shortcut: str = "auto",
        paste_delay_ms: int = 120,
        gtk_clipboard_setter: Callable[[str], bool] | None = None,
    ) -> None:
        self.method = method
        self.shortcut = shortcut
        self.paste_delay_ms = paste_delay_ms
        self.gtk_clipboard_setter = gtk_clipboard_setter

    def paste_text(self, text: str) -> None:
        self._set_clipboard(text)
        time.sleep(max(self.paste_delay_ms, 0) / 1000)
        self._press_paste()

    def _set_clipboard(self, text: str) -> None:
        if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-copy"):
            subprocess.run(["wl-copy"], input=text.encode(), check=True)
            return
        if shutil.which("xclip"):
            subprocess.run(["xclip", "-selection", "clipboard"], input=text.encode(), check=True)
            return
        if shutil.which("xsel"):
            subprocess.run(["xsel", "--clipboard", "--input"], input=text.encode(), check=True)
            return
        if self.gtk_clipboard_setter and self.gtk_clipboard_setter(text):
            return
        raise RuntimeError("No clipboard setter found. Install wl-clipboard, xclip, or xsel.")

    def _press_paste(self) -> None:
        if self.method != "auto":
            methods = [self.method]
        elif os.environ.get("WAYLAND_DISPLAY"):
            methods = ["ydotool", "wtype", "uinput", "xdotool"]
        else:
            methods = ["xdotool", "ydotool", "uinput", "wtype"]
        shortcut = PasteShortcut.parse(resolve_paste_shortcut(self.shortcut))
        errors: list[str] = []
        for method in methods:
            try:
                if method == "ydotool" and shutil.which("ydotool"):
                    subprocess.run(["ydotool", "key", "--key-delay=35", *shortcut.ydotool_events()], check=True)
                    LOG.info("Pasted via ydotool using %s", shortcut.label)
                    return
                if method == "xdotool" and shutil.which("xdotool"):
                    subprocess.run(["xdotool", "key", "--clearmodifiers", shortcut.xdotool_name()], check=True)
                    LOG.info("Pasted via xdotool using %s", shortcut.label)
                    return
                if method == "wtype" and shutil.which("wtype"):
                    subprocess.run(["wtype", *shortcut.wtype_args()], check=True)
                    LOG.info("Pasted via wtype using %s", shortcut.label)
                    return
                if method == "uinput":
                    UInputPasteKeyboard().paste(shortcut)
                    LOG.info("Pasted via uinput using %s", shortcut.label)
                    return
            except Exception as exc:
                errors.append(f"{method}: {exc}")
                LOG.warning("Paste method %s failed: %s", method, exc)
        detail = "; ".join(errors) if errors else "no supported paste tool is installed"
        raise RuntimeError(f"Could not synthesize Ctrl+V: {detail}")


class PasteShortcut:
    KEY_MAP = {
        "ctrl": KEY_LEFTCTRL,
        "leftctrl": KEY_LEFTCTRL,
        "control": KEY_LEFTCTRL,
        "shift": KEY_LEFTSHIFT,
        "leftshift": KEY_LEFTSHIFT,
        "v": KEY_V,
    }

    def __init__(self, label: str, codes: list[int], names: list[str]) -> None:
        self.label = label
        self.codes = codes
        self.names = names

    @classmethod
    def parse(cls, raw: str) -> "PasteShortcut":
        names = [part.strip().lower() for part in raw.replace("-", "+").split("+") if part.strip()]
        if not names:
            names = ["ctrl", "shift", "v"]
        codes: list[int] = []
        for name in names:
            if name not in cls.KEY_MAP:
                raise ValueError(f"Unsupported paste shortcut key: {name}")
            codes.append(cls.KEY_MAP[name])
        return cls("+".join(names), codes, names)

    def ydotool_events(self) -> list[str]:
        return [f"{code}:1" for code in self.codes] + [f"{code}:0" for code in reversed(self.codes)]

    def xdotool_name(self) -> str:
        mapped = ["ctrl" if name in {"leftctrl", "control"} else name for name in self.names]
        mapped = ["shift" if name == "leftshift" else name for name in mapped]
        return "+".join(mapped)

    def wtype_args(self) -> list[str]:
        modifiers = [name for name in self.names[:-1] if name in {"ctrl", "leftctrl", "control", "shift", "leftshift"}]
        key = self.names[-1]
        args: list[str] = []
        for modifier in modifiers:
            args.extend(["-M", modifier_name(modifier)])
        args.extend(["-k", key])
        for modifier in reversed(modifiers):
            args.extend(["-m", modifier_name(modifier)])
        return args


def modifier_name(name: str) -> str:
    return "ctrl" if name in {"ctrl", "leftctrl", "control"} else "shift"


def resolve_paste_shortcut(configured: str) -> str:
    configured = configured.strip().lower()
    if configured and configured != "auto":
        return configured
    app_hint = active_app_hint()
    if is_terminal_hint(app_hint):
        LOG.info("Active app looks terminal-like (%s); using ctrl+shift+v", app_hint)
        return "ctrl+shift+v"
    if is_unreliable_app_hint(app_hint):
        LOG.info("Active app hint is unavailable or unreliable (%s); using terminal-safe ctrl+shift+v", app_hint or "unknown")
        return "ctrl+shift+v"
    LOG.info("Active app hint %s; using ctrl+v", app_hint or "unknown")
    return "ctrl+v"


def active_app_hint() -> str:
    env_hint = os.environ.get("ECHOSCRIBE_ACTIVE_APP_HINT", "").strip()
    if env_hint:
        return env_hint
    file_hint = trusted_gnome_focus_hint()
    if file_hint:
        return file_hint
    try:
        import gi

        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi

        desktop = Atspi.get_desktop(0)
        candidates: list[str] = []
        for i in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(i)
            app_name = safe_atspi_name(app)
            for j in range(app.get_child_count()):
                child = app.get_child_at_index(j)
                state_set = child.get_state_set()
                if (
                    state_set.contains(Atspi.StateType.ACTIVE)
                    and state_set.contains(Atspi.StateType.SHOWING)
                ):
                    child_name = safe_atspi_name(child)
                    candidates.append(" ".join(part for part in (app_name, child_name) if part))
        return candidates[-1] if candidates else ""
    except Exception as exc:
        LOG.debug("Could not inspect active app via AT-SPI: %s", exc)
        return ""


def trusted_gnome_focus_hint() -> str:
    if os.environ.get("ECHOSCRIBE_TRUST_GNOME_FOCUS_HINT") != "1":
        return ""
    raw_path = os.environ.get("ECHOSCRIBE_GNOME_FOCUS_HINT_FILE", "").strip()
    if raw_path:
        path = Path(raw_path).expanduser()
    else:
        state_home = Path(os.environ.get("XDG_STATE_HOME", "~/.local/state")).expanduser()
        path = state_home / "echoscribe" / "focus-app-hint"
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def safe_atspi_name(accessible: object) -> str:
    try:
        return str(accessible.get_name() or "")
    except Exception:
        return ""


def is_terminal_hint(hint: str) -> bool:
    lowered = hint.lower()
    terminal_markers = (
        "terminal",
        "ptyxis",
        "kgx",
        "konsole",
        "alacritty",
        "kitty",
        "wezterm",
        "tilix",
        "xterm",
        "urxvt",
        "gnome-terminal",
        "org.gnome.ptyxis",
        "org.gnome.console",
        "com.mitchellh.ghostty",
    )
    return any(marker in lowered for marker in terminal_markers)


def is_unreliable_app_hint(hint: str) -> bool:
    lowered = hint.strip().lower()
    if not lowered:
        return True
    unreliable_markers = (
        "desktop icons",
        "gnome shell",
        "desktop window",
    )
    return any(marker in lowered for marker in unreliable_markers)


class UInputPasteKeyboard:
    def __init__(self, device: str = "/dev/uinput") -> None:
        self.device = device
        self.fd: int | None = None

    def paste(self, shortcut: PasteShortcut) -> None:
        self._open()
        try:
            for code in shortcut.codes:
                self._emit_key(code, 1)
            time.sleep(0.03)
            for code in reversed(shortcut.codes):
                self._emit_key(code, 0)
        finally:
            self._close()

    def _open(self) -> None:
        import fcntl

        self.fd = os.open(self.device, os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_SYN)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, KEY_LEFTCTRL)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, KEY_LEFTSHIFT)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, KEY_V)
        name = b"EchoScribe Paste Keyboard"
        user_dev = struct.pack("80sHHHHI", name, BUS_USB, 0x1209, 0x5750, 1, 0)
        user_dev += bytes(4 * 64 * 4)
        os.write(self.fd, user_dev)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        time.sleep(0.05)

    def _close(self) -> None:
        if self.fd is None:
            return
        import fcntl

        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        finally:
            os.close(self.fd)
            self.fd = None

    def _emit_key(self, code: int, value: int) -> None:
        self._emit(EV_KEY, code, value)
        self._emit(EV_SYN, SYN_REPORT, 0)

    def _emit(self, ev_type: int, code: int, value: int) -> None:
        if self.fd is None:
            raise RuntimeError("uinput device is not open")
        now = time.time()
        sec = int(now)
        usec = int((now - sec) * 1_000_000)
        os.write(self.fd, EVENT_STRUCT.pack(sec, usec, ev_type, code, value))

