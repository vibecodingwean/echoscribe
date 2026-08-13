export function extractPagePayload(selectionText = '', pageDocument = document, pageLocation = location, pageWindow = window) {
  const contentLimit = 120_000;
  const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
  const declaredLanguage = () => {
    const candidates = [
      pageDocument.documentElement?.lang,
      pageDocument.documentElement?.getAttribute('lang'),
      pageDocument.documentElement?.getAttribute('xml:lang'),
      pageDocument.querySelector('meta[property="og:locale"]')?.content,
      pageDocument.querySelector('meta[http-equiv="content-language"]')?.content,
      pageDocument.querySelector('meta[name="language"]')?.content
    ];
    for (const value of candidates) {
      const normalized = String(value || '').trim().toLowerCase().replace(/_/g, '-').split(',')[0].trim();
      const match = normalized.match(/^([a-z]{2,3})(?:-[a-z0-9]{2,8})?$/);
      if (match) return match[1];
    }
    return '';
  };
  const title = clean(pageDocument.title).slice(0, 512);
  const description = clean(pageDocument.querySelector('meta[name="description"]')?.content).slice(0, 2_000);
  const sourceLimit = Math.max(0, contentLimit - title.length - description.length);
  const selection = clean(selectionText || pageWindow.getSelection?.()?.toString()).slice(0, sourceLimit);
  const main = pageDocument.querySelector('article')
    || pageDocument.querySelector('main')
    || pageDocument.querySelector('[role="main"]')
    || pageDocument.body;
  const sourceText = selection || main?.innerText || main?.textContent || pageDocument.body?.innerText || pageDocument.body?.textContent || '';
  return {
    url: String(pageLocation.href || ''),
    title,
    description,
    language: declaredLanguage(),
    selection,
    text: clean(sourceText).slice(0, sourceLimit)
  };
}
