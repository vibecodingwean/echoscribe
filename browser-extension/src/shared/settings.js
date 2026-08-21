import { PROVIDERS } from './constants.js';

const LANGUAGE_CODE = /^(auto|[a-z]{2,3}(?:-[a-z0-9]{2,8})?)$/i;
const DEPRECATED_MODELS = Object.freeze({
  'gemini-3.1-flash-lite': 'gemini-3.7-flash',
  'gemini-3.6-flash': 'gemini-3.7-flash',
  'grok-4.5': 'grok-4.6'
});

export function defaultSettings() {
  return {
    provider: 'openai',
    models: Object.fromEntries(Object.entries(PROVIDERS).map(([id, value]) => [id, value.defaultModel])),
    apiKeys: Object.fromEntries(Object.keys(PROVIDERS).map((id) => [id, ''])),
    targetLanguage: 'auto',
    customPrompt: ''
  };
}

export function normalizeSettings(value = {}) {
  const defaults = defaultSettings();
  const provider = Object.hasOwn(PROVIDERS, value.provider) ? value.provider : defaults.provider;
  const models = { ...defaults.models };
  const apiKeys = { ...defaults.apiKeys };

  for (const id of Object.keys(PROVIDERS)) {
    const model = String(value.models?.[id] ?? '').trim();
    if (model) models[id] = (DEPRECATED_MODELS[model] || model).slice(0, 200);
    apiKeys[id] = String(value.apiKeys?.[id] ?? '').trim().slice(0, 10_000);
  }

  const language = String(value.targetLanguage ?? '').trim().toLowerCase();
  return {
    provider,
    models,
    apiKeys,
    targetLanguage: LANGUAGE_CODE.test(language) ? language : 'auto',
    customPrompt: String(value.customPrompt ?? '').trim().slice(0, 20_000)
  };
}

export function publicSettings(value = {}) {
  const settings = normalizeSettings(value);
  const { apiKeys, ...visible } = settings;
  return {
    ...visible,
    configuredProviders: Object.fromEntries(Object.keys(PROVIDERS).map((id) => [id, Boolean(apiKeys[id])]))
  };
}

export function maskApiKey(value) {
  const key = String(value ?? '');
  if (!key) return '';
  if (key.length <= 4) return '•'.repeat(key.length);
  return `••••••${key.slice(-4)}`;
}
