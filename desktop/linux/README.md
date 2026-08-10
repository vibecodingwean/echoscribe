# EchoScribe Linux / GNOME

EchoScribe provides toggle-to-record dictation on GNOME 45–50 under Wayland
and Xorg. Press the configured shortcut once to start recording and press it
again to stop and transcribe. Ubuntu 26.04 with GNOME 50 is the primary target.

The runtime has two deliberately separate parts:

- GNOME Shell owns the global start/stop shortcut, state machine, status UI,
  clipboard, terminal detection, and virtual-keyboard paste.
- Short-lived Python workers own audio recording and transcription providers.

There is no background Python process while EchoScribe is idle. EchoScribe does
not read `/dev/input`, use `/dev/uinput`, or require `ydotool`, `wtype`,
`xdotool`, X11 clipboard helpers, a GTK overlay, or a user service.

## Install and update

From a Git checkout or extracted release archive:

```bash
cd desktop/linux                 # Git checkout
# cd linux                       # extracted Linux release
./install.sh
```

The installer validates a complete staged application before replacing
`${XDG_DATA_HOME:-~/.local/share}/echoscribe/app`. It uses Ubuntu's system
Python for the core. Existing config, secrets, and GSettings values are not
replaced on update.

As a one-time migration from the former desktop-linked browser extension,
install and uninstall remove only EchoScribe's obsolete
`de.echoscribe.nativehost.json` manifests. Browser profiles, installed store
extensions, desktop configuration, and provider keys are not modified.

Supported options:

```bash
./install.sh --dry-run
./install.sh --reconfigure       # backs up config, then runs setup again
./install.sh --skip-deps
```

The extension installer compiles its GSettings schema and verifies the state
reported by GNOME. If the current Shell process cannot discover a newly copied
extension, installation stops with the exact logout/login command instead of
reporting success.

Local Whisper remains an optional, separate step:

```bash
./scripts/install-local-ai.sh --help
```

The standalone EchoScribe Web Summary extension is maintained independently in
the repository's `browser-extension/` directory. It communicates directly with
the user's selected provider and does not use this desktop installation or a
Native Messaging host.

Local Whisper keeps its own isolated venv under
`${XDG_DATA_HOME:-~/.local/share}/echoscribe/local-ai`; this venv is not used by
the core application. Run `./scripts/install-local-ai.sh --whisper` to install
or update the Faster-Whisper server and selected speech-to-text model.

## Configuration

Configuration lives at `~/.config/echoscribe/config.toml`; provider secrets
default to `~/.config/echoscribe/secrets.env` with mode `0600`. Unknown TOML
fields are tolerated for forward and update compatibility.

The GNOME Extension Preferences contain:

- enabled state;
- the standard GNOME accelerator used to start and stop dictation;
- shell-status or notification feedback;
- application installation path;
- Python path.

Provider/model/endpoint configuration is backed by the normal EchoScribe
config. Preferences show API keys only as set or
missing; stored keys are never printed back into the UI.

The shell-status feedback remains visible for the full recording. After 90
seconds EchoScribe shows a reminder notification but continues recording. There
is no local duration cutoff; the selected transcription provider's upload and
API limits apply. Set `recorder.reminder_seconds = 0` to disable the reminder.
An existing legacy `recorder.max_seconds` value is retained in the config for
update compatibility but is no longer used as a recording cutoff.

The remaining paste options are `paste.shortcut` (`auto`, `ctrl+v`, or
`ctrl+shift+v`) and `paste_delay_ms`. `auto` selects `Ctrl+Shift+V` for terminal
applications and `Ctrl+V` elsewhere.

## Public commands

```bash
python3 -m echoscribe doctor
python3 -m echoscribe config-get transcription-provider
python3 -m echoscribe config-set transcription-provider openai
python3 -m echoscribe config-tui
python3 -m echoscribe gnome-worker status --json
python3 -m echoscribe gnome-worker start --json
python3 -m echoscribe gnome-worker stop --recording-id ID --json
python3 -m echoscribe gnome-worker cancel --recording-id ID --json
```

Worker JSON always includes `ok`, `state`, `message`, `recording_id`, recorder
metadata, and `reminder_seconds`. The reminder value is not a duration limit.
Successful transcription additionally returns `transcript`, `paste_shortcut`,
and `paste_delay_ms`. Errors have the `[ECHOSCRIBE ERROR]` prefix and a non-zero
exit code.

## Verification

```bash
PYTHONPATH=. python3 -m unittest discover -s tests -v
node --test tests/test_gnome_logic.mjs
python3 -m compileall -q echoscribe
glib-compile-schemas --strict gnome-extension/echoscribe@wean.de/schemas
python3 -m echoscribe doctor
```

An isolated extension copy check that does not touch the running Shell:

```bash
./scripts/install_gnome_extension.sh \
  --target-dir /tmp/echoscribe-extension-test \
  --skip-enable \
  --skip-settings
```

## Uninstall

```bash
./uninstall.sh
```

Core uninstall removes the GNOME extension, installed application, and
EchoScribe-owned runtime state. Config, secrets, Local Whisper
models/venv are retained unless their explicit removal options are selected.
Existing packages, group memberships, and shared `ydotool` configuration are
not removed.
