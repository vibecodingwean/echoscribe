"""Audio recording through common Linux command-line tools."""

from __future__ import annotations

import logging
import os
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path


LOG = logging.getLogger(__name__)


class AudioRecorder:
    def __init__(self, command_template: str = "", minimum_bytes: int = 2048) -> None:
        self.command_template = command_template.strip()
        self.minimum_bytes = minimum_bytes
        self.process: subprocess.Popen[bytes] | None = None
        self.path: Path | None = None

    def start(self) -> Path:
        if self.process is not None:
            raise RuntimeError("Recorder is already running")
        fd, raw_path = tempfile.mkstemp(prefix="echoscribe_", suffix=".wav")
        os.close(fd)
        self.path = Path(raw_path)
        command = self._build_command(self.path)
        LOG.info("Starting recorder: %s", " ".join(shlex.quote(part) for part in command))

        preexec = None
        if sys.platform.startswith("linux"):
            def set_pdeathsig():
                import ctypes
                try:
                    # PR_SET_PDEATHSIG is 1, SIGTERM is 15
                    ctypes.CDLL(None).prctl(1, 15)
                except Exception:
                    pass
            preexec = set_pdeathsig

        self.process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            start_new_session=True,
            preexec_fn=preexec,
        )
        return self.path

    def stop(self) -> Path:
        if self.process is None or self.path is None:
            raise RuntimeError("Recorder is not running")
        process = self.process
        path = self.path
        self.process = None
        self.path = None

        if process.poll() is None:
            if process.stdin:
                try:
                    process.stdin.write(b"q\n")
                    process.stdin.flush()
                except OSError:
                    pass
            try:
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGINT)
                except OSError:
                    process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()

        if not path.exists() or path.stat().st_size < self.minimum_bytes:
            stderr = b""
            if process.stderr:
                stderr = process.stderr.read()[-500:]
            raise RuntimeError(f"Recording failed or was too short. {stderr.decode(errors='ignore')}")
        LOG.info("Recorded %s bytes to %s", path.stat().st_size, path)
        return path

    def abort(self) -> None:
        if self.process is None:
            return
        try:
            os.killpg(self.process.pid, signal.SIGINT)
        except OSError:
            self.process.terminate()
        self.process = None

    def _build_command(self, path: Path) -> list[str]:
        return build_record_command(self.command_template, path)


def build_record_command(command_template: str, path: Path) -> list[str]:
    if command_template:
        return shlex.split(command_template.format(path=str(path)))
    if shutil.which("ffmpeg"):
        command = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "pulse",
            "-i",
            "default",
            "-ac",
            "1",
            "-ar",
            "16000",
        ]
        command.append(str(path))
        return command
    if shutil.which("arecord"):
        command = [
            "arecord",
            "-q",
            "-f",
            "S16_LE",
            "-r",
            "16000",
            "-c",
            "1",
            "-t",
            "wav",
        ]
        command.append(str(path))
        return command
    raise RuntimeError("Neither ffmpeg nor arecord is installed")
