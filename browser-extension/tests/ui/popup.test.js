import { JSDOM } from 'jsdom';
import { describe, expect, it, vi } from 'vitest';
import { bindPopup } from '../../src/popup/popup.js';

function popupDocument() {
  return new JSDOM(`<body>
    <span id="provider-model"></span><select id="language"><option value="auto">Auto</option><option value="de">DE</option></select>
    <button id="summarize"></button><button id="retry"></button><button id="copy"></button><button id="settings"></button>
    <div id="status"></div><article id="summary"></article>
    <dialog id="pdf-confirm"><button id="pdf-ok"></button><button id="pdf-cancel"></button></dialog>
  </body>`).window.document;
}

function setup(response = { ok: true, summary: 'New summary', provider: 'openai', model: 'gpt-test' }, options = {}) {
  const document = popupDocument();
  const api = {
    tabs: { query: vi.fn(async () => [options.tab || { id: 7, url: 'https://example.com/article', title: 'Article' }]) },
    storage: { local: { get: vi.fn(async () => ({ latestSummary: 'Old summary', latestProvider: 'xai', latestModel: 'grok', summaryTargetLanguage: 'de' })), set: vi.fn(async () => {}) } },
    runtime: { sendMessage: vi.fn(async (message) => message.type === 'getSummaryReadiness'
      ? { ok: true, provider: 'openai', configured: true }
      : response), openOptionsPage: vi.fn(async () => {}) }
  };
  const clipboard = { writeText: vi.fn(async () => {}) };
  const confirmAction = options.confirmAction || vi.fn(() => true);
  const loadPdfPayload = options.loadPdfPayload || vi.fn(async () => ({ title: 'PDF', text: 'PDF text' }));
  return { document, api, clipboard, confirmAction, loadPdfPayload, controller: bindPopup(document, api, clipboard, { confirmAction, loadPdfPayload }) };
}

