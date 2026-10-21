# D native result

Commit: `32de5e008d877e8ce2ea81745ed5df45198a3041`
Subject: Preserve native ink through live editing and study layouts
Branch: `mdnote-live-ink/native-ink`
Worktree clean after commit. No merge, push, or external write.

Owned source changes: DocumentCanvasViewController.swift, InkStore.swift,
DocumentExporter.swift, new DocumentInputCanvas.swift, InkStrokeIdentity.swift,
MarkdownFileWriter.swift, Tests/ArchiveTests/NativeInkTests.swift and
scripts/check-native-ink-contract.mjs. Evidence is committed under
`.omo/evidence/native-ink/`. NoteArchive.swift needed no format change; existing
companion-byte transport is reused, while native export now scans supplement assets.

API contract: `artifacts/D-api.md`. Depends on A's final editor DTOs/renderer API
and B's v2 models; this isolated branch alone does not contain those peer changes.

Implemented: coordinated exact-text conflict checks/atomic Markdown writes,
watcher self-save baseline, local recovery copy with sidecar, explicit text/pen
routing retaining the existing canvas zoom/offset, stable original ink groups,
derived underline/highlight fragments, active-Pencil replacement guards, trusted
UTF16 edits and split/merge mapping, historyID attachment undo, study persistence
and ink restoration on insertion undo, composed export flushing and supplement
assets, future-sidecar mutation guards.

Executed: 12 native source-contract checks PASS; archive contract PASS; real
bundled Markdown asset extraction 18 fixtures PASS; git diff --check exit 0.
`npm audit --json` returned ENOLOCK because this D branch has no npm manifest/
lockfile and adds no dependency; A owns its editor toolchain audit.

Unrun: native compile, 10 authored XCTest scenarios, Simulator/iPad Pencil,
IME/touch/zoom, PDF visual acceptance. Swift, Xcode and SourceKit absent on Windows.
Exact Mac commands and all scenario observables are in
`worktrees/D/.omo/evidence/native-ink/README.md`.

Important acceptance focus: PencilKit may normalize stroke serialization when
assigning a drawing; fingerprint/eraser/native undo must be verified on Apple
runtime. Pen-mode undo is PencilKit history; text-mode undo is unified JS
text/study history. There is no automatic arbitrary handwriting recognition.

Evidence receipt:
`C:/Users/picom/orca/.omo/evidence/mdnote-native-D/verification.txt`
