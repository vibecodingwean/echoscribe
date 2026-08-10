export function extractPagePayload(selectionText = '', pageDocument = document, pageLocation = location, pageWindow = window) {
  const contentLimit = 120_000;
  const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
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
    selection,
    text: clean(sourceText).slice(0, sourceLimit)
  };
}
