const HOST_NAME = "de.echoscribe.nativehost";
const PDF_BYTE_LIMIT = 16 * 1024 * 1024;

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "echoscribe-summarize",
    title: "Mit EchoScribe zusammenfassen",
    contexts: ["page", "selection"]
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== "echoscribe-summarize" || !tab) return;
  summarizeTab(tab, info.selectionText || "").catch(async (error) => {
    await chrome.storage.local.set({
      latestSummary: "",
      latestError: error.message || String(error),
      latestUpdatedAt: Date.now()
    });
  });
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "summarizeActiveTab") return false;

  summarizeActiveTab()
    .then((response) => sendResponse(response))
    .catch((error) => sendResponse({ ok: false, error: error.message || String(error) }));

  return true;
});

async function summarizeActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) throw new Error("No active tab found.");
  return summarizeTab(tab, "");
}

async function summarizeTab(tab, selectionText) {
  if (!tab.id) throw new Error("The active tab cannot be accessed.");

  const result = await buildPagePayload(tab, selectionText);

  const response = await sendNativeMessage({
    type: "summarize",
    ...result
  });

  await chrome.storage.local.set({
    latestSummary: response.summary || "",
    latestProvider: response.provider || "",
    latestModel: response.model || "",
    latestUrl: result.url || "",
    latestError: "",
    latestUpdatedAt: Date.now()
  });

  return response;
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
    const [injection] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: extractPagePayload,
      args: [selectionText]
    });
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
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_NAME, payload, (response) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) {
        reject(new Error(lastError.message));
        return;
      }
      if (!response) {
        reject(new Error("EchoScribe Native Host returned no response."));
        return;
      }
      if (response.ok === false) {
        reject(new Error(response.error || "EchoScribe summary failed."));
        return;
      }
      resolve(response);
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
