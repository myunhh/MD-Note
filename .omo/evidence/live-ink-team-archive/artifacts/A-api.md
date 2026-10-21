# A editor API (frozen)

`MarkdownRenderer.render(markdown: String, blocks: [BlockSnapshot] = [],
documentUnchanged: Bool = false) async`. Pass MAIN source snapshots only,
excluding study section IDs and their persisted child blockIDs. When unchanged,
restores IDs in source order; otherwise only unique exact hash+text matches
reuse IDs. Ambiguous/deleted blocks never inherit positional IDs.

`setTextEditing(Bool) async`, `editorCommand(String) async` (bold, italic, code,
heading, paragraph, bullet, numbered, quote, source, newParagraph, undo, redo).
`flushEditor() async throws -> EditorSnapshot`.
Snapshot Codable JSON: `{markdown, revision, composing, historyID, edits, mappings}`.
historyID is a UUID interned by the exact JSON state (source, block IDs, studies),
restored when undo/redo returns to that state; map resets on render.
edits: `[{blockID,startUTF16,endUTF16,insertedText,oldText}]`, grapheme-aligned
half-open UTF16 replacements. Apply against supplied oldText, not stale geometry.
mappings: `[{fromBlockID,toBlockID,fromStartUTF16,fromEndUTF16,
offsetDeltaUTF16,targetText}]`. Apply edits first, then remap only anchors wholly
inside the source segment. A range crossing a split safely detaches.
Both arrays are always present. `flushEditor` returns empty maps because edit
events already delivered each map; do not apply a map twice.
`onDocumentEdited: ((EditorSnapshot) -> Void)?` receives only completed valid
snapshots. Revisions increase per edit during this renderer lifetime.
`onEditorState: ((EditorState) -> Void)?` JSON fields composing, canUndo, canRedo,
optional error. During composition no save event is emitted and flush throws.
An open source fallback also requires Apply before flush succeeds. Native saves
must persist the received revision, never acknowledge a later revision as saved.
There is no JS ack overwrite: native reports failures/status through session.

`setStudyInsertions([StudyInsertion], recordUndo: Bool = false) async`,
`selectedTextAnchor() async -> TextAnchor?`,
`rangeGeometry(TextAnchor) async -> [CGRect]?` (nil means unresolved),
`onStudyInsertionsChanged: (([StudyInsertion]) -> Void)?`.
JS calls C's `snapshot`, `rangeGeometry` (status attached), `applyInsertions`
with safe markdown-it render callback (markdown,item). StudyInsertion.blockIDs
persist UUID child identities. Empty supplements get an editable blank paragraph.
JS owns joint document/study undo history. Native inserts use recordUndo:true;
restore uses false. Study callback precedes documentEdited so native stores study
state before receiving its historyID. Commands studyGrow/studyShrink (80px),
studyUp/studyDown (adjacent source boundary), studyRemove support undo.
Native controller API: setTextEditing, insertStudySpace(kind:),
setInkBehavior, editorCommand, saveRecoveryCopy. Session property textEditing.

Unsupported blocks use deliberate raw editing; untouched source slices including
frontmatter and reference definitions never pass through the rich serializer.
CommonMark rich editor operates on the selected rendered block. Splits preserve
the first block ID and allocate new IDs; other blocks retain IDs by source offsets.
Backspace/Delete at adjacent ordinary paragraph boundaries merge them and emit
the right-to-left mapping. Unsupported boundaries are preserved. Rich keyboard
undo falls back to the joint history after the local ProseMirror history is empty.
