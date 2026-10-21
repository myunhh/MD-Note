# Baseline verification

Baseline commit: `26a04d173fbcacc4161e77048de04f1cea8f03e7`, Windows / Node v24.19.0, before product edits in the parent integration checkout.

Executed by leader:

- `node MDNoteCore/Tests/parity/hash_parity.mjs`: PASS, 8/8 golden hash cases.
- `node scripts/check-localization.mjs`: PASS, 140 bilingual keys and 161 Swift lookups.
- `node scripts/check-archive-contract.mjs`: PASS, JS fixtures/contracts only, not native ZIP execution.
- `node scripts/check-archive-renderer.mjs`: PASS, 18 fixtures execute bundled markdown-it and bridge.imageSources.
- `node --check MDNote/Resources/WebAssets/app/bridge.js`: PASS.
- Initial `node scripts/check-document-search.mjs`: environment setup failure before browser execution; required `MDNOTE_OMOWRIGHT_LOADER`. Re-ran with task-local loader and Chrome executable environment overrides: PASS, 28/28 actual DOM checks in an owned headless Chrome profile. Evidence: `.omo/evidence/baseline-live-ink-search/{dom-results.json,highlight.png,fallback.png}`. Parent baseline SHA remained unchanged. Integration must rerun the scenario on the final integrated tree.

`swift` and `xcodebuild` not found on PATH. Native build, Swift tests, UIKit/WebKit/PencilKit use and native archive roundtrip are not verified here. User will perform Mac/iPad acceptance. No remote action authorized.

All five native agents were created with explicit role plus requested model and reasoning fields. A-D: `gpt-6.1-sol` / `xhigh`; I: `gpt-6-astra` / `xhigh`. The runtime has no independent exact-model introspection, so these fields are configuration evidence, not an independently attested model identity.
