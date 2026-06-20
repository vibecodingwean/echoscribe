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
    'Each section heading MUST be formatted as "## <emoji> <1-3 word title>", '
    "followed by one concise sentence. "
    "Do not write a section heading without an emoji. "
    "If the content is simple, write 1-3 concise sentences. "
    "Do not add prefaces, labels, or meta commentary."
)
LANGUAGE_RETRY_NOTE = (
    "The previous output did not follow the requested language. "
    "Regenerate the summary now and obey the language rule exactly."
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
- If the content contains multiple distinct aspects (e.g. results, ingredients, steps, features, findings), organize the summary into 2-4 short sections.
- Each section heading MUST be formatted as "## <emoji> <1-3 word title>".
- Do not write a section heading without an emoji.
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
    language = requested_language.strip() or str(summary_cfg.get("target_language", "auto")).strip()
    directive = language_directive(language)
    system_prompt = (
        "You are a precise summarizer. Follow the language rule exactly. "
        f"{directive} Output only the summary, with no preface or labels."
    )
    user_prompt = f"{directive}\n\n{base_prompt}\n\nText:\n{source_text}"
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

    def generate(prompt: str, system: str) -> str:
        if resolved == "openai":
            return summarize_openai(api_key, model, system, prompt)
        if resolved == "gemini":
            return summarize_gemini(api_key, model, prompt)
        if resolved == "anthropic":
            return summarize_anthropic(api_key, model, system, prompt)
        if resolved == "xai":
            summary_cfg = config.data.get("summary", {})
            effort = ""
            if isinstance(summary_cfg, dict):
                effort = str(summary_cfg.get("xai_reasoning_effort", "none")).strip()
            return summarize_xai(api_key, model, system, prompt, effort)
        if resolved == "localai":
            section = config.data.get("localai", {})
            endpoint = str(section.get("llm_url", "") if isinstance(section, dict) else "").strip()
            return summarize_local_ai(endpoint, model, system, prompt)
        raise ApiError(f"Unsupported summary provider '{resolved}'")

    text = generate(user_prompt, system_prompt)
    if needs_language_retry(text, requested_language):
        retry_system = (
            system_prompt
            + " This is mandatory: the complete response must be in the requested target language."
        )
        retry_prompt = f"{LANGUAGE_RETRY_NOTE}\n\n{language_directive(requested_language)}\n\n{user_prompt}"
        text = generate(retry_prompt, retry_system)
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
        "think": False,
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
    code = (code or "auto").strip().lower()
    if code and code != "auto":
        return (
            f'Critical language rule: Output MUST be entirely in {language_name(code)} ("{code}"). '
            "Translate the summary into that target language even when the source text uses a different language. "
            "Do not use another language except for proper nouns, product names, or short quoted source terms."
        )
    return (
        "Critical language rule: Auto means detect the dominant source language and write the summary entirely "
        "in that same language. Do not use the browser, operating-system, or configured locale as the output "
        "language. If the input is English, output English; if German, output German; if Spanish, output Spanish."
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


def needs_language_retry(text: str, requested_code: str) -> bool:
    code = (requested_code or "").strip().lower()
    if not text.strip() or code in {"", "auto"}:
        return False
    if code == "en":
        return language_marker_score(text, "de") >= 4 and language_marker_score(text, "en") <= 2
    if code == "de":
        return language_marker_score(text, "en") >= 4 and language_marker_score(text, "de") <= 2
    return False


def language_marker_score(text: str, code: str) -> int:
    lowered = f" {text.lower()} "
    markers = {
        "de": (
            " der ",
            " die ",
            " das ",
            " und ",
            " ist ",
            " sind ",
            " wurde ",
            " werden ",
            " mit ",
            " für ",
            " ueber ",
            " über ",
            " nicht ",
            " eine ",
            " einen ",
            " im ",
            " auf ",
            " dass ",
            " berichtet ",
        ),
        "en": (
            " the ",
            " and ",
            " is ",
            " are ",
            " was ",
            " were ",
            " with ",
            " for ",
            " about ",
            " not ",
            " a ",
            " an ",
            " in ",
            " on ",
            " that ",
            " reports ",
        ),
    }.get(code, ())
    return sum(lowered.count(marker) for marker in markers)
