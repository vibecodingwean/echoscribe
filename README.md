# 🎙️ EchoScribe: Your API Key & Data

**Summarize voice, messages, and URLs. Your API Key — Your Data!**

EchoScribe is a privacy-first, zero-backend Flutter application designed for users who want full control over their AI experience. By using your own API keys (BYOK), you ensure that your data stays between you and the AI provider. No subscriptions, no tracking, no middleman.

---

## 🔒 Privacy & Security (BYOK)
- **No Backend:** Processing happens directly between your device and the AI provider. Your data is never stored on any third-party servers.
- **Secure Storage:** API keys are stored using hardware-backed encryption (Android Keystore / iOS Keychain).
- **Transparency:** Built for privacy-focused needs. No ads, no tracking, no hidden costs.

## ✨ Key Features

### 🎙️ Audio & Transcription
- **On-Device Recording:** Capture high-quality audio with live amplitude feedback.
- **Whisper & Gemini Support:** Choose between OpenAI Whisper or Google Gemini for near-perfect transcriptions.
- **Voice Message Summary:** Share voice messages from WhatsApp or other apps directly to EchoScribe.

### ✍️ Smart Summarization
- **Audio • Text • URL:** Summarize everything in one tap.
- **Local URL Extraction:** A privacy-first mechanism extracts web content directly on your device, bypassing paywalls and bot-detection while keeping your browsing private.
- **Custom Prompts:** Fine-tune how your summaries look and feel in the settings.

### 🚀 Pro Mode & Models
Access the world's most powerful AI models with a single toggle:
- **Standard:** GPT-4o-mini, Gemini 1.5 Flash, Claude 3.5 Sonnet.
- **Pro Mode:** GPT-4o (Flagship), Gemini 1.5 Pro, Claude 3.5 Opus.

### 🌍 Intelligent Re-Translation
Need a result in another language? Change the target language via the globe icon, and EchoScribe will automatically re-process the source content to provide a high-quality summary in the new language.

### 📺 Fullscreen Mode
Double-tap any transcription or summary to enter an immersive, distraction-free reading mode with smooth animations.

### 🔊 Text-to-Speech (TTS)
Listen to your summaries on the go. Supports high-quality neural voices from OpenAI (MP3) and Google (WAV) with local caching.

---

## 🔑 Getting Started
To use EchoScribe, you'll need at least one API key:
- **OpenAI:** [Get API Key](https://platform.openai.com/api-keys)
- **Google Gemini:** [Get API Key](https://aistudio.google.com/app/apikey)
- **Anthropic Claude:** [Get API Key](https://console.anthropic.com/settings/keys)

*Tip: Set a usage limit in your AI provider's dashboard to keep full control over your costs.*

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

---

## ✉️ Feedback & Support
Built by a developer for developers and privacy enthusiasts.
Feedback or Bugs? Reach out at: **app@wean.de**

---
*MIT License - Use it, fork it, make it yours.*
