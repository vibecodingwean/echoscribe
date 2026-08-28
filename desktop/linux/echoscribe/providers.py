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
    interactions_endpoint = "https://generativelanguage.googleapis.com/v1beta/interactions"

    def __init__(self, api_key: str, timeout: int = 180) -> None:
        self.api_key = api_key
        self.timeout = timeout

    def transcribe(self, audio_path: Path, model: str, language: str = "auto", **_: Any) -> str:
        if not self.api_key:
            raise ApiError("GEMINI_API_KEY is not configured")
        mime_type = guess_mime_type(audio_path)
        file_obj = self._upload_file(audio_path, mime_type)
        if is_gemini_dedicated_transcribe_model(model):
            return self._transcribe_interactions(
                model=model,
                mime_type=mime_type,
                file_uri=str(file_obj["uri"]),
                language=language,
            )
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

    def _transcribe_interactions(
        self,
        *,
        model: str,
        mime_type: str,
        file_uri: str,
        language: str = "auto",
    ) -> str:
        body = build_gemini_interactions_request(
            model=model,
            file_uri=file_uri,
            mime_type=mime_type,
            language=language,
        )
        response = http_post_json(
            self.interactions_endpoint,
            headers={"x-goog-api-key": self.api_key},
            body=body,
            timeout=self.timeout,
        )
        payload = json_or_error(response)
        return parse_gemini_interactions_transcript(payload)

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


class LocalAIProvider:
    def __init__(self, timeout: int = 180) -> None:
        self.timeout = timeout

    def transcribe(
        self,
        audio_path: Path,
        model: str = "whisper-1",
        language: str = "auto",
        endpoint: str = "",
        **_: Any,
    ) -> str:
        if not endpoint:
            raise ApiError("Local AI Whisper URL is not configured")
        data: dict[str, str] = {"model": model, "response_format": "json"}
        if language and language != "auto":
            data["language"] = language
        response = post_multipart(
            endpoint,
            headers={},
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
            raise ApiError("Local AI transcription returned empty text")
        return text


def create_provider(
    provider: str,
    api_key: str,
    timeout: int = 180,
) -> OpenAIProvider | GeminiProvider | XAIProvider | ElevenLabsProvider | LocalAIProvider:
    if provider == "openai":
        return OpenAIProvider(api_key=api_key, timeout=timeout)
    if provider == "gemini":
        return GeminiProvider(api_key=api_key, timeout=timeout)
    if provider == "xai":
        return XAIProvider(api_key=api_key, timeout=timeout)
    if provider == "elevenlabs":
        return ElevenLabsProvider(api_key=api_key, timeout=timeout)
    if provider == "localai":
        return LocalAIProvider(timeout=timeout)
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


def build_gemini_interactions_request(
    *,
    model: str,
    file_uri: str,
    mime_type: str,
    language: str = "auto",
) -> dict[str, Any]:
    transcription_config: dict[str, Any] = {
        "mode": {
            "type": "verbatim",
            "diarization_mode": "speaker",
        }
    }
    if language and language != "auto":
        transcription_config["language_codes"] = [language]
    return {
        "model": model,
        "input": [
            {
                "type": "audio",
                "uri": file_uri,
                "mime_type": mime_type,
            }
        ],
        "generation_config": {
            "transcription_config": transcription_config,
        },
    }


def is_gemini_dedicated_transcribe_model(model: str) -> bool:
    normalized = model.strip().lower()
    return "3.5-transcribe" in normalized and "-live" not in normalized


def normalize_speaker_label(raw: str) -> str:
    trimmed = raw.strip()
    if not trimmed:
        return "Speaker 1"
    lowered = trimmed.lower()
    for prefix in ("spk_", "spk-", "spk ", "speaker "):
        if lowered.startswith(prefix):
            digits = "".join(ch for ch in trimmed[len(prefix) :] if ch.isdigit())
            if digits:
                return f"Speaker {digits}"
    digits = "".join(ch for ch in trimmed if ch.isdigit())
    if digits:
        return f"Speaker {digits}"
    if trimmed.startswith("Speaker "):
        return trimmed
    return f"Speaker {trimmed}"


def format_native_speaker_turns(turns: list[tuple[str, str]]) -> str:
    if not turns:
        return ""
    lines: list[str] = []
    current_speaker = ""
    current_parts: list[str] = []

    def flush() -> None:
        nonlocal current_speaker, current_parts
        text = " ".join(part for part in current_parts if part).strip()
        if current_speaker and text:
            lines.append(f"{current_speaker}: {text}")
        current_parts = []

    for speaker, text in turns:
        label = normalize_speaker_label(speaker)
        piece = text.strip()
        if not piece:
            continue
        if label == current_speaker:
            current_parts.append(piece)
        else:
            flush()
            current_speaker = label
            current_parts = [piece]
    flush()
    return "\n".join(lines).strip()


def parse_gemini_interactions_transcript(payload: dict[str, Any]) -> str:
    words: list[tuple[str, str]] = []

    def collect_annotations(annotations: Any) -> None:
        if not isinstance(annotations, list):
            return
        for annotation in annotations:
            if not isinstance(annotation, dict):
                continue
            type_name = str(annotation.get("type", "")).strip().lower()
            if type_name and type_name not in {"word_info", "word"}:
                continue
            text = str(annotation.get("text") or annotation.get("word") or "").strip()
            speaker = annotation.get("speaker")
            if not text or speaker is None:
                continue
            speaker_text = str(speaker).strip()
            if not speaker_text:
                continue
            words.append((speaker_text, text))

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            if "annotations" in node:
                collect_annotations(node.get("annotations"))
                for key, value in node.items():
                    if key == "annotations":
                        continue
                    walk(value)
                return
            type_name = str(node.get("type", "")).strip().lower()
            if type_name in {"word_info", "word"}:
                collect_annotations([node])
                return
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(payload)
    if words:
        formatted = format_native_speaker_turns(words)
        if formatted:
            return formatted

    output_text = str(payload.get("output_text", "")).strip()
    if output_text:
        return output_text

    texts: list[str] = []
    steps = payload.get("steps")
    if isinstance(steps, list):
        for step in steps:
            if not isinstance(step, dict):
                continue
            content = step.get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if isinstance(item, dict):
                    text = str(item.get("text", "")).strip()
                    if text:
                        texts.append(text)
    joined = "\n".join(texts).strip()
    if joined:
        return joined
    raise ApiError("Gemini transcription returned empty text")


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
