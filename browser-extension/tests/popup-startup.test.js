import { describe, expect, it } from 'vitest';
import { inlinePopupAssets } from '../scripts/inline-popup.mjs';

describe('popup cold-start build optimization', () => {
  it('inlines EchoScribe critical CSS without requiring decorative UI images', () => {
    const source = '<head><link rel="stylesheet" href="popup.css"></head><body><strong>EchoScribe</strong><script src="popup.js"></script></body>';
    const result = inlinePopupAssets(source, 'body { width: 380px; }', new Map());
    expect(result).toContain('<style>body { width: 380px; }</style>');
    expect(result).not.toContain('href="popup.css"');

    expect(result).toContain('<script src="popup.js"></script>');
  });
});
