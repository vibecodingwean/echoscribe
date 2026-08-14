# 🎙️ EchoScribe: Your API Key & Data

**Summarize voice, messages, and URLs. Your API Key — Your Data!**

EchoScribe is a privacy-first, zero-backend Flutter application designed for users who want full control over their AI experience. By using your own API keys (BYOK), you ensure that your data stays between you and the AI provider. No subscriptions, no tracking, no middleman.

---

## 🔒 Privacy & Security (BYOK)
- **No EchoScribe Backend:** Processing happens directly between your device and the selected AI provider. Provider-side processing and retention follow that provider's terms and privacy policy.
- **Secure Storage:** API keys are stored using hardware-backed encryption (Android Keystore).
- **Transparency:** Built for privacy-focused needs. No ads, no tracking, no hidden costs.

## ✨ Key Features

### 🎙️ Audio & Transcription
- **On-Device Recording:** Capture high-quality audio with live amplitude feedback.
- **OpenAI, Gemini, xAI & Local AI Support:** Choose OpenAI, Google Gemini, xAI Grok, or a local Whisper-compatible endpoint for voice transcription.
- **Realtime STT:** Stream live transcription through OpenAI GPT Live Transcribe or ElevenLabs Scribe v2 Realtime in the installed app. ElevenLabs uses its own securely stored API key and is unavailable in the browser build because browser WebSockets cannot attach the required authentication header.
- **Voice Message Summary:** Share voice messages from WhatsApp or other apps directly to EchoScribe.
- **Note:** Claude 🦀 is text-only for app-side speech input.

### 🖥️ Desktop Companions
- **Linux:** GNOME Shell integration for start/stop toggle dictation.
- **Same BYOK/local model:** Desktop requests go directly from your computer to the selected AI provider or your own Local AI endpoints.

### ✍️ Floating Dictation on Android
- **System-Wide Voice Input:** Enable the Android accessibility service and overlay permission to use a movable EchoScribe dictation button in editable text fields.
- **Explicit Insert:** EchoScribe records only after you tap the floating button, shows a preview, and inserts text only after you tap Insert.
- **Safety Guards:** The floating button hides in password, PIN, credit-card, phone-pad, banking, and payment fields.

### ✍️ Smart Summarization
- **Audio • Text • URL:** Summarize everything in one tap.
- **Local URL Extraction:** A privacy-first mechanism extracts web content directly on your device, bypassing paywalls and bot-detection while keeping your browsing private. Mandatory for Claude 🦀 and Grok 𝕏.
- **Local AI Provider:** The Flutter app can use an Ollama-compatible `/api/chat` endpoint for summaries/translations. Desktop companions can use an OpenAI-compatible Whisper endpoint for local speech-to-text; they do not install or configure summary models.
- **Custom Prompts:** Fine-tune how your summaries look and feel in the settings.

### 🚀 Pro Mode & Models
Access the world's most powerful AI models with a single toggle:
- **Standard (Fast):** GPT-5.6 Terra, Gemini 3.7 Flash, Claude Sonnet 5, Grok 4.3, or local `qwen2.5:7b`.
- **Pro Mode (Premium):** GPT-5.6 Sol, Gemini 3.1 Pro Preview, Claude Opus 5, Grok 4.5.
- **Speech Models:** OpenAI Pro file transcription uses GPT Transcribe; OpenAI Realtime uses GPT Live Transcribe; optional ElevenLabs Realtime uses Scribe v2 Realtime.

### 🌍 Intelligent Re-Translation
Need a result in another language? Change the target language via the globe icon, and EchoScribe will automatically re-process the source content to provide a high-quality summary in the new language.

### 📺 Fullscreen Mode
Double-tap any transcription or summary to enter an immersive, distraction-free reading mode with smooth animations.

### 🔊 Text-to-Speech (TTS)
Listen to your summaries on the go. Supports high-quality neural voices from OpenAI (MP3), Google (WAV), and xAI Grok (MP3) with local caching.

---

