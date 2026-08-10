import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '..');
const path = (relative) => resolve(root, relative);
describe('release source contract', () => {
  it('uses package.json as the single release version source', () => {
    const config = readFileSync(path('scripts/config.mjs'), 'utf8');
    expect(config).toContain("new URL('../package.json', import.meta.url)");
    expect(config).not.toMatch(/version:\s*['"]\d+\.\d+\.\d+['"]/);
  });

  it('contains complete popup and options pages without inline executable code', () => {
    for (const file of ['src/popup/popup.html', 'src/popup/popup.css', 'src/options/options.html', 'src/options/options.css']) {
      expect(existsSync(path(file)), file).toBe(true);
    }
    for (const file of ['src/popup/popup.html', 'src/options/options.html']) {
      const html = readFileSync(path(file), 'utf8');
      expect(html).not.toMatch(/<script(?![^>]*\bsrc=)/i);
      expect(html).not.toMatch(/\son\w+=/i);
    }
  });

  it('uses EchoScribe branding throughout public source and package metadata', () => {
    for (const file of ['package.json', 'README.md', 'LICENSE', 'store/PRIVACY_POLICY.md', 'store/STORE_LISTING.md', 'store/REVIEW_NOTES.md']) {
      const source = readFileSync(path(file), 'utf8');
      expect(source).toMatch(/EchoScribe/);
    }
    const packageScript = readFileSync(path('scripts/package.py'), 'utf8');
    expect(packageScript).toContain('echoscribe-web-summary-');
    expect(packageScript).toContain('ARTIFACTS.glob("*.zip")');
    expect(packageScript).toContain('(ARTIFACTS / "SHA256SUMS.json").write_text');
    expect(packageScript).toContain('(ARTIFACTS / "SHA256SUMS").write_text');
  });


  it('documents the actual curated and API-refreshed model dropdown', () => {
    const readme = readFileSync(path('README.md'), 'utf8');
    const listing = readFileSync(path('store/STORE_LISTING.md'), 'utf8');
    const reviewer = readFileSync(path('store/REVIEW_NOTES.md'), 'utf8');
    expect(readme).toMatch(/curated.*model.*dropdown/i);
    expect(listing).toMatch(/curated.*model/i);
    expect(reviewer).toMatch(/choose a model from the dropdown/i);
    expect(`${readme}\n${listing}\n${reviewer}`).not.toMatch(/free model-ID entry|enter any supported model ID manually|choose\/enter/i);
    expect(reviewer).toMatch(/click \*\*Summarize\*\*/);
    expect(reviewer).toMatch(/Summarize with EchoScribe\*\*/);
  });


  it('discloses authenticated PDF cookie refetch in the store listing', () => {
    const listing = readFileSync(path('store/STORE_LISTING.md'), 'utf8');
    expect(listing).toMatch(/authenticated HTTP\(S\) PDFs/i);
    expect(listing).toMatch(/website cookies/i);
  });

  it('contains build, package, validation, and store documentation sources', () => {
    for (const file of [
      'scripts/build.mjs', 'scripts/package.py', 'scripts/validate.py',
      'README.md', 'store/PRIVACY_POLICY.md', 'store/STORE_LISTING.md',
      'store/CHROME_PUBLISHING.md', 'store/CHROME_PUBLISHING.md',
      'store/CHROME_PUBLISHING.md', 'store/REVIEW_NOTES.md'
    ]) expect(existsSync(path(file)), file).toBe(true);
  });
});
