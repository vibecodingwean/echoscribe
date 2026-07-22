from __future__ import annotations

import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


EXTENSION = Path(__file__).resolve().parents[1] / "gnome-extension/echoscribe@wean.de/extension.js"
SCHEMA = EXTENSION.parent / "schemas/org.gnome.shell.extensions.echoscribe.gschema.xml"


class ExtensionStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = EXTENSION.read_text(encoding="utf-8")

    def test_native_keybinding_and_dynamic_rebind_are_present(self) -> None:
        self.assertIn("Main.wm.addKeybinding", self.source)
        self.assertNotIn("display.add_keybinding", self.source)
        self.assertIn("changed::toggle-shortcut", self.source)
        self.assertIn("this._rebindShortcut()", self.source)
        self.assertIn("Main.wm.removeKeybinding", self.source)
        self.assertIn("const KEYBINDING_SETTING = 'echoscribe-toggle-shortcut'", self.source)
        self.assertIn("this._syncKeybindingSetting()", self.source)

    def test_shortcut_is_an_explicit_start_stop_toggle(self) -> None:
        self.assertNotIn("Meta.KeyBindingFlags.TRIGGER_RELEASE", self.source)
        self.assertIn("Meta.KeyBindingFlags.IGNORE_AUTOREPEAT", self.source)
        self.assertIn("_onShortcutTriggered()", self.source)
        self.assertIn("this._stopRequested = true", self.source)
        self.assertNotIn("captured-event", self.source)
        self.assertNotIn("releaseRequested", self.source)

    def test_recording_reminder_does_not_stop_and_shell_status_is_persistent(self) -> None:
        self.assertIn("_scheduleRecordingReminder", self.source)
        self.assertIn("Main.notify('EchoScribe', `Still recording", self.source)
        reminder = self.source[self.source.index("_scheduleRecordingReminder(seconds)"):]
        reminder = reminder[:reminder.index("_clearRecordingReminder() {")]
        self.assertNotIn("_requestStop()", reminder)
        self.assertIn("state !== PHASE.IDLE", self.source)

    def test_shell_owns_clipboard_and_virtual_keyboard_paste(self) -> None:
        self.assertIn("St.Clipboard.get_default().set_text", self.source)
        self.assertIn("create_virtual_device", self.source)
        self.assertIn("notify_keyval", self.source)

    def test_idle_polling_and_focus_hint_files_are_absent(self) -> None:
        self.assertNotIn("650", self.source)
        self.assertNotIn("focus-app-hint", self.source)
        self.assertNotIn("notify::focus-window", self.source)

    def test_gsettings_schema_contains_only_runtime_settings(self) -> None:
        root = ET.parse(SCHEMA).getroot()
        keys = {node.attrib["name"] for node in root.findall(".//key")}
        self.assertEqual(
            keys,
            {
                "enabled",
                "toggle-shortcut",
                "echoscribe-toggle-shortcut",
                "echoscribe-ptt-shortcut",
                "feedback-mode",
                "install-path",
                "python-path",
            },
        )


if __name__ == "__main__":
    unittest.main()
