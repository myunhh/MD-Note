# Live editing and anchored ink: Mac / iPad validation

Run commands from the repository root. Record `git rev-parse HEAD`, macOS/Xcode/iPadOS versions, device, command exit code, and screenshot/log paths. Windows browser evidence does **not** establish a Swift build, coordinated file writes, native undo, PencilKit drawing fidelity, ZIP round trips, or PDF output.

## Mac build and native tests

Prerequisites: Swift 6, Xcode with an iOS 17-or-newer SDK, XcodeGen, and an available iPad simulator. The scheme is `MDNote`; its test target is `MDNoteArchiveTests`.

```bash
mkdir -p .omo/evidence/mac-live-ink
git rev-parse HEAD > .omo/evidence/mac-live-ink/commit.txt
swift test --package-path MDNoteCore \
  > .omo/evidence/mac-live-ink/swift-test.log 2>&1
xcodegen generate
xcodebuild build -project MDNote.xcodeproj -scheme MDNote \
  -destination 'generic/platform=iOS Simulator' \
  > .omo/evidence/mac-live-ink/build.log 2>&1
xcodebuild -showdestinations -project MDNote.xcodeproj -scheme MDNote
```

Check each exit code before continuing. Pick a simulator UUID from the last command:

```bash
export MDNOTE_SIMULATOR_ID='replace-with-available-iPad-UUID'
xcodebuild test -project MDNote.xcodeproj -scheme MDNote \
  -destination "platform=iOS Simulator,id=$MDNOTE_SIMULATOR_ID" \
  -only-testing:MDNoteArchiveTests \
  -resultBundlePath .omo/evidence/mac-live-ink/native-tests.xcresult \
  > .omo/evidence/mac-live-ink/native-tests.log 2>&1
```

Use a fresh result-bundle path on reruns. Core tests cover grapheme-safe UTF-16 mapping, duplicate targets, stable identities, v1 migration and future-version protection. `NativeInkTests` covers real web-layout JSON decoding into stable blocks and ink capture/reanchor, softbreak edit-event decoding with an untouched annotation, coordinated conflicts, invalid UTF-8, original ink bytes across reflow/recapture, partial erasure/undo, range deletion/attachment restoration, study removal/reinsertion and archive/sidecar roundtrip. These tests were authored but **not executed on Windows**.

## 브라우저 회귀 검사

Use an installed OmO browser skill loader and Chrome. These tests create and close their own temporary headless profiles. Do not attach them to the user's open browser.

```bash
export MDNOTE_OMOWRIGHT_LOADER='/absolute/path/to/browser/scripts/omowright.mjs'
export MDNOTE_CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
MDNOTE_EVIDENCE_DIR=.omo/evidence/mac-live-ink/editor node scripts/check-rich-editor.mjs
MDNOTE_EVIDENCE_DIR=.omo/evidence/mac-live-ink/boundaries node scripts/check-editor-boundaries.mjs
MDNOTE_EVIDENCE_DIR=.omo/evidence/mac-live-ink/layout node scripts/check-annotation-layout.mjs
MDNOTE_EVIDENCE_DIR=.omo/evidence/mac-live-ink/search node scripts/check-document-search.mjs
node MDNoteCore/Tests/parity/hash_parity.mjs
node MDNoteCore/Tests/parity/anchor_fixture_check.mjs
node scripts/check-localization.mjs
node scripts/check-archive-renderer.mjs
node scripts/check-archive-contract.mjs
node scripts/check-native-ink-contract.mjs
```

PowerShell uses `$env:NAME='value'` for these variables. The rich editor test exercises real keyboard input, but its synthetic composition events do not replace physical Korean IME testing. The native-contract script only inspects source.

## iPad acceptance

Use a disposable copy of a real note, with a local image in the same folder. Keep the original `.md` and `.md.inknote` copies for comparison. Test English and Korean, portrait and landscape, small and large text scale, and VoiceOver. The app intentionally uses a light paper canvas with one fixed document coordinate system; device rotation/zoom should not change ink-to-text alignment.

