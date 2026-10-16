# Trash native QA handoff

Status: NOT RUN. This Windows host has no Swift, Xcode, simulator, or sourcekit-lsp. No screenshots or native runtime results are claimed.

Run on macOS: `swift test --package-path MDNoteCore --filter TrashRepositoryTests`. Save the full output as `swift-tests-native.log`; success requires all 13 fixture tests to pass. Then generate/open the normal Xcode project and build the iPad target. Save build output as `xcode-build-native.log`.

Use the real iPad application with English and Korean system/app languages, portrait and landscape, standard and largest accessibility text. The project deliberately forces light appearance; also verify the sheet remains legible with dark system appearance. Capture every listed state after the final build. No visual PASS can be derived from source inspection.

| Scenario | Invocation / actions | Binary observable | Required native artifact |
|---|---|---|---|
| Note recovery | Make a nested note with ink and bookmarks; set paper and scroll/zoom; favorite and open it; context menu Move to Trash; relaunch; Add menu > Trash > Restore to Original Folder | Note and both companion bytes restored; paper/view/favorite/recent state restored; trash row gone | note-roundtrip screenshots and before/after file hashes |
| Folder recovery | Make a folder containing nested notes, images, ink, bookmarks and preferences; trash and restore | Folder contents byte-identical; image renders; nested metadata restored | folder-roundtrip file hashes and rendered note screenshot |
| Collision | Trash note.md; create a new note.md and orphan note 2.md.bookmarks; restore | Old note and its companions restored as note 3.md; existing files unchanged; metadata follows restored path | collision file hashes and library screenshot |
| Missing parent | Trash nested note; remove its parent; restore to original, then restore to Documents | First action shows localized missing-folder explanation without loss; second restores to root | missing-parent error and root-restored screenshots |
| Permanent deletion | Open selected trash item; Delete Permanently; cancel; repeat and confirm | Cancel keeps all files; confirmation names the item; confirm removes only selected item | confirmation, cancellation, deletion screenshots and file listing |
| Listing exclusion | Trash note and folder; inspect library and recursive search | Neither .Trash nor its content appears in normal/search results | library and search screenshots |
| Accessibility | Navigate empty/populated/error/confirmation states with VoiceOver, hardware keyboard, large text | Every action named and reachable; Close exits; labels do not clip; destructive action has explicit confirmation | VoiceOver notes and state screenshots in en/ko |
| Recovery errors | Use XCTest injected move failures and corrupt manifests | Failed moves roll back; failed rollback preserves manifest and remaining payload; errors remain visible in app | XCTest output and localized error screenshot |

The fixture suite names exact file assertions for round trip, folder images, collision reservation, missing parent, failed discard rollback, failed restore rollback, rollback failure retention, selected permanent deletion, outside-root rejection, symlinked trash rejection, malformed manifest retention, manifest-named folder, and unexpected recovery-file retention.

Recovery limitations requiring review: disk operations are synchronous and serialized on the main actor in the UI; an abrupt process termination during multiple companion moves can leave a partial trash bundle requiring manual recovery. Rollback failures intentionally retain the manifest and remaining payload. Core test execution, Swift compilation, rendered layout, VoiceOver behavior, and preferences integration remain unverified here.
