# Independent correctness review — REJECT

Reviewed SHA: `9e03057263b6c6024652019b94722ed681885745`

Baseline: `26a04d173fbcacc4161e77048de04f1cea8f03e7`

Review checkout: `C:/Users/picom/orca/MD-Note/.omo/reviews/live-ink-9e03057`. HEAD verified before and after review; `git status --short` empty. Product files were not modified. Review covered the baseline-to-final source changes and relevant neighbors, especially the actual geometry adapter. Generated vendor output was exercised in Chrome, not manually audited line by line.

`codeQualityStatus: BLOCK`
`recommendation: REQUEST_CHANGES`

## CRITICAL

None established.

## HIGH

### H1 — Native geometry decoding discards all stable block IDs

Locations: `MDNote/Core/BlockGeometry.swift:7`, `:18`; `MDNote/Core/MarkdownRenderer.swift:245`; `MDNote/Core/InkStore.swift:96`.

The actual `MarkdownRenderer.blocks()` path decodes `MDNote.layout()` through `BlockGeometryDTO`. That existing DTO has no `blockID` property, and its `block` conversion never supplies `blockID` to the new `Block` initializer. The initializer defaults it to nil. Browser layout does emit IDs, but every native block loses them.

Trigger: select text, choose underline/highlight, switch to pen mode and draw. `captureAnchor.blockID` contains the JS ID; `block.blockID` is nil. The equality guarding `item.anchor = anchor; item.behavior = captureBehavior` is false. The stroke is saved as rigid rather than following the selected range. Similarly, all saved block snapshots lose identity, trusted edit mappings cannot address ordinary captured ink, and an edited block falls back to content-hash recovery and can orphan its ink. Study target restoration also compares against missing native IDs.

Evidence: direct source trace of the DTO, renderer conversion, initializer default, and capture branch. Browser layout in this review returned a nonempty `blockID`; the adapter cannot retain it. Native tests construct `Block(..., blockID: ...)` directly and never exercise this adapter, which explains their failure to detect it.

Smallest fix: decode an optional `blockID` in `BlockGeometryDTO` and forward it into `Block`. Add a regression decoding representative real layout JSON through this DTO, then exercise capture/reanchor using that decoded block. Run the native regression on Mac when available.

### H2 — Editing shortcut references destroys their Markdown meaning

Locations: `editor/editor.js:11`, `:18`, `:87`; bridge call site `MDNote/Resources/WebAssets/app/bridge.js:210`.

Trigger fixture:

```md
Read [guide] here.

[guide]: https://example.org
```

In the bundled page, call `MDNote.render(fixture)` and `MDNote.setTextEditing(true)`, click `#content p`, press End, and type `!`.

Observed in an independently launched owned Chrome instance:

```json
{"supports":true,"before":"Read <a href=\"https://example.org\">guide</a> here.","savedMarkdown":"Read \\[guide\\] here.!\n\n[guide]: https://example.org\n"}
```

The support filter catches explicit/collapsed reference syntax but misses shortcut `[guide]`. ProseMirror receives only this block, without the document-level reference definition, so it parses literal brackets and serializes escaped text on the first edit. Native `acceptEditorSnapshot` persists that source. The original working link is destroyed by an unrelated character insertion.

Smallest fix: route shortcut references whose semantics cannot survive isolated parsing to the source-preserving fallback, or pass the correct reference context while retaining lossless serialization. Add a real keyboard editing regression for shortcut links and images. Rebuild the checked-in offline bundle.

### H3 — Soft-break normalization is reported as deletion of untouched annotated text

Locations: `MDNote/Resources/WebAssets/app/bridge.js:78`, `:87`; `editor/editor.js:87`; `MDNoteCore/Sources/MDNoteCore/TextAnchor.swift:88`; `MDNote/Core/InkStore.swift:449`.

Trigger: a paragraph has source `First line\nsecond line\n`. Its rendered range text is `First line\nsecond line`; underline the word `second` at UTF16 `[11,17)`. Open rich editing, press End, type `!`.

Exact independently observed documentEdited payload, with random identity fields omitted:

```json
{
  "markdown":"First line second line!\n",
  "edits":[{
    "startUTF16":10,
    "endUTF16":22,
    "insertedText":" second line!",
    "oldText":"First line\nsecond line"
  }],
  "mappings":[]
}
```

ProseMirror normalizes the soft break to a space while also appending the user's character. The bridge collapses both changes into one broad replacement. Native `TextAnchor.applyingReplacement` correctly treats a replacement covering `[11,17)` as whole-target deletion and returns nil; `InkStore.applyTextReplacement` moves the annotation to orphans. The word was not deleted. This remains a bug after H1 is corrected.

Smallest fix: provide accurate edit mappings that distinguish serializer normalization from the user's edit, or conservatively use source fallback where rich parsing cannot preserve the rendered text coordinate space. Do not weaken the native genuine-full-deletion guard. Add an integration regression using the actual emitted edits and an anchor on `second`.

Evidence boundary: the browser payload is executed evidence; the resulting native detachment is a deterministic source trace, not a claim of executed PencilKit behavior.

## MEDIUM

### M1 — Native source-contract checks mirror implementation instead of behavior

