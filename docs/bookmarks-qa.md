# Bookmarks native verification

Implementation is provided; native execution and rendered UI validation are **pending**.
The implementation host is Windows without Swift, Xcode, SourceKit, or an iOS simulator.
Node localization and hash checks do not validate Swift compilation or UI behavior.

## Automated checks on macOS

Run `swift test --package-path MDNoteCore` and retain its full output. The eight
`BookmarkStoreTests` cover multiple persisted entries, rename/delete/reopen,
duplicate-block identity, layout changes, missing-anchor fallback, malformed/newer
sidecars, external replacement/deletion, competing writers, invalid numbers,
document/folder relocation, and destination collision preservation.

Generate the Xcode project with `xcodegen generate`, then build the MDNote scheme
for an available iPad simulator. Retain the build log and simulator identity.

## Manual scenarios (English and Korean)

Use a disposable library containing a long Markdown note with repeated paragraphs,
headings, and an image. Capture each scenario's before/after screenshot and record
the observed result. Repeat at normal and accessibility text sizes, in full-screen
and narrow iPad Split View. The app's existing light-only appearance is intentional.

1. Open More > Bookmarks. Empty state explains the add action. Save at least three
   distinct positions; names default to nearby block text. Rename one in its actions
   menu, cancel another rename, delete one. Relaunch: the two retained names and IDs
   persist in `<note>.md.bookmarks`; `.inknote` bytes remain unchanged.
2. Set non-default zoom and horizontal offset. Jump to each bookmark: the saved
   reading position returns without changing x/zoom. Repeat with Reduce Motion on:
   there must be no animated positional jump. Verify first and last document positions.
3. Insert content above an anchored block, reopen, and jump. The bookmark follows
   the same hash/occurrence sequence. Remove that block: jump uses the saved document
   fraction, shows the explanatory status, and keeps the bookmark in the list.
4. Rename the note and then its containing folder in the library. Reopen and jump;
   both `.inknote` and `.bookmarks` follow. While the note is open, rename it and its
   folder in Files; the same behavior holds. A preexisting destination companion
   prevents overwrite. Record SHA-256 before/after for both conflicting companions.
5. Replace `.bookmarks` with malformed JSON and reopen. The list shows a read error;
   adding/editing are disabled and bytes are unchanged. Repeat with version 2 JSON.
   Restore a valid sidecar and choose Reload bookmarks to recover.
6. With bookmarks loaded, externally modify or delete the companion, then attempt
   add/rename/delete. An error appears; the foreign bytes or absence are preserved.
   Reload explicitly before retry. In two windows, save in the first then save from
   stale state in the second: the second save must fail without losing the first.
7. Force an external-rename companion collision. Show the error, resolve the conflict
   in Files, and select Reload bookmarks. The original bookmarks follow the renamed
   note. No file should be silently deleted or replaced.
8. VoiceOver and hardware keyboard: More > Bookmarks, add, row jump, named actions
   menu, rename field/save/cancel, delete, reload, and close all remain reachable and
   labeled. Long Korean names wrap without clipping. Actions have 44-point targets.
9. Integration with other features: trash/restore and archive export/import retain
   `.bookmarks` byte-for-byte; document find, outline, beginning/end, undo, and ink
   still work. These integrations require the other feature commits.

## Integration locations

`DocumentSession` imports MDNoteCore and publishes bookmark state. `DocumentScreen`
adds a More menu item and sheet. `DocumentCanvasViewController` opens/relocates the
store, reports load readiness, and delegates jumps to the existing scroll function
that preserves x/zoom and honors Reduce Motion. `LibraryStore.rename(doc:to:)`
moves note, ink and bookmarks as a group with collision preflight and reverse rollback.
If rollback itself fails, the error directs recovery in Files; no bytes are discarded.
