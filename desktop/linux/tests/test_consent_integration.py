"""Exercise the real Linux worker CLI against an isolated local STT server."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ConsentIntegrationTests(unittest.TestCase):
    def test_worker_sends_audio_only_after_explicit_endpoint_approval(self) -> None:
        requests: list[bytes] = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                length = int(self.headers["content-length"])
                requests.append(self.rfile.read(length))
                body = b'{"text":"Integrated transcript"}'
                self.send_response(200)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as raw:
                base = Path(raw)
                recorder = base / "fake_recorder.py"
                recorder.write_text(
                    "import pathlib, signal, sys, time\n"
                    "pathlib.Path(sys.argv[1]).write_bytes(b'RIFF-fake-recorded-audio')\n"
                    "signal.signal(signal.SIGINT, lambda *_: sys.exit(0))\n"
                    "while True: time.sleep(0.1)\n",
                    encoding="utf-8",
                )
                endpoint = f"http://127.0.0.1:{server.server_port}/v1/audio/transcriptions"
                config = base / "config.toml"
                config.write_text(
                    f'[providers]\ntranscription = "localai"\n'
                    f'[localai]\nwhisper_url = "{endpoint}"\n'
                    f'[recorder]\ncommand = "{sys.executable} {recorder} {{path}}"\nminimum_bytes = 8\n',
                    encoding="utf-8",
                )
                env = {
                    **os.environ,
                    "PYTHONPATH": str(ROOT),
                    "ECHOSCRIBE_CONFIG": str(config),
                    "XDG_STATE_HOME": str(base / "state"),
                }

                def command(*args: str) -> subprocess.CompletedProcess[str]:
                    return subprocess.run(
                        [sys.executable, "-m", "echoscribe", *args],
                        cwd=ROOT, env=env, capture_output=True, text=True, timeout=12,
                        check=False,
                    )

                denied = command("gnome-worker", "start", "--json")
                self.assertNotEqual(denied.returncode, 0)
                self.assertIn("Audio transfer", json.loads(denied.stdout)["message"])
                self.assertEqual(requests, [])
                self.assertEqual(command("config-set", "consent", "localai", "allow").returncode, 0)
                started = command("gnome-worker", "start", "--json")
                self.assertEqual(started.returncode, 0, started.stderr)
                state = json.loads(started.stdout)
                audio = Path(state["audio_file"])
                deadline = time.monotonic() + 5
                while (not audio.exists() or audio.stat().st_size < 8) and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(audio.exists() and audio.stat().st_size >= 8)
                stopped = command("gnome-worker", "stop", "--recording-id", state["recording_id"], "--json")
                self.assertEqual(stopped.returncode, 0, stopped.stderr)
                self.assertEqual(json.loads(stopped.stdout)["transcript"], "Integrated transcript")
                self.assertEqual(len(requests), 1)
                self.assertIn(b"RIFF-fake-recorded-audio", requests[0])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
