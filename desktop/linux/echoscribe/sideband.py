"""Manage the legacy floating sideband runner."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", "~/.local/state")).expanduser() / "echoscribe"


def pid_file() -> Path:
    return state_dir() / "sideband.pid"


def log_file() -> Path:
    return state_dir() / "sideband.log"


def mode_file() -> Path:
    return state_dir() / "sideband.mode"


def shortcut_file() -> Path:
    return state_dir() / "sideband.shortcut"


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


def read_pid() -> int:
    try:
        return int(pid_file().read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return 0


def read_mode() -> str:
    try:
        return mode_file().read_text(encoding="utf-8").strip() or "legacy"
    except OSError:
        return "legacy"


def read_shortcut() -> str:
    try:
        return shortcut_file().read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def requested_shortcut() -> str:
    return os.environ.get("ECHOSCRIBE_DICTATION_HOLD", "").strip()


def should_reuse_running_sideband(current: dict[str, Any], mode: str, shortcut: str) -> bool:
    return bool(current.get("running") and current.get("mode") == mode and current.get("shortcut") == shortcut)


def status_payload() -> dict[str, Any]:
    pid = read_pid()
    running = process_is_alive(pid)
    if not running:
        try:
            pid_file().unlink(missing_ok=True)
            mode_file().unlink(missing_ok=True)
            shortcut_file().unlink(missing_ok=True)
        except OSError:
            pass
        pid = 0
    mode = read_mode() if running else "stopped"
    shortcut = read_shortcut() if running else ""
    return {
        "running": running,
        "pid": pid,
        "mode": mode,
        "shortcut": shortcut,
        "message": f"{mode.title()} sideband running" if running else "Floating sideband stopped",
    }


def start(headless: bool = False) -> dict[str, Any]:
    mode = "headless" if headless else "legacy"
    shortcut = requested_shortcut()
    current = status_payload()
    if current["running"]:
        if should_reuse_running_sideband(current, mode, shortcut):
            return current
        stop()
    state_dir().mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["ECHOSCRIBE_ALLOW_LEGACY_LINUX_RUN"] = "1"
    if headless:
        env["ECHOSCRIBE_HEADLESS_OVERLAY"] = "1"
    else:
        env.pop("ECHOSCRIBE_HEADLESS_OVERLAY", None)
    env.setdefault("GDK_BACKEND", "x11,wayland")
    log_handle = log_file().open("ab")
    try:
        process = subprocess.Popen(
            [sys.executable, "-m", "echoscribe", "run"],
            stdin=subprocess.DEVNULL,
            stdout=log_handle,
            stderr=log_handle,
            env=env,
            start_new_session=True,
        )
    finally:
        log_handle.close()
    pid_file().write_text(f"{process.pid}\n", encoding="utf-8")
    mode_file().write_text(f"{mode}\n", encoding="utf-8")
    shortcut_file().write_text(f"{shortcut}\n", encoding="utf-8")
    return {
        "running": True,
        "pid": process.pid,
        "mode": mode,
        "shortcut": shortcut,
        "message": f"{mode.title()} sideband started",
    }


def stop() -> dict[str, Any]:
    pid = read_pid()
    if pid <= 0 or not process_is_alive(pid):
        try:
            pid_file().unlink(missing_ok=True)
            mode_file().unlink(missing_ok=True)
            shortcut_file().unlink(missing_ok=True)
        except OSError:
            pass
        return {"running": False, "pid": 0, "message": "Floating sideband stopped"}
    for sig, wait_seconds in ((signal.SIGTERM, 1.5), (signal.SIGKILL, 0.0)):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            break
        deadline = time.monotonic() + wait_seconds
        while wait_seconds > 0 and time.monotonic() < deadline:
            if not process_is_alive(pid):
                break
            time.sleep(0.05)
        if not process_is_alive(pid):
            break
    try:
        pid_file().unlink(missing_ok=True)
        mode_file().unlink(missing_ok=True)
        shortcut_file().unlink(missing_ok=True)
    except OSError:
        pass
    return {"running": False, "pid": 0, "message": "Floating sideband stopped"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="echoscribe sideband")
    parser.add_argument("action", choices=["start", "stop", "toggle", "status"])
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--headless", action="store_true")
    args = parser.parse_args(argv)

    if args.action == "start":
        payload = start(headless=args.headless)
    elif args.action == "stop":
        payload = stop()
    elif args.action == "toggle":
        payload = stop() if status_payload()["running"] else start(headless=args.headless)
    else:
        payload = status_payload()

    if args.json:
        print(json.dumps(payload, ensure_ascii=False))
    else:
        print(payload["message"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

