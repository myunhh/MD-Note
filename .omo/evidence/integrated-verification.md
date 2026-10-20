# Integrated feature verification

Runtime source HEAD: fd4489c6ebd5a92770db16e08de407abd85de966. All six feature branches locally merged into main; no remote push.

Executed on Windows after final merge:

- `node scripts/check-localization.mjs`: PASS, 140 English/Korean keys, 161 Swift lookups, localized samples and resource configuration.
- `node MDNoteCore/Tests/parity/hash_parity.mjs`: PASS, 8/8 golden hash cases.
- `node scripts/check-archive-contract.mjs`: PASS, 10 regex/contract fixtures; does not execute Swift or ZIPFoundation.
- `node scripts/check-archive-renderer.mjs`: PASS, 14 fixtures using actual bundled markdown-it and bridge image source parser.
- `node scripts/check-document-search.mjs` with installed Omowright loader and Chrome: PASS, 28/28 actual DOM cases on merged renderer. Evidence in `integrated-document-search/`.
- Visually inspected `integrated-document-search/highlight.png` and `fallback.png`: active/inactive highlight paint present, text readable, no changed text layout in fixture. This is renderer evidence, not native app UI evidence.
- `git diff 4ad8a7c..HEAD --check`: PASS.

The temporary integration-F localization helper requires unresolved Git merge stages and cannot run after commit. Its post-merge invocation failed for absent stage 1; the supported localization script above passed on final sources.

Native Swift compilation, XCTest, UIKit/SwiftUI/WebKit interaction, ZIP roundtrip, iPad layout/accessibility, and PencilKit verification were not executable on this Windows host. See `docs/feature-integration-qa.md` for native commands and scenarios.

Independent integrated source review identified one blocking MEDIUM defect: generic ZIP imports rejected valid Markdown code examples because of a second, incomplete parser. The archive worker removed this generic-image rejection while keeping manifest validation and safe extraction. Seven generic Markdown import cases are encoded in the native regression test (unrun); own-format missing-asset and unsafe-path assertions remain.

Post-fix root checks: localization 140 keys/161 lookups PASS; archive export unescape/dependency/error-resource contract PASS; actual renderer parser 18/18 PASS; hash parity 8/8 PASS; bridge syntax and whitespace PASS. Renderer runtime sources were unchanged by the fix, so the previously recorded 28/28 DOM run still applies. The temporary picker source-order assertion was removed in response to nonblocking review finding M2.

`npm audit --json` before final local commits returned ENOLOCK: this Swift project has no npm package lock. No package or lockfile was created solely to satisfy that command. This is not a dependency-audit pass.

Final bounded independent correction review: CLEAR / APPROVE, no blockers; report: `integrated-feature-code-review.md`. Archive correction committed as `3221be9`; final documentation commit / delivered HEAD: `34a3a9ff7db97e998bbcefd83570fdcd5aff19fb`. Product working tree clean after both commits. No push or external publication.
