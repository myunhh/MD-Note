# MD Note feature integration

Baseline: 4ad8a7c on main. Existing English support and navigation committed before fan-out. No existing Graphify graph present. Local integration only; no push or remote publication.

## Acceptance

- A: reversible note/folder trash, companions and safe restore, explicit permanent deletion.
- B: in-document text find, highlighting and previous/next without layout or ink identity changes.
- C: multiple named persisted bookmarks, navigate/rename/delete and companion preservation.
- D: favorite state and actual recent-open order, rename-aware persistence.
- E: whole-library recursive search with paths, cancellation, safe traversal and preserved folder browsing.
- F: portable images/ink/bookmark archives and safe direct ZIP import.
- English/Korean strings cover all new flows. Existing hash parity remains intact.
- Integrate all six committed branches, resolve interacting metadata/rename/trash/archive paths, run independent review.
- Native build/UI/Pencil checks require macOS/iPad and are not claimed from Windows source checks.

## Execution and cleanup

- [x] Inspect baseline/instructions and initialize team.
- [x] Create and bind A-F isolated worktrees.
- [x] Receive and verify A-F commits.
- [x] Merge A-F locally and resolve conflicts with an implementation member.
- [x] Verify available integrated checks and independent review (native execution explicitly unavailable).
- [x] Remove clean owned A worktree after integration.
- [x] Remove clean owned B worktree after integration.
- [x] Remove clean owned C worktree after integration.
- [x] Remove clean owned D worktree after integration.
- [x] Remove clean owned E worktree after integration.
- [x] Remove clean owned F worktree after integration.
- [x] Archive team, preserve final evidence, delete runtime team state.

## Shared contracts

Document companion suffixes: .inknote and .bookmarks. Trash hidden directory: .Trash. Favorites/recents: docLibraryMetadata: relative URL keys via LibraryMetadataStore.shared, with recursive move/remove methods. All features preserve Markdown/ink bytes and selected language. Each branch owns its feature-specific files and minimal integration hooks; root resolves combined behavior after merges.

All six feature branch tips verified as ancestors of fd4489c. Worker evidence copied to `.omo/evidence/feature-worker-evidence/`; each untracked file byte-compared before removing its worktree. Branch history retained. Independent review found one generic ZIP regex false positive, assigned to archive worker in root for correction. Native runtime checks remain unavailable on Windows.

Final archive correction `3221be9` resolves M1/M2; independent bounded recheck CLEAR / APPROVE, no blockers. Final documentation/delivered HEAD `34a3a9ff7db97e998bbcefd83570fdcd5aff19fb`. Available final checks pass: 140 bilingual keys/161 Swift lookups, 28 real DOM search cases, 18 actual renderer parser fixtures, 8 hash parity cases, export contract and JavaScript syntax/diff checks. Native build/XCTest/iPad/Pencil not executable on Windows; documented in docs/feature-integration-qa.md. npm audit ENOLOCK is not an audit pass. Product tree clean. No remote actions.
