# Native ink implementation evidence

This is D's isolated implementation evidence. Windows source checks passed; no native compilation, simulator run, Pencil input, or PDF visual acceptance is claimed.

## Executed checks

| Scenario | Invocation | Binary observable | Captured artifact |
| --- | --- | --- | --- |
| Save/ink/input/undo integration source contracts | `node scripts/check-native-ink-contract.mjs` | 12 checks pass, exit 0 | `static-contract.txt` |
| Existing archive source contracts | `node scripts/check-archive-contract.mjs` | PASS, exit 0 | `archive-contract.txt` |
| Real bundled Markdown image extraction | `node scripts/check-archive-renderer.mjs` | 18 fixtures pass, exit 0 | `archive-renderer.txt` |
| Patch whitespace | `git diff --check` | exit 0 | `diff-check.txt` |
| Dependency audit attempt | `npm audit --json` | ENOLOCK; this branch adds no npm manifest/dependency | `npm-audit.txt` |
| Active attempt lookup | toolkit Node entrypoint `ulw-loop status --json` | ULW_LOOP_PLAN_MISSING; no active attempt directory | `attempt-status-node.txt` |
| Native toolchain availability | PowerShell `Get-Command` for Swift/Xcode/SourceKit | unavailable | `toolchain.txt` |

The source-contract checks inspect integration structure. They do not execute Swift and are not substitutes for the following native acceptance.

## Required Mac commands, not executed here

Run after integrating A+B+C+D:

```sh
mkdir -p .omo/evidence/native-ink-mac
swift test --package-path MDNoteCore 2>&1 | tee .omo/evidence/native-ink-mac/core-tests.txt
xcodegen generate
xcrun simctl list devices available
# Set SIMULATOR_ID to an available iPad simulator UUID from the preceding command.
xcodebuild -project MDNote.xcodeproj -scheme MDNote \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -resultBundlePath .omo/evidence/native-ink-mac/NativeInk.xcresult \
  test 2>&1 | tee .omo/evidence/native-ink-mac/xcode-tests.txt
```

`Tests/ArchiveTests/NativeInkTests.swift` is included by the existing XcodeGen test source directory. Its ten executable scenarios cover:

1. A coordinated local save succeeds; a stale write after an external atomic save throws and leaves external bytes intact.
2. Invalid UTF-8 throws on read/write and remains byte-identical.
3. Twenty rigid reflow/recapture cycles preserve stable ink UUID and original stroke bytes.
4. Twenty two-line underline projection/recapture cycles preserve one annotation and original bytes.
5. Erase one rigid stroke, reflow twice, undo erasure: no resurrection before undo and both strokes restored afterward.
6. Delete a selected range, preserve orphan payload, restore the saved attachment on undo.
7. Insert Korean text inside a selected range, update quote/range, preserve stroke bytes.
8. Remove an inked study insertion, keep its orphan ink, restore its identity/payload on undo.
9. Sidecar plus ZIP roundtrip preserves study additions, original ink and a referenced supplement image.
10. A future-version sidecar stays read-only and byte-identical.

## Required iPad checks, not executed here

Record a screen video plus exported files under `.omo/evidence/native-ink-mac/`.

- Open a note, zoom to 200%, switch Text/Pen repeatedly. Text selection and Korean IME must work; two-finger pan and pinch in Text mode must retain the canvas coordinates. Draw a crossing mark before/after switching; it must align.
- Keep Pencil down while an image loads or text scale changes. The active stroke must continue without replacement/cancellation; after lift, layout catches up without drift.
- Select a phrase, choose underline/highlight, draw, then insert Korean text within it, wrap it across lines, split/merge the paragraph and undo/redo. Fragments follow whole selected ranges; a crossing-split range safely detaches with originals retained.
- Delete the marked range and undo. The mark must return attached, not remain in the orphan tray.
- Draw a formula/circle/arrow in rigid mode, edit surrounding text and reflow repeatedly. Its shape must remain unchanged; there is no automatic ink recognition.
- Insert blank and Markdown study spaces, draw on each, resize/move/remove and undo/redo. Following content and ink move in the same coordinates. Removing and undoing an inked insertion must restore its ink.
- Edit the `.md` externally while local editing is pending. The external file must remain unchanged, the local editor must remain open with an error, and Save recovery copy must create unique `.md` plus `.inknote` companions.
- Close/reopen, source-archive roundtrip and PDF export. Verify study content, supplement images, original ink and composed spacing. Exports above 500 pages now fail explicitly instead of silently truncating.
- Open v1 and future sidecars. v1 migrates without dropping orphan ink; future payload remains unchanged and editing/inking are disabled.

## Implementation boundaries

- Text-mode undo/redo is the web editor's shared text/study history. Pen-mode undo/redo remains PencilKit's drawing history.
- Range semantics are explicit: selected underline/highlight behavior applies to new strokes. Arbitrary handwriting remains rigid. Erasing a projected fragment removes the semantic annotation group; original bytes remain available to drawing undo during the session.
- Native shape fingerprints include path points, times, tool/color, transform and mask. Runtime serialization and PencilKit eraser/undo behavior must be checked by the native tests.
- The initial rendered baseline restores main-document block IDs by order only when the source hash is unchanged. Changed external source uses A's conservative unique matching. Study and supplement IDs are excluded from main-document identity restoration.
- Markdown writes compare exact prior UTF-8 text inside the file-coordination accessor before atomic replacement. Successful writes advance the watcher baseline synchronously. Sidecar writes are suppressed during a Markdown conflict; recovery copies preserve the local annotation state.
- Swift/SourceKit were unavailable. No toolchain was installed and no global configuration changed. The LSP decline tool was not callable in this session.

## Skill provenance

- `comment-checker/SKILL.md`: SHA-256 `2E33BA95D76C486B818C12097DEC4CCE17B0ACEC1329CAF311765B99874BC0EF`.
- `git-master/SKILL.md`: SHA-256 `7CF754F2CC328ADBD5A168A0D6717D05ACFC4A847CDF8BEACA49CE32AD4B68FC`.

Both were read from `C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.38/skills/`. Apple API reference was checked for `NSFileCoordinator.coordinate(writingItemAt:options:error:byAccessor:)` and `PKStroke.init(ink:path:transform:mask:)`; this is API inspection, not native build evidence.
