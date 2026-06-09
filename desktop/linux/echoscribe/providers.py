"""API provider clients for transcription."""

from __future__ import annotations

from pathlib import Path
import time
from typing import Any

from .http_client import (
    HttpResponse,
    get_json as http_get_json,
    guess_mime_type as http_guess_mime_type,
    post_json as http_post_json,
    post_multipart,
    post_raw,
)
from .openai_client import ApiError, OpenAIClient


class OpenAIProvider:
    def __init__(self, api_key: str, timeout: int = 180) -> None:
        self.client = OpenAIClient(api_key=api_key, timeout=timeout)

    def transcribe(self, audio_path: Path, model: str, language: str = "auto", **_: Any) -> str:
        return self.client.transcribe(audio_path, model=model, language=language)

class GeminiProvider:
    upload_endpoint = "https://generativelanguage.googleapis.com/upload/v1beta/files"
    files_endpoint = "https://generativelanguage.googleapis.com/v1beta"
    models_endpoint = "https://generativelanguage.googleapis.com/v1beta/models"

    def __init__(self, api_key: str, timeout: int = 180) -> None:
        self.api_key = api_key
        self.timeout = timeout

    def transcribe(self, audio_path: Path, model: str, language: str = "auto", **_: Any) -> str:
        if not self.api_key:
            raise ApiError("GEMINI_API_KEY is not configured")
        mime_type = guess_mime_type(audio_path)
        file_obj = self._upload_file(audio_path, mime_type)
        language_hint = ""
        if language and language != "auto":
            language_hint = f" Use language code {language} when relevant."
        prompt = (
            "Transcribe the following audio accurately. Auto-detect the spoken language "
            "and return only the raw transcript text without any extra words."
            f"{language_hint}"
        )
        body = {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {"text": prompt},
                        {
                            "file_data": {
                                "file_uri": file_obj["uri"],
                                "mime_type": mime_type,
                            }
                        },
                    ],
                }
            ]
        }
        payload = post_json(
            f"{self.models_endpoint}/{model}:generateContent?key={self.api_key}",
            body,
            timeout=self.timeout,
        )
        return gemini_text(payload, "Gemini transcription returned empty text")

    def _upload_file(self, audio_path: Path, mime_type: str) -> dict[str, Any]:
        data = audio_path.read_bytes()
        start_response = http_post_json(
            f"{self.upload_endpoint}?key={self.api_key}",
            headers={
                "X-Goog-Upload-Protocol": "resumable",
                "X-Goog-Upload-Command": "start",
                "X-Goog-Upload-Header-Content-Length": str(len(data)),
                "X-Goog-Upload-Header-Content-Type": mime_type,
            },
            body={"file": {"display_name": audio_path.name}},
            timeout=self.timeout,
        )
        json_or_error(start_response)
        upload_url = header_value(start_response.headers, "x-goog-upload-url")
        if not upload_url:
            raise ApiError("Gemini upload did not return an upload URL")
        response = post_raw(
            upload_url,
            headers={
                "Content-Type": mime_type,
                "Content-Length": str(len(data)),
                "X-Goog-Upload-Offset": "0",
                "X-Goog-Upload-Command": "upload, finalize",
            },
            body=data,
            timeout=self.timeout,
        )
        payload = json_or_error(response)
        file_obj = payload.get("file") if isinstance(payload.get("file"), dict) else payload
        if not isinstance(file_obj, dict):
            raise ApiError("Gemini upload returned no file object")
        if not file_obj.get("uri"):
            name = str(file_obj.get("name", "")).strip()
            if name:
                file_obj["uri"] = f"https://generativelanguage.googleapis.com/v1beta/{name}"
        if not file_obj.get("uri"):
            raise ApiError("Gemini upload returned no file URI")
        return self._wait_for_file_active(file_obj)

    def _wait_for_file_active(self, file_obj: dict[str, Any]) -> dict[str, Any]:
        state = gemini_file_state(file_obj)
        if not state or state == "ACTIVE":
            return file_obj
        if state == "FAILED":
            raise ApiError("Gemini file processing failed")
        if state != "PROCESSING":
            raise ApiError(f"Gemini file returned unexpected state: {state}")
        name = str(file_obj.get("name", "")).strip()
        if not name:
            raise ApiError(f"Gemini file is {state.lower()} but returned no file name")
        for _ in range(12):
            time.sleep(1)
            payload = json_or_error(
                http_get_json(
                    f"{self.files_endpoint}/{name}?key={self.api_key}",
                    timeout=self.timeout,
                )
            )
            polled = payload.get("file") if isinstance(payload.get("file"), dict) else payload
            if not isinstance(polled, dict):
                raise ApiError("Gemini file status returned no file object")
            file_obj = {**file_obj, **polled}
            if not file_obj.get("uri"):
                file_obj["uri"] = f"https://generativelanguage.googleapis.com/v1beta/{name}"
            state = gemini_file_state(file_obj)
            if state == "ACTIVE":
                return file_obj
            if state == "FAILED":
                raise ApiError("Gemini file processing failed")
            if state != "PROCESSING":
                raise ApiError(f"Gemini file returned unexpected state: {state}")
        raise ApiError("Gemini file stayed in processing state")


