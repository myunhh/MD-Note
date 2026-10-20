# Favorites and recently opened metadata

Assigned worktree: D, branch `team/team-7dc35eaa/D`.

Implementation uses a main-actor observable singleton, per-note PropertyList-encoded UserDefaults entries under `docLibraryMetadata:` plus `LibraryStore.relativeKey`, and published updates. The library provides a favorite context action, star and VoiceOver value, persisted current-folder favorites filter with reset action, and recently-opened sort with deterministic name/path ties. Canvas creation records the open; list loads and SwiftUI canvas updates do not. Note/folder renames and open-document external moves carry metadata. Trash integration relies on A snapshotting this prefix and posting `libraryMetadataDidChange` after mutations.

## Evidence ledger

| Criterion / scenario | Invocation / inspection | Binary observable | Artifact |
|---|---|---|---|
| English/Korean feature strings resolve without missing or duplicate keys | `node scripts/check-localization.mjs` | exit 0 and bilingual-key success line | `checks.log` |
| Existing block hash identity remains stable | `node MDNoteCore/Tests/parity/hash_parity.mjs` | exit 0 and golden-vector success lines | `checks.log` |
| Patch whitespace is valid | `git diff --check` | exit 0 | `checks.log` |
| Only approved app/preferences/UI/localization hooks change | `git diff` plus `LibraryMetadataStore.swift` source | Changed paths and source bytes captured; source inspection only | `implementation.diff`, `LibraryMetadataStore.swift.txt`, `sha256.json` |
| Favorites persist and re-render; sorting uses opens rather than modifications | Inspect published store save/reload, `visibleDocuments`, canvas construction hook | Source wiring present; native behavior UNVERIFIED | `implementation.diff`, `LibraryMetadataStore.swift.txt` |
| Metadata follows note, folder, and open-document external rename | Inspect exact-key/descendant boundary migration and three rename call sites | Source wiring present; native behavior UNVERIFIED | `implementation.diff`, `LibraryMetadataStore.swift.txt` |
| Trash/restore metadata round trip and permanent deletion | Contract with member A: plist snapshot of prefix and notification | Integration and native behavior UNVERIFIED in isolated D branch | this report |
| Native build, persistence restart, visual layout, VoiceOver and controls | Tool availability probe | Swift, sourcekit-lsp, Xcode and iPad simulator unavailable | `environment.log` |

## Required native verification

1. Add a favorite from a note menu; verify filled star and VoiceOver Favorite value. Toggle the favorites filter, remove the last favorite, and use Show All Notes to recover the list. Repeat English/Korean, long names, large Dynamic Type and iPad portrait/landscape.
2. Open A, then B without editing either; Recently Opened must place B first. Force quit/relaunch and confirm favorites and open order persist. Listing, searching, changing sort and changing document UI state must not record additional opens. Never-opened and equal-timestamp notes must sort by localized name then relative path.
3. Rename a favorited/opened note and its containing folder; both favorite state and timestamp must follow. Verify neighboring folder prefixes such as `/Folder2` remain untouched when `/Folder` moves. Rename an open note using Files and verify the external-move hook.
4. With A integrated, trash a favorite note/folder, create a different same-name note, and confirm it does not inherit the old metadata. Restore to a collision-safe destination and confirm the old favorite/time follow the restored item. Permanently delete and confirm snapshot preferences are removed.
5. Before/after metadata actions, compare note and ink sidecar bytes. The implementation writes preferences only; runtime byte equality is still to be checked on iPad.

## Limits and review notes

No Swift compiler or simulator is present. No native build, Swift persistence test, or visual/accessibility PASS is claimed. Source inspection and Node checks cannot substitute for those observations. The visual-qa capture/reviewer gate is unsatisfied because the native surface cannot run in this environment. No new dependencies or package manifests were added; npm/pip audit does not apply to this Swift-only feature. The existing JS hash parity runner exercises the real renderer hashing code.

The `omo-agent-toolkit` Windows wrapper failed with a syntax error; direct Node CLI `ulw-loop status --json` reported `ULW_LOOP_PLAN_MISSING`, so evidence is under `.omo/evidence/`. An attempted absolute Git Bash invocation landed in a Linux path and could not resolve the Windows worktree gitdir; all mutations and subsequent validation use native PowerShell. No global settings or LSP installation were changed. No upstream is configured for this local feature branch.
