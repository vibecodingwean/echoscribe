# EchoScribe Linux

Linux desktop companion for EchoScribe push-to-talk transcription and local browser summaries.

Core behavior:

- Hold the configured hotkey to record.
- Release the hotkey to transcribe.
- The transcript is copied to the clipboard and pasted into the focused window.
- Errors use the `[ECHOSCRIBE ERROR]` prefix.
- The browser extensions can summarize the current page, selected text, or PDF content through the local Native Messaging host.

## Setup

From a GitHub release, extract `EchoScribe-Linux-GNOME-<version>.tar.gz`, then run:

```bash
cd EchoScribe-Linux-GNOME-<version>/linux
./install.sh
```

The wizard installs Linux dependencies, creates `.venv`, writes the per-user
EchoScribe config, stores provider keys in the configured per-user secret env
file, installs the GNOME Shell extension, and can register browser native hosts
for Chromium-based browsers and Firefox.

On GNOME, EchoScribe starts through the installed GNOME Shell extension when you log into the desktop. The helper service installed by `install_user_service.sh` is only for `ydotool`; it is not an EchoScribe background app service.

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

1. Chrome, Edge, Brave, or Chromium: open the browser extensions page, enable developer mode, and load the package's `browser-extension` folder as an unpacked extension.
2. Firefox: open `about:debugging#/runtime/this-firefox` and load the package's `firefox-extension/manifest.json` as a temporary add-on.

## Configuration

Config lives in the per-user EchoScribe config file. Secrets can be exported in
the shell or stored in the configured secret env file:

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
- `gemini`: default model `gemini-3.5-flash`
- `xai`: default model `xai-stt`
- `localai`: Local AI Whisper-compatible endpoint, default URL `http://127.0.0.1:8000/v1/audio/transcriptions`, default model `whisper-1`

Summary providers:

- `openai`: default model `gpt-5.4-mini`
- `gemini`: default model `gemini-3.5-flash`
- `anthropic`: default model `claude-sonnet-4-6`
- `xai`: default model `grok-4.3`
- `localai`: Ollama-compatible `/api/chat`, default URL `http://127.0.0.1:11434/api/chat`, default model `qwen2.5:7b`

Local AI sends Ollama chat requests with `model`, `stream: false`, `think: false`, and `messages`, then reads `message.content`. Local Whisper STT sends multipart `file`, `model`, `response_format=json`, and optional `language`, then reads `text`. Example Ollama models: `qwen2.5:7b`, `gemma4:e4b`, `gemma3`, `deepseek-r1`. For PoC use, keep endpoints on a trusted local network or VPN; EchoScribe does not add authentication to Local AI requests.

## Verification

```bash
.venv/bin/python -m echoscribe doctor
.venv/bin/python -m echoscribe gnome-worker status --json
```

For an isolated GNOME extension install check:

```bash
./scripts/install_gnome_extension.sh \
  --target-dir /tmp/echoscribe-extension-test \
  --skip-enable \
  --skip-settings
```
