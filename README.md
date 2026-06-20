# 🎙️ EchoScribe: Your API Key & Data

**Summarize voice, messages, and URLs. Your API Key — Your Data!**

EchoScribe is a privacy-first, zero-backend Flutter application designed for users who want full control over their AI experience. By using your own API keys (BYOK), you ensure that your data stays between you and the AI provider. No subscriptions, no tracking, no middleman.

---

## 🔒 Privacy & Security (BYOK)
- **No Backend:** Processing happens directly between your device and the AI provider. Your data is never stored on any third-party servers.
- **Secure Storage:** API keys are stored using hardware-backed encryption (Android Keystore).
- **Transparency:** Built for privacy-focused needs. No ads, no tracking, no hidden costs.

## ✨ Key Features

### 🎙️ Audio & Transcription
- **On-Device Recording:** Capture high-quality audio with live amplitude feedback.
- **OpenAI, Gemini, xAI & Local AI Support:** Choose OpenAI, Google Gemini, xAI Grok, or a local Whisper-compatible endpoint for voice transcription.
- **Voice Message Summary:** Share voice messages from WhatsApp or other apps directly to EchoScribe.
- **Note:** Claude 🦀 is text-only for app-side speech input.

### 🖥️ Desktop Companions
- **Linux:** GNOME Shell integration for push-to-talk dictation plus local browser summary extensions.
- **Same BYOK/local model:** Desktop requests go directly from your computer to the selected AI provider or your own Local AI endpoints.

### ✍️ Floating Dictation on Android
- **System-Wide Voice Input:** Enable the Android accessibility service and overlay permission to use a movable EchoScribe dictation button in editable text fields.
- **Explicit Insert:** EchoScribe records only after you tap the floating button, shows a preview, and inserts text only after you tap Insert.
- **Safety Guards:** The floating button hides in password, PIN, credit-card, phone-pad, banking, and payment fields.

### ✍️ Smart Summarization
- **Audio • Text • URL:** Summarize everything in one tap.
- **Local URL Extraction:** A privacy-first mechanism extracts web content directly on your device, bypassing paywalls and bot-detection while keeping your browsing private. Mandatory for Claude 🦀 and Grok 𝕏.
- **Local AI Provider:** Use an Ollama-compatible `/api/chat` endpoint for summaries/translations and an OpenAI-compatible Whisper endpoint for STT. Defaults are `qwen2.5:7b` and `whisper-1`; local model names remain editable.
- **Custom Prompts:** Fine-tune how your summaries look and feel in the settings.

### 🚀 Pro Mode & Models
Access the world's most powerful AI models with a single toggle:
- **Standard (Fast):** GPT-5.4-mini, Gemini 3.5 Flash, Claude 4.6 Sonnet, Grok 4.3, or local `qwen2.5:7b`.
- **Pro Mode (Premium):** GPT-5.5, Gemini 3.1 Pro, Claude 4.8 Opus, Grok 4.3.

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
- **Local AI:** Configure your own Ollama endpoint such as `http://host:11434/api/chat` and a Whisper-compatible endpoint such as `http://host:8000/v1/audio/transcriptions`. Example local LLMs include `qwen2.5:7b`, `gemma4:e4b`, `gemma3`, and `deepseek-r1`.

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

The wizard is intended for Debian-based GNOME systems. It installs dependencies,
creates the Python environment, writes local config, stores provider keys in the
configured per-user secret env file, installs the GNOME Shell extension, and can
register Native Messaging hosts for Chromium-based browsers and Firefox.

Browser extensions are loaded manually:

1. Chrome, Edge, Brave, or Chromium: enable developer mode and load the `browser-extension` folder from the extracted package.
2. Firefox: open `about:debugging#/runtime/this-firefox` and load `firefox-extension/manifest.json`.

More details: [`desktop/linux/README.md`](desktop/linux/README.md).

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
- Browser summaries use manually loaded Chromium-based or Firefox extensions plus a local Native Messaging host. The native host is registered by the installer but only runs when an extension sends a summary request.

---

## ✉️ Feedback & Support
Built by a developer for developers and privacy enthusiasts.
Feedback or Bugs? Reach out at: **app@wean.de**

---
*MIT License - Use it, fork it, make it yours.*
