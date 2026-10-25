from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


LINUX_ROOT = Path(__file__).resolve().parents[1]


class CliContractTests(unittest.TestCase):
    def run_cli(self, *args: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-m", "echoscribe", *args],
            cwd=LINUX_ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_worker_status_and_error_are_stable_json(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            env = {
                **os.environ,
                "PYTHONPATH": str(LINUX_ROOT),
                "XDG_STATE_HOME": str(Path(raw) / "state"),
                "ECHOSCRIBE_CONFIG": str(Path(raw) / "missing.toml"),
            }
            status = self.run_cli("gnome-worker", "status", "--json", env=env)
            self.assertEqual(status.returncode, 0, status.stderr)
            payload = json.loads(status.stdout)
            self.assertEqual(payload["ok"], True)
            self.assertEqual(payload["state"], "idle")
            self.assertIn("recording_id", payload)

            stopped = self.run_cli("gnome-worker", "stop", "--json", env=env)
            self.assertNotEqual(stopped.returncode, 0)
            error = json.loads(stopped.stdout)
            self.assertEqual(error["ok"], False)
            self.assertTrue(error["message"].startswith("[ECHOSCRIBE ERROR]"))

    def test_removed_worker_commands_and_secret_read_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            secret = "must-never-be-printed"
            env = {
                **os.environ,
                "PYTHONPATH": str(LINUX_ROOT),
                "XDG_STATE_HOME": str(Path(raw) / "state"),
                "OPENAI_API_KEY": secret,
            }
            toggle = self.run_cli("gnome-worker", "toggle", "--json", env=env)
            self.assertNotEqual(toggle.returncode, 0)
            no_paste = self.run_cli("gnome-worker", "stop", "--no-paste", env=env)
            self.assertNotEqual(no_paste.returncode, 0)
            key_read = self.run_cli("config-get", "api-key", "openai", env=env)
            self.assertNotEqual(key_read.returncode, 0)
            self.assertNotIn(secret, key_read.stdout + key_read.stderr)

    def test_removed_summary_configuration_commands_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            env = {
                **os.environ,
                "PYTHONPATH": str(LINUX_ROOT),
                "ECHOSCRIBE_CONFIG": str(Path(raw) / "missing.toml"),
            }
            commands = (
                ("config-get", "summary-provider"),
                ("config-get", "summary-model", "openai"),
                ("config-get", "local-ai-llm-url"),
                ("config-set", "summary-provider", "openai"),
                ("config-set", "summary-model", "openai", "unused"),
                ("config-set", "local-ai-llm-url", "http://127.0.0.1:11434/api/chat"),
                ("config-set", "api-key", "anthropic"),
            )
            for command in commands:
                with self.subTest(command=command):
                    result = self.run_cli(*command, env=env)
                    self.assertNotEqual(result.returncode, 0)

    def test_consent_is_explicit_revocable_and_bound_to_local_endpoint(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "config.toml"
            path.write_text("", encoding="utf-8")
            env = {**os.environ, "PYTHONPATH": str(LINUX_ROOT), "ECHOSCRIBE_CONFIG": str(path)}
            self.assertEqual(self.run_cli("config-get", "consent-status", "openai", env=env).stdout.strip(), "blocked")
            self.assertEqual(self.run_cli("config-set", "consent", "openai", "allow", env=env).returncode, 0)
            self.assertEqual(self.run_cli("config-get", "consent-status", "openai", env=env).stdout.strip(), "allowed")
            self.assertEqual(self.run_cli("config-get", "consent-status", "localai", env=env).stdout.strip(), "blocked")
            self.assertEqual(self.run_cli("config-set", "consent", "localai", "allow", env=env).returncode, 0)
            self.assertEqual(self.run_cli("config-get", "consent-status", "localai", env=env).stdout.strip(), "allowed")
            self.assertEqual(self.run_cli("config-set", "local-ai-whisper-url", "https://other.example/stt", env=env).returncode, 0)
            self.assertEqual(self.run_cli("config-get", "consent-status", "localai", env=env).stdout.strip(), "blocked")
            self.assertEqual(self.run_cli("config-set", "consent", "localai", "revoke", env=env).returncode, 0)
            self.assertEqual(self.run_cli("config-get", "consent-status", "localai", env=env).stdout.strip(), "blocked")


if __name__ == "__main__":
    unittest.main()
