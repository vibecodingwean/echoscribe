# EchoScribe Web Summary

EchoScribe Web Summary is a standalone browser extension that summarizes the active webpage, selected text, or a browser-opened text PDF with a cloud AI provider chosen by the user.

## Features

- OpenAI, Anthropic, Google Gemini, and xAI
- Curated Fast/Pro model dropdown plus explicit API refresh
- User-supplied API keys (BYOK)
- Editable summary prompt with one-click reset
- Summary language selection
- Popup and context-menu workflows
- Chrome build (load unpacked from `dist/chrome`, or the Chrome Web Store ZIP)
- No backend, analytics, telemetry, native host, remote executable code, or local-LLM connection

## Important privacy boundary

A provider key is stored in browser-managed local extension storage. This is not an operating-system credential vault and is not guaranteed to be encrypted. Use a dedicated restricted provider key, configure provider-side spending/rate limits, and rotate or revoke the key if needed.

Network access occurs only after an explicit action: invoking a summary or clicking **Refresh model list**. A summary sends extracted page/PDF or selected text, the bounded page title and meta description, and the selected provider's key directly over HTTPS to that provider. Refreshing models sends the key to that provider's model-list endpoint but sends no page content. EchoScribe Web Summary does not receive any of it.

To support authenticated web PDFs, the browser may re-fetch the active HTTP(S) PDF with that website's cookies. The URL and cookies stay between the browser and the website and are not sent to the AI provider.

## Local installation

### Chrome

1. Run `npm ci && npm run build`.
2. Open `chrome://extensions`.
3. Enable **Developer mode**.
4. Choose **Load unpacked** and select `dist/chrome`.

## Development and verification

Requirements: Node.js 22, npm 10, Python 3.

```bash
npm ci
npm run verify
```

`npm run verify` runs the full Vitest suite, ESLint, the Chrome build, deterministic packaging, and exact-archive validation. Store ZIP files and SHA-256 hashes are written to `artifacts/`. The Chrome store ZIP omits `manifest.key`; unpacked `dist/chrome` keeps it.

Verified listing media lives in `store/screenshots/`; the rendered 1400 × 560 promotional image is `store/promo-1400x560.png`.

## Known boundaries

- Local `file://` PDFs are intentionally unsupported.
- Image-only/scanned PDFs require OCR elsewhere; EchoScribe Web Summary does not ship OCR.
- Some authenticated or cross-origin redirected PDFs can be blocked by browser permissions.
- Provider API behavior, pricing, retention, and model availability are governed by the selected provider.

## License and trademarks

The source code is licensed under the [MIT License](LICENSE). The EchoScribe name and brand assets remain subject to the [trademark and branding policy](TRADEMARKS.md). Publicly distributed forks must use distinct branding and identifiers and must not imply an official connection.

PDF text extraction uses bundled PDF.js under the Apache License 2.0; the release package includes its notice.
