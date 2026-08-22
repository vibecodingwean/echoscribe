import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { createIconPng, createLogoSvg } from '../scripts/brand.mjs';
import { CHROMIUM_EXTENSION_KEY, makeManifest } from '../scripts/config.mjs';


describe('generated manifests', () => {
  it('uses the EchoScribe identity and minimal cloud-only Chromium permissions', () => {
    const manifest = makeManifest();
    expect(manifest.manifest_version).toBe(3);
    expect(manifest.name).toBe('EchoScribe Web Summary');
    expect(manifest.action.default_title).toBe('EchoScribe Summary');
    expect(manifest.description).toMatch(/^Summarize webpages/);
    expect(CHROMIUM_EXTENSION_KEY).toMatch(/^MIIB[A-Za-z0-9+/=]{300,}$/);
    expect(manifest.key).toBe(CHROMIUM_EXTENSION_KEY);
    expect(manifest.permissions.sort()).toEqual(['activeTab', 'clipboardWrite', 'contextMenus', 'scripting', 'storage'].sort());
    expect(JSON.stringify(manifest)).not.toMatch(/nativeMessaging|localhost|127\.0\.0\.1|telemetry/i);
    expect(manifest.background).toEqual({ service_worker: 'background.js' });
    expect(manifest).not.toHaveProperty('browser_specific_settings');
    expect(manifest.host_permissions).toEqual(expect.arrayContaining([
      'https://api.openai.com/*', 'https://api.anthropic.com/*',
      'https://generativelanguage.googleapis.com/*', 'https://api.x.ai/*'
    ]));
  });
});

describe('lazy PDF parser build boundary', () => {
  it('keeps PDF.js out of the service-worker entry and builds a separate parser module', () => {
    const backgroundEntry = readFileSync(new URL('../src/background/main.js', import.meta.url), 'utf8');
    const popupEntry = readFileSync(new URL('../src/popup/popup.js', import.meta.url), 'utf8');
    const buildScript = readFileSync(new URL('../scripts/build.mjs', import.meta.url), 'utf8');
    expect(backgroundEntry).not.toMatch(/pdfjs-dist|pdf\.worker|GlobalWorkerOptions/);
    expect(popupEntry).toContain("import('/pdf-parser.js')");
    expect(popupEntry).not.toMatch(/import\([^'"`]/);
    expect(buildScript).toContain('src/pdf/parser.js');
    expect(buildScript).toContain('pdf-parser.js');
  });
});

describe('EchoScribe branding', () => {
  it('creates a deterministic, self-contained EchoScribe SVG', () => {
    const first = createLogoSvg();
    expect(first).toBe(createLogoSvg());
    expect(first).toContain('<svg');
    expect(first).toContain('EchoScribe');

    expect(first).not.toMatch(/<script|(?:href|src)=["']https?:/i);
  });

  it('uses deterministic EchoScribe PNGs at every requested size', () => {
    for (const size of [16, 32, 48, 96, 128]) {
      const asset = new URL(`../assets/icons/icon-${size}.png`, import.meta.url);
      expect(existsSync(asset), `${size}px icon`).toBe(true);
      const first = createIconPng(size);
      const second = createIconPng(size);
      expect(first.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
      expect(createHash('sha256').update(first).digest('hex')).toBe(createHash('sha256').update(second).digest('hex'));
      expect(first.readUInt32BE(16)).toBe(size);
      expect(first.readUInt32BE(20)).toBe(size);
    }
  });
});