| Scenario / action | Required observable | Evidence |
|---|---|---|
| Open a note containing frontmatter, a reference image, bold text, table, math and fenced code. Enter text mode, edit a rendered paragraph, then inspect the actual file in Files/Finder. | The file contains the completed edit; untouched raw source sections remain byte-for-byte unchanged. Formatting is rendered while editing. | Before/after Markdown, screen recording. |
| Type Korean with a hardware or software Korean keyboard. While composing, attempt pen mode, export, background and return. Complete the syllable and reopen. | No partial composition or placeholder overwrites the file. Completed text survives; composition is neither duplicated nor discarded silently. | Recording plus file diff. |
| Draw ordinary handwriting, a formula and a graph. Add text before their target, resize text and rotate. Repeat reflow 20 times. | Groups translate without changing shape or accumulating distortion. Existing strokes are not duplicated. | Before/after captures, sidecar original payload comparison. |
| Select a nonempty text range, choose follow-text underline/highlight, switch to pen and draw. Insert text before and inside it; test repeated identical words. | Picker shows the accepted mode. The mark follows the correct current line fragments, expands for interior edits and stays on the intended repeated occurrence. Empty selection is rejected. | Recording and sidecar anchors. |
| Split the marked paragraph; merge it back. Delete all marked text, undo, redo, undo. | Wholly mapped ranges follow the new block; crossing ranges safely detach. Deleted ink remains in the tray; undo restores the original attachment and stroke payload. | Recording, before/after IDs and payload hashes. |
| Open a table/math block or explicit source fallback, then cancel; repeat with Apply. | Rendered preview remains visible, existing ink does not become orphaned just from opening the editor, Cancel preserves bytes, Apply saves only explicit edits. | Screen recording and file diff. |
| Open `Read [guide] here.` with its `[guide]: URL` definition, and a shortcut reference image. Append a character through source Apply. Edit the end of an ordinary soft-wrapped paragraph with a marked word on its second line. | Reference links/images retain their meaning and definitions. Ordinary multiline paragraphs remain rich-editable, soft line breaks survive, and the untouched marked word is not detached. | File diff, edit-event JSON and recording. |
| Insert blank space and Markdown space after the selected block. Write in both, edit the supplement, grow/shrink, move, remove, then undo. | Real reserved height moves downstream content/ink. Space and child IDs survive editing/reopen. Removing an inked target preserves ink; undo reattaches it. | Recording, sidecar, reopen capture. |
| Keep Pencil touching the page while an image loads or another layout update arrives. Lift Pencil, erase one stroke, undo, reflow. | No canvas replacement cancels a live stroke. Projection updates after lifting. Erased strokes stay erased until explicit undo. | Physical iPad recording. |
| Edit the same file externally between native edits; also test a read-only/unavailable file and invalid UTF-8 copy. | Conflict/read errors are visible. External bytes remain intact; no localized error text becomes Markdown. No initial-load failure writes an empty sidecar. Recovery copy retains local edits and companion ink. | Original and recovery files plus error capture. |
| Save, background, force-quit after a successful save, reopen; then rename the document through Files. | Text, study additions, IDs and original ink survive. Note/sidecar remain paired. | Before/after files and captures. |
| Open a v1 sidecar with live and orphan ink; reopen after migration. Open a separate future-version sidecar. | Migration preserves every payload and persists IDs. Future bytes are not changed; editing/inking is blocked. | Sidecar diffs and hashes. |
| Export/import ZIP with different reference labels and supplement-only images; include an unfinished code fence in the main source. | Each fragment's image references are collected in its own parse scope. Imported note renders offline with study additions, ink and bookmarks. | ZIP, imported files, offline capture. |
| Export PDF with wrapped marks, blank/study spaces, images/math and trailing ink; test a long multipage document. | Composed positions match the page; source editing must be applied/cancelled before export. No missing middle/end pages or ink. | PDF and image of every page. |
| Search literal punctuation/Korean; navigate outline/bookmarks; change paper and reopen archive. Toggle text/pen with VoiceOver. | Existing search/navigation/paper work, controls announce correctly, and body remains accessible after returning to pen mode. | Captures/recording. |

Pen-mode undo uses PencilKit; text-mode undo uses the shared text/study history. Test both explicitly. Recognition of arbitrary handwritten shapes is outside this feature: follow-text behavior is chosen by the user.

Mark a row PASS only after observing it on the named device/runtime and storing its artifact. Until then leave it UNRUN; the Windows source audit and browser checks are not substitutes.
