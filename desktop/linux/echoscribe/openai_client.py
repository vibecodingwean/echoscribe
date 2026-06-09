"""OpenAI-compatible API calls for transcription."""

from __future__ import annotations

import logging
from pathlib import Path
from .http_client import HttpResponse, post_multipart, read_file_part


LOG = logging.getLogger(__name__)


class ApiError(RuntimeError):
    pass


class OpenAIClient:
    def __init__(self, api_key: str, timeout: int = 180) -> None:
        self.api_key = api_key
        self.timeout = timeout

    def transcribe(self, audio_path: Path, model: str, language: str = "auto") -> str:
        if not self.api_key:
            raise ApiError("OPENAI_API_KEY is not configured")
        url = "https://api.openai.com/v1/audio/transcriptions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        data = {"model": model, "response_format": "json"}
        if language and language != "auto":
            data["language"] = language
        filename, body, mime_type = read_file_part(audio_path, fallback_mime="audio/wav")
        response = post_multipart(
            url,
            headers=headers,
            fields=data,
            files={"file": (filename, body, mime_type)},
            timeout=self.timeout,
        )
        payload = self._json_or_error(response)
        text = str(payload.get("text", "")).strip()
        if not text:
            raise ApiError("Transcription returned empty text")
        return text

    @staticmethod
    def _json_or_error(response: HttpResponse) -> dict[str, object]:
        try:
            payload = response.json()
        except ValueError:
            payload = {}
        if 200 <= response.status_code < 300:
            return payload
        message = ""
        if isinstance(payload, dict):
            error = payload.get("error")
            if isinstance(error, dict):
                message = str(error.get("message", ""))
            message = message or str(payload.get("message", ""))
        raise ApiError(message or f"Request failed with HTTP {response.status_code}")
