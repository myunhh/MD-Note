# Existing MD Note editor surface

## 1. Atmosphere & Identity
Preserve the continuous warm paper and the empty right handwriting margin.
Editing happens in the selected rendered block, with native SwiftUI controls.

## 2. Color
Reuse theme.css --paper, --ink, --ink-soft, --rule, --accent, --accent-soft and
--code-bg unchanged. Focus uses --accent; active editing uses --accent-soft.

## 3. Typography
Inherit the existing system/SF/Apple SD Gothic stack and scaled 18px body.
Native controls use system labels and SF Symbols. Source fallback uses monospace.

## 4. Spacing & Layout
Retain the fixed 1390px page and 1080px text column. Native PKCanvas owns scrolling.
New control spacing uses 8px; minimum controls use 44px hit targets.

## 5. Components
Rich block: default rendered content, editing contenteditable, composing, error.
Native mode button: text/pen state with accessible name.
Source fallback: retained rendered preview above a labeled textarea, explicit Apply
and Cancel; preview keeps ink targets and range geometry while raw text is edited.
Reference links/images use this fallback because their definitions live outside
the selected block. Ordinary rich paragraphs preserve softbreak UTF-16 coordinates.
Study controls: native menu and inline resize/move/remove controls, no new webview.

## 6. Motion & Interaction
No new animation. Focus rings on keyboard focus. Composition never triggers a
save or block replacement. Escape commits a completed block; fallback has Cancel.

## 7. Depth & Surface
Reuse warm paper and tonal selected wash; neutral rule separators. No cards.

## 8. Accessibility Constraints & Accepted Debt
Named contenteditable and buttons, keyboard shortcuts, Korean text supported.
The fixed document canvas is intentionally zoomed by native UI on narrow screens.
Windows browser evidence cannot establish iPad Pencil or physical Korean IME QA.
