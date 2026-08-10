import { normalizeModelIds, requestJson, requireCredentials } from './common.js';

const BASE_URL = 'https://api.anthropic.com/v1';
const headers = (apiKey) => ({
  'content-type': 'application/json',
  'x-api-key': apiKey,
  'anthropic-version': '2023-06-01',
  'anthropic-dangerous-direct-browser-access': 'true'
});

export const anthropic = {
  async summarize({ apiKey, model, prompt, fetchImpl = fetch }) {
    requireCredentials(apiKey, model);
    const body = await requestJson(`${BASE_URL}/messages`, {
      fetchImpl,
      request: {
        method: 'POST', headers: headers(apiKey),
        body: JSON.stringify({ model, max_tokens: 1200, messages: [{ role: 'user', content: prompt }] })
      }
    }, apiKey);
    const summary = (body.content || []).filter((item) => item.type === 'text').map((item) => item.text).join('\n').trim();
    if (!summary) throw new Error('The provider returned an empty summary.');
    return summary;
  },

  async listModels({ apiKey, fetchImpl = fetch }) {
    if (!String(apiKey || '').trim()) throw new Error('An API key is required for the selected provider.');
    const body = await requestJson(`${BASE_URL}/models`, {
      fetchImpl, request: { method: 'GET', headers: headers(apiKey) }
    }, apiKey);
    return normalizeModelIds((body.data || []).map((item) => item.id));
  }
};
