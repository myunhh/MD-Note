# Integrated feature code review

Baseline `4ad8a7c` to runtime HEAD `fd4489c`; reviewed 2026-10-16. Scope: trash/restore, document find, bookmarks, favorites/recents, recursive library search, and ZIP transfer. Read-only product review; no implementation edits.

codeQualityStatus: WATCH
recommendation: REQUEST_CHANGES
blockers: Generic ZIP import must not reject Markdown code examples as missing image assets (M1).

## Findings

### CRITICAL

None found.

### HIGH

None found. Native compilation and iPad execution remain unverified, not claimed as passes.

### MEDIUM

**M1 — Incomplete second Markdown parser rejects valid generic ZIP imports.** `MDNote/Core/NoteArchive.swift:84`, `:96`, `:261`, `:264`.

Reproduction: create a ZIP with one UTF-8 `note.md` containing four spaces followed by `![example](missing.png)` and no manifest. Markdown renders this as an indented code block, with no image. The import scanner retains that line, extracts `missing.png`, and the import loop calls `regularFile`, which throws `missingAsset`; the otherwise valid archive is never published. The same parser disagreement affects other Markdown constructs (the concrete indented-code example is sufficient to establish the defect).

Independent probe on this checkout used the bundled markdown-it and the inline regex extracted from production Swift. Observed output:

```json
{"input":"    ![example](missing.png)","rendered":"<pre><code>![example](missing.png)\n</code></pre>\n","importScannerCaptures":["missing.png"]}
```

This is source/data-flow evidence plus execution of the exact regex in JavaScript, not an executed native ZIP reproduction. Native XCTest should import that one-note archive and assert exact note bytes. Minimal fix: remove incomplete heuristic asset rejection for generic ZIPs while preserving path/type/size/CRC checks and own-format manifest verification, or supply references from the actual renderer parser. Avoid extending the regex into another Markdown parser.

**M2 — ZIP picker check pins Swift source formatting instead of behavior.** `scripts/check-archive-contract.mjs:25`.

The assertion requires the literal ordered source fragment `.plainText, .text, .zip`. Reordering equivalent accepted types or extracting the list into a value fails this check without changing behavior; leaving this text in an unused declaration passes despite a picker regression. Remove this assertion or verify the actual accepted content types at a native behavioral seam. The regex fixture checks in this script are explicitly limited compatibility probes and are not native import coverage. This finding is nonblocking independently of M1.

### LOW

None requiring action within the requested correctness-focused scope.

## Review basis and skill perspectives

Loaded the canonical `programming/SKILL.md` and `remove-ai-slops/SKILL.md` from installed OmO 5.1.33. Applied shared test, boundary, duplication, and complexity criteria; Swift has no language-specific reference in programming's language table. The two perspectives identify M1's redundant, divergent parser and M2's implementation-shaped assertion. No prompt-prose, deletion-only, or tautological newly added native tests found. Native filesystem fixtures cover meaningful outcomes (bytes, collisions, rejected writes, and rollback). Imported path/manifest validation is justified at the untrusted archive boundary and should remain. No cleanup/refactor was performed in this read-only review.

Inspected changes and relevant callers in LibraryView, DocumentScreen, DocumentSession, DocumentCanvasViewController, MarkdownRenderer, bridge.js/theme.css, new UI/store/core files, project.yml, native tests, and JavaScript regression scripts. Inspected worker reports for archive-transfer/bookmarks/trash and their referenced renderer, contract and unavailable-native logs. Inspected `.omo/evidence/integrated-verification.md` and all 28 records in `integrated-document-search/dom-results.json`. These show reported Chrome DOM checks, not iPad behavior. Independently ran `git diff --check 4ad8a7c fd4489c` successfully and the indented-code probe above. Parent runs the full Node regressions; this reviewer did not rerun or claim their browser session.

The ZIP dependency is pinned to 0.9.20 and the archive XCTest target is included in project.yml. No definite compile/API defect was established by source review. Archive extraction stages before publishing, reserves collision destinations, checks streaming bounds and CRC, and rejects unsafe paths/symlinks. Trash retains rollback payloads and reserves companion names. Bookmarks compare loaded bytes before coordinated replacement. These observations are source-review conclusions, not native runtime certification.

No Swift/Xcode toolchain is available on this Windows host. Swift compilation, native XCTest, NSFileCoordinator/presenter interactions, multiwindow edits during trash/rename, native ZIP roundtrip, PencilKit, VoiceOver and iPad visual behavior remain unverified. No unsupported success claim is approved.

Applicable supplied AGENTS instructions and `../AGENTS.md` were consulted. No Graphify artifact was supplied/found; no mutation gate needed for this read-only review. The `omo-agent-toolkit ulw-loop status --json` wrapper failed with a syntax error. Invoking its installed Node status entry point directly returned `ULW_LOOP_PLAN_MISSING`, so this is the fallback `.omo/evidence/<goal>-code-review.md` artifact. Team context/notepad: `.omo/teams/team-7dc35eaa/guide.md`; integrated evidence: `.omo/evidence/integrated-verification.md`.

Parent acknowledged M1 and assigned a bounded fix after this review; the verdict above applies to `fd4489c` until the fix is rechecked.

## Final verdict after bounded correction recheck

Reviewed the working-tree correction over `fd4489c` in NoteArchive.swift, NoteArchiveTests.swift, check-archive-contract.mjs, and check-archive-renderer.mjs. This section supersedes the initial verdict; historical findings above remain for traceability.

codeQualityStatus: CLEAR
recommendation: APPROVE
blockers: []

- M1 resolved in source: the incomplete generic Markdown image scanner and its rejection loop are removed. Generic ZIPs preserve document bytes without inferring asset requirements. Own-format manifests still validate version, note path/type/existence, image count, image paths and required files. Entry path/type/symlink checks, case/Unicode collision checks, file-parent collision checks, declared and actual extraction bounds, CRC checks, staging cleanup and collision-safe final publication are unchanged. This removes heuristic validation, not extraction security.
- M2 resolved: the ordered Swift picker-source assertion is removed.
- The new native test imports seven Markdown fixtures and asserts exact output bytes and staging cleanup, including the original indented-code failure. It exercises public import behavior rather than asserting deletion of an implementation. Manifest tests additionally assert the specific missingAsset/unsafePath outcomes. The removed parser tests have no remaining production parser to cover; real export-parser behavior remains covered by the renderer suite.
- Reapplied the previously loaded programming/remove-ai-slops perspectives to the bounded diff: no new violation found. The fix reduces duplicated parsing and adds relevant behavioral regressions.

Independent checks executed on the corrected working tree: `node scripts/check-archive-renderer.mjs` PASS (18 real parser fixtures); `node scripts/check-archive-contract.mjs` PASS (path-unescape compatibility, dependency pin and error-localization checks only); scoped `git diff --check` PASS. Native XCTest and app compilation remain unexecuted on Windows. Approval is the source/code-quality verdict and does not certify native runtime or iPad product acceptance.
