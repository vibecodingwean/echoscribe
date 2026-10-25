"""Stored, recipient-specific permission for audio transcription transfers."""

from __future__ import annotations

from .config import Config, TRANSCRIPTION_PROVIDERS


RECIPIENTS = {
    "openai": ("OpenAI", "https://api.openai.com"),
    "gemini": ("Google Gemini", "https://generativelanguage.googleapis.com"),
    "xai": ("xAI", "https://api.x.ai"),
    "elevenlabs": ("ElevenLabs", "https://api.elevenlabs.io"),
}


def recipient(config: Config, provider: str) -> tuple[str, str]:
    if provider not in TRANSCRIPTION_PROVIDERS:
        raise ValueError(f"Unknown transcription provider: {provider}")
    if provider == "localai":
        section = config.data.get("localai", {})
        endpoint = str(section.get("whisper_url", "") if isinstance(section, dict) else "").strip()
        return "Local AI Whisper", endpoint
    return RECIPIENTS[provider]


def allowed(config: Config, provider: str) -> bool:
    _, endpoint = recipient(config, provider)
    stored = config.data.get("consent", {})
    return bool(endpoint) and isinstance(stored, dict) and stored.get(provider) == endpoint


def require_consent(config: Config, provider: str) -> None:
    if allowed(config, provider):
        return
    label, endpoint = recipient(config, provider)
    raise RuntimeError(
        f"Audio transfer to {label} ({endpoint or 'unconfigured endpoint'}) is blocked. "
        "Open EchoScribe Preferences to allow it before dictation."
    )
