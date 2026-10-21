# D native integration API

Controller exposes `setTextEditing(Bool)`, `insertStudySpace(kind: String)`, `setInkBehavior(String)`, `editorCommand(String)`, `saveRecoveryCopy()`. Session callbacks use A's `textEditing` property.

Renderer contract consumed:

- `render(markdown:blocks:documentUnchanged:)` with main-document-only snapshots; default false for external matching.
- `onDocumentEdited(EditorSnapshot)` with markdown/revision/composing/historyID/edits/mappings.
- Text edits include blockID/startUTF16/endUTF16/insertedText/**oldText**.
- Split/merge mappings include fromBlockID/toBlockID/fromStartUTF16/fromEndUTF16/offsetDeltaUTF16/targetText.
- `onEditorState` composing/canUndo/canRedo/error.
- `setTextEditing`, `flushEditor`, `editorCommand`.
- `setStudyInsertions(_:recordUndo:)`: initial restore false; user insert true.
- `onStudyInsertionsChanged`, `selectedTextAnchor`, `rangeGeometry`; nil/empty geometry detaches.

Native applies trusted replacements, then block mappings, before layout reconciliation. Attachment-only history snapshots keyed by the editor's stable historyID restore deleted-range undo without replacing original stroke data. Study orphan targets can reattach when explicit insertion IDs return. Original stroke payloads remain separate from derived range fragments.

`MarkdownFileWriter` provides coordinated UTF-8 `read` and coordinated compare-before-atomic `write(_:to:expectedText:)`. Conflicts retain local editor text and suppress sidecar saves; recovery writes a unique sibling Markdown plus sidecar. FileWatcher notifications are suppressed naturally by synchronously advancing lastDocHash after a successful write.

Text mode forwards hit testing to the existing web view. The same PKCanvasView retains scroll/zoom; root two-finger gestures update its offset/zoom. Pen mode routes back to PencilKit. All drawing replacements are guarded against active Pencil input.

Source archive export scans main and supplement Markdown for assets and uses the existing byte-preserving sidecar ZIP path. PDF flushes edits and captures the composed page/ink; >500 pages fail explicitly.

Native verification is unrun on Windows. Evidence and exact Mac/iPad scenarios: `worktrees/D/.omo/evidence/native-ink/README.md`. No native pass is claimed.
