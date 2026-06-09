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
- **OpenAI, Gemini & xAI Support:** Choose OpenAI, Google Gemini, or xAI Grok for voice transcription.
- **Voice Message Summary:** Share voice messages from WhatsApp or other apps directly to EchoScribe.
- **Note:** Claude 🦀 is text-only for app-side speech input.

### 🖥️ Desktop Companions
- **Linux:** GNOME Shell integration for push-to-talk dictation plus a local Chrome/Chromium summary extension.
- **Same BYOK model:** Desktop requests go directly from your computer to the selected AI provider using your own API keys.

### ✍️ Floating Dictation on Android
- **System-Wide Voice Input:** Enable the Android accessibility service and overlay permission to use a movable EchoScribe dictation button in editable text fields.
- **Explicit Insert:** EchoScribe records only after you tap the floating button, shows a preview, and inserts text only after you tap Insert.
- **Safety Guards:** The floating button hides in password, PIN, credit-card, phone-pad, banking, and payment fields.

### ✍️ Smart Summarization
- **Audio • Text • URL:** Summarize everything in one tap.
- **Local URL Extraction:** A privacy-first mechanism extracts web content directly on your device, bypassing paywalls and bot-detection while keeping your browsing private. Mandatory for Claude 🦀 and Grok 𝕏.
- **Custom Prompts:** Fine-tune how your summaries look and feel in the settings.

### 🚀 Pro Mode & Models
Access the world's most powerful AI models with a single toggle:
- **Standard (Fast):** GPT-5.4-mini, Gemini 3.1 Flash-Lite, Claude 4.6 Sonnet, Grok 4.3.
- **Pro Mode (Premium):** GPT-5.5, Gemini 3.1 Pro, Claude 4.7 Opus, Grok 4.3.

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

### Desktop Setup
- Linux: see `desktop/linux/README.md`.
- Model defaults are tracked in `config/ai_models.json`; run `tooling/verify_ai_models.py` after model updates.

---

## ✉️ Feedback & Support
Built by a developer for developers and privacy enthusiasts.
Feedback or Bugs? Reach out at: **app@wean.de**

---
*MIT License - Use it, fork it, make it yours.*
