# Upgrade acceptance and evidence ledger

Task: implement approved live Markdown editing, free ink anchoring/reflow, blank/Markdown insertions, then local Astra integration and bug checks. This ledger records observable outcomes; a checked design contract is not evidence of completed behavior.

## Baseline

- Baseline main: `26a04d173fbcacc4161e77048de04f1cea8f03e7`.
- Parent product worktree clean before execution; task-owned team state is untracked.
- No MD-Note Graphify graph; focused source navigation used. No graph build/install.
- Existing Node fixtures: see `baseline-verification.md`.
- Swift/Xcode/native PencilKit unavailable on Windows; user explicitly owns Mac/iPad acceptance.

## Required observable behavior

1. Rich rendered text edit → Markdown change payload → coordinated native save with conflict detection. Untouched unsupported blocks/frontmatter remain intact. Empty note creation, headings/lists, Korean IME commit boundaries, undo/redo, and failure paths covered.
2. Stable text/ink identity survives content edits and saved snapshot reload; text following uses current fragments, rigid groups retain shape, repeated layout does not accumulate drift. Deleted/ambiguous targets retain original ink for safe reattachment.
3. Blank and Markdown insertion → following text moves → attached ink moves → insertion resize/move/remove/undo → state roundtrip. Blank inserts are anchorable, supplements share the same coordinate system and can carry annotations.
4. Existing images/math/code/search/outline/bookmarks and offline rendering are preserved. Supplement images are collected for archive export; composed content included in PDF.
5. Sidecar v1 migration, v2 decode/encode, future-version read-only behavior and corruption handling remain safe. No source or sidecar clobber on failed save/external conflict.
6. Pen/text input does not break existing scrolling/zoom; no drawing replacement while Pencil is down. Native checks unavailable must be listed explicitly, never inferred from JS tests.

## Integration gate

- A-D feature reports and full local commit IDs required before INTEGRATE.
- Astra integrates main locally and records full final SHA and actual test commands/results.
- Independent read-only Astra review audits the integrated result and evidence, with exact file/line findings. Product fixes return to integrator; applicable checks repeat after fixes.
- Leader verifies final evidence and no feature worker remains active before delivery.
- No remote push/publication/merge; keep local feature branches for recovery.

## Current handoffs

- B core: `b15059c6eccf6efff0fd8dd76376134f2666a8f2`, reported. `B-api.md` and `B-result.md` are the durable API/handoff. 31 Unicode fixture assertions and 8/8 bridge hash cases passed; 14 new XCTest scenarios authored, not executed without Swift.
- C layout: latest `de9ea3aeca6f7f14c1b45cbe385ed88475677714` includes initial `78cc71d91f43cc14b85221e3d3843939076e4e74`, reported. `C-api.md` documents exact API. Leader read report and 27 true DOM assertion records, and inspected actual `narrow-highlight.png`: five range-following highlight fragments and reserved blank space in a library fixture, not app visual acceptance.
- A editor: `b401faa6ad20af7b80f33b7975375d4bf3a3dc4d`, reported 28 editor DOM + 28 search DOM + 18 archive fixtures, 165 bilingual keys and npm audit zero. Final API includes live replacement/split-merge maps and stable history IDs.
- D native: `32de5e008d877e8ce2ea81745ed5df45198a3041`, reported 12 native source-contract checks and existing archive fixtures passed; 10 native XCTest scenarios authored, not executed. Exact contracts/results in `D-api.md` and `D-result.md`.
- All four slices now have reported full commits. I Astra is authorized to resume via `followup_task` with INTEGRATE, perform local merges and cross-boundary fixes/tests in parent main, then return exact SHA/evidence. No remote actions.
- Leader combined browser smoke: PASS, exact clean commit `9e03057263b6c6024652019b94722ed681885745`, 12/12 real browser assertions; evidence `.omo/evidence/root-live-ink/verification.md`, `results.json`, `composed-page.png`. Tracked tree clean before/after and HEAD unchanged. Native runtime remains unverified.
- I integration: exact final SHA `9e03057263b6c6024652019b94722ed681885745`; normal local feature merges, fixes `13eb04a3205457049695df604fe4a5d39f1f4e9e`, docs commit final. All final available checks exit 0; editor33 + layout27 + search28 real DOM assertions. Full matrix `.omo/evidence/integration-live-ink/report.md`.
- Independent R Astra review REJECTED exact SHA `9e03057263b6c6024652019b94722ed681885745`. Three HIGH blockers: native BlockGeometryDTO drops blockID, shortcut-reference editing loses link semantics, and softbreak normalization emits a broad false-deletion edit that detaches unchanged annotations. One MEDIUM source-test quality finding. Full report preserved at `.omo/evidence/integration-live-ink/independent-review.md`.
- I Astra reactivated for a bounded H1-H3/M1 repair batch. No final approval claimed; prior clean-SHA browser passes are limited evidence and do not close the new findings. A fresh independent reviewer will audit the repaired SHA after affected checks and leader smoke rerun.
- Completed R checkout was verified clean, unlocked and removed after its terminal verdict. Its report remains intact.
- R1 repair committed by I: `310933ac01b671ce98e803eac1181e355a6d1a62`, clean tracked tree. H1 real DTO forwarding/native adapter regression, H2 shortcut-reference safe fallback, H3 preserved softbreak parser/schema coordinate text, M1 reduced source pseudo-checks. Repair matrix `.omo/evidence/integration-live-ink/repair-r1.md`; original rejection unchanged.
- Repaired exact-SHA checks PASS: browser boundary25 + editor33 + layout27 + search28; Node/syntax/audit/reproducibility checks; leader independently reran combined browser smoke12/12 on clean `310933ac01b671ce98e803eac1181e355a6d1a62`, HEAD unchanged before/after. Native execution still UNRUN. A fresh R2 independent review is next; no final approval yet.
- Final R2 independent repair review: APPROVE / codeQualityStatus CLEAR / no established blockers at exact SHA `310933ac01b671ce98e803eac1181e355a6d1a62`. Report `.omo/evidence/integration-live-ink/independent-review-r2.md`; canonical pointer `.omo/evidence/mdnote-live-ink-code-review.md`. R2 freshly executed boundary25 + editor33 + static10 checks and traced actual DTO/consumer seams. Original rejection is preserved. Reviewer outputs durably copied under `independent-r2-browser/`; original temporary result directories retained after policy rejection of deletion, with no equivalent retry.
- Exact final coverage: leader real-browser smoke PASS (12 checks) and independent R2 APPROVE both bind to `310933ac01b671ce98e803eac1181e355a6d1a62`. User-deferred native build/device acceptance is explicitly UNRUN, not a passing row. No product edits after this coverage. Local delivery achieved; team resource/state cleanup remains.
- A-D workers have ended. Their evidence was copied to `.omo/evidence/live-ink-workers/{A,B,C,D}`, exact tips and clean tracked source verified, then their task-owned worktrees removed. Feature branches remain. See preserved evidence index for old-path mapping. R review tree and team artifacts remain intact.
- Hook receipt quirk: worker C/B stop verification accepts only session-origin `.omo/evidence` rather than a command's workdir. Task-specific receipts allowed at `C:/Users/picom/orca/.omo/evidence/mdnote-layout-C/` and `mdnote-core-B/`; product edits remain isolated. No runtime model introspection is exposed; explicit spawn configuration is recorded in baseline report.
