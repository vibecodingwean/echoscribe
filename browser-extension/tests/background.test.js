import { describe, expect, it, vi } from 'vitest';
import { installBackground } from '../src/background/service-worker.js';

function event() {
  let listener;
  return {
    addListener: vi.fn((value) => { listener = value; }),
    fire: (...args) => {
      if (listener.length < 3) return listener(...args);
      return new Promise((resolve, reject) => {
        const returned = listener(...args, {}, resolve);
        if (returned !== true) Promise.resolve(returned).then(resolve, reject);
      });
    },
    invoke: (...args) => listener(...args)
  };
}

function setup() {
  const onInstalled = event();
  const onClicked = event();
  const onMessage = event();
  const api = {
    runtime: { onInstalled, onMessage },
    contextMenus: { create: vi.fn(), removeAll: vi.fn(async () => {}), onClicked },
    storage: { local: { get: vi.fn(async () => ({ settings: {} })), set: vi.fn(async () => {}), clear: vi.fn(async () => {}) } }
  };
  const orchestrator = {
    summarizeActiveTab: vi.fn(async () => ({ ok: true })),
    summarizePayload: vi.fn(async () => ({ ok: true })),
    summarizeTab: vi.fn(async () => ({ ok: true })),
    retryLatest: vi.fn(async () => ({ ok: true })),
    readSettings: vi.fn(async () => ({ provider: 'openai', apiKeys: { openai: 'key' } }))
  };
  const listModels = vi.fn(async () => ['model-a']);
  installBackground({ api, orchestrator, listModels });
  return { api, onInstalled, onClicked, onMessage, orchestrator, listModels };
}

describe('background event wiring', () => {
  it('creates page and selection context menu entries on install', async () => {
    const { api, onInstalled } = setup();
    await onInstalled.fire();
    expect(api.contextMenus.removeAll).toHaveBeenCalled();
    expect(api.contextMenus.create).toHaveBeenCalledWith(expect.objectContaining({ id: 'echoscribe-summarize', contexts: ['page', 'selection'] }));
  });

  it('summarizes context-menu selections', async () => {
    const { onClicked, orchestrator } = setup();
    await onClicked.fire({ menuItemId: 'echoscribe-summarize', selectionText: 'Chosen' }, { id: 9 });
    expect(orchestrator.summarizeTab).toHaveBeenCalledWith({ id: 9 }, 'Chosen', '');
  });

  it('routes popup summary messages', async () => {
    const { onMessage, orchestrator } = setup();
    await expect(onMessage.fire({ type: 'summarizeActiveTab', targetLanguage: 'fr' })).resolves.toEqual({ ok: true });
    expect(orchestrator.summarizeActiveTab).toHaveBeenCalledWith('fr');
  });

  it('rejects obsolete retry messages instead of retaining raw content', async () => {
    const { onMessage } = setup();
    await expect(onMessage.fire({ type: 'retrySummary' })).resolves.toEqual({ ok: false, error: 'Unsupported request.' });
  });

  it('keeps Chromium message channels open and replies through sendResponse', async () => {
    const { onMessage } = setup();
    const sendResponse = vi.fn();
    const returned = onMessage.invoke({ type: 'summarizeActiveTab', targetLanguage: 'fr' }, {}, sendResponse);
    expect(returned).toBe(true);
    await vi.waitFor(() => expect(sendResponse).toHaveBeenCalledWith({ ok: true }));
  });

  it('routes an already extracted PDF payload without a URL', async () => {
    const { onMessage, orchestrator } = setup();
    const page = { title: 'report.pdf', description: '', selection: '', text: 'PDF text' };
    await expect(onMessage.fire({ type: 'summarizePayload', page, targetLanguage: 'de' })).resolves.toEqual({ ok: true });
    expect(orchestrator.summarizePayload).toHaveBeenCalledWith(page, 'de');
  });

  it('lists models using only the selected stored provider credentials', async () => {
    const { onMessage, listModels } = setup();
    await expect(onMessage.fire({ type: 'listModels', provider: 'openai' })).resolves.toEqual({ ok: true, models: ['model-a'] });
    expect(listModels).toHaveBeenCalledWith({ provider: 'openai', apiKey: 'key' });
  });

  it('returns settings metadata without exposing stored API keys', async () => {
    const { onMessage } = setup();
    const response = await onMessage.fire({ type: 'getSettings' });
    expect(response.ok).toBe(true);
    expect(response.settings).not.toHaveProperty('apiKeys');
    expect(response.settings.configuredProviders.openai).toBe(true);
    expect(JSON.stringify(response)).not.toContain('key');
  });

  it('updates one key without accepting or exposing an aggregate credential map', async () => {
    const { onMessage, api } = setup();
    const response = await onMessage.fire({
      type: 'saveSettings',
      settings: { provider: 'openai', models: { openai: 'gpt-user' }, customPrompt: 'Concise' },
      apiKey: { provider: 'openai', value: 'replacement-key' }
    });
    const persisted = api.storage.local.set.mock.calls[0][0].settings;
    expect(persisted.apiKeys.openai).toBe('replacement-key');
    expect(response.settings).not.toHaveProperty('apiKeys');
    expect(response.settings.configuredProviders.openai).toBe(true);
  });

  it('clears one provider key without clearing other settings', async () => {
    const { onMessage, api } = setup();
    const response = await onMessage.fire({ type: 'clearProviderKey', provider: 'openai' });
    const persisted = api.storage.local.set.mock.calls[0][0].settings;
    expect(persisted.apiKeys.openai).toBe('');
    expect(response.settings.configuredProviders.openai).toBe(false);
  });

  it('clears all local extension data on request', async () => {
    const { onMessage, api } = setup();
    await expect(onMessage.fire({ type: 'clearData' })).resolves.toEqual({ ok: true });
    expect(api.storage.local.clear).toHaveBeenCalled();
  });
});
