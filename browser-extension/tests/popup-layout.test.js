import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '..');
const html = readFileSync(resolve(root, 'src/popup/popup.html'), 'utf8');
const css = readFileSync(resolve(root, 'src/popup/popup.css'), 'utf8');
const optionsHtml = readFileSync(resolve(root, 'src/options/options.html'), 'utf8');
const optionsCss = readFileSync(resolve(root, 'src/options/options.css'), 'utf8');
const tokensCss = readFileSync(resolve(root, 'src/styles/tokens.css'), 'utf8');

describe('EchoScribe popup visual contract', () => {
  it('uses the exact EchoScribe popup identity and compact shell geometry', () => {
    const document = new JSDOM(html).window.document;
    expect(document.title).toBe('EchoScribe Summary');
    expect(document.querySelector('header strong')?.textContent).toBe('EchoScribe');
    expect(css).toMatch(/body\s*{[^}]*width:\s*380px/is);
    expect(css).toMatch(/font:\s*14px\/1\.45\s+"Segoe UI",\s*system-ui,\s*sans-serif/i);
    expect(css).not.toMatch(/height:\s*600px|@media\s*\(min-resolution/i);
  });

  it('uses the exact EchoScribe reference palette, controls, and summary surface', () => {
    expect(css).toMatch(/body\s*{[^}]*color:\s*#1f2933[^}]*background:\s*#f7f8fa/is);
    expect(css).toMatch(/header\s*{[^}]*color:\s*#fff[^}]*background:\s*#243b53/is);
    expect(css).toMatch(/\.primary\s*{[^}]*border-color:\s*#1269cc[^}]*background:\s*#1269cc[^}]*color:\s*#fff/is);
    expect(css).toMatch(/button,\s*select\s*{[^}]*border:\s*1px solid #bcccdc[^}]*border-radius:\s*6px/is);
    expect(css).toMatch(/\.summary\s*{[^}]*max-height:\s*420px[^}]*overflow:\s*auto[^}]*border:\s*1px solid #d9e2ec[^}]*border-radius:\s*8px/is);
  });

  it('keeps all required controls in the compact text-first layout', () => {
    const document = new JSDOM(html).window.document;
    for (const id of ['summarize', 'language', 'copy', 'settings', 'retry', 'pdf-confirm', 'pdf-ok', 'pdf-cancel']) {
      expect(document.querySelector(`#${id}`), id).not.toBeNull();
    }
    expect(document.querySelectorAll('img')).toHaveLength(0);

  });
});

describe('EchoScribe settings visual contract', () => {
  it('uses the same identity, type, palette, and modern surfaces as the popup', () => {
    const document = new JSDOM(optionsHtml).window.document;
    expect(document.title).toBe('EchoScribe Settings');
    expect(document.querySelector('header strong')?.textContent).toBe('EchoScribe');
    expect(`${tokensCss}\n${optionsCss}`).toMatch(/"Segoe UI",\s*system-ui,\s*sans-serif/i);
    expect(optionsCss).toMatch(/background:\s*#f7f8fa/i);
    expect(optionsCss).toMatch(/background:\s*#243b53/i);
    expect(optionsCss).toMatch(/border:\s*1px solid #d9e2ec/i);

    expect(document.querySelectorAll('img')).toHaveLength(0);
  });
});
