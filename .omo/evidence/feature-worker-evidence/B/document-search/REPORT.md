# Document search evidence

Worktree: `C:/Users/picom/orca/MD-Note/.omo/teams/team-7dc35eaa/worktrees/B`
Branch: `team/team-7dc35eaa/B`. Base: `4ad8a7c`. No upstream configured.
No active attempt CLI is available; evidence is under `.omo/evidence/document-search/`.

## Implemented surface

More > Find in Document opens a native safe-area search bar. It provides query,
status, previous/next, clear and close. Session callbacks invoke the renderer;
returned y uses the existing native `scroll(toDocumentY:)`, which preserves x
and zoom and honors Reduce Motion. Requests use cancellation and revision checks
in Swift and monotonic revision rejection in JS. Native integration is source
reviewed only, not compiled or interactively validated in this Windows host.

The bridge uses escaped literal Unicode case-insensitive RegExp matching with
DOM ranges across inline text nodes, without changing content DOM, hashes or
block dimensions. Hard breaks and paragraph/cell boundaries are separated.
CSS Highlight API is primary; a clipped fixed overlay outside content is fallback.
WebKit confirms API support begins at Safari 17.2:
https://webkit.org/blog/14787/webkit-features-in-safari-17-2/
Thus fallback remains necessary for the project's iOS 17.0 minimum.

## Actual invocations and binary observables

Run from the worktree:

```sh
MDNOTE_OMOWRIGHT_LOADER='C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.33/skills/browser/scripts/omowright.mjs' MDNOTE_CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe' node scripts/check-document-search.mjs
node scripts/check-localization.mjs
node MDNoteCore/Tests/parity/hash_parity.mjs
node --check MDNote/Resources/WebAssets/app/bridge.js
git diff --check
npm audit --json
```

| Criterion / exact scenario | Binary observable | Captured artifact |
| --- | --- | --- |
| Mixed-case English, inline bold split, Korean, emoji and accented Latin; literal regex/HTML/script-looking text | Actual Chrome Range/count assertions all true | `dom-results.json`, `browser.log` |
| Empty document/query, absent term, next/previous modulo wrap | Actual result count/index assertions all true | `dom-results.json` |
| Stale revision submitted after current query | Prior 3-match result retained | `dom-results.json` |
| Clear both CSS and fallback; rerender replacement/removal | Registry/overlay gone or reattached to new DOM as expected | `dom-results.json` |
| Content/ink identity safety during CSS and fallback | JSON.stringify(layout()), content innerHTML and contentHeight equal pre-search baseline | `dom-results.json` |
| Navigation coordinate | Last match y > 500 and browser scrollY stays zero | `dom-results.json` |
| Fallback after text scale | Overlay y matches new Range y; layout unchanged by repaint | `dom-results.json` |
| Hard break and paragraph boundary | No concatenated-word false positive | `dom-results.json` |
| Actual highlight appearance | Both modes visibly paint active and inactive ranges without reflow; screenshots directly inspected | `highlight.png`, `fallback.png` |
| English/Korean resources and formatter compatibility | 80 keys / 95 lookups pass, exit 0 | `localization.log` |
| Existing JS/Swift hash golden table | 8/8 pass, exit 0 | `hash-parity.log` |
| JS syntax and whitespace | Both exit 0 | `verification.json` |
| Dependency audit | ENOLOCK, exit 1; project has no package.json/lockfile; no dependency added | `npm-audit.json` |

DOM suite is 28/28. It loads the production WebAssets index in installed Chrome
through the installed omowright owned engine and uses actual DOM Range/layout,
not stubs. The profile is under the evidence directory and removed after closing.
Screenshots demonstrate only web highlighting, not the SwiftUI bar.

## Unverified native acceptance / remaining manual checks

Swift, XcodeGen, Xcode and iPad simulator are unavailable. No native compilation,
full visual QA pass or VoiceOver/Pencil acceptance is claimed. On macOS run:

```sh
xcodegen generate
xcodebuild build -scheme MDNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
swift test --package-path MDNoteCore
```

On iPad repeat in English/Korean, portrait/landscape/narrow Split View, large
Dynamic Type, system light/dark (app is intentionally light-only): open the find
bar, type rapidly, clear and close during search, submit/next/previous repeatedly,
verify count and disabled states. Enable VoiceOver and Reduce Motion. Zoom and pan
horizontally, jump to the last match and verify zoom/x unchanged. Annotate text,
search/clear, externally edit, load late images and change text scale; verify ink
anchors and reapplied highlights. Check iOS 17.0/17.1 fallback and modern WebKit
primary behavior. Export PDF with active search and confirm highlights omitted.
These exact scenarios remain unverified, not inferred from Chrome or source.

## Integration

Preserve bookmark/favorites/archive sibling additions when merging:
DocumentScreen adds one State, safeAreaInset and More menu item;
DocumentSession adds only document search fields/methods;
DocumentCanvasViewController adds fields, open-reset, refreshNavigationAids hook,
and refreshDocumentSearch; existing scroll implementation is untouched.
MarkdownRenderer adds DTO and search method. Localization keys are exclusively
`documentSearch.*`. New Swift file is picked up by existing project.yml directory
sources. No ink schema, dependencies, global config or external resources changed.
Evidence is deliberately untracked; temporary screenshots are not in the commit.
