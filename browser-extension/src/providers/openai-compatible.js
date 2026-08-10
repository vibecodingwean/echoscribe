import { normalizeModelIds, requestJson, requireCredentials } from './common.js';

export function createOpenAiCompatible(baseUrl) {
  return {
    async summarize({ apiKey, model, prompt, fetchImpl = fetch }) {
      requireCredentials(apiKey, model);
      const body = await requestJson(`${baseUrl}/v1/chat/completions`, {
        fetchImpl,
        request: {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${apiKey}` },
          body: JSON.stringify({ model, messages: [{ role: 'user', content: prompt }] })
        }
      }, apiKey);
      const summary = body?.choices?.[0]?.message?.content?.trim();
      if (!summary) throw new Error('The provider returned an empty summary.');
      return summary;
    },

    async listModels({ apiKey, fetchImpl = fetch }) {
      if (!String(apiKey || '').trim()) throw new Error('An API key is required for the selected provider.');
      const body = await requestJson(`${baseUrl}/v1/models`, {
        fetchImpl,
        request: { method: 'GET', headers: { Authorization: `Bearer ${apiKey}` } }
      }, apiKey);
      return normalizeModelIds((body.data || []).map((item) => item.id));
    }
  };
}
