const summarizeButton = document.getElementById("summarize");
const copyButton = document.getElementById("copy");
const statusEl = document.getElementById("status");
const summaryEl = document.getElementById("summary");
const providerEl = document.getElementById("provider");
const extensionApi = typeof browser !== "undefined" ? browser : chrome;
const usesPromiseApi = typeof browser !== "undefined";

summarizeButton.addEventListener("click", summarize);
copyButton.addEventListener("click", copySummary);

loadLatest();

async function loadLatest() {
  const state = await getLocalStorage([
    "latestSummary",
    "latestProvider",
    "latestModel",
    "latestError"
  ]);
  if (state.latestSummary) {
    summaryEl.textContent = state.latestSummary;
    providerEl.textContent = [state.latestProvider, state.latestModel].filter(Boolean).join(" / ");
  }
  if (state.latestError) statusEl.textContent = state.latestError;
}

async function summarize() {
  setBusy(true, "Summarizing...");
  try {
    const response = await sendRuntimeMessage({ type: "summarizeActiveTab" });
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

async function copySummary() {
  const text = summaryEl.textContent.trim();
  if (!text) return;
  await navigator.clipboard.writeText(text);
  statusEl.textContent = "Copied";
}

function setBusy(busy, message = "") {
  summarizeButton.disabled = busy;
  copyButton.disabled = busy;
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
