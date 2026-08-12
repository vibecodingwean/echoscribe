import { PROVIDERS } from '../shared/constants.js';
import { DEFAULT_SUMMARY_PROMPT } from '../shared/prompt.js';
import { defaultSettings, normalizeSettings } from '../shared/settings.js';

function normalizePublicSettings(value = {}) {
  const normalized = normalizeSettings(value);
  const visible = { ...normalized };
  delete visible.apiKeys;
  return {
    ...visible,
    configuredProviders: Object.fromEntries(
      Object.keys(PROVIDERS).map((id) => [id, Boolean(value.configuredProviders?.[id])])
    )
  };
}

export function bindOptions(document, api, confirmAction = (message) => window.confirm(message)) {
  const ids = [
    'provider', 'api-key', 'key-status', 'clear-key', 'model',
    'fetch-models', 'model-refresh-help', 'prompt', 'reset-prompt', 'save', 'clear-data', 'status'
  ];
  const elements = Object.fromEntries(ids.map((id) => [id, document.getElementById(id)]));
  let settings = normalizePublicSettings(defaultSettings());
  let renderedProvider = settings.provider;
  let restoreRefreshLabelTimer = 0;

  for (const [id, provider] of Object.entries(PROVIDERS)) {
    const option = document.createElement('option');
    option.value = id;
    option.textContent = provider.label;
    elements.provider.append(option);
  }

  function captureCurrentProvider(provider = renderedProvider) {
    if (!provider) return;
    const model = elements.model.value.trim();
    if (model) settings.models[provider] = model;
  }

  function renderProvider() {
    const provider = elements.provider.value;
    renderedProvider = provider;
    elements['api-key'].value = '';
    elements['api-key'].placeholder = settings.configuredProviders[provider]
      ? 'Configured — enter a replacement only'
      : 'Enter a dedicated provider API key';
    elements['key-status'].textContent = settings.configuredProviders[provider]
      ? 'API key configured locally'
      : 'No API key configured';
    elements['clear-key'].disabled = !settings.configuredProviders[provider];
    elements['model-refresh-help'].textContent = settings.configuredProviders[provider]
      ? 'Refreshes the live model list for this provider. It sends the key but no page content.'
      : `An API key for ${PROVIDERS[provider].label} is required to refresh its live model list.`;
    const selectedModel = settings.models[provider] || PROVIDERS[provider].defaultModel;
    elements.model.replaceChildren();
    for (const model of PROVIDERS[provider].models) {
      const option = document.createElement('option');
      option.value = model.id;
      option.textContent = `${model.tier} — ${model.id}`;
      elements.model.append(option);
    }
    if (![...elements.model.options].some((option) => option.value === selectedModel)) {
      const option = document.createElement('option');
      option.value = selectedModel;
      option.textContent = `Custom — ${selectedModel}`;
      elements.model.append(option);
    }
    elements.model.value = selectedModel;
  }

  function applyPublicSettings(value) {
    settings = normalizePublicSettings(value);
    elements.provider.value = settings.provider;
    elements.prompt.value = settings.customPrompt || DEFAULT_SUMMARY_PROMPT;
    renderProvider();
  }

  const ready = api.runtime.sendMessage({ type: 'getSettings' }).then((response) => {
    if (!response?.ok) throw new Error(response?.error || 'Settings could not be loaded.');
    applyPublicSettings(response.settings);
  }).catch((error) => { elements.status.textContent = error?.message || String(error); });

  async function save() {
    captureCurrentProvider();
    const provider = elements.provider.value;
    settings.provider = provider;
    settings.customPrompt = elements.prompt.value.trim() === DEFAULT_SUMMARY_PROMPT
      ? ''
      : elements.prompt.value.trim();
    const replacement = elements['api-key'].value.trim();
    const message = { type: 'saveSettings', settings };
    if (replacement) message.apiKey = { provider, value: replacement };
    const response = await api.runtime.sendMessage(message);
    if (!response?.ok) throw new Error(response?.error || 'Settings could not be saved.');
    applyPublicSettings(response.settings || settings);
    elements.status.textContent = 'Settings saved locally.';
  }

  async function fetchModels() {
    const provider = elements.provider.value;
    const label = PROVIDERS[provider].label;
    const replacement = elements['api-key'].value.trim();
    if (!settings.configuredProviders[provider] && !replacement) {
      elements.status.textContent = `Add an API key for ${label} before refreshing the model list.`;
      showRefreshProgress('API key required', `API key required. Add an API key for ${label} before refreshing.`);
      restoreRefreshButton();
      return;
    }

    try {
      showRefreshProgress('Saving API key…', `Saving the ${label} API key locally…`);
      await save();
      showRefreshProgress(`Contacting ${label}…`, `Contacting ${label} to retrieve its live model list…`);
      const response = await api.runtime.sendMessage({ type: 'listModels', provider });
      if (!response?.ok) throw new Error(response?.error || 'Models could not be loaded.');

      const selectedModel = elements.model.value;
      const existing = new Set([...elements.model.options].map((option) => option.value));
      for (const model of response.models) {
        if (existing.has(model)) continue;
        const option = document.createElement('option');
        option.value = model;
        option.textContent = `API — ${model}`;
        elements.model.append(option);
        existing.add(model);
      }
      elements.model.value = selectedModel;
      elements.status.textContent = `${response.models.length} models loaded.`;
      showRefreshProgress('Model list updated', `Model list updated. ${response.models.length} models are available.`);
    } catch (error) {
      elements.status.textContent = error?.message || 'Models could not be loaded.';
      showRefreshProgress('Refresh failed', `Refresh failed. ${elements.status.textContent}`);
    } finally {
      restoreRefreshButton();
    }
  }

  function showRefreshProgress(label, detail) {
    elements['fetch-models'].textContent = label;
    elements['fetch-models'].disabled = true;
    elements['model-refresh-help'].textContent = detail;
  }

  function restoreRefreshButton() {
    if (restoreRefreshLabelTimer) clearTimeout(restoreRefreshLabelTimer);
    restoreRefreshLabelTimer = setTimeout(() => {
      elements['fetch-models'].textContent = 'Refresh model list';
      elements['fetch-models'].disabled = false;
      restoreRefreshLabelTimer = 0;
    }, 1600);
  }

  function resetPrompt() {
    elements.prompt.value = DEFAULT_SUMMARY_PROMPT;
    elements.status.textContent = 'Default prompt restored. Save to apply.';
  }

  async function clearProviderKey() {
    const provider = elements.provider.value;
    if (!confirmAction(`Remove the saved ${PROVIDERS[provider].label} API key?`)) return;
    const response = await api.runtime.sendMessage({ type: 'clearProviderKey', provider });
    if (!response?.ok) throw new Error(response?.error || 'API key could not be cleared.');
    applyPublicSettings(response.settings || settings);
    elements.status.textContent = 'Provider API key cleared.';
  }

  async function clearData() {
    if (!confirmAction('Clear all EchoScribe settings, API keys, and summaries?')) return;
    const response = await api.runtime.sendMessage({ type: 'clearData' });
    if (!response?.ok) throw new Error(response?.error || 'Data could not be cleared.');
    applyPublicSettings(normalizePublicSettings(defaultSettings()));
    elements.status.textContent = 'All local data cleared.';
  }

  elements.provider.addEventListener('change', () => {
    captureCurrentProvider(renderedProvider);
    settings.provider = elements.provider.value;
    renderProvider();
  });
  elements['fetch-models'].addEventListener('click', fetchModels);
  elements['reset-prompt'].addEventListener('click', resetPrompt);
  elements['clear-key'].addEventListener('click', clearProviderKey);
  elements.save.addEventListener('click', save);
  elements['clear-data'].addEventListener('click', clearData);

  return { ready, save, fetchModels, resetPrompt, clearProviderKey, clearData };
}
