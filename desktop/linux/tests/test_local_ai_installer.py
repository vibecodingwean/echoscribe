from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


LINUX_ROOT = Path(__file__).resolve().parents[1]
INSTALLER = LINUX_ROOT / "scripts/install-local-ai.sh"


class LocalAiInstallerTests(unittest.TestCase):
    def run_installer(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(INSTALLER), *args],
            cwd=LINUX_ROOT,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=20,
            check=False,
        )

    def test_help_describes_only_local_whisper(self) -> None:
        result = self.run_installer("--help")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Local Whisper", result.stdout)
        self.assertIn("--whisper-model", result.stdout)
        self.assertNotIn("Ollama", result.stdout)
        self.assertNotIn("recommend-models", result.stdout)

    def test_removed_ollama_option_is_rejected(self) -> None:
        result = self.run_installer("--pull-ollama")

        self.assertEqual(result.returncode, 2)
        self.assertIn("Unknown option", result.stderr)


if __name__ == "__main__":
    unittest.main()