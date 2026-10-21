# B core API contract

All additions preserve old source call sites with defaults.

## Persistent block and ink identity

`Block` and `BlockSnapshot` append `blockID: String? = nil` to existing initializers.
Hash/seq remain unchanged for bookmarks and v1 references.

`AnchoredInk` appends these parameters after `lastKnownOrigin`:
`blockID: String? = nil, anchor: TextAnchor? = nil, behavior: AnnotationBehavior = .rigid`.
Behavior raw JSON values: `rigid`, `underline`, `highlight`.
Resolution uses `anchor?.blockID ?? blockID`, with no fallback to hashes when a stable
ID is missing from the document. Core never modifies original `strokeData`.

`StableBlockIdentity.reconcile(old: [Block], new: [Block], documentUnchanged: Bool = false) -> [Block]`
returns blocks with IDs. Preserve unique incoming editor IDs; otherwise restore unique
exact hash AND text matches from saved snapshots. Set `documentUnchanged: true` ONLY
after comparing actual document hash with sidecar.documentHash: this permits duplicate
paragraph restoration using saved seq on reopen. Ambiguous changed blocks get new UUIDs.
Do not regenerate IDs on every render. Persist returned IDs back to the editor and sidecar.

## Text ranges

TextAnchor Codable JSON keys:
`{blockID:String,startUTF16:Int,endUTF16:Int,quote:String,prefix:String,suffix:String}`.
Offsets are half-open UTF16 in rendered plain block text, NOT Markdown source offsets,
Swift Character indices, or Unicode scalar counts. Optional init quote/context default empty.
Empty quote cannot be reconciled as a text mark.

- `TextAnchor.capture(blockID:text:startUTF16:endUTF16:) -> TextAnchor?`
- `TextAnchor.stringRange(in:startUTF16:endUTF16:) -> Range<String.Index>?`
- `anchor.reconciled(in: String) -> TextAnchor?`: unique quote or uniquely contextual match.
- `anchor.applyingReplacement(startUTF16:endUTF16:replacement:oldText:) -> TextAnchor?`:
  trusted editor transaction; excludes insertions exactly at selection edges, expands
  interior edits, detaches complete target replacement/deletion.
- `anchor.remapped(blockID:text:offsetDeltaUTF16:) -> TextAnchor?`: trusted editor split/merge
  mapping. Validate resulting whole-grapheme range and exact quote; crossing a split detaches.
  Undo restores prior value snapshots. Do not infer split/merge maps from hashes.

`Reanchor.reanchor(ink:oldBlocks:newBlocks:)` uses stable IDs first, updates legacy
hash/seq fields, and reconciles non-rigid text anchors. Without an ID, only unique
exact content on both sides can follow. Ambiguity/deletion returns original ink in
`orphaned`, with last known origin when available. Callers retain it.

## Study insertion DTO

`StudyInsertion(id: String = UUID().uuidString, afterBlockID: String? = nil,
kind: StudyInsertionKind = .blank, markdown: String = "", height: Double = 160,
placement: StudyPlacement = .flow, order: Int = 0, blockIDs: [String] = [])`.
JSON has exactly these keys (nil afterBlockID may be omitted).
kind raw strings `blank`, `markdown`; placement `flow`, `floating`.
The insertion `id` is its ink-target block ID. `afterBlockID == nil` means document start.
Missing non-nil parents remain detached; callers must not silently relocate additions.
`height` is reserved document-coordinate height; floating is explicit opt-in.
`blockIDs` persists the ordered editor-owned stable child block IDs for Markdown supplements.
It defaults to [] when absent in existing JSON. A owns ID assignment and transaction mapping;
the core does not derive these IDs from content/position. Save the updated IDs alongside markdown.

`StudyInsertions.upserting(_:in:) -> [StudyInsertion]?` validates ID/height/self-parent.
`StudyInsertions.removing(id:from:) -> [StudyInsertion]` returns new array.
Retain prior arrays for undo/redo; removing an insertion does not delete ink.

## Sidecar

currentVersion = 2; `studyInsertions: [StudyInsertion] = []` appended AFTER appVersion.
`Sidecar.decoded(from:)` and direct JSONDecoder both reject future versions via
`SidecarError.newerVersion(Int)` before payload parsing. `encoded()` also rejects future
versions. Added unsupportedVersion for versions below 1.
v1 decode migrates in memory to v2, assigns UUIDs to snapshot blocks, links uniquely
identified legacy hash/seq ink, moves unresolved live ink to preserved orphans,
and retains existing orphans verbatim. Save migrated sidecar to persist generated IDs.
v2 decode does not silently regenerate IDs.

## Verification contract

Shared fixture `MDNoteCore/Tests/Fixtures/anchor-utf16.json` is consumed by Swift tests
and Node Intl.Segmenter check. Node command:
`node MDNoteCore/Tests/parity/anchor_fixture_check.mjs`.
Swift required on macOS: `swift test --package-path MDNoteCore`.
This Windows host has no Swift/SourceKit; Swift tests are authored but not executed here.
