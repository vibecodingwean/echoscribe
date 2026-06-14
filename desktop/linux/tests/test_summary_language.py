from __future__ import annotations

import unittest
from unittest.mock import patch

from echoscribe import summary
from echoscribe.native_host import handle_summary


class FakeConfig:
    def __init__(self) -> None:
        self.data = {
            "providers": {"summary": "openai", "transcription": "openai"},
            "summary": {
                "target_language": "auto",
                "url_summary_prompt": "",
                "xai_reasoning_effort": "none",
                "app_fetch_url": False,
            },
            "openai": {"summary_model": "test-summary-model"},
        }

    def summary_model(self, provider: str) -> str:
        self.last_summary_provider = provider
        return "test-summary-model"

    def provider_api_key(self, provider: str) -> str:
        return "test-api-key" if provider == "openai" else ""


class SummaryLanguageTests(unittest.TestCase):
    def test_explicit_language_prompt_requires_target_translation(self) -> None:
        system_prompt, user_prompt = summary.build_prompt(
            FakeConfig(),
            "Titel: Kommunalwahl. Inhalt: Die Stadt plant neue Buslinien.",
            requested_language="en",
            provider="openai",
        )

        self.assertIn('Output MUST be entirely in English ("en")', system_prompt)
        self.assertIn("Translate the summary into that target language", user_prompt)
        self.assertLess(user_prompt.index("Critical language rule"), user_prompt.index("Text:"))

    def test_auto_prompt_preserves_dominant_source_language(self) -> None:
        system_prompt, user_prompt = summary.build_prompt(
            FakeConfig(),
            "Title: Weather update. Content: Heavy rain is expected tonight.",
            requested_language="auto",
            provider="openai",
        )

        self.assertIn("Auto means detect the dominant source language", system_prompt)
        self.assertIn("If the input is English, output English", user_prompt)
        self.assertNotIn('Output MUST be entirely in German ("de")', user_prompt)

    def test_explicit_english_retries_when_model_returns_german(self) -> None:
        with patch(
            "echoscribe.summary.summarize_openai",
            side_effect=[
                "Die Stadt meldet neue Buslinien und berichtet über den Fahrplan.",
                "The city reports new bus routes and timetable changes.",
            ],
        ) as summarize_openai:
            result = summary.summarize(
                FakeConfig(),
                "Die Stadt plant neue Buslinien und einen geänderten Fahrplan.",
                requested_language="en",
            )

        self.assertEqual(result["summary"], "The city reports new bus routes and timetable changes.")
        self.assertEqual(summarize_openai.call_count, 2)
        retry_prompt = summarize_openai.call_args.args[3]
        self.assertIn("previous output did not follow", retry_prompt)

    def test_auto_language_does_not_retry(self) -> None:
        with patch(
            "echoscribe.summary.summarize_openai",
            return_value="Die Stadt meldet neue Buslinien und berichtet über den Fahrplan.",
        ) as summarize_openai:
            result = summary.summarize(
                FakeConfig(),
                "Die Stadt plant neue Buslinien und einen geänderten Fahrplan.",
                requested_language="auto",
            )

        self.assertIn("Die Stadt", result["summary"])
        self.assertEqual(summarize_openai.call_count, 1)

    def test_native_host_forwards_target_language_code(self) -> None:
        with patch(
            "echoscribe.native_host.summarize",
            return_value={"summary": "The page summary.", "provider": "openai", "model": "test-summary-model"},
        ) as summarize_call:
            response = handle_summary(
                {
                    "url": "https://example.com",
                    "title": "Beispiel",
                    "text": "Dies ist ein deutscher Beispieltext mit mehreren Fakten.",
                    "targetLanguageCode": "en",
                },
                FakeConfig(),
            )

        self.assertTrue(response["ok"])
        self.assertEqual(summarize_call.call_args.kwargs["requested_language"], "en")


if __name__ == "__main__":
    unittest.main()
