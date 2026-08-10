import * as pdfjs from 'pdfjs-dist/legacy/build/pdf.mjs';
import { extractPdfText, fetchPdfBytes, isWebPdfTab } from '../background/pdf.js';

export async function loadPdfPayload(tab, workerSrc, { fetchImpl = fetch, now = Date.now } = {}) {
  const url = String(tab?.url || '');
  if (!isWebPdfTab(tab)) throw new Error('The active tab is not a supported web PDF.');
  pdfjs.GlobalWorkerOptions.workerSrc = workerSrc;
  const bytes = await fetchPdfBytes(url, fetchImpl);
  const text = await extractPdfText(bytes, pdfjs, now);
  return {
    title: String(tab?.title || 'PDF').slice(0, 512),
    description: '',
    selection: '',
    text
  };
}
