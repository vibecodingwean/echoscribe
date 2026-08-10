import { MAX_SUMMARY_CHARS } from '../shared/constants.js';
import { anthropic } from './anthropic.js';
import { gemini } from './gemini.js';
import { createOpenAiCompatible } from './openai-compatible.js';

const adapters = {
  openai: createOpenAiCompatible('https://api.openai.com'),
  anthropic,
  gemini,
  xai: createOpenAiCompatible('https://api.x.ai')
};

function adapterFor(provider) {
  const adapter = adapters[provider];
  if (!adapter) throw new Error('Unsupported provider.');
  return adapter;
}

export async function summarizeWithProvider(options) {
  const summary = await adapterFor(options.provider).summarize(options);
  return { summary: String(summary).slice(0, MAX_SUMMARY_CHARS), provider: options.provider, model: options.model };
}

export function listProviderModels(options) {
  return adapterFor(options.provider).listModels(options);
}
