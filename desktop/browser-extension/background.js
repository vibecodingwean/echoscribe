const HOST_NAME = "de.echoscribe.nativehost";
const PDF_BYTE_LIMIT = 16 * 1024 * 1024;
const DEFAULT_TARGET_LANGUAGE_CODE = "auto";
const extensionApi = typeof browser !== "undefined" ? browser : chrome;
const usesPromiseApi = typeof browser !== "undefined";

extensionApi.runtime.onInstalled.addListener(() => {
  extensionApi.contextMenus.create({
    id: "echoscribe-summarize",
    title: "Summarize with EchoScribe",
    contexts: ["page", "selection"]
  });
});

extensionApi.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== "echoscribe-summarize" || !tab) return;
  summarizeTab(tab, info.selectionText || "").catch(async (error) => {
    await setLocalStorage({
      latestSummary: "",
      latestError: error.message || String(error),
      latestUpdatedAt: Date.now()
    });
  });
});

extensionApi.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "summarizeActiveTab") return false;

  const response = summarizeActiveTab(message.targetLanguageCode || "")
    .catch((error) => ({ ok: false, error: error.message || String(error) }));

  if (usesPromiseApi) {
    return response;
  }

  response.then((value) => sendResponse(value));

  return true;
});

async function summarizeActiveTab(targetLanguageCode = "") {
  const [tab] = await queryTabs({ active: true, currentWindow: true });
  if (!tab) throw new Error("No active tab found.");
  return summarizeTab(tab, "", targetLanguageCode);
}

async function summarizeTab(tab, selectionText, targetLanguageCode = "") {
  if (!tab.id) throw new Error("The active tab cannot be accessed.");

  const result = await buildPagePayload(tab, selectionText);
  const resolvedLanguage = await resolveTargetLanguageCode(targetLanguageCode);

  const response = await sendNativeMessage({
    type: "summarize",
    targetLanguageCode: resolvedLanguage,
    ...result
  });

  await setLocalStorage({
    latestSummary: response.summary || "",
    latestProvider: response.provider || "",
    latestModel: response.model || "",
    latestUrl: result.url || "",
    latestTargetLanguageCode: resolvedLanguage,
    latestError: "",
    latestUpdatedAt: Date.now()
  });

  return response;
}

async function resolveTargetLanguageCode(requested) {
  const normalized = normalizeTargetLanguageCode(requested);
  if (normalized) return normalized;
  const state = await getLocalStorage(["summaryTargetLanguageCode"]);
  return normalizeTargetLanguageCode(state.summaryTargetLanguageCode) || DEFAULT_TARGET_LANGUAGE_CODE;
}

function normalizeTargetLanguageCode(value) {
  const code = String(value || "").trim().toLowerCase();
  if (!code) return "";
  return /^[a-z]{2,3}(-[a-z0-9]+)?$/i.test(code) ? code : DEFAULT_TARGET_LANGUAGE_CODE;
}

async function buildPagePayload(tab, selectionText) {
  let result = {
    url: tab.url || "",
    title: tab.title || "",
    description: "",
    selection: selectionText || "",
    text: ""
  };

  try {
    const [injection] = await executePageScript(tab.id, selectionText);
    if (injection?.result) result = injection.result;
  } catch (error) {
    result.text = "";
    result.injectionError = error.message || String(error);
  }

  if (shouldFetchPdf(result, tab)) {
    const pdf = await fetchPdfPayload(result.url || tab.url || "");
    result = {
      ...result,
      ...pdf,
      text: result.selection || result.text || ""
    };
  }

  return result;
}

function shouldFetchPdf(result, tab) {
  const url = result.url || tab.url || "";
  const title = result.title || tab.title || "";
  if (result.selection || (result.text && result.text.length > 500)) return false;
  return /\.pdf($|[?#])/i.test(url) || /\.pdf($|[?#])/i.test(title) || title.toLowerCase().includes(".pdf");
}

async function fetchPdfPayload(url) {
  if (/^file:\/\//i.test(url)) {
    return {
      mimeType: "application/pdf",
      pdfBase64: ""
    };
  }

  if (!/^https?:\/\//i.test(url)) {
    throw new Error("PDF text could not be extracted from this PDF URL.");
  }

  let response;
  try {
    response = await fetch(url, { credentials: "include" });
  } catch {
    return {
      mimeType: "application/pdf",
      pdfBase64: ""
    };
  }

  if (!response.ok) {
    return {
      mimeType: "application/pdf",
      pdfBase64: ""
    };
  }

  const contentType = response.headers.get("content-type") || "application/pdf";
  const blob = await response.blob();
  if (blob.size > PDF_BYTE_LIMIT) {
    throw new Error(`PDF is too large for local summarization (${Math.round(blob.size / 1024 / 1024)} MB).`);
  }

  const bytes = new Uint8Array(await blob.arrayBuffer());
  return {
    mimeType: contentType,
    pdfBase64: uint8ToBase64(bytes)
  };
}

function uint8ToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

function sendNativeMessage(payload) {
  if (usesPromiseApi) {
    return extensionApi.runtime.sendNativeMessage(HOST_NAME, payload).then(validateNativeResponse);
  }

  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_NAME, payload, (response) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) {
        reject(new Error(lastError.message));
        return;
      }
      try {
        resolve(validateNativeResponse(response));
      } catch (error) {
        reject(error);
      }
    });
  });
}

function validateNativeResponse(response) {
  if (!response) {
    throw new Error("EchoScribe Native Host returned no response.");
  }
  if (response.ok === false) {
    throw new Error(response.error || "EchoScribe summary failed.");
  }
  return response;
}

function queryTabs(query) {
  if (usesPromiseApi) {
    return extensionApi.tabs.query(query);
  }
  return new Promise((resolve, reject) => {
    chrome.tabs.query(query, (tabs) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) reject(new Error(lastError.message));
      else resolve(tabs);
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

function executePageScript(tabId, selectionText) {
  if (extensionApi.scripting?.executeScript) {
    if (usesPromiseApi) {
      return extensionApi.scripting.executeScript({
        target: { tabId },
        func: extractPagePayload,
        args: [selectionText]
      });
    }

    return new Promise((resolve, reject) => {
      chrome.scripting.executeScript({
        target: { tabId },
        func: extractPagePayload,
        args: [selectionText]
      }, (result) => {
        const lastError = chrome.runtime.lastError;
        if (lastError) reject(new Error(lastError.message));
        else resolve(result);
      });
    });
  }

  const code = `(${extractPagePayload.toString()})(${JSON.stringify(selectionText)})`;
  if (usesPromiseApi) {
    return extensionApi.tabs.executeScript(tabId, { code }).then((results) => {
      return (results || []).map((result) => ({ result }));
    });
  }

  return new Promise((resolve, reject) => {
    chrome.tabs.executeScript(tabId, { code }, (results) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) reject(new Error(lastError.message));
      else resolve((results || []).map((result) => ({ result })));
    });
  });
}

function extractPagePayload(selectionText) {
  const selection = (selectionText || String(window.getSelection() || "")).trim();
  const title = document.title || "";
  const description = document.querySelector('meta[name="description"]')?.content || "";
  const main =
    document.querySelector("article") ||
    document.querySelector("main") ||
    document.querySelector('[role="main"]') ||
    document.body;

  let text = selection || main?.innerText || document.body?.innerText || "";
  text = text.replace(/\s+/g, " ").trim();
  if (text.length > 120000) text = text.slice(0, 120000);

  return {
    url: location.href,
    title,
    description,
    selection,
    text
  };
}
