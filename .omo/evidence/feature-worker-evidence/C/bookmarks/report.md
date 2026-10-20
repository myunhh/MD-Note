# Bookmark implementation evidence

Worktree: `C:/Users/picom/orca/MD-Note/.omo/teams/team-7dc35eaa/worktrees/C`
Branch: `team/team-7dc35eaa/C`; baseline `4ad8a7c`.

## Executed observations

| Scenario | Invocation | Binary observable | Artifact |
|---|---|---|---|
| Bilingual resource coverage and lookup consistency | `node scripts/check-localization.mjs` | PASS: 87 bilingual keys, 104 Swift lookups | `localization.log` |
| Existing block identity hash parity | `node MDNoteCore/Tests/parity/hash_parity.mjs` | PASS: 8/8 cases | `hash-parity.log` |
| Whitespace integrity | `git diff --check` | PASS: exit 0 | `diff-check.log` |
| Native persistence/anchor tests | `swift test --package-path MDNoteCore` | NOT RUN: command not found | `native-tests.log` |
| Dependency audit before commit | `npm audit --offline` | NOT AVAILABLE: ENOLOCK; repository has no npm lockfile, no dependencies added | `dependency-audit.log` |
| Attempt directory lookup | `omo-agent-toolkit ulw-loop status --json` | NOT AVAILABLE: command not found; using `.omo/evidence/` | `attempt-status.log` |

## Acceptance mapping and remaining verification

| Criterion | Implemented path and exact scenario | Required native observable | Status/artifact |
|---|---|---|---|
| Multiple named persisted positions, rename/delete/reopen | `testMultipleBookmarksRenameDeleteAndReopen` | Reopened values exactly equal saved values, no ink sidecar created | Unexecuted XCTest source; native-tests.log |
| Stable hash/sequence plus offset, reflow and missing block fallback | `testStableAnchorFollowsReflowAndDuplicateSequence` | Duplicate seq 1 resolves to 412; missing block uses y 560 and fallback flag, lastY 112 without height | Unexecuted XCTest source; native-tests.log |
| Corrupt/newer bytes preserved | `testCorruptAndNewerFilesArePreserved` | Initialization throws and bytes remain equal | Unexecuted XCTest source; native-tests.log |
| Loaded sidecar replacement/deletion preserved | `testExternalReplacementOrDeletionCannotBeOverwritten` | Save throws, foreign bytes or absence unchanged, published entries unchanged | Unexecuted XCTest source; native-tests.log |
| Concurrent stale first save rejected | `testCompetingWriterCannotOverwriteFirstSave` | Second store save throws and first saved entry remains | Unexecuted XCTest source; native-tests.log |
| Invalid values rejected | `testInvalidValuesDoNotReplaceSavedBytes` | Infinity rejected, prior bytes equal | Unexecuted XCTest source; native-tests.log |
| File/folder movement | `testDocumentAndFolderRelocationPreserveBytes` | Relocation preserves bytes and reopened records | Unexecuted XCTest source; native-tests.log |
| Destination collision preservation | `testRelocationCollisionPreservesBothFiles` | Relocation throws; both original and destination bytes equal | Unexecuted XCTest source; native-tests.log |
| Accessible bilingual list/add/jump/name/delete UI | docs/bookmarks-qa.md scenarios 1, 8 | Live iPad controls reachable, correct labels and text layout | Pending native screenshots and VoiceOver; no visual PASS claimed |
| x/zoom and Reduce Motion | docs/bookmarks-qa.md scenario 2 | x/zoom unchanged; reduce-motion jump unanimated | Existing scroll path reused; pending native execution |
| Library transaction and external move recovery | docs/bookmarks-qa.md scenarios 4, 7 | Both companions retained, failed rename rolls back, recovery reload follows note | Pending native execution |
| Trash/archive integration | docs/bookmarks-qa.md scenario 9 | Companion bytes unchanged across round trips | Pending integration with A/F commits |

New native test source: `MDNoteCore/Tests/MDNoteCoreTests/BookmarkStoreTests.swift`.
Manual invocation and captures: `docs/bookmarks-qa.md`.
SourceKit LSP is unavailable and its installation-decision tool is not exposed;
no tools were installed or global configuration changed.

## Self-review

Reviewed new store and UI sources, complete integration diff, and tests. Writes use
file coordination plus a byte comparison and atomic replacement; mutations publish
only after success. The store rejects unsupported/invalid records. Relocation errors
retain the recovery source URL for explicit retry. Library note rename preflights
all destinations and reverse-rolls back moved note/companions. Folder rename carries
companions with the folder. No ink schema or renderer changes. Fresh runtime/UI
evidence and independent integrated review remain required on a native host.
