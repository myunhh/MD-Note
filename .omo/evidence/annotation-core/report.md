# Annotation core evidence

Worktree: `C:/Users/picom/orca/MD-Note/.omo/teams/team-e43dac36/worktrees/B`
Branch: `mdnote-live-ink/annotation-core`
Scope: B only, stable block/range models, conservative reconciliation, v2 migration, study values.

## Executed observations

| Scenario | Exact invocation | Binary observable | Captured artifact |
| --- | --- | --- | --- |
| Korean/emoji/CRLF UTF16 fixture compatibility with JavaScript graphemes | `node MDNoteCore/Tests/parity/anchor_fixture_check.mjs` | Exit 0, 4 fixtures / 31 assertions passed | `unicode-fixtures.log` |
| Existing real bridge content hashing unchanged | `node MDNoteCore/Tests/parity/hash_parity.mjs` | Exit 0, 8/8 golden values | `hash-parity.log` |
| Patch whitespace validity | `git diff --check` | Exit 0 | `environment-and-diff.log` |
| Native test availability | `Get-Command swift,sourcekit-lsp -ErrorAction SilentlyContinue` | Swift available: False | `environment-and-diff.log` |
| Active attempt directory | `node C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.38/dist/cli-node/index.js ulw-loop status --json` | No loop plan, exit 1; use .omo/evidence | `loop-status.log` |
| Precommit dependency audit | `npm audit --package-lock-only --ignore-scripts` | ENOLOCK exit 1; no root package/lockfile or new npm dependency in this slice | `npm-audit.log` |

Node checks validate JavaScript boundary fixtures and the existing bridge. They do NOT
execute the new Swift implementation. No native build or XCTest pass is claimed.
Git Bash dispatch unexpectedly entered Linux `/mnt/c` and could not use the Windows
worktree/gitfile; verification used Windows PowerShell. No installation performed.

## Authored native acceptance scenarios, pending Mac execution

Invocation for ALL scenarios: `swift test --package-path MDNoteCore`.
Expected binary observable: exit 0 with named XCTest passing. Captured execution
artifact is currently unavailable because this host has no Swift; this is a limitation.

- `StableAnnotationTests.testUTF16RejectsSurrogateCombiningAndJoinedEmojiInteriors`
- `StableAnnotationTests.testSharedUTF16Fixtures`
- `StableAnnotationTests.testKnownReplacementMovesAndExpandsRangeWithoutChangingGraphemes`
- `StableAnnotationTests.testExplicitSplitMergeMappingAndUndoUseOriginalRange`
- `StableAnnotationTests.testExternalQuoteResolutionDoesNotTrustOldOffset`
- `StableAnnotationTests.testStableIDSurvivesTextEditMoveAndDuplicateContent`
- `StableAnnotationTests.testIdentityRestorationUsesSnapshotAndNotHashAlone`
- `StableAnnotationTests.testFollowingTextPreservesOriginalBytesAndDetachesDeletedQuote`
- `StableAnnotationTests.testDuplicateStableIDsNeverResolve`
- `StableAnnotationTests.testUnchangedRepeatedTextKeepsExactRangeOnReopen`
- `StableAnnotationTests.testV1MigrationPreservesOrphansAndNewIDsAcrossSecondLoad`
- `StableAnnotationTests.testV1UnresolvedLiveInkMovesToOrphansWithoutPayloadLoss`
- `StableAnnotationTests.testFutureVersionRejectedEvenByDirectDecoderAndEncoder`
- `StableAnnotationTests.testStudyRoundTripAndValueUndoPreserveInk`
- Existing `ReanchorTests` updated only where old duplicate guessing conflicts with
  approved detach/preserve policy; unique moved/deleted/edited-block scenarios retained.
- Existing `SidecarTests`, `BookmarkStoreTests`, and other package suites remain required.

## Integration conditions

1. Callers persist/restore reconciled IDs and set documentUnchanged only after actual hash check.
2. A owns editor transaction ID mapping and supplement blockIDs. D retains ink snapshots
   for undo, since inverse text deltas alone cannot recover a detached annotation.
3. Keep orphan arrays and original strokeData intact when spaces or target ranges disappear.
4. Core has no rendering, PencilKit capture or coordinated write authority; those checks
   belong to A/C/D integration. Do not infer UI acceptance from these core artifacts.
5. StudyInsertion.blockIDs defaults [] on decoding older DTOs. The API is detailed in
   shared `artifacts/B-api.md`.

## Skills consulted

- git-master SKILL.md SHA256 `7CF754F2CC328ADBD5A168A0D6717D05ACFC4A847CDF8BEACA49CE32AD4B68FC`
- comment-checker SKILL.md SHA256 `2E33BA95D76C486B818C12097DEC4CCE17B0ACEC1329CAF311765B99874BC0EF`

Requested model: gpt-6.1-sol / xhigh. Runtime identity cannot be independently
introspected in this member session, so no stronger verification is claimed.
