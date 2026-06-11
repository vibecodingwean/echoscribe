const summarizeButton = document.getElementById("summarize");
const copyButton = document.getElementById("copy");
const languageSelect = document.getElementById("summary-language");
const statusEl = document.getElementById("status");
const summaryEl = document.getElementById("summary");
const providerEl = document.getElementById("provider");
const extensionApi = typeof browser !== "undefined" ? browser : chrome;
const usesPromiseApi = typeof browser !== "undefined";

summarizeButton.addEventListener("click", summarize);
copyButton.addEventListener("click", copySummary);
languageSelect.addEventListener("change", saveLanguagePreference);

loadLatest();

async function loadLatest() {
  const state = await getLocalStorage([
    "latestSummary",
    "latestProvider",
    "latestModel",
    "latestError",
    "summaryTargetLanguageCode"
  ]);
  languageSelect.value = normalizeLanguageCode(state.summaryTargetLanguageCode);
  if (state.latestSummary) {
    summaryEl.textContent = state.latestSummary;
    providerEl.textContent = [state.latestProvider, state.latestModel].filter(Boolean).join(" / ");
  }
  if (state.latestError) statusEl.textContent = state.latestError;
}

async function summarize() {
  const targetLanguageCode = normalizeLanguageCode(languageSelect.value);
  setBusy(true, targetLanguageCode === "auto" ? "Summarizing..." : `Summarizing (${targetLanguageCode.toUpperCase()})...`);
  try {
    await setLocalStorage({ summaryTargetLanguageCode: targetLanguageCode });
    const response = await sendRuntimeMessage({
      type: "summarizeActiveTab",
      targetLanguageCode
    });
    if (!response || response.ok === false) throw new Error(response?.error || "Summary failed.");
    summaryEl.textContent = response.summary || "";
    providerEl.textContent = [response.provider, response.model].filter(Boolean).join(" / ");
    statusEl.textContent = "Done";
  } catch (error) {
    statusEl.textContent = error.message || String(error);
  } finally {
    setBusy(false);
  }
}

async function saveLanguagePreference() {
  await setLocalStorage({ summaryTargetLanguageCode: normalizeLanguageCode(languageSelect.value) });
}

function normalizeLanguageCode(value) {
  const code = String(value || "").trim().toLowerCase();
  return code || "auto";
}

async function copySummary() {
  const text = summaryEl.textContent.trim();
  if (!text) return;
  await navigator.clipboard.writeText(text);
  statusEl.textContent = "Copied";
}

function setBusy(busy, message = "") {
  summarizeButton.disabled = busy;
  copyButton.disabled = busy;
  languageSelect.disabled = busy;
  if (message) statusEl.textContent = message;
}

function getLocalStorage(keys) {
  if (usesPromiseApi) {
    return extensionApi.storage.local.get(keys);
  }
  return new Promise((resolve, reject) => {
    chrome.storage.local.get(keys, (value) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) reject(new Error(lastError.message));
      else resolve(value);
    });
  });
}

function setLocalStorage(value) {
  if (usesPromiseApi) {
    return extensionApi.storage.local.set(value);
  }
  return new Promise((resolve, reject) => {
    chrome.storage.local.set(value, () => {
      const lastError = chrome.runtime.lastError;
      if (lastError) reject(new Error(lastError.message));
      else resolve();
    });
  });
}

function sendRuntimeMessage(message) {
  if (usesPromiseApi) {
    return extensionApi.runtime.sendMessage(message);
  }
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(message, (response) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) reject(new Error(lastError.message));
      else resolve(response);
    });
  });
}
