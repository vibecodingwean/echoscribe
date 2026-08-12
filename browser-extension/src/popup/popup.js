import { PROVIDERS } from '../shared/constants.js';
import { isWebPdfTab } from '../background/pdf.js';

export function bindPopup(document, api, clipboard = navigator.clipboard, {
  confirmAction,
  loadPdfPayload = async (tab, extensionApi) => {
    const parser = await import('/pdf-parser.js');
    return parser.loadPdfPayload(tab, extensionApi.runtime.getURL('vendor/pdf.worker.min.mjs'));
  }
} = {}) {
  const elements = Object.fromEntries(['provider-model', 'language', 'summarize', 'retry', 'copy', 'settings', 'status', 'summary', 'pdf-confirm', 'pdf-ok', 'pdf-cancel']
    .map((id) => [id, document.getElementById(id)]));

  const requestPdfConfirmation = confirmAction || (() => new Promise((resolve) => {
    const dialog = elements['pdf-confirm'];
    const finish = (accepted) => {
      elements['pdf-ok'].removeEventListener('click', accept);
      elements['pdf-cancel'].removeEventListener('click', cancel);
      dialog.removeEventListener('cancel', cancelEvent);
      dialog.close();
      resolve(accepted);
    };
    const accept = () => finish(true);
    const cancel = () => finish(false);
    const cancelEvent = (event) => { event.preventDefault(); finish(false); };
    elements['pdf-ok'].addEventListener('click', accept);
    elements['pdf-cancel'].addEventListener('click', cancel);
    dialog.addEventListener('cancel', cancelEvent);
    dialog.showModal();
  }));

  const providerLabel = (id) => PROVIDERS[id]?.label || id || '';
  const showResult = (result) => {
    elements.summary.textContent = result.summary || '';
    elements['provider-model'].textContent = [providerLabel(result.provider), result.model].filter(Boolean).join(' / ');
  };
  const setBusy = (busy, message = '') => {
    elements.summarize.disabled = busy;
    elements.retry.disabled = busy;
    elements.copy.disabled = busy;
    elements.language.disabled = busy;
    if (message) elements.status.textContent = message;
  };

  const ready = api.storage.local.get([
    'latestSummary', 'latestProvider', 'latestModel', 'latestError', 'summaryTargetLanguage'
  ]).then((state) => {
    elements.language.value = state.summaryTargetLanguage || 'auto';
    if (state.latestSummary) {
      showResult({ summary: state.latestSummary, provider: state.latestProvider, model: state.latestModel });
      elements.status.textContent = 'Done';
    }
    if (state.latestError) {
      elements.status.textContent = state.latestError;
      elements.retry.hidden = true;
    }
  });

  async function perform(message) {
    setBusy(true, 'Summarizing…');
    try {
      const result = await api.runtime.sendMessage(message);
      if (!result?.ok) throw new Error(result?.error || 'Summary failed.');
      showResult(result);
      elements.status.textContent = 'Done';
      elements.retry.hidden = true;
    } catch (error) {
      elements.status.textContent = error?.message || String(error);
      elements.retry.hidden = false;
    } finally {
      setBusy(false);
    }
  }

  async function summarize() {
    const targetLanguage = elements.language.value || 'auto';
    const readiness = await api.runtime.sendMessage({ type: 'getSummaryReadiness' });
    if (!readiness?.ok) {
      elements.status.textContent = readiness?.error || 'Summary settings could not be checked.';
      elements.retry.hidden = true;
      return;
    }
    if (!readiness.configured) {
      elements.status.textContent = 'An API key is required for the selected provider.';
      elements.retry.hidden = true;
      return;
    }
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    if (isWebPdfTab(tab)) {
      if (!await requestPdfConfirmation('The PDF text will be sent to your selected AI provider. Continue?')) {
        elements.status.textContent = 'Cancelled';
        return;
      }
      let page;
      setBusy(true, 'Reading PDF locally…');
      try {
        page = await loadPdfPayload(tab, api);
      } catch (error) {
        elements.status.textContent = error?.message || 'PDF could not be read locally.';
        elements.retry.hidden = true;
        return;
      } finally {
        setBusy(false);
      }
      await api.storage.local.set({ summaryTargetLanguage: targetLanguage });
      return perform({ type: 'summarizePayload', page, targetLanguage });
    }
    await api.storage.local.set({ summaryTargetLanguage: targetLanguage });
    return perform({ type: 'summarizeActiveTab', targetLanguage });
  }
  const retry = () => summarize();
  async function copy() {
    const value = elements.summary.textContent.trim();
    if (!value) return;
    await clipboard.writeText(value);
    elements.status.textContent = 'Copied';
  }
  const openSettings = () => api.runtime.openOptionsPage();

  elements.summarize.addEventListener('click', summarize);
  elements.retry.addEventListener('click', retry);
  elements.copy.addEventListener('click', copy);
  elements.settings.addEventListener('click', openSettings);
  elements.language.addEventListener('change', () => api.storage.local.set({ summaryTargetLanguage: elements.language.value || 'auto' }));

  return { ready, summarize, retry, copy, openSettings };
}
