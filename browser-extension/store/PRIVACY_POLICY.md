# EchoScribe Web Summary Privacy Policy

**Effective date:** 2026-08-08

EchoScribe Web Summary is a bring-your-own-key browser extension for summarizing webpages, selected text, and text-based PDFs. It has no developer-operated server, account system, advertising, analytics, or telemetry.

## Data handled

- **Website/PDF content and metadata:** After the user explicitly invokes Summarize or the context-menu command, EchoScribe Web Summary extracts bounded selected text or relevant page/PDF text plus the bounded page title and HTML meta description. A meta description is page metadata and may not be visibly rendered.
- **Authentication information:** The user may store one API key for each supported AI provider.
- **Settings and results:** Provider, model, prompt, language preference, latest summary, and a bounded safe error message may be stored locally.

EchoScribe Web Summary does not transmit the page URL to an AI provider and does not retain it with the result.

## Where data goes

On an explicit summary command, the extracted content, title, meta description, and only the selected provider's API key are sent directly over HTTPS to that provider. If the user explicitly clicks **Refresh model list**, the key is sent to that provider's model-list endpoint without page content.

- OpenAI — `api.openai.com`
- Anthropic — `api.anthropic.com`
- Google Gemini — `generativelanguage.googleapis.com`
- xAI — `api.x.ai`

The developer does not receive this content, the API key, or the generated summary. Each provider's own terms, privacy policy, and retention rules apply.

For an authenticated HTTP(S) PDF already open in the browser, EchoScribe Web Summary may re-fetch that PDF with the website's browser cookies. The PDF URL and cookies are sent only to that website, never to the AI provider, and are not retained with the summary.

## Local storage and key risk

Keys and settings use browser-managed local extension storage, not browser sync. Browser-managed local storage is not an operating-system credential vault and is not guaranteed to be encrypted. A compromised extension or a sufficiently privileged local profile user could access it. Use dedicated, restricted keys with low provider-side budgets.

Removing a key in EchoScribe Web Summary deletes the local copy but does not revoke it at the provider. Revoke or rotate it in the provider dashboard when required.

## Retention and deletion

EchoScribe Web Summary stores only the latest summary/status plus settings locally. Raw webpage/PDF content and PDF bytes are not intentionally persisted. Use **Clear all local data** in Settings to remove locally stored keys, settings, and results. Uninstalling the extension also removes its extension storage according to browser behavior.

## Security and code

All extension code and PDF.js are packaged locally. EchoScribe Web Summary does not download or execute remote code, execute model output, render it as HTML, or automatically follow model-provided links. Output is displayed as inert text.

## Changes and publication contact

Material changes will be reflected in this policy and store disclosures before publication.

- Support contact: `app@wean.de`
- Published policy: https://github.com/vibecodingwean/echoscribe/blob/main/browser-extension/store/PRIVACY_POLICY.md
