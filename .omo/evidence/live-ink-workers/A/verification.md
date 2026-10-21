# A rendered editor verification

Worktree: `C:/Users/picom/orca/MD-Note/.omo/teams/team-e43dac36/worktrees/A`
Branch: `mdnote-live-ink/rendered-editor`
Base: `26a04d173fbcacc4161e77048de04f1cea8f03e7`

## Invocations and binary observables

Environment for browser commands:

```
MDNOTE_OMOWRIGHT_LOADER=C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.38/skills/browser/scripts/omowright.mjs
MDNOTE_CHROME=C:/Program Files/Google/Chrome/Application/chrome.exe
MDNOTE_LAYOUT_MODULE=C:/Users/picom/orca/MD-Note/.omo/teams/team-e43dac36/worktrees/C/MDNote/Resources/WebAssets/app/annotation-layout.js
```

The last variable injects C's committed module for isolated A testing; omit it
after local integration includes C's file. No other worker file was modified.

| Scenario | Invocation | Observable | Artifact |
|---|---|---|---|
| Rendered keyboard edit, Korean text, rich marks, frontmatter CRLF/reference/table preservation | `node scripts/check-rich-editor.mjs` | 28/28 named assertions pass | `results.json`, `run.log`, `rich-editor.png` |
| Composition blocks save/flush, explicit source Apply/Cancel | same | named composition/fallback assertions pass | `results.json`, `source-applied.png` |
| Backspace/Delete merge, split maps, before/inside-range maps, keyboard undo, history IDs | same | exact oldText/UTF16/maps/identity assertions pass | `results.json`, `events.json` |
| Study rich editing, stable children, empty supplement, resize/remove/undo | same | DOM content, IDs, actual height assertions pass | `results.json`, `rich-editor.png` |
| External reorder/duplicate identity safety | same | unique match restored; ambiguous IDs not reused | `results.json` |
| Existing search behavior | `node scripts/check-document-search.mjs` | 28/28 | `search.log`, `../document-search/dom-results.json`, `../document-search/highlight.png`, `../document-search/fallback.png` |
| Existing image/reference parser | `node scripts/check-archive-renderer.mjs` | 18/18 | `archive.log` |
| Localization | `node scripts/check-localization.mjs` | 165 matching bilingual keys, 169 lookups | `localization.log` |
| Offline reproducible build | `cd editor; npm run build; npm ci --ignore-scripts; npm run build` | generated bundle SHA256 identical | `build.log` |
| Dependency security | `cd editor; npm audit --json` | zero vulnerabilities | `npm-audit.json` |
| CSS draft lint | `bun C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.38/skills/frontend/scripts/perfection/check-accent-stripes.ts MDNote/Resources/WebAssets/app/theme.css` | 1 file, no accent stripes | `checks.txt` |
| Diff whitespace | `git diff --check` | exit 0 | `checks.txt` |

## Limits

This Windows host cannot build UIKit/WebKit/PencilKit Swift or run physical
iPad Korean IME, Pencil input routing, native save conflicts/export/archive.
Composition event regression proves the JS suppression guard, not OS keyboard QA.
Screenshots are real owned Chrome desktop captures of the fixed document canvas;
native zoom, compact SwiftUI toolbar, iPad accessibility, and iPad performance
remain integration/device acceptance. Independent review belongs to I/root.

The editor deliberately uses source fallback for unsupported CommonMark
extensions (tables, task lists, callouts, math, raw HTML, reference syntax).
Adjacent ordinary paragraphs merge in the rendered editor. Other unsupported
boundaries are kept separate. Source slices outside the edited block are untouched.

Skill SHA256:
programming `3CD471C76187629F4DD0A45890A847EAFA5CD5FFEC3BD71425D97C71AC90B5E4`
frontend `A2542F14B599D2C3195FCC0633FF803ADD0B44D358DEA7B1837C1E46D08CFBD3`
git-master `7CF754F2CC328ADBD5A168A0D6717D05ACFC4A847CDF8BEACA49CE32AD4B68FC`

The installed `omo-agent-toolkit ulw-loop status --json` failed with
`The syntax of the command is incorrect.` Evidence therefore uses .omo/evidence.
