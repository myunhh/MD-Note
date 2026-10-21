# Annotation layout verification

Executed 2026-10-20 in isolated member C worktree. Invocation: `node scripts/check-annotation-layout.mjs` with MDNOTE_OMOWRIGHT_LOADER set to `C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.38/skills/browser/scripts/omowright.mjs` and MDNOTE_CHROME set to `C:/Program Files/Google/Chrome/Application/chrome.exe`.

Binary observable: process exit 0; **27/27 real Chrome DOM checks passed**. Every exact scenario name and pass boolean is captured in `dom-results.json` beside this report. This is not a mock DOM test. `fixture.html` captures the actual module source loaded for the run. `narrow-highlight.png` is the fresh 1440x900 screenshot: five highlighted line fragments, visible reserved blank area, math/image blocks below it. The prior visually identical 26-check capture was opened and inspected; final callback regression changes no screenshot state.

| Criterion | Exact scenario(s) in dom-results.json | Captured artifact |
|---|---|---|
| Stable geometry plus legacy keys | legacy identity retained; supplement blocks identifiable across reopen; renderer receives persisted supplement block IDs | dom-results.json |
| Real multiline reflow | multiline range reflows; text scale reflows fragments; underline and highlight map every line | dom-results.json, narrow-highlight.png |
| Reserved blank height | blank insertion reserves height; blank is ink target; resize pushes downstream by delta; removal restores downstream geometry | dom-results.json, narrow-highlight.png |
| Move/boundaries | move follows selected boundary; null boundary inserts at start; missing insertion boundary preserved visibly | dom-results.json |
| Original ink retention | repeated placement has zero accumulated drift; rigid shape and pressure preserved; rigid range deletion detaches without losing originals | dom-results.json |
| Unicode | UTF16 splits inside emoji rejected; combining grapheme splits rejected; whole emoji grapheme accepted | dom-results.json |
| Ambiguity/deletion | ambiguous quote preserved detached; deleted quote preserved detached; duplicate block IDs ambiguous; deleted rigid target preserves original | dom-results.json |
| Math/image safety | math and image retain rigid targets; math range refuses glyph/source mismatch | dom-results.json |
| Transactional input validation | invalid insertions do not mutate live content | dom-results.json |

Additional checks: `node --check MDNote/Resources/WebAssets/app/annotation-layout.js` exited 0; `git diff --check` exited 0. No runtime npm dependencies were added. Required precommit `npm audit --offline` attempted, failed ENOLOCK because this base has no package lock; no audit pass claimed. Missing TypeScript LSP was not installed (no authorization; tool discovery unavailable). Toolkit attempt status wrapper failed before returning state; evidence therefore uses `.omo/evidence/`.

Known boundaries: standalone module only; app undo/history, actual persisted supplement inner IDs, bridge callbacks, native PencilKit drawing lifecycle and WebKit rendering require integration validation. Content-derived supplement child IDs safely detach on changed content unless the supplied renderer persists stable IDs. Math/image ranges intentionally refuse glyph/source mapping; rigid placement remains available. No arbitrary stroke recognition. Floating supplements explicitly opt out of flow and need reapplication after anchor layout shifts. No native build or iPad QA claimed.

Canonical skills read: frontend SHA256 A2542F14B599D2C3195FCC0633FF803ADD0B44D358DEA7B1837C1E46D08CFBD3; browser 76D063D0A112CD61F635BAA95BFAD85AB0A7D3F15BA4612A689DD43F0B1917C3; visual-qa B2BD99FEF65350CDB8BB433BB45D59EF90E3E12CA897FB52D8DB9D65A7777719; git-master 7CF754F2CC328ADBD5A168A0D6717D05ACFC4A847CDF8BEACA49CE32AD4B68FC. These live under `C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.38/skills/`. Library geometry scope adds no product visual design; final integrated UI review is assigned to the integrator.
