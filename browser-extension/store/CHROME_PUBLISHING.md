# Chrome Web Store Publishing

1. Create/register a Chrome Web Store developer account, accept the terms, enable 2-step verification, verify the contact email, and pay the one-time fee shown in the dashboard.
2. Use the published policy URL from `PRIVACY_POLICY.md` and the verified support contact `app@wean.de`.
3. Run `npm ci && npm run verify` from a clean source tree.
4. Open the existing EchoScribe item in the Developer Dashboard and upload the versioned `artifacts/echoscribe-web-summary-chrome-v<version>.zip` replacement package. The retained public manifest key preserves the previous unpacked/enterprise ID; the store item remains the authority for store-distributed updates.
5. Complete Package, Store Listing, Privacy, Distribution, and Test instructions.
6. Declare website content and authentication information. Do not declare browsing activity unless code changes to transmit URLs.
7. Select **No remote code**, explain the single purpose, and paste every permission justification from `STORE_LISTING.md`.
8. Add the reviewer flow from `REVIEW_NOTES.md`. Never place a real personal key in listing text or screenshots.
9. Submit for review. Choose automatic or deferred publishing; an approved deferred release must be published within the dashboard deadline.

If no existing dashboard item is verifiably available, stop rather than silently creating a parallel listing. Creating a new item requires an explicit retirement/migration decision. For updates, increment the package version, rebuild the complete ZIP, update disclosures and reviewer notes, and upload it to the existing item.

Official references: https://developer.chrome.com/docs/webstore/register · https://developer.chrome.com/docs/webstore/publish · https://developer.chrome.com/docs/webstore/cws-dashboard-privacy
