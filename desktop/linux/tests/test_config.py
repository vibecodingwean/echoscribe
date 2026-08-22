from __future__ import annotations

import os
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

from echoscribe.config import Config, DEFAULTS, load_config, normalize_provider, write_env_value


class ConfigTests(unittest.TestCase):
    def test_defaults_exclude_linux_legacy_sections(self) -> None:
        self.assertNotIn("hotkeys", DEFAULTS)
        self.assertNotIn("overlay", DEFAULTS)
        self.assertNotIn("summary", DEFAULTS)
        self.assertNotIn("summary", DEFAULTS["providers"])
        self.assertNotIn("anthropic", DEFAULTS)
        self.assertNotIn("llm_url", DEFAULTS["localai"])
        for provider in DEFAULTS["providers"].values():
            self.assertNotEqual(provider, "anthropic")
        for section in DEFAULTS.values():
            if isinstance(section, dict):
                self.assertNotIn("summary_model", section)
        self.assertNotIn("method", DEFAULTS["paste"])
        self.assertEqual(DEFAULTS["paste"]["shortcut"], "auto")
        self.assertEqual(DEFAULTS["recorder"]["reminder_seconds"], 90)
        self.assertNotIn("max_seconds", DEFAULTS["recorder"])
        self.assertEqual(DEFAULTS["elevenlabs"]["transcription_model"], "scribe_v2")

    def test_unknown_toml_fields_are_tolerated_and_merged(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            config = root / "config.toml"
            config.write_text(
                '[providers]\ntranscription = "localai"\n[future]\nvalue = 42\n',
                encoding="utf-8",
            )
            with patch.dict(os.environ, {"ECHOSCRIBE_CONFIG": str(config)}, clear=False):
                loaded = load_config(root)
            self.assertEqual(loaded.active_provider("transcription"), "localai")
            self.assertEqual(loaded.data["future"]["value"], 42)
            self.assertIn("recorder", loaded.data)

    def test_legacy_recording_limit_is_preserved_but_does_not_replace_reminder(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            config = root / "config.toml"
            config.write_text("[recorder]\nmax_seconds = 90\n", encoding="utf-8")
            with patch.dict(os.environ, {"ECHOSCRIBE_CONFIG": str(config)}, clear=False):
                loaded = load_config(root)
            self.assertEqual(loaded.data["recorder"]["reminder_seconds"], 90)
            self.assertEqual(loaded.data["recorder"]["max_seconds"], 90)

    def test_secret_file_write_is_private_and_replaces_value(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "secrets.env"
            write_env_value(path, "OPENAI_API_KEY", "first")
            write_env_value(path, "OPENAI_API_KEY", "second")
            self.assertEqual(path.read_text(encoding="utf-8"), "OPENAI_API_KEY=second\n")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_provider_capabilities_are_enforced_per_stage(self) -> None:
        data = deepcopy(DEFAULTS)
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            config = Config(data, None, root, root / "secrets.env")
            data["providers"]["transcription"] = "unsupported"
            with self.assertRaisesRegex(ValueError, "Unsupported API provider"):
                config.active_provider("transcription")

    def test_legacy_gemini_fast_defaults_migrate_to_3_7_flash(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            config = root / "config.toml"
            config.write_text(
                '[gemini]\ntranscription_model = "gemini-3.6-flash"\n',
                encoding="utf-8",
            )
            with patch.dict(os.environ, {"ECHOSCRIBE_CONFIG": str(config)}, clear=False):
                loaded = load_config(root)
            self.assertEqual(loaded.data["gemini"]["transcription_model"], "gemini-3.7-flash")

    def test_summary_only_provider_is_no_longer_supported(self) -> None:
        with self.assertRaisesRegex(ValueError, "Unsupported API provider"):
            normalize_provider("anthropic")


if __name__ == "__main__":
    unittest.main()
