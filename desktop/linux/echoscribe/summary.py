"""Web summary provider clients for EchoScribe."""

from __future__ import annotations

from typing import Any

from .config import Config, SUMMARY_PROVIDERS, normalize_provider
from .http_client import HttpResponse, post_json as http_post_json
from .openai_client import ApiError
from .providers import gemini_text


LOCAL_AI_MAX_SOURCE_CHARS = 1200
LOCAL_AI_MAX_OUTPUT_TOKENS = 180
LOCAL_AI_TIMEOUT_SECONDS = 75
LOCAL_AI_SUMMARY_PROMPT = (
    "Summarize the webpage content using only facts present in the text. "
    "If the content has multiple distinct aspects, use 2-4 short sections. "
    'Each section starts with a short "##" heading and one fitting emoji, '
    "followed by one concise sentence. "
    "If the content is simple, write 1-3 concise sentences. "
    "Do not add prefaces, labels, or meta commentary."
)

DEFAULT_URL_SUMMARY_PROMPT = """Summarize the provided webpage content.

Rules:
- Use ONLY information present in the content.
- Never guess or invent missing details.
- Replace vague or clickbait headlines with the specific subject described in the text.
- Prefer concrete facts (names, numbers, results, ingredients, products).
- Remove filler and marketing language.
- Adapt to the content type automatically.

Structure:
- If the content contains multiple distinct aspects (e.g. results, ingredients, steps, features, findings), you MAY organize the summary into 2-4 short sections.
- Each section may have a short "##" heading and one fitting emoji.
- Keep section titles very short (1-3 words).
- Each section should contain one concise sentence.
- If the content is simple, write a short paragraph instead (1-3 sentences).

If the content is missing or insufficient, state the reason or describe why a summary cannot be created."""


def resolve_summary_provider(config: Config, requested: str = "") -> str:
    candidates = [requested, str(config.data["providers"].get("summary", ""))]
    transcription = str(config.data["providers"].get("transcription", ""))
    if transcription:
        candidates.append(transcription)
    for candidate in candidates:
        if not candidate:
            continue
        provider = normalize_provider(candidate)
        if provider in SUMMARY_PROVIDERS:
            return provider
    for provider in ("openai", "gemini", "anthropic", "xai", "localai"):
        if config.provider_api_key(provider):
            return provider
    return "openai"


def build_prompt(
    config: Config,
    source_text: str,
    requested_language: str = "",
    provider: str = "",
) -> tuple[str, str]:
    summary_cfg = config.data.get("summary", {})
    if not isinstance(summary_cfg, dict):
        summary_cfg = {}
    base_prompt = str(summary_cfg.get("url_summary_prompt", "")).strip()
    if not base_prompt:
        base_prompt = LOCAL_AI_SUMMARY_PROMPT if provider == "localai" else DEFAULT_URL_SUMMARY_PROMPT
    language = requested_language.strip() or str(summary_cfg.get("target_language", "de")).strip()
    directive = language_directive(language)
    system_prompt = (
        "You are a precise summarizer. "
        f"{directive} Output only the summary, with no preface or labels."
    )
    user_prompt = f"{base_prompt}\n\n{directive}\n\nText:\n{source_text}"
    return system_prompt, user_prompt


def summarize(config: Config, source_text: str, provider: str = "", requested_language: str = "") -> dict[str, str]:
    resolved = resolve_summary_provider(config, provider)
    model = config.summary_model(resolved)
    api_key = "" if resolved == "localai" else config.provider_api_key(resolved)
    if resolved != "localai" and not api_key:
        raise ApiError(f"API key for summary provider '{resolved}' is missing")
    if resolved == "localai":
        source_text = limit_local_ai_source(source_text)
    system_prompt, user_prompt = build_prompt(config, source_text, requested_language, resolved)
    if resolved == "openai":
        text = summarize_openai(api_key, model, system_prompt, user_prompt)
    elif resolved == "gemini":
        text = summarize_gemini(api_key, model, user_prompt)
    elif resolved == "anthropic":
        text = summarize_anthropic(api_key, model, system_prompt, user_prompt)
    elif resolved == "xai":
        summary_cfg = config.data.get("summary", {})
        effort = ""
        if isinstance(summary_cfg, dict):
            effort = str(summary_cfg.get("xai_reasoning_effort", "none")).strip()
        text = summarize_xai(api_key, model, system_prompt, user_prompt, effort)
    elif resolved == "localai":
        section = config.data.get("localai", {})
        endpoint = str(section.get("llm_url", "") if isinstance(section, dict) else "").strip()
        text = summarize_local_ai(endpoint, model, system_prompt, user_prompt)
    else:  # pragma: no cover - guarded by resolve_summary_provider.
        raise ApiError(f"Unsupported summary provider '{resolved}'")
    return {"summary": text.strip(), "provider": resolved, "model": model}


