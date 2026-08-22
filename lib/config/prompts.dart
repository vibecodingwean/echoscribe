// ignore_for_file: constant_identifier_names
const String kDefaultSummaryPrompt =
    'Summarize the following transcript into a structured, concise, and neutral summary.\n'
    '\n'
    'Guidelines:\n'
    '- Write in clear, objective language.\n'
    '- If multiple speakers are detected, identify them generically (e.g., Speaker A, Speaker B) '
    'and summarize their viewpoints, questions, and decisions.\n'
    '- Capture key outcomes, actions, or follow-ups if discussed.\n'
    '- If the text appears to be a personal note or monologue, focus only on the core ideas, insights, or intentions.\n'
    '- Skip filler words, small talk, and redundant statements.\n'
    '\n'
    'Formatting:\n'
    '- Do not start with meta-phrases like "This transcript..." or "The text says...".\n'
    '- Return only the summary content.';

const String kDefaultUrlSummaryPrompt =
    'Summarize the provided webpage content.\n\n'
    'Rules:\n'
    '- Use ONLY information present in the content.\n'
    '- Never guess or invent missing details.\n'
    '- Replace vague or clickbait headlines with the specific subject described in the text.\n'
    '- Prefer concrete facts (names, numbers, results, ingredients, products).\n'
    '- Remove filler and marketing language.\n'
    '- Adapt to the content type automatically.\n\n'
    'Structure:\n'
    '- If the content contains multiple distinct aspects (e.g. results, ingredients, steps, features, findings), organize the summary into 2–4 short sections.\n'
    '- Each section heading MUST be formatted as "## <emoji> <1–3 word title>".\n'
    '- Do not write a section heading without an emoji.\n'
    '- Keep section titles very short (1–3 words).\n'
    '- Each section should contain one concise sentence.\n'
    '- If the content is simple, write a short paragraph instead (1–3 sentences).\n\n'
    'If the content is missing or insufficient, state the reason or describe why a summary cannot be created.';

const String kDefaultDictationPrompt =
    'Rewrite this dictated transcript for direct text input. '
    'Output in the same language as the input; for mixed or unclear input, use the dominant language. '
    'Keep the core meaning, tone level, names, and numbers, but make it polite, respectful, and natural. '
    'Remove filler words and speech artifacts. '
    'Never preserve insults, profanity, slurs, threats, or aggressive wording; turn them into calm, friendly wording with the same intent. '
    'Do not summarize. '
    'For emails or lists, add clear paragraphs, line breaks, and bullets when implied. '
    'Add 1-2 fitting emojis when natural. '
    'Return only the final text.';

/// Centralized AI model configuration. Update these values to change defaults app-wide.
class AiModelConfig {
  // ---------- OpenAI ----------
  // Pro models (July 2026)
  static const String openAiSummaryPro = 'gpt-5.6-sol';
  static const String openAiTranslationPro = 'gpt-5.6-sol';
  static const String openAiTranscriptionPro = 'gpt-transcribe';
  static const String openAiImagePro = 'gpt-image-2';
  static const String openAiReasoningEffortPro = 'medium';

  // Fast models
  static const String openAiSummaryFast = 'gpt-5.6-terra';
  static const String openAiTranslationFast = 'gpt-5.6-terra';
  static const String openAiTranscriptionFast = 'gpt-4o-mini-transcribe';
  static const String openAiImageFast = 'gpt-image-1-mini';
  static const String openAiTts = 'gpt-4o-mini-tts';
  static const String openAiRealtimeTranscription = 'gpt-live-transcribe';
  static const String openAiRealtimeTranslation = 'gpt-realtime-translate';
  static const String elevenLabsTranscription = 'scribe_v2';
  static const String elevenLabsRealtimeTranscription = 'scribe_v2_realtime';
  static const String elevenLabsTts = 'eleven_flash_v2_5';
  static const String elevenLabsTtsVoice = 'JBFqnCBsd6RMkjVDRZzb';
  static const String elevenLabsVoiceLibraryUrl =
      'https://elevenlabs.io/app/voice-library';
  static const String openAiReasoningEffortFast = 'none';

