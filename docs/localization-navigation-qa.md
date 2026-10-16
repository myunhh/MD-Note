# Localization and navigation QA

## Automated checks

Run from the repository root:

```sh
node scripts/check-localization.mjs
node MDNoteCore/Tests/parity/hash_parity.mjs
git diff --check
```

The localization check verifies matching English/Korean keys, placeholder types,
Swift lookups, untranslated Korean literals, localized samples, and resource
configuration. It does not compile the app or verify the generated bundle.

## macOS build

```sh
xcodegen generate
xcodebuild build -scheme MDNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
swift test --package-path MDNoteCore
```

Inspect the built app for `en.lproj` and `ko.lproj`, each containing
`Localizable.strings` and `Sample.md`.

## iPad acceptance checks

Use a disposable test library. Repeat the UI checks in English and Korean,
portrait, landscape, narrow Split View, and a large accessibility text size.
The app intentionally uses a light appearance, including when iPadOS is dark.

| Surface | Scenario and expected result |
| --- | --- |
| Fresh library | The sample matches the selected app language; all text, code, tables, and math render. |
| Language change | Change the per-app language in iPad settings and relaunch. UI changes; existing names, note contents, ink, and sample stay intact. |
| Fallback | A fresh launch with an unsupported preferred language uses English unless Korean is a lower supported preference. |
| Library | Check populated/empty/search-empty states, sorting, Add menu, new note/folder prompts, rename prompts, import errors, and empty previews. No resource keys or unexpected Korean appear in English UI. |
| Document | Check More menu, paper/text-size options, statistics, export progress/failure, and reanchor messages. Counts display correctly for 0, 1, and several items. |
| Ink tray | Check empty and populated trays, item labels, restore/delete/close, and VoiceOver labels. |
| Outline | Search a mixed-case English heading and a Korean heading. Matching rows retain order and indentation. Select a result: the popover closes and the original heading is reached. |
| Outline empty result | Search an absent term: translated guidance appears. Clear restores all headings. Whitespace-only input shows all headings. |
| Beginning/end | Test long and short notes, including one without headings. More > Go to Beginning reaches the top; Go to End reaches the legal bottom without overscrolling. |
| Zoom and persistence | Zoom and pan horizontally, then jump. Zoom and horizontal offset stay unchanged. Close/reopen and verify the resulting position is restored. |
| Late layout | Restore a saved position in a note with slow images, then jump. Finishing image layout must not restore the old saved fraction over the explicit jump. |
| Accessibility | Enable Reduce Motion: jumps are immediate. Check translated VoiceOver toolbar/search/clear labels and heading levels. |
| Layout | Check toolbar, menus, prompts, tray, outline search with keyboard open, and no-results guidance for clipping and inaccessible controls. |

## Verification status in this workspace

The Node localization and hash checks passed on Windows. Swift, XcodeGen,
Xcode, and an iPad simulator are unavailable here. Native compilation, resource
bundle inspection, screenshots, Pencil behavior, and the interactive checks
above remain unverified; source review is not a visual QA pass.
