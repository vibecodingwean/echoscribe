from __future__ import annotations

import json
import os
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest.mock import Mock, patch

from echoscribe.config import Config, DEFAULTS
from echoscribe import gnome_worker as worker


class GnomeWorkerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"XDG_STATE_HOME": str(self.root / "state")}, clear=False)
        self.env.start()
        data = deepcopy(DEFAULTS)
        data["recorder"]["command"] = "fake-recorder {path}"
        data["recorder"]["minimum_bytes"] = 8
        self.config = Config(data, None, self.root, self.root / "secrets.env")

    def tearDown(self) -> None:
        self.env.stop()
        self.temp.cleanup()

    def start(self) -> dict[str, object]:
        fake = Mock(pid=4321)
        with patch.object(worker.subprocess, "Popen", return_value=fake):
            return worker.start_recording(self.config)

    def add_audio(self, payload: dict[str, object], content: bytes = b"RIFF-valid-audio") -> None:
        Path(str(payload["audio_file"])).write_bytes(content)

    def test_state_file_is_atomic_and_has_only_contract_fields(self) -> None:
        payload = self.start()
        saved = json.loads(worker.state_file().read_text(encoding="utf-8"))
        self.assertEqual(set(saved), set(worker.STATE_KEYS))
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["state"], "recording")
        self.assertTrue(payload["recording_id"])
        self.assertEqual(payload["reminder_seconds"], 90)
        self.assertNotIn("limit_seconds", payload)

    def test_start_does_not_import_provider_module(self) -> None:
        import sys

        previous = sys.modules.pop("echoscribe.providers", None)
        try:
            self.start()
            self.assertNotIn("echoscribe.providers", sys.modules)
        finally:
            if previous is not None:
                sys.modules["echoscribe.providers"] = previous

    def test_start_command_has_no_local_duration_limit(self) -> None:
        fake = Mock(pid=4321)
        with (
            patch.object(worker, "build_record_command", return_value=["fake-recorder"]) as build,
            patch.object(worker.subprocess, "Popen", return_value=fake),
        ):
            started = worker.start_recording(self.config)
        self.assertTrue(started["ok"])
        build.assert_called_once()
        self.assertEqual(len(build.call_args.args), 2)
        self.assertEqual(build.call_args.kwargs, {})

    def test_double_start_is_rejected_without_replacing_id(self) -> None:
        first = self.start()
        with patch.object(worker, "process_is_alive", return_value=True):
            second = worker.start_recording(self.config)
        self.assertFalse(second["ok"])
        self.assertEqual(second["recording_id"], first["recording_id"])

    def test_recording_continues_past_reminder_and_transcribes_on_toggle(self) -> None:
        started = self.start()
        self.add_audio(started)
        state = worker.read_state()
        state["started_at"] -= int(state["reminder_seconds"]) + 30
        worker.write_state(state)
        with (
            patch.object(worker, "process_is_alive", return_value=True),
            patch.object(worker, "stop_process_group"),
            patch.object(worker, "transcribe", return_value="hello world"),
        ):
            stopped = worker.stop_recording(self.config, str(started["recording_id"]))
        self.assertTrue(stopped["ok"])
        self.assertEqual(stopped["transcript"], "hello world")
        self.assertEqual(stopped["recording_id"], started["recording_id"])
        self.assertEqual(stopped["paste_shortcut"], "auto")
        self.assertEqual(stopped["paste_delay_ms"], 120)
        self.assertFalse(Path(str(started["audio_file"])).exists())

    def test_stale_stop_and_cancel_do_not_change_active_recording(self) -> None:
        started = self.start()
        stale_stop = worker.stop_recording(self.config, "old-id")
        stale_cancel = worker.cancel("old-id")
        self.assertFalse(stale_stop["ok"])
        self.assertFalse(stale_cancel["ok"])
        self.assertEqual(worker.read_state()["recording_id"], started["recording_id"])

    def test_cancel_during_processing_wins_over_late_transcript(self) -> None:
        started = self.start()
        self.add_audio(started)

        def cancel_then_return(*_args: object) -> str:
            canceled = worker.cancel(str(started["recording_id"]))
            self.assertTrue(canceled["ok"])
            return "must not be delivered"

        with (
            patch.object(worker, "process_is_alive", return_value=True),
            patch.object(worker, "stop_process_group"),
            patch.object(worker, "transcribe", side_effect=cancel_then_return),
        ):
            stopped = worker.stop_recording(self.config, str(started["recording_id"]))
        self.assertFalse(stopped["ok"])
        self.assertIn("canceled", stopped["message"].lower())
        self.assertEqual(worker.read_state()["state"], "idle")

    def test_too_short_recording_and_recorder_crash_are_errors(self) -> None:
        started = self.start()
        self.add_audio(started, b"bad")
        with (
            patch.object(worker, "process_is_alive", return_value=True),
            patch.object(worker, "stop_process_group"),
        ):
            stopped = worker.stop_recording(self.config, str(started["recording_id"]))
        self.assertFalse(stopped["ok"])
        self.assertEqual(stopped["state"], "error")
        self.assertNotEqual(stopped["message"].find("[ECHOSCRIBE ERROR]"), -1)

    def test_early_recorder_crash_rejects_even_large_partial_audio(self) -> None:
        started = self.start()
        self.add_audio(started, b"RIFF-partial-but-large")
        with patch.object(worker, "process_is_alive", return_value=False):
            stopped = worker.stop_recording(self.config, str(started["recording_id"]))
        self.assertFalse(stopped["ok"])
        self.assertIn("exited unexpectedly", stopped["message"])

    def test_status_marks_any_natural_recorder_exit_as_error(self) -> None:
        started = self.start()
        self.add_audio(started)
        state = worker.read_state()
        state["started_at"] -= int(state["reminder_seconds"]) + 30
        worker.write_state(state)
        with patch.object(worker, "process_is_alive", return_value=False):
            result = worker.status()
        self.assertFalse(result["ok"])
        self.assertEqual(result["state"], "error")
        self.assertFalse(Path(str(started["audio_file"])).exists())

    def test_repeated_cancel_is_idempotent(self) -> None:
        started = self.start()
        with (
            patch.object(worker, "process_is_alive", return_value=False),
            patch.object(worker, "stop_process_group"),
        ):
            first = worker.cancel(str(started["recording_id"]))
            second = worker.cancel(str(started["recording_id"]))
        self.assertTrue(first["ok"])
        self.assertTrue(second["ok"])
        self.assertEqual(second["state"], "idle")

    def test_cancel_clears_persisted_error_state(self) -> None:
        worker.write_state(worker.make_state("error", recording_id="failed-id"))
        cleared = worker.cancel("failed-id")
        self.assertTrue(cleared["ok"])
        self.assertEqual(cleared["state"], "idle")
        self.assertEqual(worker.read_state()["state"], "idle")


if __name__ == "__main__":
    unittest.main()
