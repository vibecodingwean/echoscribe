import { JSDOM } from 'jsdom';
import { describe, expect, it } from 'vitest';
import { extractPagePayload } from '../src/content/extract-page.js';

function page(html, url = 'https://example.com/story') {
  return new JSDOM(html, { url });
}

describe('extractPagePayload', () => {
  it('uses selected text before article, main, or body text', () => {
    const dom = page('<title>Title</title><meta name="description" content="Description"><article>Article body</article>');
    const result = extractPagePayload('  selected\n text  ', dom.window.document, dom.window.location, dom.window);
    expect(result).toEqual({
      url: 'https://example.com/story', title: 'Title', description: 'Description',
      language: '', selection: 'selected text', text: 'selected text'
    });
  });

  it('prefers article then main then role-main before body', () => {
    const dom = page('<body>Body <main>Main text</main><article>Article text</article></body>');
    expect(extractPagePayload('', dom.window.document, dom.window.location, dom.window).text).toBe('Article text');
    dom.window.document.querySelector('article').remove();
    expect(extractPagePayload('', dom.window.document, dom.window.location, dom.window).text).toBe('Main text');
  });

  it('collapses whitespace and enforces the content length bound', () => {
    const dom = page(`<main>${'word   '.repeat(30_000)}</main>`);
    const result = extractPagePayload('', dom.window.document, dom.window.location, dom.window);
    expect(result.text.length).toBeLessThanOrEqual(120_000);
    expect(result.text).not.toMatch(/\s{2}/);
  });

  it('bounds selection, title, and description from untrusted pages', () => {
    const huge = 'x'.repeat(150_000);
    const dom = page(`<title>${huge}</title><meta name="description" content="${huge}"><main>${huge}</main>`);
    const result = extractPagePayload(huge, dom.window.document, dom.window.location, dom.window);
    expect(result.selection.length).toBeLessThanOrEqual(120_000);
    expect(result.text.length).toBeLessThanOrEqual(120_000);
    expect(result.title.length).toBeLessThanOrEqual(512);
    expect(result.description.length).toBeLessThanOrEqual(2_000);
  });

  it('reads a sanitized page language from html lang or locale metadata', () => {
    const htmlLang = page('<html lang="de-DE"><title>Titel</title><article>Artikel</article></html>');
    expect(extractPagePayload('', htmlLang.window.document, htmlLang.window.location, htmlLang.window).language).toBe('de');

    const ogLocale = page('<html><head><meta property="og:locale" content="de_AT"></head><article>Artikel</article></html>');
    expect(extractPagePayload('', ogLocale.window.document, ogLocale.window.location, ogLocale.window).language).toBe('de');

    const contentLanguage = page('<html><head><meta http-equiv="content-language" content="fr, en"></head><article>Texte</article></html>');
    expect(extractPagePayload('', contentLanguage.window.document, contentLanguage.window.location, contentLanguage.window).language).toBe('fr');

    const hostile = page('<html lang="en; DROP TABLE"><article>Body</article></html>');
    expect(extractPagePayload('', hostile.window.document, hostile.window.location, hostile.window).language).toBe('');
  });

  it('returns plain metadata rather than page markup', () => {
    const dom = page('<title>Specific subject</title><meta name="description" content="Concrete details"><main><script>bad()</script>Useful text</main>');
    const result = extractPagePayload('', dom.window.document, dom.window.location, dom.window);
    expect(result.title).toBe('Specific subject');
    expect(result.description).toBe('Concrete details');
    expect(result.text).not.toContain('<script>');
  });
});
