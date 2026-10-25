import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const here = dirname(fileURLToPath(import.meta.url));
const extension = resolve(here, '../dist/chrome');
const option = process.argv.indexOf('--chrome');
if (option < 0 || !process.argv[option + 1]) {
  throw new Error('Pass --chrome /absolute/path/to/Chrome-for-Testing');
}

const profile = await mkdtemp(resolve(tmpdir(), 'echoscribe-chrome-smoke-'));
let context;
try {
  context = await chromium.launchPersistentContext(profile, {
    executablePath: resolve(process.argv[option + 1]),
    headless: true,
    args: [
      `--disable-extensions-except=${extension}`,
      `--load-extension=${extension}`,
      '--disable-background-networking',
    ],
    ignoreDefaultArgs: ['--disable-extensions'],
    timeout: 20000,
  });
  const worker = context.serviceWorkers()[0] || await context.waitForEvent('serviceworker', { timeout: 10000 });
  const extensionId = new URL(worker.url()).host;
  const page = await context.newPage();
  await page.goto(`chrome-extension://${extensionId}/options.html`);
  await page.locator('#provider').selectOption('anthropic');
  await page.locator('#model option').first().waitFor({ state: 'attached' });
  assert.deepEqual(await page.locator('#model option').allTextContents(), [
    'Fast — claude-haiku-5-5', 'Pro — claude-opus-5-5',
  ]);
  assert.equal(await page.locator('#model').inputValue(), 'claude-haiku-5-5');

  // The isolated browser profile has a placeholder key. No provider request
  // leaves the browser: its service-worker fetch is replaced before dispatch.
  await worker.evaluate(() => {
    globalThis.fetch = async (url, request) => {
      globalThis.__echoscribeSmoke = { url, body: JSON.parse(request.body) };
      if (url.includes('gemini-4-argon')) {
        return new Response(JSON.stringify({ candidates: [{
          finishReason: 'STOP', content: { parts: [{ thought: true, text: 'Hidden' }, { text: 'Mocked Gemini summary.' }] }
        }] }), { status: 200, headers: { 'content-type': 'application/json' } });
      }
      return new Response(JSON.stringify({ content: [{ type: 'text', text: 'Mocked provider summary.' }] }), {
        status: 200, headers: { 'content-type': 'application/json' },
      });
    };
  });
  const saved = await page.evaluate(() => chrome.runtime.sendMessage({
    type: 'saveSettings',
    settings: { provider: 'anthropic', models: { anthropic: 'claude-sonnet-5' } },
    apiKey: { provider: 'anthropic', value: 'placeholder-only' },
  }));
  assert.equal(saved.ok, true);
  assert.equal(saved.settings.models.anthropic, 'claude-haiku-5-5');
  const denied = await page.evaluate(() => chrome.runtime.sendMessage({
    type: 'summarizePayload', page: { title: 'Fixture', text: 'A short synthetic sentence.' }, targetLanguage: 'en'
  }));
  assert.equal(denied.ok, false);
  assert.equal(await worker.evaluate(() => globalThis.__echoscribeSmoke || null), null);
  await page.locator('#provider-consent-toggle').click();
  assert.match(await page.locator('#provider-consent-status').textContent(), /allowed/i);
  const result = await page.evaluate(() => chrome.runtime.sendMessage({
    type: 'summarizePayload',
    page: { title: 'Fixture', text: 'A short synthetic sentence.' },
    targetLanguage: 'en',
  }));
  const request = await worker.evaluate(() => globalThis.__echoscribeSmoke || null);
  assert.equal(result.ok, true);
  assert.equal(result.model, 'claude-haiku-5-5');
  assert.equal(result.summary, 'Mocked provider summary.');
  assert.equal(request?.url, 'https://api.anthropic.com/v1/messages');
  assert.equal(request?.body?.model, 'claude-haiku-5-5');
  await page.locator('#provider').selectOption('gemini');
  await page.locator('#model').selectOption('gemini-4-argon');
  await page.locator('#api-key').fill('placeholder-gemini-only');
  await page.locator('#save').click();
  await page.locator('#provider-consent-toggle').click();
  const geminiResult = await page.evaluate(() => chrome.runtime.sendMessage({
    type: 'summarizePayload', page: { title: 'Fixture', text: 'A short synthetic sentence.' }, targetLanguage: 'en'
  }));
  const geminiRequest = await worker.evaluate(() => globalThis.__echoscribeSmoke || null);
  assert.equal(geminiResult.ok, true);
  assert.equal(geminiResult.summary, 'Mocked Gemini summary.');
  assert.match(geminiRequest?.url, /gemini-4-argon:generateContent$/);
  assert.equal(geminiRequest?.body?.generationConfig?.thinkingConfig?.thinkingLevel, 'low');
  console.log('chrome_smoke=PASS models=claude-haiku-5-5,gemini-4-argon consent=verified');
} finally {
  await context?.close();
  await rm(profile, { recursive: true, force: true });
}
