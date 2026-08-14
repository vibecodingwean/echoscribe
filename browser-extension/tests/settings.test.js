import { describe, expect, it } from 'vitest';
import { defaultSettings, maskApiKey, normalizeSettings, publicSettings } from '../src/shared/settings.js';

describe('defaultSettings', () => {
  it('uses a cloud provider with a known model and no API key', () => {
    const settings = defaultSettings();
    expect(settings.provider).toBe('openai');
    expect(settings.models.openai).toBeTruthy();
    expect(settings.apiKeys).toEqual({ openai: '', anthropic: '', gemini: '', xai: '' });
    expect(settings.targetLanguage).toBe('auto');
  });
});

describe('normalizeSettings', () => {
  it('merges partial persisted values without losing provider defaults', () => {
    const settings = normalizeSettings({
      provider: 'anthropic',
      models: { anthropic: 'claude-custom' },
      apiKeys: { anthropic: 'user-secret' }
    });
    expect(settings.provider).toBe('anthropic');
    expect(settings.models.anthropic).toBe('claude-custom');
    expect(settings.models.openai).toBeTruthy();
    expect(settings.apiKeys.anthropic).toBe('user-secret');
    expect(settings.apiKeys.gemini).toBe('');
  });

  it('rejects unsupported providers and invalid language codes', () => {
    expect(normalizeSettings({ provider: 'other', targetLanguage: 'english' })).toMatchObject({
      provider: 'openai', targetLanguage: 'auto'
    });
  });

  it('migrates retained Gemini Fast defaults to 3.7 Flash', () => {
    const settings = normalizeSettings({
      provider: 'gemini',
      models: { gemini: 'gemini-3.6-flash' }
    });
    expect(settings.models.gemini).toBe('gemini-3.7-flash');
  });

  it('trims free-entry model names and bounds custom prompts', () => {
    const settings = normalizeSettings({
      models: { xai: '  grok-user-choice  ' },
      customPrompt: `  ${'x'.repeat(30_000)}  `
    });
    expect(settings.models.xai).toBe('grok-user-choice');
    expect(settings.customPrompt.length).toBe(20_000);
  });
});

describe('publicSettings', () => {
  it('reports key presence without exposing any credential value', () => {
    const visible = publicSettings(normalizeSettings({ apiKeys: { openai: 'private-key' } }));
    expect(visible).not.toHaveProperty('apiKeys');
    expect(visible.configuredProviders).toEqual({ openai: true, anthropic: false, gemini: false, xai: false });
    expect(JSON.stringify(visible)).not.toContain('private-key');
  });
});

describe('maskApiKey', () => {
  it('never exposes a complete stored key', () => {
    expect(maskApiKey('sk-example-sensitive-1234')).toBe('••••••1234');
    expect(maskApiKey('tiny')).toBe('••••');
    expect(maskApiKey('')).toBe('');
  });
});