def summarize_openai(api_key: str, model: str, system_prompt: str, prompt: str) -> str:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": prompt},
        ],
    }
    response = http_post_json(
        "https://api.openai.com/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        body=payload,
        timeout=90,
    )
    body = json_or_error(response)
    return str(body["choices"][0]["message"].get("content", ""))


def summarize_gemini(api_key: str, model: str, prompt: str) -> str:
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [{"text": prompt}],
            }
        ]
    }
    response = http_post_json(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        headers={"x-goog-api-key": api_key},
        body=payload,
        timeout=90,
    )
    return gemini_text(json_or_error(response), "Gemini summary returned empty text")


def summarize_anthropic(api_key: str, model: str, system_prompt: str, prompt: str) -> str:
    payload = {
        "model": model,
        "max_tokens": 1200,
        "system": system_prompt,
        "messages": [{"role": "user", "content": prompt}],
    }
    response = http_post_json(
        "https://api.anthropic.com/v1/messages",
        headers={"x-api-key": api_key, "anthropic-version": "2023-06-01"},
        body=payload,
        timeout=90,
    )
    body = json_or_error(response)
    content = body.get("content", [])
    if not isinstance(content, list):
        return ""
    return "".join(str(part.get("text", "")) for part in content if isinstance(part, dict))


def summarize_xai(api_key: str, model: str, system_prompt: str, prompt: str, reasoning_effort: str) -> str:
    payload: dict[str, Any] = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": prompt},
        ],
    }
    if reasoning_effort:
        payload["reasoning_effort"] = reasoning_effort
    response = http_post_json(
        "https://api.x.ai/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        body=payload,
        timeout=90,
    )
    body = json_or_error(response)
    return str(body["choices"][0]["message"].get("content", ""))


def summarize_local_ai(endpoint: str, model: str, system_prompt: str, prompt: str) -> str:
    if not endpoint:
        raise ApiError("Local AI LLM URL is not configured")
    payload = {
        "model": model,
        "stream": False,
        "options": {
            "num_ctx": 2048,
            "num_predict": LOCAL_AI_MAX_OUTPUT_TOKENS,
            "temperature": 0.2,
        },
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": prompt},
        ],
    }
    response = http_post_json(
        endpoint,
        headers={},
        body=payload,
        timeout=LOCAL_AI_TIMEOUT_SECONDS,
    )
    body = json_or_error(response)
    message = body.get("message", {})
    if not isinstance(message, dict):
        return ""
    return str(message.get("content", ""))


def limit_local_ai_source(source_text: str) -> str:
    if len(source_text) <= LOCAL_AI_MAX_SOURCE_CHARS:
        return source_text
    return (
        source_text[:LOCAL_AI_MAX_SOURCE_CHARS]
        + "\n\n[Content truncated for Local AI performance.]"
    )


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


def language_directive(code: str) -> str:
    code = (code or "auto").strip()
    if code and code != "auto":
        return f'Language rule: Output MUST be in {language_name(code)} ("{code}"). Do not use any other language.'
    return (
        "Language rule: Detect the input language and write the summary strictly in that same language. "
        "If the input is German, output German; if Spanish, output Spanish. Never switch languages."
    )


def language_name(code: str) -> str:
    return {
        "de": "German",
        "en": "English",
        "es": "Spanish",
        "fr": "French",
        "pt": "Portuguese",
        "it": "Italian",
        "nl": "Dutch",
        "tr": "Turkish",
        "ja": "Japanese",
        "ko": "Korean",
        "zh": "Chinese (Simplified)",
    }.get(code, code)
