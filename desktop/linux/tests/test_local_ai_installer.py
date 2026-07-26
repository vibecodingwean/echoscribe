from __future__ import annotations

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


LINUX_ROOT = Path(__file__).resolve().parents[1]
INSTALLER = LINUX_ROOT / "scripts/install-local-ai.sh"


class LocalAiInstallerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        fake_curl = self.bin / "curl"
        fake_curl.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                set -e
                url=""
                for arg in "$@"; do
                  case "$arg" in http*) url="$arg" ;; esac
                done
                case "$url" in
                  */api/recommend)
                    printf '%s' '{"recommendations":[{"modelId":"qwen3.5-9b","quantization":"Q8_0","grade":"B","status":"comfortable"},{"modelId":"gemma4-e2b-it","quantization":"Q8_0","grade":"B","status":"comfortable"},{"modelId":"gemma3-4b","quantization":"F16","grade":"B","status":"comfortable"},{"modelId":"qwen3-4b","quantization":"F16","grade":"B","status":"comfortable"},{"modelId":"qwen3.5-4b","quantization":"Q8_0","grade":"B","status":"comfortable"}]}'
                    ;;
                  */api/models/gemma3-4b)
                    printf '%s' '{"name":"Gemma 3 4B","ollamaId":"gemma3:4b"}'
                    ;;
                  */api/models/qwen3-4b)
                    printf '%s' '{"name":"Qwen 3 4B","ollamaId":"qwen3:4b"}'
                    ;;
                  */api/models/qwen3.5-4b)
                    printf '%s' '{"name":"Qwen 3.5 4B","ollamaId":"qwen3.5:4b"}'
                    ;;
                  *)
                    exit 22
                    ;;
                esac
                """
            ),
            encoding="utf-8",
        )
        fake_curl.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "ECHOSCRIBE_HARDWARE_RAM_GB": "60,5",
            "ECHOSCRIBE_HARDWARE_CPU_NAME": "Test CPU",
            "ECHOSCRIBE_HARDWARE_GPU_NAME": "Test Integrated GPU",
            "ECHOSCRIBE_HARDWARE_VRAM_GB": "45,4",
            "ECHOSCRIBE_HARDWARE_VRAM_SOURCE": "test shared-memory estimate",
            "ECHOSCRIBE_HARDWARE_UNIFIED": "yes",
            "ECHOSCRIBE_CANIRUN_API_BASE": "https://canirun.test",
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_installer(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(INSTALLER), *args],
            cwd=LINUX_ROOT,
            env=self.env,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=20,
            check=False,
        )

    def test_recommendations_normalize_localized_numbers_and_show_six_unique_models(self) -> None:
        result = self.run_installer("--recommend-models")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CanIRun.ai request parameters", result.stdout)
        self.assertIn("RAM:                 60.5 GB", result.stdout)
        self.assertIn("CPU (local only):    Test CPU", result.stdout)
        self.assertIn("VRAM sent to API:    45.4 GB", result.stdout)
        self.assertIn("estimate, not dedicated VRAM", result.stdout)
        self.assertIn("gemma4:e2b-it-qat", result.stdout)
        self.assertIn("qwen3.5:9b", result.stdout)
        self.assertIn("qwen3.6:35b-a3b-mtp-q4_K_M", result.stdout)
        self.assertIn("gemma3:4b", result.stdout)
        self.assertIn("qwen3:4b", result.stdout)
        self.assertIn("qwen3.5:4b", result.stdout)
        self.assertEqual(result.stdout.count("qwen3.5:9b"), 2)
        self.assertIn("Recommended model: qwen3.5:9b", result.stdout)

    def test_no_canirun_keeps_built_in_offline_choices(self) -> None:
        result = self.run_installer("--recommend-models", "--no-canirun")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("CanIRun.ai request parameters", result.stdout)
        self.assertIn("No additional CanIRun.ai choices are available.", result.stdout)
        self.assertIn("Recommended model: qwen3.5:9b", result.stdout)


if __name__ == "__main__":
    unittest.main()
