"""Small terminal configuration menu for EchoScribe."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .config import Config


def run_config_tui(config: Config) -> int:
    path = config.path or Path("~/.config/echoscribe/config.toml").expanduser()
    ensure_config_file(path)
    while True:
        print()
        print("EchoScribe Config")
        print("1) Transcription provider")
        print("2) Summary provider")
        print("3) Paste shortcut")
        print("4) Paste delay")
        print("5) Recording reminder")
        print("6) Show config path")
        print("q) Quit")
        choice = input("> ").strip().lower()
        if choice == "1":
            provider = choose(
                "Transcription provider",
                ["openai", "gemini", "xai", "elevenlabs", "localai"],
                str(config.data["providers"].get("transcription", "openai")),
            )
            set_value(path, "providers", "transcription", provider)
            config.data["providers"]["transcription"] = provider
        elif choice == "2":
            provider = choose(
                "Summary provider",
                ["openai", "gemini", "anthropic", "xai", "localai"],
                str(config.data["providers"].get("summary", "openai")),
            )
            set_value(path, "providers", "summary", provider)
            config.data["providers"]["summary"] = provider
        elif choice == "3":
            shortcut = choose(
                "Paste shortcut",
                ["auto", "ctrl+v", "ctrl+shift+v"],
                str(config.data["paste"].get("shortcut", "auto")),
            )
            set_value(path, "paste", "shortcut", shortcut)
            config.data["paste"]["shortcut"] = shortcut
        elif choice == "4":
            current = str(config.data["paste"].get("paste_delay_ms", 120))
            value = prompt("Paste delay in milliseconds", current)
            try:
                delay = max(0, int(value))
            except ValueError:
                print("Keeping current value")
                continue
            set_value(path, "paste", "paste_delay_ms", delay)
            config.data["paste"]["paste_delay_ms"] = delay
        elif choice == "5":
            current = str(config.data["recorder"].get("reminder_seconds", 90))
            value = prompt("Reminder after seconds (0 disables it; recording continues)", current)
            try:
                seconds = max(0, int(value))
            except ValueError:
                print("Keeping current value")
                continue
            set_value(path, "recorder", "reminder_seconds", seconds)
            config.data["recorder"]["reminder_seconds"] = seconds
        elif choice == "6":
            print(path)
        elif choice in {"q", "quit", "exit"}:
            return 0
        else:
            print("Unknown choice")


def ensure_config_file(path: Path) -> None:
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("", encoding="utf-8")


def choose(label: str, options: list[str], current: str) -> str:
    print(f"{label} [{current}]")
    for index, option in enumerate(options, start=1):
        print(f"{index}) {option}")
    raw = input("> ").strip().lower()
    if not raw:
        return current
    if raw.isdigit() and 1 <= int(raw) <= len(options):
        return options[int(raw) - 1]
    if raw in options:
        return raw
    print("Keeping current value")
    return current


def prompt(label: str, current: str) -> str:
    value = input(f"{label} [{current}]: ").strip()
    return value or current


def set_value(path: Path, section: str, key: str, value: Any) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    rendered = render_value(value)
    section_header = f"[{section}]"
    section_start = find_section(lines, section_header)
    if section_start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend([section_header, f"{key} = {rendered}"])
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return
    next_section = find_next_section(lines, section_start + 1)
    end = next_section if next_section is not None else len(lines)
    for index in range(section_start + 1, end):
        stripped = lines[index].strip()
        if stripped.startswith(f"{key} " ) or stripped.startswith(f"{key}="):
            lines[index] = f"{key} = {rendered}"
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return
    lines.insert(end, f"{key} = {rendered}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def render_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(render_value(item) for item in value) + "]"
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def find_section(lines: list[str], header: str) -> int | None:
    for index, line in enumerate(lines):
        if line.strip() == header:
            return index
    return None


def find_next_section(lines: list[str], start: int) -> int | None:
    for index in range(start, len(lines)):
        stripped = lines[index].strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            return index
    return None
