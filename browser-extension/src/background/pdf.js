import { MAX_CONTENT_CHARS, MAX_PDF_BYTES, MAX_PDF_DOWNLOAD_MS, MAX_PDF_PAGES, MAX_PDF_PROCESSING_MS } from '../shared/constants.js';

export function isWebPdfTab(tab = {}) {
  const url = String(tab.url || '');
  return /^https?:\/\//i.test(url) && /\.pdf(?:$|[?#\s])/i.test(`${url} ${tab.title || ''}`);
}

function withinPdfDeadline(promise, startedAt, now) {
  const remaining = MAX_PDF_PROCESSING_MS - (now() - startedAt);
  if (remaining <= 0) return Promise.reject(new Error('PDF text extraction exceeded the 30 second processing limit.'));
  let timer;
  return Promise.race([
    Promise.resolve(promise),
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('PDF text extraction exceeded the 30 second processing limit.')), remaining);
    })
  ]).finally(() => clearTimeout(timer));
}

export function isPdfCandidate(page = {}, tab = {}) {
  if (page.selection || String(page.text || '').length > 500) return false;
  const target = `${page.url || ''} ${page.title || ''} ${tab.url || ''} ${tab.title || ''}`;
  return /\.pdf(?:$|[?#\s])/i.test(target);
}

export async function fetchPdfBytes(url, fetchImpl = fetch) {
  if (!/^https?:\/\//i.test(String(url || ''))) throw new Error('PDF extraction requires an HTTP or HTTPS web URL.');
  const controller = new globalThis.AbortController();
  let timedOut = false;
  let reader;
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
      reject(new Error('PDF download exceeded the 30 second limit.'));
    }, MAX_PDF_DOWNLOAD_MS);
  });
  const withinDeadline = (promise) => Promise.race([Promise.resolve(promise), timeout]);

  try {
    const response = await withinDeadline(fetchImpl(url, { credentials: 'include', signal: controller.signal }));
    if (!response.ok) throw new Error(`PDF download failed with HTTP ${response.status}.`);
    const declaredSize = Number(response.headers.get('content-length') || 0);
    if (declaredSize > MAX_PDF_BYTES) throw new Error('PDF is too large for local extraction (16 MB maximum).');
    if (!response.body?.getReader) {
      const bytes = new Uint8Array(await withinDeadline(response.arrayBuffer()));
      if (bytes.byteLength > MAX_PDF_BYTES) throw new Error('PDF is too large for local extraction (16 MB maximum).');
      return bytes;
    }

    reader = response.body.getReader();
    const chunks = [];
    let total = 0;
    while (true) {
      const { done, value } = await withinDeadline(reader.read());
      if (done) break;
      total += value.byteLength;
      if (total > MAX_PDF_BYTES) {
        await reader.cancel();
        throw new Error('PDF is too large for local extraction (16 MB maximum).');
      }
      chunks.push(value);
    }

    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return bytes;
  } catch (error) {
    if (timedOut) {
      try { await reader?.cancel(); } catch { /* The aborted stream may already be closed. */ }
      throw new Error('PDF download exceeded the 30 second limit.');
    }
    throw error;
  } finally {
    clearTimeout(timer);
    reader?.releaseLock();
  }
}

export async function extractPdfText(bytes, pdfjs, now = Date.now) {
  if (!pdfjs?.getDocument) throw new Error('Local PDF.js is unavailable.');
  const loadingTask = pdfjs.getDocument({ data: bytes, isEvalSupported: false });
  const startedAt = now();
  let document;
  try {
    document = await withinPdfDeadline(loadingTask.promise, startedAt, now);
    if (document.numPages > MAX_PDF_PAGES) throw new Error(`This PDF has too many pages (${MAX_PDF_PAGES} maximum).`);
    let result = '';
    for (let number = 1; number <= document.numPages; number += 1) {
      if (now() - startedAt > MAX_PDF_PROCESSING_MS) throw new Error('PDF text extraction exceeded the 30 second processing limit.');
      const page = await withinPdfDeadline(document.getPage(number), startedAt, now);
      const content = await withinPdfDeadline(page.getTextContent(), startedAt, now);
      const remaining = MAX_CONTENT_CHARS - result.length - (result ? 2 : 0);
      if (remaining <= 0) break;
      let text = '';
      for (const item of content.items) {
        if (text.length >= remaining) break;
        const fragment = String(item.str || '').replace(/\s+/g, ' ').trim();
        if (!fragment) continue;
        text += `${text ? ' ' : ''}${fragment}`;
      }
      text = text.slice(0, remaining);
      if (text) result += `${result ? '\n\n' : ''}${text}`;
      await page.cleanup?.();
      if (result.length >= MAX_CONTENT_CHARS) break;
    }
    if (!result) throw new Error('This PDF contains no extractable text.');
    return result;
  } finally {
    if (loadingTask.destroy) await loadingTask.destroy();
    else await document?.destroy?.();
  }
}
