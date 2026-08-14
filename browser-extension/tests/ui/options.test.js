import { JSDOM } from 'jsdom';
import { describe, expect, it, vi } from 'vitest';
import { DEFAULT_SUMMARY_PROMPT } from '../../src/shared/prompt.js';
import { bindOptions } from '../../src/options/options.js';

function optionsDocument() {
  return new JSDOM(`<body>
    <select id="provider"></select><input id="api-key" type="password"><span id="key-status"></span><button id="clear-key"></button><select id="model"></select>
    <button id="fetch-models"></button><p id="model-refresh-help"></p><textarea id="prompt"></textarea><button id="reset-prompt"></button>
    <button id="save"></button><button id="clear-data"></button><div id="status"></div>
  </body>`).window.document;
}

function setup() {
  const settings = {
    provider: 'gemini',
    models: {
      openai: 'gpt-5.6-terra', anthropic: 'claude-sonnet-5',
      gemini: 'gemini-3.1-pro-preview', xai: 'grok-4.3'
    },
    configuredProviders: { openai: false, anthropic: false, gemini: true, xai: false },
    targetLanguage: 'auto', customPrompt: 'My custom prompt'
  };
  const api = { runtime: { sendMessage: vi.fn(async (message) => {
    if (message.type === 'getSettings') return { ok: true, settings };
    if (message.type === 'listModels') return { ok: true, models: ['gemini-api-extra', 'gemini-3.7-flash'] };
    return { ok: true };
  }) } };
  const document = optionsDocument();
  return { document, api, controller: bindOptions(document, api, () => true) };
}

const modelOptions = (document) => [...document.querySelectorAll('#model option')]
  .map((option) => ({ value: option.value, label: option.textContent }));

describe('options', () => {
  it('loads a real model dropdown with visible Fast and Pro choices', async () => {
    const { document, controller } = setup();
    await controller.ready;
    expect([...document.querySelectorAll('#provider option')].map((option) => option.value)).toEqual(['openai', 'anthropic', 'gemini', 'xai']);
    expect(document.querySelector('#provider').value).toBe('gemini');
    expect(document.querySelector('#api-key').type).toBe('password');
    expect(document.querySelector('#api-key').value).toBe('');
    expect(document.querySelector('#key-status').textContent).toContain('configured');
    expect(modelOptions(document)).toEqual([
      { value: 'gemini-3.7-flash', label: 'Fast — gemini-3.7-flash' },
      { value: 'gemini-3.1-pro-preview', label: 'Pro — gemini-3.1-pro-preview' }
    ]);
    expect(document.querySelector('#model').value).toBe('gemini-3.1-pro-preview');
    expect(document.querySelector('#prompt').value).toBe('My custom prompt');
  });

  it('appends explicit API-refreshed choices without removing Fast and Pro', async () => {
    const { document, api, controller } = setup();
    await controller.ready;
    await controller.fetchModels();
    expect(api.runtime.sendMessage).toHaveBeenCalledWith({ type: 'listModels', provider: 'gemini' });
    expect(modelOptions(document)).toEqual([
      { value: 'gemini-3.7-flash', label: 'Fast — gemini-3.7-flash' },
      { value: 'gemini-3.1-pro-preview', label: 'Pro — gemini-3.1-pro-preview' },
      { value: 'gemini-api-extra', label: 'API — gemini-api-extra' }
    ]);
    expect(document.querySelector('#fetch-models').textContent).toBe('Model list updated');
    expect(document.querySelector('#model-refresh-help').textContent).toContain('Model list updated. 2 models are available');
  });

  it('explains that a key is required and never contacts a provider without one', async () => {
    const { document, api, controller } = setup();
    await controller.ready;
    const provider = document.querySelector('#provider');
    provider.value = 'openai';
    provider.dispatchEvent(new document.defaultView.Event('change'));

    await controller.fetchModels();

    expect(document.querySelector('#model-refresh-help').textContent).toContain('Add an API key for OpenAI');
    expect(document.querySelector('#status').textContent).toContain('Add an API key for OpenAI');
    expect(document.querySelector('#fetch-models').textContent).toBe('API key required');
    expect(document.querySelector('#model-refresh-help').textContent).toContain('API key required');
    expect(api.runtime.sendMessage).not.toHaveBeenCalledWith({ type: 'listModels', provider: 'openai' });
  });

  it('shows provider-request and completion progress in the refresh button', async () => {
    const { document, api, controller } = setup();
    await controller.ready;
    let completeRequest;
    api.runtime.sendMessage.mockImplementation(async (message) => {
      if (message.type === 'listModels') return new Promise((resolve) => { completeRequest = resolve; });
      if (message.type === 'getSettings') return { ok: true, settings: {
        provider: 'gemini', models: {}, configuredProviders: { gemini: true }, targetLanguage: 'auto', customPrompt: ''
      } };
      return { ok: true };
    });

    const refresh = controller.fetchModels();
    await vi.waitFor(() => expect(document.querySelector('#fetch-models').textContent).toBe('Contacting Google Gemini…'));
    expect(document.querySelector('#model-refresh-help').textContent).toContain('Contacting Google Gemini');
    completeRequest({ ok: true, models: ['gemini-new'] });
    await refresh;

    expect(document.querySelector('#fetch-models').textContent).toBe('Model list updated');
    expect(document.querySelector('#status').textContent).toContain('1 models loaded');
  });

  it('preserves each provider model when switching providers', async () => {
    const { document, controller } = setup();
    await controller.ready;
    const provider = document.querySelector('#provider');
    const model = document.querySelector('#model');
    provider.value = 'openai';
    provider.dispatchEvent(new document.defaultView.Event('change'));
    expect(modelOptions(document)).toEqual([
      { value: 'gpt-5.6-terra', label: 'Fast — gpt-5.6-terra' },
      { value: 'gpt-5.6-sol', label: 'Pro — gpt-5.6-sol' }
    ]);
    model.value = 'gpt-5.6-sol';
    provider.value = 'gemini';
    provider.dispatchEvent(new document.defaultView.Event('change'));
    expect(model.value).toBe('gemini-3.1-pro-preview');
    provider.value = 'openai';
    provider.dispatchEvent(new document.defaultView.Event('change'));
    expect(model.value).toBe('gpt-5.6-sol');
  });

  it('resets the prompt and clears local data after confirmation', async () => {
    const { document, api, controller } = setup();
    await controller.ready;
    controller.resetPrompt();
    expect(document.querySelector('#prompt').value).toBe(DEFAULT_SUMMARY_PROMPT);
    await controller.clearData();
    expect(api.runtime.sendMessage).toHaveBeenLastCalledWith({ type: 'clearData' });
    expect(document.querySelector('#status').textContent).toContain('cleared');
  });
});
