import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '..');
const path = (relative) => resolve(root, relative);
const canonicalMitLicense = `MIT License

Copyright (c) 2026 vibecodingwean

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
`;

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

  it('uses EchoScribe branding in public product metadata and a standard MIT license', () => {
    for (const file of ['package.json', 'README.md', 'store/PRIVACY_POLICY.md', 'store/STORE_LISTING.md', 'store/REVIEW_NOTES.md']) {
      const source = readFileSync(path(file), 'utf8');
      expect(source).toMatch(/EchoScribe/);
    }

    const license = readFileSync(path('LICENSE'), 'utf8');
    const rootLicense = readFileSync(path('../LICENSE'), 'utf8');
    expect(license).toBe(canonicalMitLicense);
    expect(rootLicense).toBe(canonicalMitLicense);
    expect(license).toBe(rootLicense);

    expect(existsSync(path('TRADEMARKS.md'))).toBe(true);
    const trademarks = readFileSync(path('TRADEMARKS.md'), 'utf8');
    expect(trademarks).toBe(readFileSync(path('../TRADEMARKS.md'), 'utf8'));
    expect(trademarks).toMatch(/does not reduce, replace, or add conditions to those software-license rights/i);
    expect(trademarks).toMatch(/intended for public distribution must be renamed and rebranded/i);
    expect(trademarks).toMatch(/may not be published under the name “EchoScribe” or with the EchoScribe logo/i);
    expect(trademarks).toMatch(/must not state or imply that their version is official, approved, sponsored, endorsed, or otherwise affiliated/i);
    expect(trademarks).toMatch(/“derived from the EchoScribe source code” are permitted/i);

    const packageScript = readFileSync(path('scripts/package.py'), 'utf8');
    expect(packageScript).toContain('ROOT / "TRADEMARKS.md"');
    expect(packageScript).toContain('manifest.pop("key", None)');
    expect(packageScript).toMatch(/target != "chrome"/);
    const validationScript = readFileSync(path('scripts/validate.py'), 'utf8');
    expect(validationScript).toContain('ROOT / "TRADEMARKS.md"');
    expect(validationScript).toContain('store ZIP must omit key');
    expect(validationScript).toContain('unpacked dist must keep the Chromium public key');
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
      'store/CHROME_PUBLISHING.md', 'store/REVIEW_NOTES.md'
    ]) expect(existsSync(path(file)), file).toBe(true);
  });
});
