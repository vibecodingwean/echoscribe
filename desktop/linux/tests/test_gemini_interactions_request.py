from __future__ import annotations

import unittest

from echoscribe.providers import build_gemini_interactions_request


class GeminiInteractionsRequestTests(unittest.TestCase):
    def test_auto_language_omits_language_hints_and_language_codes(self) -> None:
        body = build_gemini_interactions_request(
            model="gemini-3.5-transcribe",
            file_uri="https://example.invalid/file",
            mime_type="audio/mp4",
        )
        config = body["generation_config"]["transcription_config"]
        self.assertNotIn("language_hints", config)
        self.assertNotIn("language_codes", config)
        self.assertEqual(
            config["mode"],
            {"type": "verbatim", "diarization_mode": "speaker"},
        )

    def test_explicit_language_uses_language_codes(self) -> None:
        body = build_gemini_interactions_request(
            model="gemini-3.5-transcribe",
            file_uri="https://example.invalid/file",
            mime_type="audio/wav",
            language="de-DE",
        )
        config = body["generation_config"]["transcription_config"]
        self.assertEqual(config["language_codes"], ["de-DE"])
        self.assertNotIn("language_hints", config)
