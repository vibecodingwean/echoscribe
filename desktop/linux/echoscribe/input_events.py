"""Global hold-hotkey listener using Linux input events."""

from __future__ import annotations

import glob
import logging
import os
import selectors
import struct
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass

from .keycodes import Hotkey


LOG = logging.getLogger(__name__)
EV_KEY = 0x01
EVENT_STRUCT = struct.Struct("llHHi")


@dataclass(frozen=True)
class Binding:
    name: str
    hotkeys: list[Hotkey]
    on_start: Callable[[], None]
    on_stop: Callable[[], None]


class InputHotkeyListener:
    def __init__(self, bindings: list[Binding], device_glob: str = "/dev/input/event*") -> None:
        self.bindings = bindings
        self.device_glob = device_glob
        self.selector = selectors.DefaultSelector()
        self.pressed: set[int] = set()
        self.active: Binding | None = None
        self.active_codes: frozenset[int] | None = None
        self.blocked_until_release: frozenset[int] | None = None
        self._last_rescan = 0.0
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        self._open_devices()
        self._thread = threading.Thread(target=self._run, name="echoscribe-input", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)
        for key in list(self.selector.get_map().values()):
            try:
                os.close(key.fd)
            except OSError:
                pass

    def _open_devices(self) -> None:
        opened = 0
        for path in sorted(glob.glob(self.device_glob)):
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                self.selector.register(fd, selectors.EVENT_READ, data=path)
                opened += 1
            except PermissionError:
                LOG.debug("No permission for %s", path)
            except OSError as exc:
                LOG.debug("Could not open %s: %s", path, exc)
        if opened == 0:
            raise RuntimeError(
                "No readable /dev/input/event* devices. Add the user to the input group "
                "or run the system setup script, then log in again."
            )
        LOG.info("Watching %s input devices", opened)

    def _run(self) -> None:
        while not self._stop.is_set():
            for key, _ in self.selector.select(timeout=0.2):
                self._read_fd(key.fd, str(key.data))
            self._maybe_rescan()

    def _maybe_rescan(self) -> None:
        # Keep this lightweight; it lets hot-plugged keyboards appear eventually.
        now = time.monotonic()
        if now - self._last_rescan < 7:
            return
        self._last_rescan = now
        registered = {str(key.data) for key in self.selector.get_map().values()}
        for path in sorted(glob.glob(self.device_glob)):
            if path in registered:
                continue
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                self.selector.register(fd, selectors.EVENT_READ, data=path)
                LOG.info("Watching input device %s", path)
            except OSError:
                pass

    def _read_fd(self, fd: int, path: str) -> None:
        try:
            data = os.read(fd, EVENT_STRUCT.size * 64)
        except BlockingIOError:
            return
        except OSError as exc:
            LOG.warning("Lost input device %s: %s", path, exc)
            try:
                self.selector.unregister(fd)
            except Exception:
                pass
            try:
                os.close(fd)
            except OSError:
                pass
            return

        for offset in range(0, len(data) - EVENT_STRUCT.size + 1, EVENT_STRUCT.size):
            _, _, ev_type, code, value = EVENT_STRUCT.unpack_from(data, offset)
            if ev_type == EV_KEY:
                self._handle_key(code, value)

    def _handle_key(self, code: int, value: int) -> None:
        if value == 1:
            self.pressed.add(code)
            self._check_start()
        elif value == 0:
            self.pressed.discard(code)
            if self.blocked_until_release and not self.blocked_until_release.issubset(self.pressed):
                self.blocked_until_release = None
            self._check_stop()
        elif value == 2:
            self._check_start()

    def _check_start(self) -> None:
        if self.active is not None:
            return
        if self.blocked_until_release and self.blocked_until_release.issubset(self.pressed):
            return
        for binding in self.bindings:
            for hotkey in binding.hotkeys:
                if hotkey.codes.issubset(self.pressed):
                    self.active = binding
                    self.active_codes = hotkey.codes
                    LOG.info("Hotkey active: %s (%s)", binding.name, hotkey.label)
                    binding.on_start()
                    return

    def _check_stop(self) -> None:
        if self.active is None or self.active_codes is None:
            return
        if not self.active_codes.issubset(self.pressed):
            binding = self.active
            released_codes = self.active_codes
            self.active = None
            self.active_codes = None
            self.blocked_until_release = released_codes
            LOG.info("Hotkey released: %s", binding.name)
            binding.on_stop()

