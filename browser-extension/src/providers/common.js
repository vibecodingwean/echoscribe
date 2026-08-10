import {
  MAX_MODEL_ID_CHARS,
  MAX_MODEL_IDS,
  MAX_PROVIDER_REQUEST_MS,
  MAX_PROVIDER_RESPONSE_BYTES
} from '../shared/constants.js';

export function requireCredentials(apiKey, model) {
  if (!String(apiKey || '').trim()) throw new Error('An API key is required for the selected provider.');
  if (!String(model || '').trim()) throw new Error('A model is required for the selected provider.');
}

export function safeMessage(value, secrets = []) {
  let message = String(value || 'Provider request failed.');
  for (const secret of secrets.filter(Boolean)) message = message.split(secret).join('[redacted]');
  return message.slice(0, 500);
}

async function readBoundedText(response, withinDeadline) {
  const declaredSize = Number(response.headers.get('content-length') || 0);
  if (declaredSize > MAX_PROVIDER_RESPONSE_BYTES) throw new Error('The provider response is too large.');
  if (!response.body?.getReader) {
    const text = await withinDeadline(response.text());
    if (new TextEncoder().encode(text).byteLength > MAX_PROVIDER_RESPONSE_BYTES) {
      throw new Error('The provider response is too large.');
    }
    return text;
  }

  const reader = response.body.getReader();
  const decoder = new globalThis.TextDecoder();
  let total = 0;
  let text = '';
  try {
    while (true) {
      const { done, value } = await withinDeadline(reader.read());
      if (done) break;
      total += value.byteLength;
      if (total > MAX_PROVIDER_RESPONSE_BYTES) {
        await reader.cancel();
        throw new Error('The provider response is too large.');
      }
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } catch (error) {
    try { await reader.cancel(); } catch { /* The stream may already be aborted. */ }
    throw error;
  } finally {
    reader.releaseLock();
  }
}

export async function requestJson(url, init, apiKey) {
  const controller = new globalThis.AbortController();
  let timedOut = false;
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
      reject(new Error('Provider request timed out after 30 seconds.'));
    }, MAX_PROVIDER_REQUEST_MS);
  });
  const withinDeadline = (promise) => Promise.race([Promise.resolve(promise), timeout]);

  try {
    const request = { ...init.request, signal: controller.signal };
    const fetchImpl = init.fetchImpl;
    const response = await withinDeadline(fetchImpl(url, request));
    const text = await readBoundedText(response, withinDeadline);
    let body = {};
    try {
      body = text ? JSON.parse(text) : {};
    } catch {
      if (response.ok) throw new Error('The provider returned an invalid JSON response.');
    }
    if (!response.ok) {
      const detail = body?.error?.message || body?.message || `HTTP ${response.status}`;
      throw new Error(`Provider request failed: ${safeMessage(detail, [apiKey])}`);
    }
    return body;
  } catch (error) {
    if (timedOut) throw new Error('Provider request timed out after 30 seconds.');
    throw new Error(safeMessage(error?.message || 'Network request failed.', [apiKey]));
  } finally {
    clearTimeout(timer);
  }
}

export function normalizeModelIds(values) {
  const unique = new Set();
  for (const value of Array.isArray(values) ? values : []) {
    const model = String(value || '').trim().slice(0, MAX_MODEL_ID_CHARS);
    if (model) unique.add(model);
    if (unique.size >= MAX_MODEL_IDS) break;
  }
  return [...unique].sort();
}
