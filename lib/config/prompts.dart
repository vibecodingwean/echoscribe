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
'- If the content contains multiple distinct aspects (e.g. results, ingredients, steps, features, findings), you MAY organize the summary into 2–4 short sections.\n'
'- Each section may have a short "##" heading and one fitting emoji.\n'
'- Keep section titles very short (1–3 words).\n'
'- Each section should contain one concise sentence.\n'
'- If the content is simple, write a short paragraph instead (1–3 sentences).\n\n'

'If the content is missing or insufficient, state the reason or describe why a summary cannot be created.';

/// Centralized AI model configuration. Update these values to change defaults app-wide.
class AiModelConfig {
  // ---------- OpenAI ----------
  // Pro models (Dez 2025 Flagship)
  // Hinweis: Der Transcriptions-Endpunkt akzeptiert nur 'whisper-1'. 
  // GPT-4o-Audio läuft über die Chat-API, was einen Umbau erfordern würde.
  static const String openAiSummaryPro = 'gpt-5.4';
  static const String openAiTranslationPro = 'gpt-5.4';
  static const String openAiTranscriptionPro = 'whisper-1'; 
  static const String openAiImagePro = 'gpt-image-1';

  // Fast models (Upgrade auf die effiziente 5er-Serie)
  static const String openAiSummaryFast = 'gpt-5-mini';
  static const String openAiTranslationFast = 'gpt-5-mini';
  static const String openAiTranscriptionFast = 'whisper-1';
  static const String openAiImageFast = 'gpt-image-1';
  static const String openAiTts = 'gpt-4o-mini-tts';

  // ---------- Gemini ----------
  // Pro models (Preview der nächsten Generation)
  static const String geminiSummaryPro = 'gemini-3.1-pro-preview';
  static const String geminiTranscriptionPro = 'gemini-3.1-pro-preview';
  static const String geminiTranslationPro = 'gemini-3.1-pro-preview';
  static const String geminiImagePro = 'gemini-3-pro-image-preview';

  // Fast models (Standardisierung auf 3 Flash für alles)
  static const String geminiSummaryFast = 'gemini-3-flash-preview';
  static const String geminiTranscriptionFast = 'gemini-3-flash-preview';
  static const String geminiTranslationFast = 'gemini-3-flash-preview';
  static const String geminiImageFast = 'gemini-3.1-flash-image-preview';
  static const String geminiTts = 'gemini-2.5-flash-preview-tts';

  // Helper methods to get the right model based on 'Pro' toggle
  static String openAiSummary({required bool pro}) => pro ? openAiSummaryPro : openAiSummaryFast;
  static String openAiTranslation({required bool pro}) => pro ? openAiTranslationPro : openAiTranslationFast;
  static String openAiTranscription({required bool pro}) => pro ? openAiTranscriptionPro : openAiTranscriptionFast;

  static String geminiSummary({required bool pro}) => pro ? geminiSummaryPro : geminiSummaryFast;
  static String geminiTranslation({required bool pro}) => pro ? geminiTranslationPro : geminiTranslationFast;
  static String geminiTranscription({required bool pro}) => pro ? geminiTranscriptionPro : geminiTranscriptionFast;

  // ---------- Anthropic (Claude) ----------
  static const String anthropicSummaryPro = 'claude-opus-4-6';
  static const String anthropicTranslationPro = 'claude-opus-4-6';

  static const String anthropicSummaryFast = 'claude-sonnet-4-6';
  static const String anthropicTranslationFast = 'claude-sonnet-4-6';

  static String anthropicSummary({required bool pro}) => pro ? anthropicSummaryPro : anthropicSummaryFast;
  static String anthropicTranslation({required bool pro}) => pro ? anthropicTranslationPro : anthropicTranslationFast;

  // ---------- xAI (Grok) ----------
  static const String xaiSummaryPro = 'grok-4-0709';
  static const String xaiTranslationPro = 'grok-4-0709';
  static const String xaiImagePro = 'grok-imagine-image';

  static const String xaiSummaryFast = 'grok-4-1-fast-non-reasoning';
  static const String xaiTranslationFast = 'grok-4-1-fast-non-reasoning';
  static const String xaiImageFast = 'grok-imagine-image';

  static String xaiSummary({required bool pro}) => pro ? xaiSummaryPro : xaiSummaryFast;
  static String xaiTranslation({required bool pro}) => pro ? xaiTranslationPro : xaiTranslationFast;
  static String xaiImage({required bool pro}) => pro ? xaiImagePro : xaiImageFast;
  
  static String openAiImage({required bool pro}) => pro ? openAiImagePro : openAiImageFast;
  static String geminiImage({required bool pro}) => pro ? geminiImagePro : geminiImageFast;
}