## 🔑 Getting Started
To use EchoScribe, you'll need at least one API key:
- **OpenAI:** [Get API Key](https://platform.openai.com/api-keys)
- **Google Gemini:** [Get API Key](https://aistudio.google.com/app/apikey)
- **Anthropic Claude:** [Get API Key](https://console.anthropic.com/settings/keys)
- **xAI Grok:** [Get API Key](https://console.x.ai/)
- **ElevenLabs Realtime STT:** [Get API Key](https://elevenlabs.io/app/settings/api-keys)
- **Local AI:** In the Flutter app, configure your own Ollama endpoint such as `http://host:11434/api/chat`. Desktop companions accept a Whisper-compatible endpoint such as `http://host:8000/v1/audio/transcriptions`.

*Tip: Set a usage limit in your AI provider's dashboard to keep full control over your costs. For Local AI PoC use, keep endpoints on a trusted local network or VPN; EchoScribe does not add authentication to Local AI requests.*

---

## 📦 Installation

### Android

Install EchoScribe on Android from the Play Store or from a GitHub release APK.

After installing:

1. Open EchoScribe.
2. Add at least one provider API key in settings.
3. Optional: enable Floating Dictation by granting the Android accessibility service and overlay permission.

Floating Dictation only shows a dictation button in editable fields, records after an explicit tap, and inserts text only after confirmation. It hides in password, PIN, payment, banking, credit-card, and phone fields.


### Linux / GNOME

Download `EchoScribe-Linux-GNOME-<version>.tar.gz` from GitHub releases, extract it, then run:

```bash
cd EchoScribe-Linux-GNOME-<version>/linux
./install.sh
```

The installer targets GNOME 45–50 on Wayland and Xorg. Press the GNOME shortcut
once to start recording and again to stop and transcribe. GNOME Shell owns the
global toggle shortcut, persistent recording status, clipboard, and paste;
short-lived system-Python workers record and transcribe. A notification after
90 seconds is only a reminder: recording continues until the next shortcut
press, subject to the selected provider's upload/API limits. Updates preserve
config, secrets, and GSettings.
Local Whisper remains a separate optional setup step. The core does
not need a general venv, `/dev/input`, `uinput`,
`ydotool`, or a background user service.

More details: [`desktop/linux/README.md`](desktop/linux/README.md).

To uninstall the Linux/GNOME integration, run `~/.local/share/echoscribe/app/linux/uninstall.sh`.

### Browser Extension

[EchoScribe Web Summary](browser-extension/README.md) is the single browser
extension for Chrome. It uses one shared source
tree, communicates directly with the cloud AI provider selected by the user,
and does not require the Linux desktop app, Native Messaging, or a
local bridge process.

For development and release packaging:

```bash
cd browser-extension
npm ci
npm run verify
```

---

## 🛠️ Tech Stack & Development
- **Framework:** Flutter (Dart)
- **State Management:** Provider-based architecture.
- **Security:** Flutter Secure Storage (AES/Keychain/Keystore).
- **Vibe-Coding:** This project was built and refined using "vibe-coding" powered by Google Gemini.

### Local Setup
1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. Clone the repository.
3. Run `flutter pub get`.
4. Connect your device and run `flutter run`.

### Desktop Setup
- Linux: see `desktop/linux/README.md`.
- Browser extension: see [`browser-extension/README.md`](browser-extension/README.md).

---

## ✉️ Feedback & Support
Built by a developer for developers and privacy enthusiasts.
Feedback or Bugs? Reach out at: **app@wean.de**

---

## License and trademarks

Source code in this repository is licensed under the [MIT License](LICENSE),
except where a file or bundled third-party component states otherwise.

The EchoScribe name and brand assets are subject to the separate
[trademark and branding policy](TRADEMARKS.md). The MIT License permits use,
modification, and distribution of the covered code, but does not grant the
right to present a fork as the official EchoScribe application.

Forks intended for public distribution must use a distinct product name,
package or bundle identifier, signing identity, icons, and store presentation.
Only vibecodingwean, through the original
[EchoScribe repository](https://github.com/vibecodingwean/echoscribe) and its
controlled store records, publishes the official EchoScribe application unless
prior written permission states otherwise.
