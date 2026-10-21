# Integrated MD Note verification

Final tested commit: `9e03057263b6c6024652019b94722ed681885745`.
Baseline: `26a04d173fbcacc4161e77048de04f1cea8f03e7`.
All paths below are relative to `.omo/evidence/integration-live-ink/`.
Windows execution, Node v24.19.0, owned headless Chrome; no user browser attached.

## Local integration

Normal no-ff merges, preserving all source history:

- B `b15059c6eccf6efff0fd8dd76376134f2666a8f2` -> merge `c6b89654a725a21e155b96ba32c2e4d5c5a3b945`.
- C `de9ea3aeca6f7f14c1b45cbe385ed88475677714` -> merge `94564b6de7a8be4842a031c1dab57113a76322b0`.
- A `b401faa6ad20af7b80f33b7975375d4bf3a3dc4d` -> merge `b4559453c2f3e11b942ccac15056067f2345d606`.
- D `32de5e008d877e8ce2ea81745ed5df45198a3041` -> merge `607fe38677ed7358c9dccba217b7f64ea49c2b7a`.
- Integration fixes/tests: `13eb04a3205457049695df604fe4a5d39f1f4e9e`.
- README and Mac/iPad guide: final commit above.

No remote action, rewritten history, or worker checkout modification.

## Executed scenarios

| Criterion/scenario | Exact invocation (from repository root) | Binary observation | Artifact |
|---|---|---|---|
| Rich keyboard editing, original frontmatter/CRLF/reference/table preservation, composition save suppression, source Apply/Cancel, split/merge, undo/redo, deletion/undo history IDs, supplement edit/resize/removal/undo | `node scripts/check-rich-editor.mjs` | Exit 0; 33/33 assertions true | `final-browser.txt`, `editor/results.json`, `editor/events.json`, `editor/rich-editor.png`, `editor/source-applied.png`, `editor/source-preview.png` |
| Source fallback preserves existing ink target and text-range geometry | Same script, assertions 8 and final source-preview cases | Old tree failed; final tree target/hash/text and attached geometry assertions true | `source-fallback-before.txt`, `source-fallback-before/results.json`, final editor artifacts |
| Wrapped ranges, rigid shape translation, blank/study reserved height and target identity, repeated projection without drift, deletion/ambiguity, Unicode/math/image cases | `node scripts/check-annotation-layout.mjs` | Exit 0; 27/27 true | `final-browser.txt`, `layout/dom-results.json`, `layout/narrow-highlight.png`, `layout/fixture.html` |
| Existing real DOM search/navigation/highlight regression | `node scripts/check-document-search.mjs` | Exit 0; 28/28 true | `final-browser.txt`, `search/dom-results.json`, `search/highlight.png`, `search/fallback.png` |
| JS hashing parity with committed golden values | `node MDNoteCore/Tests/parity/hash_parity.mjs` | Exit 0; 8/8 | `final-checks.txt` |
| Shared UTF16/grapheme fixture boundaries | `node MDNoteCore/Tests/parity/anchor_fixture_check.mjs` | Exit 0; 31 assertions, 4 fixtures | `final-checks.txt` |
| Bilingual controls/errors and formatting parameters | `node scripts/check-localization.mjs` | Exit 0; 170 keys, 173 Swift lookups | `final-checks.txt` |
| Archive path/dependency/localization contracts | `node scripts/check-archive-contract.mjs` | Exit 0 | `final-checks.txt` |
| Real bundled Markdown parser image collection and separate supplement fence/reference scopes | `node scripts/check-archive-renderer.mjs` | Exit 0; 18 existing fixtures plus composed-scope assertion | `final-checks.txt`; old concatenation loses study.png in `archive-scope-reproduction.txt` |
| Native source wiring including save guards, maps/history, projection originals, selection UI and separate image parsing | `node scripts/check-native-ink-contract.mjs` | Exit 0; 15 source assertions (NOT native execution) | `final-checks.txt` |
| JS syntax and whitespace | `node --check` on bridge, layout, editor source and changed test scripts; `git diff --check` | All exit 0 | `final-checks.txt` |
| Reproducible offline bundle | In `editor`: `npm ci --ignore-scripts`, `npm run build`; `git diff --exit-code -- ../MDNote/Resources/WebAssets/vendor/editor.js ../MDNote/Resources/WebAssets/vendor/editor-LICENSES.txt` | Exit 0; no normalized content diff | `npm-ci.txt`, `editor-build.txt`, `verification.txt` |
| Dependency audit | In `editor`: `npm audit --json` | Exit 0; total vulnerabilities 0 | `npm-audit.json` |

