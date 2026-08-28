"""Configuration loading for EchoScribe."""

from __future__ import annotations

import os
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - used on Python 3.9/3.10.
    tomllib = None  # type: ignore[assignment]


TRANSCRIPTION_PROVIDERS = {"openai", "gemini", "xai", "elevenlabs", "localai"}
ALL_PROVIDERS = TRANSCRIPTION_PROVIDERS
DEFAULT_LOCAL_AI_WHISPER_URL = "http://127.0.0.1:8000/v1/audio/transcriptions"

# Only applied to gemini.transcription_model — never to summary/translation models.
DEPRECATED_GEMINI_TRANSCRIPTION_MODELS = {
    "gemini-3.1-flash-lite": "gemini-3.5-transcribe",  # model-migration-ok
    "gemini-3.6-flash": "gemini-3.5-transcribe",  # model-migration-ok
    "gemini-3.7-flash": "gemini-3.5-transcribe",  # model-migration-ok
    "gemini-3.1-pro-preview": "gemini-3.5-transcribe",  # model-migration-ok
}


DEFAULTS: dict[str, Any] = {
    "providers": {
        "transcription": "openai",
    },
    "openai": {
        "api_key": "",
        "api_key_env": "OPENAI_API_KEY",
        "transcription_model": "gpt-4o-mini-transcribe",
        "target_language": "auto",
    },
    "gemini": {
        "api_key": "",
        "api_key_env": "GEMINI_API_KEY",
        "transcription_model": "gemini-3.5-transcribe",
        "target_language": "auto",
    },
    "xai": {
        "api_key": "",
        "api_key_env": "XAI_API_KEY",
        "transcription_model": "xai-stt",
        "target_language": "auto",
        "stt_format": False,
    },
    "elevenlabs": {
        "api_key": "",
        "api_key_env": "ELEVENLABS_API_KEY",
        "transcription_model": "scribe_v2",
        "target_language": "auto",
        "tag_audio_events": False,
    },
    "localai": {
        "whisper_url": DEFAULT_LOCAL_AI_WHISPER_URL,
        "transcription_model": "whisper-1",
        "target_language": "auto",
    },
    "recorder": {
        "command": "",
        "minimum_bytes": 2048,
        "reminder_seconds": 90,
    },
    "paste": {
        "shortcut": "auto",
        "paste_delay_ms": 120,
    },
}

def default_secret_file(filename: str) -> Path:
    configured = os.environ.get("ECHOSCRIBE_SECRETS_DIR")
    if configured:
        return Path(configured).expanduser() / filename
    return Path("~/.config/echoscribe/secrets.env").expanduser()


@dataclass(frozen=True)
class Config:
    data: dict[str, Any]
    path: Path | None
    project_dir: Path
    env_file: Path

    @property
    def openai_api_key(self) -> str:
        return self.provider_api_key("openai")

    def provider_api_key(self, provider: str) -> str:
        provider = normalize_provider(provider)
        if provider == "localai":
            return ""
        section = self.data[provider]
        configured = str(section.get("api_key", "")).strip()
        if configured:
            return configured
        env_name = str(section.get("api_key_env", default_api_key_env(provider))).strip()
        if not env_name:
            return ""
        return os.environ.get(env_name, "").strip() or read_env_file(self.env_file).get(env_name, "")

    def active_provider(self, stage: str) -> str:
        if stage != "transcription":
            raise ValueError(f"Unsupported provider stage: {stage}")
        providers = self.data["providers"]
        provider = normalize_provider(str(providers.get(stage, "openai")))
        if provider not in TRANSCRIPTION_PROVIDERS:
            raise ValueError(f"Provider '{provider}' does not support speech-to-text in EchoScribe")
        return provider

    def configured_secret(self, section: str, key: str, env_key: str) -> str:
        section_data = self.data.get(section, {})
        if not isinstance(section_data, dict):
            return ""
        configured = str(section_data.get(key, "")).strip()
        if configured:
            return configured
        env_name = str(section_data.get(env_key, "")).strip()
        if not env_name:
            return ""
        return os.environ.get(env_name, "").strip() or read_env_file(self.env_file).get(env_name, "")

def config_search_paths(project_dir: Path | None = None) -> list[Path]:
    paths: list[Path] = []
    env_path = os.environ.get("ECHOSCRIBE_CONFIG")
    if env_path:
        paths.append(Path(env_path).expanduser())
    paths.append(Path("~/.config/echoscribe/config.toml").expanduser())
    if project_dir is not None:
        paths.append(project_dir / "config.toml")
    return paths


