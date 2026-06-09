# EchoScribe Linux

Linux desktop companion for EchoScribe push-to-talk transcription and local browser summaries.

Core behavior:

- Hold the configured hotkey to record.
- Release the hotkey to transcribe.
- The transcript is copied to the clipboard and pasted into the focused window.
- Errors use the `[ECHOSCRIBE ERROR]` prefix.
- The browser extensions can summarize the current page, selected text, or PDF content through the local Native Messaging host.

## Setup

```bash
./install.sh
```

The wizard installs Linux dependencies, creates `.venv`, writes `~/.config/echoscribe/config.toml`, stores provider keys in `~/.secrets/echoscribe.env`, installs the GNOME Shell extension, and can register browser native hosts for Chromium-based browsers and Firefox.

Manual setup:

```bash
./scripts/setup_dev.sh
./scripts/install_gnome_extension.sh
./scripts/register_chrome_host.sh
```

If GNOME does not load the extension immediately, log out and back in, then run:

```bash
gnome-extensions enable echoscribe@wean.de
gnome-extensions prefs echoscribe@wean.de
```

Then load the browser extension manually:

1. Chrome, Edge, Brave, or Chromium: open the browser extensions page, enable developer mode, and load `../browser-extension` as an unpacked extension.
2. Firefox: open `about:debugging#/runtime/this-firefox` and load `../firefox-extension/manifest.json` as a temporary add-on.

## Configuration

Config lives in `~/.config/echoscribe/config.toml`. Secrets can be exported in the shell or stored in `~/.secrets/echoscribe.env`:

```bash
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
ANTHROPIC_API_KEY=...
XAI_API_KEY=xai-...
ELEVENLABS_API_KEY=...
```

Speech-to-text providers:

- `openai`: default model `gpt-4o-mini-transcribe`
- `elevenlabs`: default model `scribe_v2`
- `gemini`: default model `gemini-3.1-flash-lite`
- `xai`: default model `xai-stt`

Summary providers:

- `openai`: default model `gpt-5.4-mini`
- `gemini`: default model `gemini-3.1-flash-lite`
- `anthropic`: default model `claude-sonnet-4-6`
- `xai`: default model `grok-4.3`

## Verification

```bash
.venv/bin/python -m unittest discover -s tests
.venv/bin/python -m echoscribe doctor
.venv/bin/python -m echoscribe native-host --self-test-config
.venv/bin/python -m echoscribe gnome-worker status --json
./scripts/verify_gnome_extension.sh --skip-live-shell
```

For an isolated GNOME extension install check:

```bash
./scripts/install_gnome_extension.sh \
  --target-dir /tmp/echoscribe-extension-test \
  --skip-enable \
  --skip-settings
```
