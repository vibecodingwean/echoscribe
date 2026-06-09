"""Small stdlib HTTP helpers used by API clients."""

from __future__ import annotations

import json
import mimetypes
import uuid
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


AUDIO_MIME_OVERRIDES = {
    ".m4a": "audio/mp4",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".webm": "audio/webm",
    ".ogg": "audio/ogg",
    ".oga": "audio/ogg",
    ".opus": "audio/opus",
}


@dataclass(frozen=True)
class HttpResponse:
    status_code: int
    body: bytes
    headers: dict[str, str]

    def json(self) -> Any:
        return json.loads(self.body.decode("utf-8"))


def post_json(
    url: str,
    *,
    headers: dict[str, str] | None = None,
    body: dict[str, Any],
    timeout: int = 180,
) -> HttpResponse:
    request_headers = {"Content-Type": "application/json", **(headers or {})}
    return post_bytes(
        url,
        headers=request_headers,
        body=json.dumps(body).encode("utf-8"),
        timeout=timeout,
    )


def post_raw(
    url: str,
    *,
    headers: dict[str, str] | None = None,
    body: bytes,
    timeout: int = 180,
) -> HttpResponse:
    return post_bytes(url, headers=headers or {}, body=body, timeout=timeout)


def get_json(
    url: str,
    *,
    headers: dict[str, str] | None = None,
    timeout: int = 180,
) -> HttpResponse:
    request = urllib.request.Request(url, headers=headers or {}, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return HttpResponse(
                status_code=response.status,
                body=response.read(),
                headers=dict(response.headers.items()),
            )
    except urllib.error.HTTPError as exc:
        return HttpResponse(
            status_code=exc.code,
            body=exc.read(),
            headers=dict(exc.headers.items()) if exc.headers else {},
        )


def post_multipart(
    url: str,
    *,
    headers: dict[str, str] | None = None,
    fields: dict[str, str] | None = None,
    files: dict[str, tuple[str, bytes, str]] | None = None,
    timeout: int = 180,
) -> HttpResponse:
    boundary = f"echoscribe-{uuid.uuid4().hex}"
    body_parts: list[bytes] = []
    for name, value in (fields or {}).items():
        body_parts.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                str(value).encode(),
                b"\r\n",
            ]
        )
    for name, (filename, data, mime_type) in (files or {}).items():
        body_parts.extend(
            [
                f"--{boundary}\r\n".encode(),
                (
                    f'Content-Disposition: form-data; name="{name}"; '
                    f'filename="{filename}"\r\n'
                ).encode(),
                f"Content-Type: {mime_type}\r\n\r\n".encode(),
                data,
                b"\r\n",
            ]
        )
    body_parts.append(f"--{boundary}--\r\n".encode())
    request_headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        **(headers or {}),
    }
    return post_bytes(
        url,
        headers=request_headers,
        body=b"".join(body_parts),
        timeout=timeout,
    )


def post_bytes(
    url: str,
    *,
    headers: dict[str, str],
    body: bytes,
    timeout: int,
) -> HttpResponse:
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return HttpResponse(
                status_code=response.status,
                body=response.read(),
                headers=dict(response.headers.items()),
            )
    except urllib.error.HTTPError as exc:
        return HttpResponse(
            status_code=exc.code,
            body=exc.read(),
            headers=dict(exc.headers.items()) if exc.headers else {},
        )


def read_file_part(path: Path, fallback_mime: str = "application/octet-stream") -> tuple[str, bytes, str]:
    return path.name, path.read_bytes(), guess_mime_type(path, fallback_mime=fallback_mime)


def guess_mime_type(path: Path, fallback_mime: str = "application/octet-stream") -> str:
    override = AUDIO_MIME_OVERRIDES.get(path.suffix.lower())
    if override:
        return override
    guessed, _ = mimetypes.guess_type(path.name)
    return guessed or fallback_mime

