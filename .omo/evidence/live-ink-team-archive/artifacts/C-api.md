# C annotation layout integration contract

Module: `MDNote/Resources/WebAssets/app/annotation-layout.js`. UMD export `window.MDNoteAnnotationLayout` / CommonJS `require(...)`. No dependencies. No bridge/index/theme/native edits.

- `snapshot(root)` returns array of `{blockID,blockHash,blockSeq,sourceLineStart,sourceLineEnd,text,rangeText,rangeStartUTF16,rangeEndUTF16,rangeSupported,studyID,x,y,width,height}`. Coordinates are document CSS pixels. `text` preserves existing data-block-text when supplied; range offsets always index `rangeText`, never Markdown source. `rangeSupported=false` for math/image blocks. Legacy hash fields remain.
- `resolveRange(text, anchor)` returns `{status,range?:{startUTF16,endUTF16},reason?}`. Half-open UTF16, grapheme boundaries validated through Intl.Segmenter. Exact range/quote first, otherwise unique quote+prefix+suffix relocation. Missing/deleted/invalid ranges detach. Multiple candidates ambiguous. No anchor mutation.
- `rangeGeometry(root, anchor)` accepts B's TextAnchor fields and returns `{status,range?,reason?,rects:[{x,y,width,height}]}`. Missing/duplicate stable IDs detach/ambiguous. Math/image content refuses text-range projection to avoid pretending rendered glyph offsets match source. Empty range returns no rects.
- `project(root,{anchor,behavior,originalBounds,originalPoints})`: underline/highlight returns geometry plus `{behavior,fragments:[{x,y,width,height}]}`. Underline fragments have height 1 and y at current line bottom; caller owns styling/thickness. Rigid returns `{status,behavior:"rigid",dx,dy,points}`. **originalBounds is the original target block frame**, not stroke bounds; points are original document-space points and preserve other fields. The result is always derived from originals; never feed previous projection back as originals. Rigid with quote validates target text still exists, except atomic math/image which follows the block. Detached results do not contain replacement stroke data: caller must retain original sidecar strokes.
- `applyInsertions(root, insertions, renderMarkdown)` consumes B's StudyInsertion fields; renderer `(markdown,item)=>sanitizedHTML` is mandatory for Markdown. Second argument allows A to apply persisted item.blockIDs. Builds before replacing existing study nodes. Returns `[{id,status,placement}]`. null afterBlockID=start; flow is default and reserves minHeight. Fixed floating only when explicitly requested and anchored to a unique existing block. Missing/ambiguous anchors keep study content visibly at flow tail with data-anchor-status. Reapply after layout changes for floating placement.

DOM attributes: source blocks `data-block-id`; study outer section `data-study-id=id`, `data-block-id=id`, `data-study-kind`, `data-anchor-status`. Blank section is an ink target. Markdown direct children inherit renderer-provided block IDs, otherwise deterministic study/content/encoded-content IDs; identical duplicate child content deliberately produces ambiguous IDs. Editing child content without persisted IDs detaches its old attachment safely. For stronger persistence, editor must provide stable child IDs in rendered HTML. Renderer postprocessing for math/images occurs AFTER applyInsertions; IDs are frozen beforehand.

This module does not own undo history, Markdown persistence, native Pencil lifecycle, projection painting, or arbitrary stroke recognition. A must call it from edit/resize/undo/redo/reopen paths and D must not replace drawings during active input.

## Reproducible browser check

PowerShell from checkout:

```powershell
$env:MDNOTE_OMOWRIGHT_LOADER='C:/Users/picom/.codex/plugins/cache/sisyphuslabs/omo/5.1.38/skills/browser/scripts/omowright.mjs'
$env:MDNOTE_CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe'
node scripts/check-annotation-layout.mjs
```

Owns headless Chrome and a temporary profile, closes/removes it in finally. No user browser attachment. Evidence default `.omo/evidence/annotation-layout/{dom-results.json,narrow-highlight.png,fixture.html}`. Override MDNOTE_EVIDENCE_DIR to retain integrated evidence.

Current worktree evidence absolute: `C:/Users/picom/orca/MD-Note/.omo/teams/team-e43dac36/worktrees/C/.omo/evidence/annotation-layout`.

Fixture covers actual multiline wrapping/text scaling, inline spans, highlight/underline projections, height reservation/resize/move/removal, blank target, repeated placement drift, supplement IDs, graphemes, deleted/ambiguous quote and block, math/image rigid targets, invalid insertion transaction. Screenshot is a geometry fixture, not integrated app visual acceptance. Native WebKit/PencilKit acceptance remains macOS/iPad work.
