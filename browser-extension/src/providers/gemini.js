import { normalizeModelIds, requestJson, requireCredentials } from './common.js';

const BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';

export const gemini = {
  async summarize({ apiKey, model, prompt, fetchImpl = fetch }) {
    requireCredentials(apiKey, model);
    const cleanModel = String(model).replace(/^models\//, '');
    const url = `${BASE_URL}/models/${encodeURIComponent(cleanModel)}:generateContent`;
    const body = await requestJson(url, {
      fetchImpl,
      request: {
        method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': apiKey },
        body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: prompt }] }] })
      }
    }, apiKey);
    const summary = (body?.candidates?.[0]?.content?.parts || []).map((part) => part.text || '').join('').trim();
    if (!summary) throw new Error('The provider returned an empty summary.');
    return summary;
  },

  async listModels({ apiKey, fetchImpl = fetch }) {
    if (!String(apiKey || '').trim()) throw new Error('An API key is required for the selected provider.');
    const url = `${BASE_URL}/models`;
    const body = await requestJson(url, {
      fetchImpl,
      request: { method: 'GET', headers: { 'x-goog-api-key': apiKey } }
    }, apiKey);
    return normalizeModelIds((body.models || [])
      .filter((item) => item.supportedGenerationMethods?.includes('generateContent'))
      .map((item) => String(item.name || '').replace(/^models\//, '')));
  }
};
