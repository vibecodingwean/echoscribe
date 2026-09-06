import { describe, expect, it } from 'vitest';
import { PROVIDERS } from '../src/shared/constants.js';

const expected = {
  openai: ['gpt-5.6-terra', 'gpt-5.6-sol'],
  anthropic: ['claude-sonnet-5', 'claude-opus-5'],
  gemini: ['gemini-3.8-flash', 'gemini-3.1-pro-preview'],
  xai: ['grok-4.3', 'grok-4.6']
};

describe('curated summary model suggestions', () => {
  it('offers exactly one validated Fast and Pro model per provider', () => {
    for (const [provider, ids] of Object.entries(expected)) {
      expect(PROVIDERS[provider].defaultModel).toBe(ids[0]);
      expect(PROVIDERS[provider].models).toEqual([
        { id: ids[0], tier: 'Fast' },
        { id: ids[1], tier: 'Pro' }
      ]);
    }
  });
});
