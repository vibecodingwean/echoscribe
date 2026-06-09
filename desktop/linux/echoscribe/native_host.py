"""Browser Native Messaging host for EchoScribe Web Summary."""

from __future__ import annotations

import base64
import html
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .config import Config, load_config
from .summary import summarize


MAX_NATIVE_MESSAGE_BYTES = 64 * 1024 * 1024
MAX_NATIVE_RESPONSE_BYTES = 1024 * 1024
MAX_SOURCE_CHARS = 120000


@dataclass(frozen=True)
class SummaryRequest:
    url: str = ""
    title: str = ""
    description: str = ""
    selection: str = ""
    text: str = ""
    pdf_base64: str = ""
    mime_type: str = ""
    provider: str = ""
    target_language_code: str = ""


def main(argv: list[str] | None = None) -> int:
    del argv
    project_dir = Path(__file__).resolve().parents[1]
    config = load_config(project_dir)
    try:
        request = read_native_message(sys.stdin.buffer)
        response = handle_message(request, config)
    except Exception as exc:
        print(exc, file=sys.stderr)
        response = {"ok": False, "summary": "", "provider": "", "model": "", "error": str(exc)}
    write_native_message(sys.stdout.buffer, response)
    return 0


def handle_message(message: dict[str, Any], config: Config) -> dict[str, Any]:
    request_type = str(message.get("type", ""))
    if request_type != "summarize":
        return {"ok": False, "summary": "", "provider": "", "model": "", "error": f"Unknown request type '{request_type}'."}
    return handle_summary(message, config)


def handle_summary(message: dict[str, Any], config: Config) -> dict[str, Any]:
    try:
        request = SummaryRequest(
            url=str(message.get("url", "")),
            title=str(message.get("title", "")),
            description=str(message.get("description", "")),
            selection=str(message.get("selection", "")),
            text=str(message.get("text", "")),
            pdf_base64=str(message.get("pdfBase64", "")),
            mime_type=str(message.get("mimeType", "")),
            provider=str(message.get("provider", "")),
            target_language_code=str(message.get("targetLanguageCode", "")),
        )
        source = build_source_text(request, config)
        result = summarize(config, source, provider=request.provider, requested_language=request.target_language_code)
        return {"ok": True, "summary": result["summary"], "provider": result["provider"], "model": result["model"], "error": ""}
    except Exception as exc:
        return {"ok": False, "summary": "", "provider": "", "model": "", "error": str(exc)}


def build_source_text(request: SummaryRequest, config: Config) -> str:
    text = first_non_empty(request.selection, request.text)
    title = request.title.strip()
    url = request.url.strip()
    description = request.description.strip()
    if not text and request.pdf_base64.strip():
        text = extract_pdf_text(base64.b64decode(request.pdf_base64))
    summary_cfg = config.data.get("summary", {})
    app_fetch_url = True
    if isinstance(summary_cfg, dict):
        app_fetch_url = bool(summary_cfg.get("app_fetch_url", True))
    if len(text) < 80 and app_fetch_url and looks_like_url(url):
        try:
            text = fetch_url_text(url, request.mime_type)
        except Exception:
            pass
    if not text:
        text = url
    if not text:
        raise RuntimeError("No webpage content was provided.")
    text = collapse_whitespace(text)
    if len(text) > MAX_SOURCE_CHARS:
        text = text[:MAX_SOURCE_CHARS]
    parts = []
    if title:
        parts.append(f"Title: {title}")
    if url:
        parts.append(f"URL: {url}")
    if description:
        parts.append(f"Description: {description}")
    parts.append("")
    parts.append("Content:")
    parts.append(text)
    return "\n".join(parts)


def fetch_url_text(url: str, mime_type: str = "") -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme == "file":
        path = Path(urllib.request.url2pathname(parsed.path))
        data = path.read_bytes()
        if is_pdf(path.name, mime_type):
            return extract_pdf_text(data)
        return data.decode("utf-8", errors="replace")
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
            content_type = response.headers.get("content-type", mime_type)
    except urllib.error.HTTPError as exc:
        data = exc.read()
        content_type = exc.headers.get("content-type", mime_type) if exc.headers else mime_type
        raise RuntimeError(f"URL fetch failed with HTTP {exc.code}: {data[:500].decode('utf-8', errors='replace')}") from exc
    if is_pdf(url, content_type):
        return extract_pdf_text(data)
    body = data.decode("utf-8", errors="replace")
    without_scripts = re.sub(r"<(script|style|noscript|svg)[\s\S]*?</\1>", " ", body, flags=re.IGNORECASE)
    without_tags = re.sub(r"<[^>]+>", " ", without_scripts)
    return collapse_whitespace(html.unescape(without_tags))


def extract_pdf_text(data: bytes) -> str:
    if not data:
        raise RuntimeError("The PDF is empty.")
    with tempfile.NamedTemporaryFile(prefix="echoscribe_pdf_", suffix=".pdf", delete=False) as handle:
        handle.write(data)
        path = Path(handle.name)
    try:
        result = subprocess.run(
            ["pdftotext", "-layout", str(path), "-"],
            input=b"",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=45,
        )
    finally:
        path.unlink(missing_ok=True)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(detail or "PDF text extraction failed. Install poppler-utils for PDF summaries.")
    text = collapse_whitespace(result.stdout.decode("utf-8", errors="replace"))
    if not text:
        raise RuntimeError("No extractable text was found in the PDF.")
    return text


def read_native_message(stream: Any) -> dict[str, Any]:
    raw_length = stream.read(4)
    if len(raw_length) != 4:
        raise EOFError("Native message length prefix is missing.")
    length = struct.unpack("<I", raw_length)[0]
    if length <= 0 or length > MAX_NATIVE_MESSAGE_BYTES:
        raise RuntimeError(f"Invalid native message length: {length}.")
    payload = stream.read(length)
    if len(payload) != length:
        raise EOFError("Native message payload ended early.")
    message = json.loads(payload.decode("utf-8"))
    if not isinstance(message, dict):
        raise RuntimeError("Native message payload must be a JSON object.")
    return message


def write_native_message(stream: Any, value: dict[str, Any]) -> None:
    payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
    if len(payload) > MAX_NATIVE_RESPONSE_BYTES:
        raise RuntimeError("Native message response exceeds Chrome's 1 MB limit.")
    stream.write(struct.pack("<I", len(payload)))
    stream.write(payload)
    stream.flush()


def first_non_empty(*values: str) -> str:
    for value in values:
        if value and value.strip():
            return value.strip()
    return ""


def collapse_whitespace(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def looks_like_url(value: str) -> bool:
    parsed = urllib.parse.urlparse(value)
    return parsed.scheme in {"http", "https", "file"} and bool(parsed.netloc or parsed.path)


def is_pdf(name_or_url: str, mime_type: str = "") -> bool:
    lowered = f"{name_or_url} {mime_type}".lower()
    return "application/pdf" in lowered or ".pdf" in lowered


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
