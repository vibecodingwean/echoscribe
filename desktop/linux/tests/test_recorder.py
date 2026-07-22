from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import patch

from echoscribe.recorder import build_record_command


class RecorderCommandTests(unittest.TestCase):
    def test_custom_command_receives_audio_path(self) -> None:
        command = build_record_command('capture --out "{path}"', Path('/tmp/a file.wav'))
        self.assertEqual(command, ["capture", "--out", "/tmp/a file.wav"])

    def test_ffmpeg_command_has_no_local_duration_limit(self) -> None:
        with patch("echoscribe.recorder.shutil.which", side_effect=lambda name: "/usr/bin/ffmpeg" if name == "ffmpeg" else None):
            command = build_record_command("", Path("/tmp/audio.wav"))
        self.assertNotIn("-t", command)

    def test_arecord_command_has_no_local_duration_limit(self) -> None:
        with patch("echoscribe.recorder.shutil.which", side_effect=lambda name: "/usr/bin/arecord" if name == "arecord" else None):
            command = build_record_command("", Path("/tmp/audio.wav"))
        self.assertNotIn("-d", command)

    def test_missing_recorders_is_reported(self) -> None:
        with patch("echoscribe.recorder.shutil.which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "Neither ffmpeg nor arecord"):
                build_record_command("", Path("/tmp/audio.wav"))


if __name__ == "__main__":
    unittest.main()