class XAIProvider:
    stt_endpoint = "https://api.x.ai/v1/stt"

    def __init__(self, api_key: str, timeout: int = 180) -> None:
        self.api_key = api_key
        self.timeout = timeout

    def transcribe(
        self,
        audio_path: Path,
        model: str = "xai-stt",
        language: str = "auto",
        stt_format: bool = False,
        **_: Any,
    ) -> str:
        del model
        if not self.api_key:
            raise ApiError("XAI_API_KEY is not configured")
        data: dict[str, str] = {"format": "true" if stt_format else "false"}
        if stt_format and (not language or language == "auto"):
            raise ApiError("xAI STT format=true requires target_language, for example de or en")
        if language and language != "auto":
            data["language"] = language
        response = post_multipart(
            self.stt_endpoint,
            headers={"Authorization": f"Bearer {self.api_key}"},
            fields=data,
            files={
                "file": (
                    patched_audio_filename(audio_path),
                    audio_path.read_bytes(),
                    guess_mime_type(audio_path),
                )
            },
            timeout=self.timeout,
        )
        payload = json_or_error(response)
        text = str(payload.get("text", "")).strip()
        if not text:
            raise ApiError("xAI transcription returned empty text")
        return text


class ElevenLabsProvider:
    stt_endpoint = "https://api.elevenlabs.io/v1/speech-to-text"

    def __init__(self, api_key: str, timeout: int = 180) -> None:
        self.api_key = api_key
        self.timeout = timeout

    def transcribe(
        self,
        audio_path: Path,
        model: str = "scribe_v2",
        language: str = "auto",
        tag_audio_events: bool = False,
        **_: Any,
    ) -> str:
        if not self.api_key:
            raise ApiError("ELEVENLABS_API_KEY is not configured")
        data: dict[str, str] = {
            "model_id": model,
            "tag_audio_events": "true" if tag_audio_events else "false",
        }
        if language and language != "auto":
            data["language_code"] = language
        response = post_multipart(
            self.stt_endpoint,
            headers={"xi-api-key": self.api_key},
            fields=data,
            files={
                "file": (
                    audio_path.name,
                    audio_path.read_bytes(),
                    guess_mime_type(audio_path),
                )
            },
            timeout=self.timeout,
        )
        payload = json_or_error(response)
        text = elevenlabs_text(payload)
        if not text:
            raise ApiError("ElevenLabs transcription returned empty text")
        return text


def create_provider(
    provider: str,
    api_key: str,
    timeout: int = 180,
) -> OpenAIProvider | GeminiProvider | XAIProvider | ElevenLabsProvider:
    if provider == "openai":
        return OpenAIProvider(api_key=api_key, timeout=timeout)
    if provider == "gemini":
        return GeminiProvider(api_key=api_key, timeout=timeout)
    if provider == "xai":
        return XAIProvider(api_key=api_key, timeout=timeout)
    if provider == "elevenlabs":
        return ElevenLabsProvider(api_key=api_key, timeout=timeout)
    raise ValueError(f"Unsupported API provider: {provider}")


def post_json(url: str, body: dict[str, Any], timeout: int) -> dict[str, Any]:
    response = http_post_json(
        url,
        body=body,
        timeout=timeout,
    )
    return json_or_error(response)


def json_or_error(response: HttpResponse) -> dict[str, Any]:
    try:
        payload = response.json()
    except ValueError:
        payload = {}
    if 200 <= response.status_code < 300:
        return payload if isinstance(payload, dict) else {}
    message = ""
    if isinstance(payload, dict):
        error = payload.get("error")
        if isinstance(error, dict):
            message = str(error.get("message", ""))
        message = message or str(payload.get("message", ""))
    raise ApiError(message or f"Request failed with HTTP {response.status_code}")


def header_value(headers: dict[str, str], name: str) -> str:
    expected = name.lower()
    for key, value in headers.items():
        if key.lower() == expected:
            return value.strip()
    return ""


def gemini_text(payload: dict[str, Any], empty_message: str) -> str:
    candidates = payload.get("candidates")
    if isinstance(candidates, list) and candidates:
        first = candidates[0]
        content = first.get("content", {}) if isinstance(first, dict) else {}
        parts = content.get("parts", []) if isinstance(content, dict) else []
        if isinstance(parts, list):
            texts = [
                str(part.get("text", "")).strip()
                for part in parts
                if isinstance(part, dict)
            ]
            text = "\n".join(part for part in texts if part).strip()
            if text:
                return text
    raise ApiError(empty_message)


def gemini_file_state(file_obj: dict[str, Any]) -> str:
    state = file_obj.get("state", "")
    if isinstance(state, dict):
        state = state.get("name", "")
    return str(state).strip().upper()


def elevenlabs_text(payload: dict[str, Any]) -> str:
    text = str(payload.get("text", "")).strip()
    if text:
        return text
    transcripts = payload.get("transcripts")
    if isinstance(transcripts, list):
        return "\n".join(
            str(item.get("text", "")).strip()
            for item in transcripts
            if isinstance(item, dict) and str(item.get("text", "")).strip()
        ).strip()
    if isinstance(transcripts, dict):
        return "\n".join(
            str(item.get("text", "")).strip()
            for item in transcripts.values()
            if isinstance(item, dict) and str(item.get("text", "")).strip()
        ).strip()
    return ""


def guess_mime_type(path: Path) -> str:
    return http_guess_mime_type(path, fallback_mime="audio/wav")


def patched_audio_filename(path: Path) -> str:
    allowed = {"m4a", "mp3", "wav", "webm", "ogg", "oga", "opus"}
    if path.suffix.lower().lstrip(".") in allowed:
        return path.name
    return f"{path.stem or 'audio'}.wav"
