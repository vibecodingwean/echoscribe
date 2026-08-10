import { listProviderModels } from '../providers/index.js';
import { safeMessage } from '../providers/common.js';
import { normalizeSettings, publicSettings } from '../shared/settings.js';

const MENU_ID = 'echoscribe-summarize';

export function installBackground({ api, orchestrator, listModels = listProviderModels }) {
  api.runtime.onInstalled.addListener(async () => {
    await api.contextMenus.removeAll();
    api.contextMenus.create({
      id: MENU_ID,
      title: 'Summarize with EchoScribe',
      contexts: ['page', 'selection']
    });
  });

  api.contextMenus.onClicked.addListener(async (info, tab) => {
    if (info.menuItemId !== MENU_ID || !tab) return;
    try {
      await orchestrator.summarizeTab(tab, info.selectionText || '', '');
    } catch {
      // The orchestrator stores a secret-safe error for the popup.
    }
  });

  async function handleMessage(message) {
    try {
      if (message?.type === 'summarizeActiveTab') return orchestrator.summarizeActiveTab(message.targetLanguage || '');
      if (message?.type === 'summarizePayload') {
        const page = {
          title: message.page?.title || '', description: message.page?.description || '',
          selection: message.page?.selection || '', text: message.page?.text || ''
        };
        return orchestrator.summarizePayload(page, message.targetLanguage || '');
      }
      if (message?.type === 'listModels') {
        const settings = await orchestrator.readSettings();
        const provider = message.provider || settings.provider;
        const models = await listModels({ provider, apiKey: settings.apiKeys[provider] });
        return { ok: true, models };
      }
      if (message?.type === 'getSettings') return { ok: true, settings: publicSettings(await orchestrator.readSettings()) };
      if (message?.type === 'saveSettings') {
        const current = await orchestrator.readSettings();
        const settings = normalizeSettings({
          ...current,
          ...message.settings,
          models: { ...current.models, ...message.settings?.models },
          apiKeys: current.apiKeys
        });
        const keyProvider = String(message.apiKey?.provider || '');
        if (Object.hasOwn(settings.apiKeys, keyProvider)) {
          const replacement = String(message.apiKey?.value || '').trim().slice(0, 10_000);
          if (replacement) settings.apiKeys[keyProvider] = replacement;
        }
        await api.storage.local.set({ settings });
        return { ok: true, settings: publicSettings(settings) };
      }
      if (message?.type === 'clearProviderKey') {
        const settings = await orchestrator.readSettings();
        const provider = String(message.provider || '');
        if (!Object.hasOwn(settings.apiKeys, provider)) return { ok: false, error: 'Unsupported provider.' };
        settings.apiKeys[provider] = '';
        await api.storage.local.set({ settings });
        return { ok: true, settings: publicSettings(settings) };
      }
      if (message?.type === 'clearData') {
        await api.storage.local.clear();
        return { ok: true };
      }
      return { ok: false, error: 'Unsupported request.' };
    } catch (error) {
      return { ok: false, error: safeMessage(error?.message || error) };
    }
  }

  api.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    handleMessage(message).then(sendResponse);
    return true;
  });
}
