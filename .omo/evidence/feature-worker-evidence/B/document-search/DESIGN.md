# Document search design contract

## 1. Atmosphere & Identity
Preserve the existing quiet native iPad document shell and warm paper canvas.

## 2. Color
Native controls use primary/secondary foreground and regularMaterial. Web search
uses --search-match (#ffe08a), --search-active (#f5aa42), and existing --ink.
The app remains light-only, including under the system dark appearance.

## 3. Typography
Use SwiftUI body and footnote, system fonts and Dynamic Type; inherit web text.

## 4. Spacing & Layout
Search occupies a top safe-area inset, with separate field and navigation rows.
Reuse native horizontal padding and 44pt minimum control targets. The existing
PKCanvasView remains the sole document scroll owner; web width stays 1390px.

## 5. Components
DocumentSearchView: labeled text field, clear, result status, previous/next and
close controls. Empty, no results, searching, failed and matched states are explicit.
Highlights use ranges or a clipped fixed overlay outside content, never wrappers.

## 6. Motion & Interaction
Reuse native scroll(toDocumentY:) and its Reduce Motion support. No new animation.
Closing clears the query and highlights. Next/previous wrap through results.

## 7. Depth & Surface
Native regularMaterial and Divider follow the existing shell. No extra shadows.

## 8. Accessibility Constraints & Accepted Debt
English/Korean labels, dynamic type, keyboard submission and 44pt targets.
Native screenshots, VoiceOver, Pencil and simulator validation require macOS/iPad;
these are explicit unverified QA gaps, not a visual acceptance claim.
