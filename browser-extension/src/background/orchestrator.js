import { extractPagePayload } from '../content/extract-page.js';
import { summarizeWithProvider } from '../providers/index.js';
import { safeMessage } from '../providers/common.js';
import { buildSummaryPrompt } from '../shared/prompt.js';
import { normalizeSettings } from '../shared/settings.js';
import { stripWebAddresses } from '../shared/text.js';
import { isPdfCandidate } from './pdf.js';

export function createOrchestrator({
  api,
  summarizeProvider = summarizeWithProvider,
  now = Date.now
}) {

  async function readSettings() {
    const state = await api.storage.local.get('settings');
    return normalizeSettings(state.settings);
  }

  async function summarizePayload(page, targetLanguage) {
    const settings = await readSettings();
    const language = targetLanguage || settings.targetLanguage;
    const provider = settings.provider;
    const model = settings.models[provider];
    const apiKey = settings.apiKeys[provider];

    try {
      const providerResult = await summarizeProvider({
        provider, model, apiKey,
        prompt: buildSummaryPrompt(page, language, settings.customPrompt)
      });
      const result = { ...providerResult, summary: stripWebAddresses(providerResult.summary) };
      await api.storage.local.set({
        latestSummary: result.summary,
        latestProvider: result.provider,
        latestModel: result.model,
        latestTargetLanguage: language,
        latestError: '',
        latestUpdatedAt: now()
      });
      return { ok: true, ...result };
    } catch (error) {
      const message = safeMessage(error?.message || error, [apiKey]);
      await api.storage.local.set({ latestSummary: '', latestError: message, latestUpdatedAt: now() });
      throw new Error(message);
    }
  }

  async function buildPayload(tab, selectionText = '') {
    let page = {
      url: tab.url || '', title: tab.title || '', description: '',
      selection: selectionText || '', text: selectionText || ''
    };
    try {
      const results = await api.scripting.executeScript({
        target: { tabId: tab.id }, func: extractPagePayload, args: [selectionText]
      });
      if (results?.[0]?.result) page = results[0].result;
    } catch {
      // Browser PDF viewers and privileged pages may reject script injection.
    }
    if (isPdfCandidate(page, tab)) {
      throw new Error('Open the extension popup to review and confirm PDF transmission.');
    }
    return page;
  }

  async function summarizeTab(tab, selectionText = '', targetLanguage = '') {
    if (!tab?.id) throw new Error('The active tab cannot be accessed.');
    const page = await buildPayload(tab, selectionText);
    return summarizePayload(page, targetLanguage);
  }

  async function summarizeActiveTab(targetLanguage = '') {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    if (!tab) throw new Error('No active tab found.');
    return summarizeTab(tab, '', targetLanguage);
  }

  return { buildPayload, readSettings, summarizeActiveTab, summarizePayload, summarizeTab };
}