  // ---------- Gemini ----------
  // Pro models
  static const String geminiSummaryPro = 'gemini-3.1-pro-preview';
  static const String geminiTranscriptionPro = 'gemini-3.1-pro-preview';
  static const String geminiTranslationPro = 'gemini-3.1-pro-preview';
  static const String geminiImagePro = 'gemini-3-pro-image';

  // Fast models
  static const String geminiSummaryFast = 'gemini-3.7-flash';
  static const String geminiTranscriptionFast = 'gemini-3.7-flash';
  static const String geminiTranslationFast = 'gemini-3.7-flash';
  static const String geminiImageFast = 'gemini-3.1-flash-image';
  static const String geminiTts = 'gemini-3.1-flash-tts-preview';

  // Helper methods to get the right model based on 'Pro' toggle
  static String openAiSummary({required bool pro}) =>
      pro ? openAiSummaryPro : openAiSummaryFast;
  static String openAiTranslation({required bool pro}) =>
      pro ? openAiTranslationPro : openAiTranslationFast;
  static String openAiTranscription({required bool pro}) =>
      pro ? openAiTranscriptionPro : openAiTranscriptionFast;
  static String openAiReasoningEffort({required bool pro}) =>
      pro ? openAiReasoningEffortPro : openAiReasoningEffortFast;

  static String geminiSummary({required bool pro}) =>
      pro ? geminiSummaryPro : geminiSummaryFast;
  static String geminiTranslation({required bool pro}) =>
      pro ? geminiTranslationPro : geminiTranslationFast;
  static String geminiTranscription({required bool pro}) =>
      pro ? geminiTranscriptionPro : geminiTranscriptionFast;

  // ---------- Anthropic (Claude) ----------
  static const String anthropicSummaryPro = 'claude-opus-5';
  static const String anthropicTranslationPro = 'claude-opus-5';

  static const String anthropicSummaryFast = 'claude-sonnet-5';
  static const String anthropicTranslationFast = 'claude-sonnet-5';

  static String anthropicSummary({required bool pro}) =>
      pro ? anthropicSummaryPro : anthropicSummaryFast;
  static String anthropicTranslation({required bool pro}) =>
      pro ? anthropicTranslationPro : anthropicTranslationFast;

  // ---------- xAI (Grok) ----------
  static const String xaiSummaryPro = 'grok-4.6';
  static const String xaiTranslationPro = 'grok-4.6';
  static const String xaiTranscriptionPro = 'xai-stt';
  static const String xaiImagePro = 'grok-imagine-image-2.0';
  static const String xaiReasoningEffortPro = 'medium';

  static const String xaiSummaryFast = 'grok-4.3';
  static const String xaiTranslationFast = 'grok-4.3';
  static const String xaiTranscriptionFast = 'xai-stt';
  static const String xaiImageFast = 'grok-imagine-image';
  static const String xaiReasoningEffortFast = 'none';

  static String xaiSummary({required bool pro}) =>
      pro ? xaiSummaryPro : xaiSummaryFast;
  static String xaiTranslation({required bool pro}) =>
      pro ? xaiTranslationPro : xaiTranslationFast;
  static String xaiTranscription({required bool pro}) =>
      pro ? xaiTranscriptionPro : xaiTranscriptionFast;
  static String xaiImage({required bool pro}) =>
      pro ? xaiImagePro : xaiImageFast;
  static String xaiReasoningEffort({required bool pro}) =>
      pro ? xaiReasoningEffortPro : xaiReasoningEffortFast;

  // ---------- Local AI ----------
  static const String localAiLlmUrl = 'http://127.0.0.1:11434/api/chat';
  static const String localAiLlmModel = 'qwen2.5:7b';
  static const String localAiWhisperUrl =
      'http://127.0.0.1:8000/v1/audio/transcriptions';
  static const String localAiWhisperModel = 'whisper-1';

  static String openAiImage({required bool pro}) =>
      pro ? openAiImagePro : openAiImageFast;
  static String geminiImage({required bool pro}) =>
      pro ? geminiImagePro : geminiImageFast;
}