def env_file_path() -> Path:
    configured = os.environ.get("ECHOSCRIBE_ENV_FILE")
    if configured:
        return Path(configured).expanduser()
    return default_secret_file("echoscribe.env")


def default_api_key_env(provider: str) -> str:
    return {
        "openai": "OPENAI_API_KEY",
        "gemini": "GEMINI_API_KEY",
        "xai": "XAI_API_KEY",
        "elevenlabs": "ELEVENLABS_API_KEY",
    }[normalize_provider(provider)]


def normalize_provider(provider: str) -> str:
    normalized = provider.strip().lower()
    aliases = {
        "gpt": "openai",
        "chatgpt": "openai",
        "google": "gemini",
        "grok": "xai",
        "eleven": "elevenlabs",
        "elevenlabs": "elevenlabs",
        "11labs": "elevenlabs",
        "local": "localai",
        "local-ai": "localai",
        "local_ai": "localai",
        "localai": "localai",
    }
    normalized = aliases.get(normalized, normalized)
    if normalized not in ALL_PROVIDERS:
        raise ValueError(f"Unsupported API provider: {provider}")
    return normalized


def read_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return parse_env_text(path.read_text(encoding="utf-8"))


def parse_env_text(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line.removeprefix("export ").strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            values[key] = value
    return values


def write_env_value(path: Path, key: str, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch(mode=0o600, exist_ok=True)
    try:
        path.chmod(0o600)
    except OSError:
        pass
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    rendered = f"{key}={value.strip()}"
    replaced = False
    out: list[str] = []
    for line in lines:
        candidate = line.strip()
        if candidate.startswith("export "):
            candidate = candidate.removeprefix("export ").strip()
        if candidate.startswith(f"{key}="):
            out.append(rendered)
            replaced = True
        else:
            out.append(line)
    if not replaced:
        out.append(rendered)
    path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def load_toml(path: Path) -> dict[str, Any]:
    if tomllib is not None:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    return parse_simple_toml(path.read_text(encoding="utf-8"))


def parse_simple_toml(text: str) -> dict[str, Any]:
    """Parse the small TOML subset EchoScribe writes on Python without tomllib."""
    data: dict[str, Any] = {}
    section: dict[str, Any] = data
    lines = iter(text.splitlines())
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section_name = line[1:-1].strip()
            section = data.setdefault(section_name, {})
            if not isinstance(section, dict):
                raise ValueError(f"Invalid TOML section: {section_name}")
            continue
        if "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        key = key.strip()
        raw_value = strip_inline_comment(raw_value.strip())
        if raw_value == '"""':
            section[key] = read_multiline_string(lines)
        else:
            section[key] = parse_simple_value(raw_value)
    return data


def strip_inline_comment(value: str) -> str:
    in_quote = False
    escaped = False
    out = []
    for char in value:
        if escaped:
            out.append(char)
            escaped = False
            continue
        if char == "\\":
            out.append(char)
            escaped = True
            continue
        if char == '"':
            in_quote = not in_quote
        if char == "#" and not in_quote:
            break
        out.append(char)
    return "".join(out).strip()


def read_multiline_string(lines: Any) -> str:
    collected: list[str] = []
    for raw_line in lines:
        if raw_line.strip() == '"""':
            return "\n".join(collected).strip()
        collected.append(raw_line)
    raise ValueError("Unterminated TOML multiline string")


def parse_simple_value(value: str) -> Any:
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_simple_value(part.strip()) for part in inner.split(",") if part.strip()]
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    try:
        return int(value)
    except ValueError:
        return value


def load_config(project_dir: Path | None = None) -> Config:
    project_dir = (project_dir or Path.cwd()).resolve()
    chosen: Path | None = None
    loaded: dict[str, Any] = {}
    for path in config_search_paths(project_dir):
        if path.exists():
            loaded = load_toml(path)
            chosen = path
            break
    migrate_loaded_config(loaded)
    return Config(data=deep_merge(DEFAULTS, loaded), path=chosen, project_dir=project_dir, env_file=env_file_path())


def migrate_loaded_config(data: dict[str, Any]) -> None:
    gemini = data.get("gemini")
    if not isinstance(gemini, dict):
        return
    value = str(gemini.get("transcription_model", "")).strip()
    replacement = DEPRECATED_GEMINI_TRANSCRIPTION_MODELS.get(value)
    if replacement:
        gemini["transcription_model"] = replacement
