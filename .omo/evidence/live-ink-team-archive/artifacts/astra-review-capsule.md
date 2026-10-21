# Independent Astra correctness review capsule

This is an executable read-only review, not implementation. The leader will supply an exact final integration SHA and an isolated locked review worktree after the integrator's checks finish. Do not spawn reviewers or implement fixes.

## User outcome

MD Note should allow Notion-like rendered Markdown writing on its existing continuous iPad page, free Pencil handwriting on top, natural text-range reflow for selected underlines/highlights, shape-preserving freehand/graphs, and inserted blank/Markdown study space that shifts following content. User explicitly requested 6.1 Sol xhigh feature research/implementation, followed by Astra xhigh local merge and bug tests. The user will run actual Mac/iPad acceptance. No remote publication/push/merge is authorized.

## Source scope

Review full diff from baseline `26a04d173fbcacc4161e77048de04f1cea8f03e7` to supplied final integration SHA, and relevant neighbors/tests. Original feature tips: A `b401faa6ad20af7b80f33b7975375d4bf3a3dc4d`; B `b15059c6eccf6efff0fd8dd76376134f2666a8f2`; C `de9ea3aeca6f7f14c1b45cbe385ed88475677714`; D `32de5e008d877e8ce2ea81745ed5df45198a3041`. Review the final integrated fixes rather than their old individual state.

Durable interfaces and requirements are `upgrade-contract.md`, `A-api.md`, `B-api.md`, `C-api.md`, `D-api.md`, and `acceptance-ledger.md` in this artifact directory. Keep context bounded; do not load old session transcripts, archived skills, or the full library.

## Focus on concrete bugs

- Offline rich editing, raw unsupported Markdown/frontmatter/CRLF/reference preservation, real keyboard paragraph split/join, Korean composition boundaries and save events.
- Actual DTO compatibility in Swift/JS, stable block IDs and child supplement IDs, explicit UTF16/grapheme boundaries, trusted replacement/split/merge mappings versus conservative external recovery.
- Undo/redo restores annotation attachments/live-orphan state alongside text/study state; duplicate words, full target deletion and restore, repeated exact text with different study state.
- Original strokes remain immutable; projected strokes cannot be recaptured as new originals; eraser/native undo handling is plausible; active Pencil guards cover every drawing replacement. New native APIs must compile plausibly with deployment iOS17/Swift version in project.yml.
- Coordinated compare-before-atomic Markdown save; watcher self-save suppression; failed read/render cannot become writable placeholder; stale save callbacks cannot overwrite newer edits; future-version sidecars remain read-only; local recovery does not clobber source.
- Blank/study space truly participates in layout and can carry ink; resize/move/remove/undo/reopen retain targets; export captures composed page and includes supplement assets with correct per-fragment Markdown scope.
- Existing search/outline/bookmarks/images/math/code/archive/PDF paths remain connected. Source fallback opening/Cancel must not orphan existing ink or treat UI labels as document text.
- Dependency exact pins and committed offline bundle reproducibility, safe Markdown rendering, localized new user-facing strings.

## Evidence and limitation

The integrator's final exact commands/results/reproductions are under parent `.omo/evidence/integration-live-ink/`. Root independently exercises a combined real owned-Chrome smoke under `.omo/evidence/root-live-ink/`, and reruns on final SHA. Feature evidence is retained separately.

Swift/Xcode and actual PencilKit/iPad runtime are unavailable on this Windows host. Native XCTests are authored but unrun. This is an explicit user-deferred acceptance constraint, not an automatically satisfied row, and not by itself a reason to block local delivery. Still identify concrete source/API defects and missing required behaviors. Do not equate JS source-contract checks with native execution.

Return `APPROVE`, `REJECT`, or `INCONCLUSIVE`, full reviewed SHA, and evidence-backed findings ordered by severity with exact file:line, trigger, consequence and smallest fix. Subjective style or hypothetical future features are notes, not blockers. Root will send concrete blockers to the integrator. One reviewer only; final reports and evidence must redact credentials/private data.
