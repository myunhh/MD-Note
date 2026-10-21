# B annotation-core handoff

Commit: `b15059c6eccf6efff0fd8dd76376134f2666a8f2`
Branch: `mdnote-live-ink/annotation-core`
Worktree B is clean after commit. No merge/push performed.

Implemented source:
- `MDNoteCore/Sources/MDNoteCore/Block.swift`
- `MDNoteCore/Sources/MDNoteCore/AnchoredInk.swift`
- `MDNoteCore/Sources/MDNoteCore/Sidecar.swift`
- `MDNoteCore/Sources/MDNoteCore/Reanchor.swift`
- `MDNoteCore/Sources/MDNoteCore/StableBlockIdentity.swift`
- `MDNoteCore/Sources/MDNoteCore/TextAnchor.swift`
- `MDNoteCore/Sources/MDNoteCore/StudyInsertion.swift`

Tests/fixtures:
- `MDNoteCore/Tests/MDNoteCoreTests/ReanchorTests.swift`
- `MDNoteCore/Tests/MDNoteCoreTests/StableAnnotationTests.swift` (14 new scenarios)
- `MDNoteCore/Tests/Fixtures/anchor-utf16.json`
- `MDNoteCore/Tests/parity/anchor_fixture_check.mjs`

Exact API and JSON contract: `B-api.md` in this artifacts directory.
New Codable fields have source-compatible initializer defaults. v1 migration assigns
snapshot IDs, keeps original bytes, retains existing orphans and detaches unresolved
legacy ink. Direct decoder and convenience decoder protect future versions.
Stable-ID-first reconciliation preserves arbitrary rigid ink shape, while text behaviors
use grapheme-safe UTF16 anchors with quote/context. Unknown ambiguous duplicates detach.
Explicit editor replacement and split/merge helpers are provided; undo must retain old values.
Study values include persistent child `blockIDs` requested by A.

Executed: 31 Unicode boundary fixture checks passed; real bridge hash parity 8/8 passed;
staged diff check passed. Artifacts committed under `.omo/evidence/annotation-core/`.
Read `.omo/evidence/annotation-core/report.md` for exact scenario/invocation/observable matrix.

Limitations: Swift and SourceKit unavailable, so XCTest and native compilation were NOT run.
Required Mac invocation: `swift test --package-path MDNoteCore`.
Precommit npm audit attempted and returned ENOLOCK (no root dependency lockfile in this slice;
no dependency added). No installation performed. Renderer/native integration and UI checks
remain with A/C/D/I; these core checks do not establish end-to-end application acceptance.

Important integration points:
- Supply saved snapshots to identity restoration before accepting newly generated IDs as trusted.
- `documentUnchanged: true` only after real document-hash comparison; allows duplicate restoration.
- Apply TextAnchor replacement helper with OLD plaintext before reconciliation against new blocks.
- Restore anchor/ink snapshots on undo; inverse text deltas cannot resurrect deleted targets.
- Persist StudyInsertion.blockIDs from A unchanged.

Evidence path:
`C:/Users/picom/orca/MD-Note/.omo/teams/team-e43dac36/worktrees/B/.omo/evidence/annotation-core/report.md`