Location: `scripts/check-native-ink-contract.mjs:22` and `:69`.

Several checks only look for implementation identifiers (`renderedSources[signature]`, `originals[id]`, `store.restoreAttachments`) or pin exactly ten test methods. They pass without any functioning adapter or native behavior, as H1 demonstrates. A test-count assertion also breaks when legitimate coverage is added. The suite labels itself as source-only, so this is not a dishonest native-pass claim, but these checks provide false confidence and unnecessary maintenance friction.

Smallest improvement: remove the exact count and implementation-presence pseudo-tests, retain any genuinely useful structural contract checks as explicitly limited tooling, and cover the real DTO/consumer seam in native tests. This is a quality finding, not an additional HIGH blocker.

## LOW

No separate correctness finding. `StableBlockIdentity.reconcile` currently has no production callers (only its test calls); it duplicates an identity policy implemented in JS. This is a nonblocking scope/maintenance observation, not a request for a broad refactor.

## Independent checks and trace matrix

Owned browser: installed Chrome at `C:/Program Files/Google/Chrome/Application/chrome.exe`, launched through the installed omowright `connectPipe` with a unique temporary profile. Opened the locked checkout's bundled `index.html` by file URL. Browser closed and owned temporary profile removed. No user browser was attached.

Representative scenarios:

1. Rich keyboard editing with CRLF and an untouched table: executed. Formatting remained rendered; modified Markdown retained CRLF and the untouched table. Save-to-disk was source-traced through coordinated comparison/atomic replacement, not run natively.
2. Selected text range geometry: executed for `beta` in `alpha beta gamma`; status `attached`, one nonempty rectangle. Native path traced and failed at H1.
3. Blank insertion and undo: executed. A 200px insertion shifted the following block by 212.59375px including flow margins; undo restored two ordinary blocks. Sidecar and archive fragment transport traced.

Edge scenarios:

1. Shortcut reference editing: executed; FAIL H2.
2. Soft-wrapped paragraph plus end insertion: executed; payload FAIL H3.
3. Undo of that edit: executed; exact original soft-break source restored.
4. Duplicate identical paragraphs: executed unchanged render using captured identity snapshots; both IDs retained.
5. Unsupported table source fallback then Cancel: executed; textarea present, no edit event on opening, original Markdown unchanged after Cancel.
6. External save conflict/read failure: source trace of `MarkdownFileWriter`; comparison occurs inside coordinated accessor before atomic write, invalid UTF8 throws. Native filesystem/coordination execution unrun.
7. Projected-ink recapture/erase/history: source trace of fingerprints, retained original indices, attachment history and projection guards; actual PencilKit serialization and undo unrun.
8. Supplement archive assets: independently ran real parser fixture script, including independent fragment scope.

Independently rerun from locked checkout, all exit 0:

- `node MDNoteCore/Tests/parity/hash_parity.mjs`: 8 golden cases.
- `node MDNoteCore/Tests/parity/anchor_fixture_check.mjs`: 31 UTF16 boundary assertions, four fixtures. Does not execute Swift.
- `node scripts/check-archive-renderer.mjs`: 18 parser fixtures and supplement fragment-scope assertion.

Inspected parent artifacts: `.omo/evidence/integration-live-ink/final-checks.txt`, `report.md`, editor/results.json (33 entries), layout/dom-results.json (27), search/dom-results.json (28), and `.omo/evidence/root-live-ink/verification.md` and results.json. Existing passes do not cover the three findings. No evidence was accepted as proof of native execution.

## Skill-perspective check

Ran the read-only `programming` and `remove-ai-slops` review perspectives before judging tests. Canonical files were loaded; SHA256:

- programming: `3CD471C76187629F4DD0A45890A847EAFA5CD5FFEC3BD71425D97C71AC90B5E4`
- remove-ai-slops: `DD90BD27F690191323DCB291FC5D2CCDF9D58768164A894D21000B5E7682C480`

The diff violates the behavioral-test perspective through M1. Genuine Swift behavior tests and browser keyboard tests are useful, but the actual native adapter is untested. No brittle natural-language prompt tests were found. No new internal validation/parsing was identified as a separate correctness blocker; boundary decoding and Unicode checks serve required contracts. Existing oversized controller/bridge modules are a maintainability concern under the skills, but subjective restructuring is outside this bounded correctness review and is not an approval blocker.

No cleanup workflow or source mutation was performed.

## Native boundary and verdict

Swift/Xcode compilation, native XCTest, WebKit transport, actual PencilKit touch/eraser/undo, physical Korean IME, native file coordination/watching, ZIP roundtrip and PDF rendering were **UNRUN** on this Windows host. The user explicitly deferred Mac/iPad acceptance; that deferral itself is not a reason for rejection.

Rejection is based on H1–H3. Fix those concrete issues and verify the affected boundaries before approval. No independent approval is asserted for a later SHA.

Report routing: `omo-agent-toolkit ulw-loop status --json` failed in its Windows wrapper; invoking the installed loop CLI directly returned `ULW_LOOP_PLAN_MISSING`. The canonical fallback code-review artifact is `.omo/evidence/mdnote-live-ink-code-review.md`, pointing to this complete assigned report.
