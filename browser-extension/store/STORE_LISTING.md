# EchoScribe Web Summary Store Listing

## Product name

EchoScribe Web Summary

## Short description

Summarize webpages, selected text, and PDFs with your own cloud AI provider and API key.

## Full description

EchoScribe Web Summary turns long webpages, selected passages, and text-based PDFs into clear summaries.

**Your provider, your model**

Choose OpenAI, Anthropic, Google Gemini, or xAI. Select a curated Fast or Pro model; an explicit model-list refresh can add compatible choices reported by the provider API.

**Your prompt**

The proven default prompt favors concrete facts, removes filler, and adapts to the content. Edit it at any time or restore it with one click.

**Explicit by design**

Nothing is transmitted automatically. A summary sends bounded page/PDF or selected text, page title, meta description, and the chosen provider key directly over HTTPS to that provider. Explicitly refreshing the model list sends the key but no page content. To read authenticated HTTP(S) PDFs after explicit user action, the browser may re-fetch the original PDF with existing website session cookies; those cookies go only to the PDF website and are not sent to the AI provider.

**No hidden machinery**

No EchoScribe Web Summary backend, account, analytics, telemetry, native host, local-LLM service, ads, or remote executable code.

API keys are stored in browser-managed local extension storage. Use a separate restricted key with provider-side spending limits. Text-only PDFs are supported; image-only PDFs need OCR elsewhere.

## Category

Productivity

## Single purpose

User-invoked summarization of the active webpage, selected text, or text-based PDF through a user-selected cloud AI provider.

## Permission justifications

- `activeTab`: temporary access to the active page only after the user invokes EchoScribe Web Summary.
- `scripting`: runs the packaged text extractor in that user-invoked tab.
- `contextMenus`: adds the explicit page/selection summary command.
- `storage`: stores settings, keys, and the latest summary locally.
- `clipboardWrite`: copies a summary only after the user clicks Copy.
- Provider host permissions: send content and the corresponding key directly to the fixed HTTPS API selected by the user.

## Data disclosures

- Authentication information: provider API key, stored locally and transmitted only to its provider.
- Website content: selected or page/PDF text plus page title and meta description, transmitted only after explicit user action.
- Authenticated PDF access: authenticated HTTP(S) PDFs may be re-fetched with existing website cookies after explicit user action; cookies are sent only to the PDF website.
- No browsing activity: page URLs are not sent to providers or retained with results.
- No analytics, telemetry, advertising, sale, or developer collection.

## Submission assets

- Popup feature screenshot: `screenshots/popup-store-1280x800.png`
- Provider, model, key, prompt, and BYOK settings screenshot: `screenshots/options-1280x800.png`
- Marquee promotional image: `promo-1400x560.png`
- Editable promotional source: `../assets/store-promo.svg`

The screenshots were captured from the release build without a configured API key or private page content.

## Support and privacy

- Support: `app@wean.de`
- Privacy policy: https://github.com/vibecodingwean/echoscribe/blob/main/browser-extension/store/PRIVACY_POLICY.md
