import { readFileSync } from 'node:fs';

const packageVersion = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version;
export const CHROMIUM_EXTENSION_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw5feX+pKmvnJP7DUnuhR+Hr3C+NoZu8PK7XLBwGL7MOatsOMPJUB7GLLMA6x/m5PXbpHnQ78IjvXzsXW3AqYQevxWKFvSB5oBS1uaIWZkNH5AG+z/beIInFtZHWDfWkIsBYhpUu/RdGlrB5cuyWUCzxlMH+7EWu3yGHUo5qoNOwjNUx8ih8OS4iQuvq78RX8JuOjKh8xUiDxDd761CZYJJEn7cpq9onOWymYUfwFkrxE3L2SrWj7p0DZyP+L2iVFe0W9txChZgjto5mlMcdn9mrwaPDmZvbxRRCa0kIB5Qsjr4oVeYSVEOFMZoWLF8iDzBU+3JOAvCNaHeualJygiQIDAQAB';

const icons = Object.fromEntries([16, 32, 48, 96, 128].map((size) => [String(size), `icons/icon-${size}.png`]));

export function makeManifest(browser) {
  const manifest = {
    manifest_version: 3,
    name: 'EchoScribe Web Summary',
    version: packageVersion,
    description: 'Summarize webpages, selected text, and PDFs with your chosen cloud AI provider.',
    permissions: ['activeTab', 'scripting', 'contextMenus', 'storage', 'clipboardWrite'],
    host_permissions: [
      'https://api.openai.com/*',
      'https://api.anthropic.com/*',
      'https://generativelanguage.googleapis.com/*',
      'https://api.x.ai/*'
    ],
    action: {
      default_title: 'EchoScribe Summary',
      default_popup: 'popup.html',
      default_icon: icons
    },
    icons,
    options_ui: { page: 'options.html', open_in_tab: true },
    content_security_policy: { extension_pages: "script-src 'self'; object-src 'none'; base-uri 'none'; worker-src 'self'" }
  };
  if (browser === 'firefox') {
    manifest.background = { scripts: ['background.js'] };
    manifest.browser_specific_settings = {
      gecko: {
        id: 'echoscribe@wean.de',
        strict_min_version: '142.0',
        data_collection_permissions: { required: ['authenticationInfo', 'websiteContent'] }
      }
    };
  } else {
    manifest.key = CHROMIUM_EXTENSION_KEY;
    manifest.background = { service_worker: 'background.js' };
  }
  return manifest;
}
