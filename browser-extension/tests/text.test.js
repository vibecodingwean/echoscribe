import { describe, expect, it } from 'vitest';
import { stripWebAddresses } from '../src/shared/text.js';

describe('web-address sanitization', () => {
  it('removes common URL forms while preserving surrounding Markdown and punctuation', () => {
    expect(stripWebAddresses([
      '[docs](https://example.com/path), then',
      'FTP ftp://files.example.org/report.pdf; mail mailto:a@example.org.',
      'Protocol //cdn.example.net/a.js and bare education.gov.yk.ca/info!',
      'File file:///tmp/private.pdf and data data:text/plain,secret.'
    ].join('\n'))).toBe([
      '[docs]([link removed]), then',
      'FTP [link removed]; mail [link removed].',
      'Protocol [link removed] and bare [link removed]!',
      'File [link removed] and data [link removed].'
    ].join('\n'));
  });

  it('does not collapse intentional spaces, indentation, or line breaks', () => {
    const input = '  Column A    Column B\n    indented text without a link  ';
    expect(stripWebAddresses(input)).toBe(input);
  });

  it('does not mistake ordinary prose, versions, or times for addresses', () => {
    const input = 'Title: Release 5.6 at 10:30. Keep normal prose unchanged.';
    expect(stripWebAddresses(input)).toBe(input);
  });
});
