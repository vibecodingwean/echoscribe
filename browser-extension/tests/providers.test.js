import { describe, expect, it, vi } from 'vitest';
import { listProviderModels, summarizeWithProvider } from '../src/providers/index.js';
import { MAX_MODEL_ID_CHARS, MAX_MODEL_IDS, MAX_SUMMARY_CHARS } from '../src/shared/constants.js';

const testKey = ['test', 'key'].join('-');

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

describe('summarizeWithProvider', () => {
  it('builds an OpenAI chat-completions request', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse({ choices: [{ message: { content: 'OpenAI summary' } }] }));
    const result = await summarizeWithProvider({ provider: 'openai', apiKey: 'openai-key', model: 'gpt-test', prompt: 'Prompt', fetchImpl });
    expect(result.summary).toBe('OpenAI summary');
    const [url, request] = fetchImpl.mock.calls[0];
    expect(url).toBe('https://api.openai.com/v1/chat/completions');
    expect(request.headers.Authorization).toBe('Bearer openai-key');
    expect(JSON.parse(request.body)).toMatchObject({ model: 'gpt-test', messages: [{ role: 'user', content: 'Prompt' }] });
  });

  it('builds an xAI chat-completions request', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse({ choices: [{ message: { content: 'xAI summary' } }] }));
    const result = await summarizeWithProvider({ provider: 'xai', apiKey: 'xai-key', model: 'grok-test', prompt: 'Prompt', fetchImpl });
    expect(result).toMatchObject({ summary: 'xAI summary', provider: 'xai', model: 'grok-test' });
    expect(fetchImpl.mock.calls[0][0]).toBe('https://api.x.ai/v1/chat/completions');
  });

  it('builds an Anthropic Messages request', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse({ content: [{ type: 'text', text: 'Claude summary' }] }));
    const result = await summarizeWithProvider({ provider: 'anthropic', apiKey: 'anthropic-key', model: 'claude-test', prompt: 'Prompt', fetchImpl });
    const [url, request] = fetchImpl.mock.calls[0];
    expect(result.summary).toBe('Claude summary');
    expect(url).toBe('https://api.anthropic.com/v1/messages');
    expect(request.headers['x-api-key']).toBe('anthropic-key');
    expect(request.headers['anthropic-version']).toBe('2023-06-01');
    expect(JSON.parse(request.body)).toMatchObject({ model: 'claude-test', messages: [{ role: 'user', content: 'Prompt' }] });
  });

  it('builds a Gemini generateContent request', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse({ candidates: [{ content: { parts: [{ text: 'Gemini summary' }] } }] }));
    const result = await summarizeWithProvider({ provider: 'gemini', apiKey: 'gemini-key', model: 'gemini-test', prompt: 'Prompt', fetchImpl });
    const [url, request] = fetchImpl.mock.calls[0];
    expect(result.summary).toBe('Gemini summary');
    expect(url).toBe('https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent');
    expect(url).not.toContain('gemini-key');
    expect(request.headers['x-goog-api-key']).toBe('gemini-key');
    expect(JSON.parse(request.body)).toEqual({ contents: [{ role: 'user', parts: [{ text: 'Prompt' }] }] });
  });

  it('fails before network access when the key or model is missing', async () => {
    const fetchImpl = vi.fn();
    await expect(summarizeWithProvider({ provider: 'openai', apiKey: '', model: 'gpt', prompt: 'x', fetchImpl })).rejects.toThrow('API key');
    await expect(summarizeWithProvider({ provider: 'openai', apiKey: 'key', model: '', prompt: 'x', fetchImpl })).rejects.toThrow('model');
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('calls a WorkerGlobalScope fetch implementation without rebinding its receiver', async () => {
    const workerFetch = function (_url, _request) {
      if (this !== undefined) throw new TypeError("Failed to execute 'fetch' on 'WorkerGlobalScope': Illegal invocation");
      return Promise.resolve(jsonResponse({ choices: [{ message: { content: 'Worker summary' } }] }));
    };
    await expect(summarizeWithProvider({
      provider: 'openai', apiKey: 'worker-key', model: 'gpt-test', prompt: 'Prompt', fetchImpl: workerFetch
    })).resolves.toMatchObject({ summary: 'Worker summary' });
  });

  it('reports HTTP and malformed-response errors without exposing secrets', async () => {
    const secret = testKey;
    const denied = vi.fn(async () => jsonResponse({ error: { message: `Rejected ${secret}` } }, 401));
    await expect(summarizeWithProvider({ provider: 'openai', apiKey: testKey, model: 'gpt', prompt: 'x', fetchImpl: denied })).rejects.not.toThrow(secret);
    const malformed = vi.fn(async () => jsonResponse({ choices: [] }));
    await expect(summarizeWithProvider({ provider: 'openai', apiKey: testKey, model: 'gpt', prompt: 'x', fetchImpl: malformed })).rejects.toThrow('empty');
  });

  it('aborts provider requests after the shared deadline', async () => {
    vi.useFakeTimers();
    try {
      const fetchImpl = vi.fn((_url, request) => new Promise((_resolve, reject) => {
        request.signal.addEventListener('abort', () => reject(new globalThis.DOMException('Aborted', 'AbortError')));
      }));
      const pending = summarizeWithProvider({ provider: 'openai', apiKey: testKey, model: 'gpt', prompt: 'x', fetchImpl });
      const assertion = expect(pending).rejects.toThrow('timed out');
      await vi.advanceTimersByTimeAsync(30_001);
      await assertion;
    } finally {
      vi.useRealTimers();
    }
  });

  it('cancels a provider response stream that stalls past the deadline', async () => {
    vi.useFakeTimers();
    let cancelled = false;
    try {
      const stream = new globalThis.ReadableStream({ cancel() { cancelled = true; } });
      const fetchImpl = vi.fn(async () => new Response(stream));
      const pending = summarizeWithProvider({ provider: 'openai', apiKey: testKey, model: 'gpt', prompt: 'x', fetchImpl });
      const assertion = expect(pending).rejects.toThrow('timed out');
      await vi.advanceTimersByTimeAsync(30_001);
      await assertion;
      expect(cancelled).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  it('bounds provider JSON and summary text before returning or persisting it', async () => {
    const huge = vi.fn(async () => jsonResponse({ choices: [{ message: { content: 'x'.repeat(2_000_000) } }] }));
    await expect(summarizeWithProvider({ provider: 'openai', apiKey: testKey, model: 'gpt', prompt: 'x', fetchImpl: huge }))
      .rejects.toThrow('too large');

    const long = vi.fn(async () => jsonResponse({ choices: [{ message: { content: 'x'.repeat(MAX_SUMMARY_CHARS + 10) } }] }));
    const result = await summarizeWithProvider({ provider: 'openai', apiKey: testKey, model: 'gpt', prompt: 'x', fetchImpl: long });
    expect(result.summary).toHaveLength(MAX_SUMMARY_CHARS);
  });
});

describe('listProviderModels', () => {
  it('normalizes model lists and keeps only Gemini generation models', async () => {
    const openaiFetch = vi.fn(async () => jsonResponse({ data: [{ id: 'z-model' }, { id: 'a-model' }] }));
    await expect(listProviderModels({ provider: 'openai', apiKey: 'key', fetchImpl: openaiFetch })).resolves.toEqual(['a-model', 'z-model']);

    const geminiFetch = vi.fn(async () => jsonResponse({ models: [
      { name: 'models/gemini-b', supportedGenerationMethods: ['generateContent'] },
      { name: 'models/embed', supportedGenerationMethods: ['embedContent'] }
    ] }));
    await expect(listProviderModels({ provider: 'gemini', apiKey: 'key', fetchImpl: geminiFetch })).resolves.toEqual(['gemini-b']);
    const [geminiUrl, geminiRequest] = geminiFetch.mock.calls[0];
    expect(geminiUrl).toBe('https://generativelanguage.googleapis.com/v1beta/models');
    expect(geminiUrl).not.toContain('key');
    expect(geminiRequest.headers['x-goog-api-key']).toBe('key');
  });

  it('bounds model count and model ID length', async () => {
    const data = Array.from({ length: MAX_MODEL_IDS + 20 }, (_, index) => ({
      id: `${String(index).padStart(4, '0')}-${'x'.repeat(MAX_MODEL_ID_CHARS + 20)}`
    }));
    const fetchImpl = vi.fn(async () => jsonResponse({ data }));
    const models = await listProviderModels({ provider: 'openai', apiKey: testKey, fetchImpl });
    expect(models).toHaveLength(MAX_MODEL_IDS);
    expect(models.every((model) => model.length <= MAX_MODEL_ID_CHARS)).toBe(true);
  });
});
