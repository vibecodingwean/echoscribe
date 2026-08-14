export const PROVIDERS = Object.freeze({
  openai: {
    label: 'OpenAI', defaultModel: 'gpt-5.6-terra',
    models: [{ id: 'gpt-5.6-terra', tier: 'Fast' }, { id: 'gpt-5.6-sol', tier: 'Pro' }]
  },
  anthropic: {
    label: 'Anthropic', defaultModel: 'claude-sonnet-5',
    models: [{ id: 'claude-sonnet-5', tier: 'Fast' }, { id: 'claude-opus-5', tier: 'Pro' }]
  },
  gemini: {
    label: 'Google Gemini', defaultModel: 'gemini-3.7-flash',
    models: [{ id: 'gemini-3.7-flash', tier: 'Fast' }, { id: 'gemini-3.1-pro-preview', tier: 'Pro' }]
  },
  xai: {
    label: 'xAI', defaultModel: 'grok-4.3',
    models: [{ id: 'grok-4.3', tier: 'Fast' }, { id: 'grok-4.5', tier: 'Pro' }]
  }
});

export const MAX_CONTENT_CHARS = 120_000;
export const MAX_TITLE_CHARS = 512;
export const MAX_DESCRIPTION_CHARS = 2_000;
export const MAX_PDF_BYTES = 16 * 1024 * 1024;
export const MAX_PDF_PAGES = 500;
export const MAX_PDF_PROCESSING_MS = 30_000;
export const MAX_PDF_DOWNLOAD_MS = 30_000;
export const MAX_PROVIDER_REQUEST_MS = 30_000;
export const MAX_PROVIDER_RESPONSE_BYTES = 1024 * 1024;
export const MAX_SUMMARY_CHARS = 120_000;
export const MAX_MODEL_IDS = 500;
export const MAX_MODEL_ID_CHARS = 200;