Browser environment used:
`MDNOTE_OMOWRIGHT_LOADER=C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.38/skills/browser/scripts/omowright.mjs`,
`MDNOTE_CHROME=C:/Program Files/Google/Chrome/Application/chrome.exe`,
`MDNOTE_EVIDENCE_DIR=.omo/evidence/integration-live-ink/{editor,layout,search}`.

## Integration corrections

1. Retain the original rendered block inside source fallback so entering/canceling it does not orphan ink; labels/textareas never enter target text.
2. Parse each main/supplement source separately for ZIP image collection. An unfinished main fence previously hid a rendered supplement image; reference labels also need local scope.
3. Restrict sidecar scheduling, insertion/recovery and export before successful loading. Failed reads must not create blank source/companions.
4. Require a nonempty selected text range for follow-text behavior, reflect accepted picker state, and clear the range when selecting ordinary rigid ink.
5. Preserve explicitly mapped live range offsets through remeasurement even for repeated quotes. External reconciliation keeps its conservative default.
6. Publish asynchronously measured ink fragments/detachments only if layout revision/store still match and Pencil is up.
7. Restore normal accessibility traversal when returning to pen mode; translate conflict/recovery/selection messages.
8. Replace the composition test's timer wait with completion-event subscription.

## Native source trace and explicit limits

Source review only, not compiled:

- `MarkdownFileWriter.swift`: coordinated read errors throw; write compares expected UTF8 source inside the same coordination accessor before atomic replacement.
- `DocumentCanvasViewController.swift:1107`: monotonic revision prevents duplicate edit-map application; attachment snapshots keyed by historyID restore deleted anchors. Saved baseline advances synchronously only after the writer succeeds.
- `DocumentCanvasViewController.swift:451`: trusted range offsets are enabled only for known live remeasurement; external load paths retain default conservative reconciliation.
- `DocumentCanvasViewController.swift:1089`: stale projection results cannot detach/publish after a newer revision, document switch or active Pencil input.
- `InkStore.swift:52`: rendered stroke fingerprints match originals; `rebuildDrawing` at line 118 derives fragments without rewriting original strokeData. Partial erasure and PencilKit serialization normalization still require actual runtime tests.
- `DocumentCanvasViewController.swift:1210`: export requires successful initial load, a completed flush, no save conflict and no active stroke.
- `MarkdownRenderer.swift:218` and controller line 910: fragment array is JSON encoded and parsed independently for archive assets.
- `project.yml`: new Swift files are included by existing Core/source directory entries; NativeInkTests belongs to the existing MDNoteArchiveTests target.

Swift and SourceKit/Xcode are absent here. Swift core tests (including the added repeated-quote trusted-map regression), all native XCTest, actual file watcher/conflict/recovery behavior, physical Korean IME, VoiceOver, touch/zoom/Pencil routing, original PKDrawing normalization, archive roundtrip and PDF rendering are **UNRUN**. No native pass is claimed.

`docs/live-ink-mac-qa.md` supplies exact Swift/Xcode commands and 14 device scenarios with expected observables. User owns Mac/iPad acceptance; root owns independent review and final product acceptance. This report is the implementation handoff, not an independent review approval.

## Visual evidence

Opened rich-editor and source-preview screenshots directly: readable Korean text, rendered formatting, reserved study height, original preview above labeled source input, visible Apply/Cancel and focus outline. Fixed 1390px light paper canvas follows existing `editor/DESIGN.md` and iPad-only configuration; these are actual bundled browser surfaces, not native screenshots. No responsive phone-site/dark-native claim.

Final vendor files were LF after deterministic build under autocrlf, temporarily appearing modified by stat; explicit normalized diff was empty. Re-adding only these two unchanged generated files refreshed the index; no staged diff remained. Final tracked product tree is clean; untracked team/evidence directories are retained intentionally.
