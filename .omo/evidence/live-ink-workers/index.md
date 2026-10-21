# Preserved feature-worker evidence

The four completed task-owned feature worktrees were removed after verifying their exact committed tips, clean tracked files, and that all remaining untracked files were task-owned evidence. Feature branches remain intact and all four tips are ancestors of the integrated main result.

- A: commit `b401faa6ad20af7b80f33b7975375d4bf3a3dc4d`, evidence copied from `worktrees/A/.omo/evidence/rich-editor/` to `A/`; additional search screenshots/results copied to `A/document-search/`.
- B: commit `b15059c6eccf6efff0fd8dd76376134f2666a8f2`, evidence copied from `worktrees/B/.omo/evidence/annotation-core/` to `B/`.
- C: commit `de9ea3aeca6f7f14c1b45cbe385ed88475677714`, evidence copied from `worktrees/C/.omo/evidence/annotation-layout/` to `C/`.
- D: commit `32de5e008d877e8ce2ea81745ed5df45198a3041`, evidence copied from `worktrees/D/.omo/evidence/native-ink/` to `D/`.

Old absolute worktree evidence paths in feature handoffs should be resolved through this mapping. Current integrated verification is under `../integration-live-ink/`; leader combined browser smoke is under `../root-live-ink/`. No uncommitted product edits or unknown user files were discarded.
