# Repair R1: independent review H1–H3 and M1

Final local commit: `310933ac01b671ce98e803eac1181e355a6d1a62`.
Parent reviewed/rejected commit: `9e03057263b6c6024652019b94722ed681885745`.
Original `independent-review.md` remains unchanged. This is a repair handoff, not independent approval.

## Changes and evidence

| Finding | Implemented correction | Scenario and invocation | Observable / captured artifact |
|---|---|---|---|
| H1: native DTO dropped IDs | `BlockGeometryDTO` decodes optional blockID and forwards it into Block | `node scripts/check-editor-boundaries.mjs` captures the actual layout for `Hello world\n\nTail\n`. `NativeInkTests.testActualWebGeometryAdapterPreservesIdentityIntoInkCaptureAndReanchor` decodes that payload using the production DTO, then captures an underline, applies an edit and reanchors; also checks snapshot identity and legacy absent-ID decoding. | Browser fixture has both stable IDs: `repair-r1-browser/layout-adapter-fixture.json`. Native regression is **authored but UNRUN**, requiring Xcode; no regex is claimed as adapter proof. |
| H2: shortcut references lost semantics | Shortcut bracket references route to deliberate source editing; offline bundle rebuilt | Same browser script, click actual shortcut link/image block, keyboard append `!`, Apply | Both exact sources/definitions preserved and link/image still rendered; 6 reference assertions in `repair-r1-browser/results.json`. Before fix fails in `repair-r1-before.txt`. |
| H3: softbreak normalization falsely deleted target | Preserve softbreak tokens as newline text; paragraph/heading schema preserves whitespace during browser DOM input | Same script, ordinary English/Korean/emoji/combining-mark multiline paragraphs, real Ctrl+End then `!`, inspect emitted map and range geometry, undo | Three cases remain rich-editable; edits are only `[text.length,text.length) -> "!"`, untouched target resolves at original UTF16 offsets, saved source keeps newlines, undo restores bytes. `repair-r1-browser/*-events.json`, `results.json`, `multiline-editor.png`. |
| H3 downstream genuine deletion protection | Added native event-decoding regression, kept core whole-target deletion guard unchanged | `NativeInkTests.testActualSoftbreakEditEventDoesNotDeleteUntouchedAnnotation` decodes the observed EditorSnapshot payload and applies it to marked `second` [11,17), then explicitly deletes that target | Native test requires unchanged quote/offsets/payload after append, then orphan preservation after real deletion. **UNRUN** on Windows. |
| M1: implementation-mirroring checks | Removed exact test-method count and five identifier-presence pseudo-tests; strengthened ordering checks against missing substrings | `node scripts/check-native-ink-contract.mjs` | 10 source boundary checks exit 0; output explicitly says ordering/guards, not runtime behavior. Real adapter and event consumers are covered by native XCTest instead. |

H3 implementation uses the pinned `prosemirror-markdown` public tokenizer rule API and `prosemirror-model` schema whitespace option. Inspection of installed pinned sources established that both the default softbreak handler and DOM-input parsing normalize newlines unless overridden. `prosemirror-model` 1.25.12 was already locked transitively and is now an explicit exact direct dependency; no package version changed. Context7 discovery failed in this session and the official ProseMirror docs returned 403, so the installed package sources were the implementation reference. Markdown-it's official documentation confirms tokenizer rules are extensible.

## Final-SHA executed checks

All artifacts below are in this directory and stamped by the final command transcripts.

- `final-r1-browser.txt`: exact SHA plus all four browser invocations/exits. Boundary 25/25, existing rich editor 33/33, layout 27/27, search 28/28.
- `repair-r1-browser/results.json`, `repair-r1-editor/results.json`, `repair-r1-layout/dom-results.json`, `repair-r1-search/dom-results.json`: all recorded assertions true.
- `final-r1-checks.txt`: hash parity 8/8; four Unicode fixtures/31 boundaries; 170 bilingual keys/173 Swift lookups; archive contract; 18 image-parser fixtures plus fragment-scope regression; 10 source boundary checks; JS syntax; git diff check. Every command exit 0.
- `repair-r1-build.txt`: `npm ci --ignore-scripts`, `npm run build`; bundle SHA256 before/after identical: `01B63C4D14FB324A0BD02E210ADEEB95EB941B389F8ABFFF40560C8E5D45D18D`.
- `repair-r1-audit.json`: `npm audit --json` exits 0, vulnerabilities total 0.
- `verification-r1.txt`: actual final HEAD and clean tracked/staged tree receipt; evidence counts.

Browser environment: installed OmO loader and Chrome at the paths in `report.md`; each invocation owns a fresh temporary headless profile and closes it. `MDNOTE_EVIDENCE_DIR` is respectively `repair-r1-browser`, `repair-r1-editor`, `repair-r1-layout`, `repair-r1-search` under this directory. Existing rejection and original-final evidence are retained.

README, editor design notes and `docs/live-ink-mac-qa.md` now describe shortcut-reference fallback, preserved multiline editing, the new browser command and native adapter/event regressions.

## Explicit remaining verification boundary

Swift/Xcode/SourceKit unavailable. Native XCTest, full Swift build, actual file coordination/watching, PencilKit normalization/undo, physical Korean IME, VoiceOver, ZIP roundtrip and PDF rendering remain **UNRUN**, as accepted for Windows delivery. New native tests must run via the guide's `xcodebuild test ... -only-testing:MDNoteArchiveTests` command on Mac. Source inspection and Chrome tests are not native passes.

Root owns the fresh independent Astra review and final product acceptance. No remote push/publication or additional agents were used.
