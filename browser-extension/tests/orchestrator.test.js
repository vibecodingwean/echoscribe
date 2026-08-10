import { describe, expect, it, vi } from 'vitest';
import { createOrchestrator } from '../src/background/orchestrator.js';

function setup(overrides = {}) {
  const stored = { settings: {
    provider: 'anthropic', models: { anthropic: 'claude-user' },
    apiKeys: { anthropic: 'private-key' }, targetLanguage: 'auto', customPrompt: ''
  } };
  const api = {
    tabs: { query: vi.fn(async () => [{ id: 7, url: 'https://example.com', title: 'Page' }]) },
    scripting: { executeScript: vi.fn(async ({ args }) => [{ result: {
      url: 'https://example.com', title: 'Page', description: 'Description',
      selection: args[0], text: args[0] || 'Page body'
    } }]) },
    storage: { local: {
      get: vi.fn(async () => stored),
      set: vi.fn(async (value) => Object.assign(stored, value)),
      clear: vi.fn(async () => { for (const key of Object.keys(stored)) delete stored[key]; })
    } }
  };
  const summarizeProvider = vi.fn(async ({ provider, model }) => ({ summary: 'Short summary', provider, model }));
  const deps = {
    api,
    summarizeProvider,
    fetchPdfBytes: vi.fn(), extractPdfText: vi.fn(), pdfjs: {},
    now: () => 12345,
    ...overrides
  };
  return { api, stored, summarizeProvider, orchestrator: createOrchestrator(deps) };
}

describe('background orchestrator', () => {
  it('summarizes the active tab with persisted provider and model', async () => {
    const { orchestrator, summarizeProvider, stored } = setup();
    const result = await orchestrator.summarizeActiveTab('de');
    expect(result).toMatchObject({ ok: true, summary: 'Short summary', provider: 'anthropic', model: 'claude-user' });
    expect(summarizeProvider).toHaveBeenCalledWith(expect.objectContaining({
      provider: 'anthropic', model: 'claude-user', apiKey: 'private-key',
      prompt: expect.stringContaining('language code "de"')
    }));
    expect(stored).toMatchObject({ latestSummary: 'Short summary', latestProvider: 'anthropic', latestModel: 'claude-user', latestUpdatedAt: 12345, latestError: '' });
    expect(stored).not.toHaveProperty('latestUrl');
  });

  it('uses context-menu selection instead of full page text', async () => {
    const { orchestrator, api, summarizeProvider } = setup();
    await orchestrator.summarizeTab({ id: 7, url: 'https://example.com' }, 'Chosen selection', 'auto');
    expect(api.scripting.executeScript.mock.calls[0][0].args).toEqual(['Chosen selection']);
    expect(summarizeProvider.mock.calls[0][0].prompt).toContain('Text:\nChosen selection\n</page_content>');
  });

  it('requires the popup confirmation before downloading a browser-opened PDF', async () => {
    const fetchPdfBytes = vi.fn(async () => new Uint8Array([1]));
    const extractPdfText = vi.fn(async () => 'Local PDF text');
    const { orchestrator, summarizeProvider } = setup({ fetchPdfBytes, extractPdfText });
    await expect(orchestrator.summarizeTab({ id: 7, url: 'https://example.com/report.pdf', title: 'report.pdf' }))
      .rejects.toThrow('extension popup');
    expect(fetchPdfBytes).not.toHaveBeenCalled();
    expect(extractPdfText).not.toHaveBeenCalled();
    expect(summarizeProvider).not.toHaveBeenCalled();
  });

  it('does not retain a raw-content retry payload in service-worker memory', () => {
    const { orchestrator } = setup();
    expect(orchestrator).not.toHaveProperty('retryLatest');
  });

  it('removes web addresses from provider summaries before returning or storing them', async () => {
    const summarizeProvider = vi.fn(async () => ({
      summary: 'Department details: http://www.education.gov.yk.ca/ and Box 2703.',
      provider: 'anthropic', model: 'claude-user'
    }));
    const { orchestrator, stored } = setup({ summarizeProvider });
    const result = await orchestrator.summarizeActiveTab();
    expect(result.summary).not.toMatch(/https?:\/\/|www\./i);
    expect(stored.latestSummary).not.toMatch(/https?:\/\/|www\./i);
    expect(result.summary).toContain('Box 2703');
  });

  it('never stores or returns API keys in errors', async () => {
    const summarizeProvider = vi.fn(async () => { throw new Error('Rejected private-key'); });
    const { orchestrator, stored } = setup({ summarizeProvider });
    await expect(orchestrator.summarizeActiveTab()).rejects.not.toThrow('private-key');
    expect(stored.latestError).not.toContain('private-key');
    expect(stored.latestError).toContain('[redacted]');
  });
});
