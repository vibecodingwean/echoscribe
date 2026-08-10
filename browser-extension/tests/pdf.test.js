import { describe, expect, it, vi } from 'vitest';
import { extractPdfText, fetchPdfBytes, isPdfCandidate, isWebPdfTab } from '../src/background/pdf.js';

describe('isPdfCandidate', () => {
  it('recognizes URL/title PDFs only when useful page text is absent', () => {
    expect(isPdfCandidate({ url: 'https://example.com/file.pdf?x=1', text: '' }, {})).toBe(true);
    expect(isPdfCandidate({ url: 'https://example.com/file.pdf', text: 'x'.repeat(600) }, {})).toBe(false);
    expect(isPdfCandidate({ url: 'https://example.com/page', title: 'report.pdf', text: '' }, {})).toBe(true);
  });

  it('accepts HTTP download endpoints when the browser tab title identifies a PDF', () => {
    expect(isWebPdfTab({ url: 'https://example.com/download?id=123', title: 'report.pdf' })).toBe(true);
    expect(isWebPdfTab({ url: 'file:///report.pdf', title: 'report.pdf' })).toBe(false);
  });
});

describe('fetchPdfBytes', () => {
  it('downloads an HTTPS PDF with browser credentials for authenticated documents', async () => {
    const fetchImpl = vi.fn(async () => new Response(new Uint8Array([1, 2, 3]), { headers: { 'content-type': 'application/pdf' } }));
    const bytes = await fetchPdfBytes('https://example.com/report.pdf', fetchImpl);
    expect([...bytes]).toEqual([1, 2, 3]);
    expect(fetchImpl).toHaveBeenCalledWith('https://example.com/report.pdf', {
      credentials: 'include', signal: expect.any(Object)
    });
  });

  it('rejects non-web URLs, failed responses, and oversized PDFs', async () => {
    await expect(fetchPdfBytes('file:///report.pdf', vi.fn())).rejects.toThrow('web URL');
    await expect(fetchPdfBytes('https://example.com/a.pdf', async () => new Response('', { status: 403 }))).rejects.toThrow('403');
    const oversized = new Uint8Array(16 * 1024 * 1024 + 1);
    await expect(fetchPdfBytes('https://example.com/a.pdf', async () => new Response(oversized))).rejects.toThrow('too large');
  });

  it('cancels a chunked PDF response as soon as the byte limit is exceeded', async () => {
    let cancelled = false;
    const chunk = new Uint8Array(1024 * 1024);
    const stream = new globalThis.ReadableStream({
      pull(controller) { controller.enqueue(chunk); },
      cancel() { cancelled = true; }
    });
    await expect(fetchPdfBytes('https://example.com/chunked.pdf', async () => new Response(stream)))
      .rejects.toThrow('too large');
    expect(cancelled).toBe(true);
  });

  it('aborts a stalled PDF download after 30 seconds', async () => {
    vi.useFakeTimers();
    try {
      const fetchImpl = vi.fn((_url, request) => new Promise((_resolve, reject) => {
        request.signal.addEventListener('abort', () => reject(new globalThis.DOMException('Aborted', 'AbortError')));
      }));
      const pending = fetchPdfBytes('https://example.com/stalled.pdf', fetchImpl);
      const assertion = expect(pending).rejects.toThrow('30 second');
      await vi.advanceTimersByTimeAsync(30_001);
      await assertion;
    } finally {
      vi.useRealTimers();
    }
  });
  it('aborts a stalled PDF response stream after 30 seconds', async () => {
    vi.useFakeTimers();
    let cancelled = false;
    try {
      const stream = new globalThis.ReadableStream({ cancel() { cancelled = true; } });
      const pending = fetchPdfBytes('https://example.com/stalled-body.pdf', async () => new Response(stream));
      const assertion = expect(pending).rejects.toThrow('30 second');
      await vi.advanceTimersByTimeAsync(30_001);
      await assertion;
      expect(cancelled).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('extractPdfText', () => {
  it('extracts and normalizes text from every page with local PDF.js', async () => {
    const destroyDocument = vi.fn();
    const destroyLoadingTask = vi.fn();
    const pdfjs = { getDocument: vi.fn(() => ({
      destroy: destroyLoadingTask,
      promise: Promise.resolve({
        numPages: 2,
        getPage: async (number) => ({ getTextContent: async () => ({ items: [{ str: number === 1 ? 'First' : 'Second' }, { str: ' page' }] }) }),
        destroy: destroyDocument
      })
    })) };
    await expect(extractPdfText(new Uint8Array([1]), pdfjs)).resolves.toBe('First page\n\nSecond page');
    expect(pdfjs.getDocument).toHaveBeenCalledWith({ data: expect.any(Uint8Array), isEvalSupported: false });
    expect(destroyLoadingTask).toHaveBeenCalled();
  });

  it('returns a safe error for empty PDFs', async () => {
    const pdfjs = { getDocument: () => ({ promise: Promise.resolve({ numPages: 1, getPage: async () => ({ getTextContent: async () => ({ items: [] }) }), destroy: async () => {} }) }) };
    await expect(extractPdfText(new Uint8Array([1]), pdfjs)).rejects.toThrow('no extractable text');
  });

  it('times out and destroys PDF.js while the document is still parsing', async () => {
    vi.useFakeTimers();
    const destroy = vi.fn();
    try {
      const pending = extractPdfText(new Uint8Array([1]), {
        getDocument: () => ({ promise: new Promise(() => {}), destroy })
      });
      const assertion = expect(pending).rejects.toThrow('30 second');
      await vi.advanceTimersByTimeAsync(30_001);
      await assertion;
      expect(destroy).toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });

  it('rejects excessive page trees and stops reading at the text budget', async () => {
    const excessive = { getDocument: () => ({ promise: Promise.resolve({ numPages: 501, destroy: async () => {} }) }) };
    await expect(extractPdfText(new Uint8Array([1]), excessive)).rejects.toThrow('too many pages');

    const getPage = vi.fn(async () => ({ getTextContent: async () => ({ items: [{ str: 'x'.repeat(80_000) }] }) }));
    const bounded = { getDocument: () => ({ promise: Promise.resolve({ numPages: 5, getPage, destroy: async () => {} }) }) };
    const text = await extractPdfText(new Uint8Array([1]), bounded);
    expect(text.length).toBeLessThanOrEqual(120_000);
    expect(getPage).toHaveBeenCalledTimes(2);
  });
});
