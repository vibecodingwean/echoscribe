const summarizeButton = document.getElementById("summarize");
const copyButton = document.getElementById("copy");
const statusEl = document.getElementById("status");
const summaryEl = document.getElementById("summary");
const providerEl = document.getElementById("provider");

summarizeButton.addEventListener("click", summarize);
copyButton.addEventListener("click", copySummary);

loadLatest();

async function loadLatest() {
  const state = await chrome.storage.local.get([
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
  setBusy(true, "Zusammenfassung laeuft...");
  try {
    const response = await chrome.runtime.sendMessage({ type: "summarizeActiveTab" });
    if (!response || response.ok === false) throw new Error(response?.error || "Zusammenfassung fehlgeschlagen.");
    summaryEl.textContent = response.summary || "";
    providerEl.textContent = [response.provider, response.model].filter(Boolean).join(" / ");
    statusEl.textContent = "Fertig";
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
  statusEl.textContent = "Kopiert";
}

function setBusy(busy, message = "") {
  summarizeButton.disabled = busy;
  copyButton.disabled = busy;
  if (message) statusEl.textContent = message;
}
