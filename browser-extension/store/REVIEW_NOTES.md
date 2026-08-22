# Reviewer Notes

EchoScribe Web Summary is a BYOK, user-invoked summarizer. It has no developer backend, account, telemetry, analytics, advertising, native messaging, local-LLM connection, or remote executable code.

## Test flow

1. Install the extension and open Settings.
2. Select OpenAI, Anthropic, Google Gemini, or xAI.
3. Enter a disposable reviewer-owned restricted API key and choose a model from the dropdown. Optionally click **Refresh model list** to add compatible choices reported by the provider API. The publisher does not provide or receive keys.
4. Open a normal public webpage. Click the EchoScribe Web Summary extension, choose a language, and click **Summarize**.
5. Select text and invoke **Summarize with EchoScribe** from the context menu; confirm the selection takes precedence.
6. Open a public text-based HTTP(S) PDF and summarize it. Image-only PDFs and local `file://` PDFs are intentionally unsupported.
7. Confirm Copy requires a click. In Settings, remove the provider key and use **Clear all local data**.

## Expected network destinations

Only the selected provider receives requests: `api.openai.com`, `api.anthropic.com`, `generativelanguage.googleapis.com`, or `api.x.ai`. Model-list loading occurs only when the reviewer explicitly clicks Refresh model list; that request sends the stored provider key but no page content. Summary requests include bounded selected/page/PDF text, page title, and meta description.

The provider key is stored in browser-managed local extension storage and is never returned to popup/options after saving. Content/model output is treated as inert text. No URL is sent to the provider or retained with the result.

## Update identity and migration

Firefox keeps the existing EchoScribe add-on ID `echoscribe@wean.de`. Chromium unpacked and enterprise-managed builds keep the previous public manifest key so those installations retain extension ID `jpenmjpoinmopahlkefpkeneokenecpf`. Store-uploaded Chrome/Edge ZIPs omit `key`; the Chrome Web Store item `pacpimdbfknllhacjkgeijkcdifnoglg` is the authority for store-distributed updates. This public key is not a credential and grants no publishing access.

The extension implementation is otherwise a complete replacement: Native Messaging, local-host permissions, and desktop browser-registration flows are removed. Updated desktop installers remove only obsolete EchoScribe Native Messaging manifests/registry keys; browser profiles and provider credentials are not changed.

## Bundled PDF.js review note

PDF extraction uses package-local `pdfjs-dist` 6.2.108 with `isEvalSupported: false`; its worker is bundled locally and no remote worker, script, font, or code is loaded. The current `web-ext lint` result is 0 errors, 0 notices, and 6 static warnings originating in bundled PDF.js feature-detection/parser paths (`Function`, dynamic import, and document-write checks). The matching source archive and lockfile are supplied for review. `npm audit` reports 0 vulnerabilities.