describe('popup', () => {
  it('loads the latest local summary and language preference', async () => {
    const { document, controller } = setup();
    await controller.ready;
    expect(document.querySelector('#summary').textContent).toBe('Old summary');
    expect(document.querySelector('#provider-model').textContent).toBe('xAI / grok');
    expect(document.querySelector('#language').value).toBe('de');
    expect(document.querySelector('#status').textContent).toBe('Done');
  });

  it('requests a summary and renders provider/model reporting', async () => {
    const { document, api, controller } = setup();
    await controller.ready;
    await controller.summarize();
    expect(api.runtime.sendMessage).toHaveBeenCalledWith({ type: 'getSummaryReadiness' });
    expect(api.runtime.sendMessage).toHaveBeenCalledWith({ type: 'summarizeActiveTab', targetLanguage: 'de' });
    expect(document.querySelector('#summary').textContent).toBe('New summary');
    expect(document.querySelector('#provider-model').textContent).toBe('OpenAI / gpt-test');
    expect(document.querySelector('#status').textContent).toBe('Done');
  });

  it('cancels a PDF summary before loading or transmitting PDF content', async () => {
    const { api, confirmAction, loadPdfPayload, controller } = setup(undefined, {
      tab: { id: 7, url: 'https://example.com/report.pdf', title: 'report.pdf' },
      confirmAction: vi.fn(() => false)
    });
    await controller.ready;
    await controller.summarize();
    expect(confirmAction).toHaveBeenCalledWith(expect.stringContaining('AI provider'));
    expect(loadPdfPayload).not.toHaveBeenCalled();
    expect(api.runtime.sendMessage).toHaveBeenCalledTimes(1);
    expect(api.runtime.sendMessage).toHaveBeenCalledWith({ type: 'getSummaryReadiness' });
  });

  it('loads a confirmed PDF locally and submits only its extracted payload', async () => {
    const tab = { id: 7, url: 'https://example.com/report.pdf', title: 'report.pdf' };
    const loadPdfPayload = vi.fn(async () => ({ title: 'report.pdf', description: '', selection: '', text: 'Extracted PDF text' }));
    const { api, controller } = setup(undefined, { tab, loadPdfPayload });
    await controller.ready;
    await controller.summarize();
    expect(loadPdfPayload).toHaveBeenCalledWith(tab, api);
    expect(api.runtime.sendMessage).toHaveBeenCalledWith({
      type: 'summarizePayload', targetLanguage: 'de',
      page: { title: 'report.pdf', description: '', selection: '', text: 'Extracted PDF text' }
    });
  });

  it('uses the in-product PDF dialog when no confirmation adapter is injected', async () => {
    const document = popupDocument();
    const dialog = document.querySelector('#pdf-confirm');
    dialog.showModal = vi.fn();
    dialog.close = vi.fn();
    const api = {
      tabs: { query: vi.fn(async () => [{ id: 7, url: 'https://example.com/report.pdf', title: 'report.pdf' }]) },
      storage: { local: { get: vi.fn(async () => ({})), set: vi.fn(async () => {}) } },
      runtime: { sendMessage: vi.fn(async (message) => message.type === 'getSummaryReadiness'
        ? { ok: true, provider: 'openai', configured: true }
        : { ok: true }), openOptionsPage: vi.fn() }
    };
    const loadPdfPayload = vi.fn();
    const controller = bindPopup(document, api, { writeText: vi.fn() }, { loadPdfPayload });
    await controller.ready;
    const pending = controller.summarize();
    await vi.waitFor(() => expect(dialog.showModal).toHaveBeenCalledOnce());
    document.querySelector('#pdf-cancel').click();
    await pending;
    expect(dialog.close).toHaveBeenCalledOnce();
    expect(loadPdfPayload).not.toHaveBeenCalled();
    expect(api.runtime.sendMessage).toHaveBeenCalledTimes(1);
    expect(api.runtime.sendMessage).toHaveBeenCalledWith({ type: 'getSummaryReadiness' });
  });

  it('surfaces a local PDF parsing failure without sending content or rejecting the UI action', async () => {
    const loadPdfPayload = vi.fn(async () => { throw new Error('PDF could not be read locally.'); });
    const { document, api, controller } = setup(undefined, {
      tab: { id: 7, url: 'https://example.com/report.pdf', title: 'report.pdf' },
      loadPdfPayload
    });
    await controller.ready;
    await expect(controller.summarize()).resolves.toBeUndefined();
    expect(document.querySelector('#status').textContent).toContain('could not be read');
    expect(api.runtime.sendMessage).toHaveBeenCalledTimes(1);
    expect(api.runtime.sendMessage).toHaveBeenCalledWith({ type: 'getSummaryReadiness' });
  });

  it('surfaces failures, supports retry, copy, and settings navigation', async () => {
    const { document, api, clipboard, controller } = setup({ ok: false, error: 'Configure an API key.' });
    await controller.ready;
    await controller.summarize();
    expect(document.querySelector('#status').textContent).toContain('Configure');
    expect(document.querySelector('#retry').hidden).toBe(false);
    api.runtime.sendMessage
      .mockResolvedValueOnce({ ok: true, provider: 'openai', configured: true })
      .mockResolvedValueOnce({ ok: true, summary: 'Retried', provider: 'openai', model: 'gpt-test' });
    await controller.retry();
    expect(api.runtime.sendMessage).toHaveBeenLastCalledWith({ type: 'summarizeActiveTab', targetLanguage: 'de' });
    document.querySelector('#summary').textContent = 'Copy me';
    await controller.copy();
    expect(clipboard.writeText).toHaveBeenCalledWith('Copy me');
    await controller.openSettings();
    expect(api.runtime.openOptionsPage).toHaveBeenCalled();
  });

  it('rejects a missing API key before reading the active tab or extracting page content', async () => {
    const { document, api, controller } = setup();
    api.runtime.sendMessage.mockImplementation(async (message) => {
      if (message.type === 'getSummaryReadiness') return { ok: true, provider: 'openai', configured: false };
      return { ok: true };
    });
    await controller.ready;
    await controller.summarize();

    expect(document.querySelector('#status').textContent).toBe('An API key is required for the selected provider.');
    expect(document.querySelector('#retry').hidden).toBe(true);
    expect(api.tabs.query).not.toHaveBeenCalled();
    expect(api.runtime.sendMessage).toHaveBeenCalledTimes(1);
  });

  it('does not offer an in-memory retry after reopening on a persisted error', async () => {
    const document = popupDocument();
    const api = {
      tabs: { query: vi.fn(async () => [{ id: 7, url: 'https://example.com/article', title: 'Article' }]) },
      storage: { local: { get: vi.fn(async () => ({ latestError: 'Previous failure' })), set: vi.fn(async () => {}) } },
      runtime: { sendMessage: vi.fn(), openOptionsPage: vi.fn() }
    };
    const controller = bindPopup(document, api, { writeText: vi.fn() }, { confirmAction: vi.fn(() => true), loadPdfPayload: vi.fn() });
    await controller.ready;
    expect(document.querySelector('#status').textContent).toBe('Previous failure');
    expect(document.querySelector('#retry').hidden).toBe(true);
  });
});
