import { listProviderModels } from '../providers/index.js';
import { safeMessage } from '../providers/common.js';
import { normalizeSettings, publicSettings } from '../shared/settings.js';

const MENU_ID = 'echoscribe-summarize';

export function installBackground({ api, orchestrator, listModels = listProviderModels }) {
  let settingsMutation = Promise.resolve();
  function mutateSettings(action) {
    const result = settingsMutation.then(action);
    settingsMutation = result.catch(() => {});
    return result;
  }

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
      await settingsMutation;
      await orchestrator.summarizeTab(tab, info.selectionText || '', '');
    } catch (error) {
      await api.storage.local.set({ latestError: safeMessage(error?.message || error) });
      if (String(error?.message || '').includes('review provider data transfer')) {
        try { await api.action?.openPopup?.(); } catch { /* The popup remains available from the toolbar. */ }
      }
    }
  });

  async function handleMessage(message) {
    try {
      if (message?.type === 'summarizeActiveTab') {
        await settingsMutation;
        return await orchestrator.summarizeActiveTab(message.targetLanguage || '');
      }
      if (message?.type === 'summarizePayload') {
        await settingsMutation;
        const page = {
          title: message.page?.title || '', description: message.page?.description || '',
          selection: message.page?.selection || '', text: message.page?.text || ''
        };
        return await orchestrator.summarizePayload(page, message.targetLanguage || '');
      }
      if (message?.type === 'listModels') {
        await settingsMutation;
        const settings = await orchestrator.readSettings();
        const provider = message.provider || settings.provider;
        if (!settings.providerConsent?.[provider]) return { ok: false, error: 'Allow this provider in Settings before refreshing models.' };
        const models = await listModels({ provider, apiKey: settings.apiKeys[provider] });
        return { ok: true, models };
      }
      if (message?.type === 'getSummaryReadiness') {
        await settingsMutation;
        const settings = await orchestrator.readSettings();
        const provider = settings.provider;
        return { ok: true, provider, configured: Boolean(settings.apiKeys[provider]), consented: Boolean(settings.providerConsent?.[provider]) };
      }
      if (message?.type === 'setProviderConsent') return await mutateSettings(async () => {
        const settings = normalizeSettings(await orchestrator.readSettings());
        const provider = String(message.provider || '');
        if (!Object.hasOwn(settings.providerConsent, provider)) return { ok: false, error: 'Unsupported provider.' };
        settings.providerConsent[provider] = message.allowed === true;
        await api.storage.local.set({ settings });
        return { ok: true, settings: publicSettings(settings) };
      });
      if (message?.type === 'getSettings') {
        await settingsMutation;
        return { ok: true, settings: publicSettings(await orchestrator.readSettings()) };
      }
      if (message?.type === 'saveSettings') return await mutateSettings(async () => {
        const current = await orchestrator.readSettings();
        const settings = normalizeSettings({
          ...current,
          ...message.settings,
          models: { ...current.models, ...message.settings?.models },
          apiKeys: current.apiKeys,
          providerConsent: current.providerConsent
        });
        const keyProvider = String(message.apiKey?.provider || '');
        if (Object.hasOwn(settings.apiKeys, keyProvider)) {
          const replacement = String(message.apiKey?.value || '').trim().slice(0, 10_000);
          if (replacement) settings.apiKeys[keyProvider] = replacement;
        }
        await api.storage.local.set({ settings });
        return { ok: true, settings: publicSettings(settings) };
      });
      if (message?.type === 'clearProviderKey') return await mutateSettings(async () => {
        const settings = await orchestrator.readSettings();
        const provider = String(message.provider || '');
        if (!Object.hasOwn(settings.apiKeys, provider)) return { ok: false, error: 'Unsupported provider.' };
        settings.apiKeys[provider] = '';
        await api.storage.local.set({ settings });
        return { ok: true, settings: publicSettings(settings) };
      });
      if (message?.type === 'clearData') return await mutateSettings(async () => {
        await api.storage.local.clear();
        return { ok: true };
      });
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
