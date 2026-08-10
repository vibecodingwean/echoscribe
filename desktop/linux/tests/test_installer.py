from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


LINUX_ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        self.home.mkdir()
        self.bin.mkdir()
        self._write_command(
            "gnome-extensions",
            '#!/bin/sh\nif [ "$1" = info ]; then echo "  State: ACTIVE"; fi\nexit 0\n',
        )
        self._write_command("gsettings", "#!/bin/sh\nexit 0\n")
        self._write_command("systemctl", "#!/bin/sh\nexit 0\n")
        self._write_command(
            "glib-compile-schemas",
            "#!/bin/sh\nfor last; do :; done\nprintf compiled >\"$last/gschemas.compiled\"\n",
        )
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "ECHOSCRIBE_INSTALL_DIR": str(self.root / "app"),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _write_command(self, name: str, text: str) -> None:
        path = self.bin / name
        path.write_text(text, encoding="utf-8")
        path.chmod(0o755)

    def install(self, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(LINUX_ROOT / "install.sh"), "--skip-deps", *extra],
            cwd=LINUX_ROOT,
            env=self.env,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )

    def test_first_install_and_update_preserve_config_and_secrets(self) -> None:
        first = self.install()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn("installed successfully", first.stdout)
        config = self.home / ".config/echoscribe/config.toml"
        secrets = self.home / ".config/echoscribe/secrets.env"
        config.write_text('[providers]\ntranscription = "localai"\n', encoding="utf-8")
        secrets.write_text("OPENAI_API_KEY=preserve-me\n", encoding="utf-8")

        second = self.install()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn('transcription = "localai"', config.read_text(encoding="utf-8"))
        self.assertEqual(secrets.read_text(encoding="utf-8"), "OPENAI_API_KEY=preserve-me\n")
        self.assertTrue((self.root / "app/linux/echoscribe/gnome_worker.py").is_file())
        self.assertTrue(
            (self.home / ".local/share/gnome-shell/extensions/echoscribe@wean.de/schemas/gschemas.compiled").is_file()
        )

    def test_install_removes_legacy_browser_native_host_manifests(self) -> None:
        relative_paths = (
            ".config/google-chrome/NativeMessagingHosts/de.echoscribe.nativehost.json",
            ".config/chromium/NativeMessagingHosts/de.echoscribe.nativehost.json",
            ".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/de.echoscribe.nativehost.json",
            ".config/microsoft-edge/NativeMessagingHosts/de.echoscribe.nativehost.json",
            ".mozilla/native-messaging-hosts/de.echoscribe.nativehost.json",
            ".librewolf/native-messaging-hosts/de.echoscribe.nativehost.json",
        )
        legacy_paths = [self.home / relative for relative in relative_paths]
        for path in legacy_paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("legacy host manifest\n", encoding="utf-8")

        result = self.install()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(not path.exists() for path in legacy_paths))

    def test_reconfigure_backs_up_config_before_noninteractive_run(self) -> None:
        self.assertEqual(self.install().returncode, 0)
        config = self.home / ".config/echoscribe/config.toml"
        config.write_text("# custom\n", encoding="utf-8")
        result = self.install("--reconfigure")
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list(config.parent.glob("config.toml.bak.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(encoding="utf-8"), "# custom\n")

    def test_validation_failure_keeps_previous_application_tree(self) -> None:
        existing = self.root / "app"
        existing.mkdir()
        marker = existing / "keep-me"
        marker.write_text("old", encoding="utf-8")
        self._write_command("glib-compile-schemas", "#!/bin/sh\nexit 1\n")
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(encoding="utf-8"), "old")


    def test_active_extension_code_update_requires_new_shell_session(self) -> None:
        self.assertEqual(self.install().returncode, 0)
        command_log = self.root / "gnome-extensions.log"
        self.env["GNOME_EXTENSIONS_TEST_LOG"] = str(command_log)
        self._write_command(
            "gnome-extensions",
            '#!/bin/sh\nprintf "%s\\n" "$*" >>"$GNOME_EXTENSIONS_TEST_LOG"\n'
            'if [ "$1" = info ]; then echo "  State: ACTIVE"; fi\nexit 0\n',
        )
        installed_extension = self.home / ".local/share/gnome-shell/extensions/echoscribe@wean.de/extension.js"
        installed_extension.write_text("// stale cached extension\n", encoding="utf-8")
        updated = self.install()
        self.assertEqual(updated.returncode, 3)
        self.assertIn("previous EchoScribe JavaScript module cached", updated.stderr)
        self.assertNotIn("installed successfully", updated.stdout)
        commands = command_log.read_text(encoding="utf-8")
        self.assertNotIn("disable echoscribe@wean.de", commands)
        self.assertNotIn("enable echoscribe@wean.de", commands)
        resumed = self.install()
        self.assertEqual(resumed.returncode, 0, resumed.stderr)

    def test_extension_not_recognized_prevents_success_report(self) -> None:
        self._write_command("gnome-extensions", "#!/bin/sh\nexit 1\n")
        result = self.install()
        self.assertEqual(result.returncode, 3)
        self.assertIn("Log out and back in", result.stderr)
        self.assertNotIn("installed successfully", result.stdout)
        state = self.home / ".local/state/echoscribe/install-state"
        self.assertEqual(state.read_text(encoding="utf-8"), "integrating\n")

        self._write_command(
            "gnome-extensions",
            '#!/bin/sh\nif [ "$1" = info ]; then echo "  State: ACTIVE"; fi\nexit 0\n',
        )
        resumed = self.install()
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertFalse(state.exists())

    def test_legacy_interrupted_default_config_is_detected(self) -> None:
        self.assertEqual(self.install().returncode, 0)
        self._write_command("gnome-extensions", "#!/bin/sh\nexit 1\n")
        extension = self.home / ".local/share/gnome-shell/extensions/echoscribe@wean.de/extension.js"
        self.assertTrue(extension.exists())
        result = self.install()
        self.assertEqual(result.returncode, 3)
        self.assertIn("Non-interactive install: kept configuration", result.stdout)

    def test_core_uninstall_retains_config_secrets_and_local_models(self) -> None:
        self.assertEqual(self.install().returncode, 0)
        config = self.home / ".config/echoscribe/config.toml"
        secrets = self.home / ".config/echoscribe/secrets.env"
        secrets.parent.mkdir(parents=True, exist_ok=True)
        secrets.write_text("OPENAI_API_KEY=keep\n", encoding="utf-8")
        local_model = self.home / ".local/share/echoscribe/local-ai/model.bin"
        local_model.parent.mkdir(parents=True, exist_ok=True)
        local_model.write_bytes(b"keep")
        uninstaller = self.root / "app/linux/uninstall.sh"
        result = subprocess.run(
            ["bash", str(uninstaller), "--all", "--non-interactive"],
            env=self.env,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "app").exists())
        self.assertTrue(config.exists())
        self.assertEqual(secrets.read_text(encoding="utf-8"), "OPENAI_API_KEY=keep\n")
        self.assertEqual(local_model.read_bytes(), b"keep")

    def test_incomplete_release_tree_is_rejected_before_changes(self) -> None:
        package = self.root / "incomplete"
        linux = package / "linux"
        linux.mkdir(parents=True)
        shutil.copy2(LINUX_ROOT / "install.sh", linux / "install.sh")
        result = subprocess.run(
            ["bash", str(linux / "install.sh"), "--dry-run"],
            env=self.env,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Incomplete EchoScribe package", result.stderr)


if __name__ == "__main__":
    unittest.main()
