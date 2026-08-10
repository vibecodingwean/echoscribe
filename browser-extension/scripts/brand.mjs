import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export function createLogoSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-labelledby="title desc">
  <title id="title">EchoScribe</title><desc id="desc">EchoScribe turns long text into a concise summary.</desc>
  <defs><linearGradient id="blue" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#4b86c5"/><stop offset="1" stop-color="#2f6baa"/></linearGradient></defs>
  <rect width="512" height="512" rx="96" fill="url(#blue)"/>
  <text x="256" y="135" fill="#fff" font-family="Segoe UI, sans-serif" font-size="62" text-anchor="middle">bla bla bla</text>
  <path d="M104 114h304" stroke="#fff" stroke-width="9" opacity=".9"/>
  <path d="M256 166v55m-25-24 25 25 25-25" fill="none" stroke="#fff" stroke-linecap="round" stroke-linejoin="round" stroke-width="13"/>
  <text x="256" y="385" fill="#fff" font-family="Segoe UI, sans-serif" font-size="146" text-anchor="middle">bla</text>
</svg>`;
}

export function createIconPng(size) {
  if (![16, 32, 48, 96, 128].includes(size)) throw new Error(`Unsupported icon size: ${size}`);
  return readFileSync(resolve(root, `assets/icons/icon-${size}.png`));
}

export function createPromoSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1400 560" role="img" aria-labelledby="title desc">
  <title id="title">EchoScribe Web Summary</title><desc id="desc">A clean EchoScribe summary interface.</desc>
  <rect width="1400" height="560" fill="#f7f8fa"/>
  <rect x="130" y="72" width="1140" height="416" rx="18" fill="#fff" stroke="#d9e2ec" stroke-width="4"/>
  <path d="M148 72h1104a18 18 0 0 1 18 18v82H130V90a18 18 0 0 1 18-18z" fill="#243b53"/>
  <text x="180" y="136" fill="#fff" font-family="Segoe UI, sans-serif" font-size="42" font-weight="700">EchoScribe</text>
  <rect x="180" y="215" width="340" height="66" rx="10" fill="#1269cc"/>
  <text x="350" y="258" fill="#fff" font-family="Segoe UI, sans-serif" font-size="28" text-anchor="middle">Summarize</text>
  <rect x="180" y="316" width="1040" height="112" rx="12" fill="#fff" stroke="#d9e2ec" stroke-width="4"/>
  <path d="M225 352h690M225 387h850" stroke="#829ab1" stroke-linecap="round" stroke-width="14"/>
</svg>`;
}
