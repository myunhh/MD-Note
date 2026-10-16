# Archive transfer implementation evidence

Historical implementation record: the generic-import scanner and its regex tests described below were removed during independent review. Current behavior and verification are recorded in `../archive-review-fix-receipt.txt`: generic ZIP notes are imported without inferring required assets from Markdown; manifest-declared assets remain mandatory. Historical command output below is retained as evidence of the earlier run, not as the current acceptance claim.

Scope: member F, portable source ZIP export and direct safe ZIP import. Worktree branch `team/team-7dc35eaa/F`. Product implementation and test cases are present; native compilation, XCTest execution, and iPad UI acceptance are **not verified** on this Windows host.

## Executed checks

| Scenario | Exact invocation | Binary observable | Artifact |
| --- | --- | --- | --- |
| Full export parser: nested alt text/destinations, all references, spaces, encoding, code/raw HTML/front matter exclusions | `node scripts/check-archive-renderer.mjs` | Exit 0; 14 fixtures execute the actual bridge helper and bundled markdown-it | `renderer.log` |
| Conservative import destinations, spaces, encoding, title and balanced parentheses | `node scripts/check-archive-contract.mjs` | Exit 0; 10 fixture assertions plus pin/picker/error contracts pass | `pattern-contract.log` |
| Renderer hash regression | `node MDNoteCore/Tests/parity/hash_parity.mjs` | Exit 0; 8/8 golden hashes unchanged | `hash-parity.log` |
| English/Korean keys and placeholders | `node scripts/check-localization.mjs` | Exit 0; all localization checks pass | `localization.log` |
| Whitespace errors in changed files | `git diff --check` | Exit 0 | `diff-check.log` |
| Pinned dependency exists | `git ls-remote https://github.com/weichsel/ZIPFoundation.git refs/tags/0.9.20` | Exact tag resolves to `86fc841708997c5bce8545e23845125f4eb28493` | `dependency-tag.log` |
| Swift availability | `swift --version` | Command not found; native tests BLOCKED | `swift-availability.log` |
| Xcode availability | `xcodebuild -list` | Command not found; UI/build BLOCKED | `xcode-availability.log` |
| Requested pre-commit npm audit | `npm audit` | ENOLOCK: this Swift project has no npm lockfile; NOT an audit pass | `npm-audit.log` |

The renderer check executes the real production helper and bundled Markdown parser in Node with a minimal document shim (image discovery itself uses parser tokens, not DOM). The contract check executes regex patterns extracted directly from Swift source. Neither executes Foundation or the archive engine; neither is represented as native behavioral proof.

## Native deterministic tests (written, not executed)

On macOS with Xcode and XcodeGen: `xcodegen generate`, then `xcodebuild test -project MDNote.xcodeproj -scheme MDNote -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath .omo/evidence/archive-transfer/NativeArchiveTests.xcresult`. Select an installed iPad simulator name if that device is absent. A passing XCTest result bundle is the required observable/artifact; none exists on this host.

`Tests/ArchiveTests/NoteArchiveTests.swift` contains 14 cases:

1. Roundtrip: exact six ZIP members (five payloads and a manifest), opaque ink/bookmark byte identity, images with spaces/encoding, no unused asset or remote asset, duplicate import preserves first folder.
2. Path policy: traversal, absolute, drive, backslash, empty component, hidden and control-character paths rejected; encoded traversal rejected.
3. Full/collapsed/shortcut reference images and ignored raw HTML (the renderer disables raw HTML).
4. Export rejects parent-folder image and symlink file.
5. Import rejects traversal, absolute and symlink entries; no staging remains.
6. Import rejects case-insensitive duplicate and file-as-parent paths.
7. Missing local asset fails after extraction with staging cleaned; archive with no note rejected.
8. Entry count above 2,000 rejected before publish.
9. Fenced/inline code image examples excluded.
10. Changed stored payload fails CRC and removes staging.
11. Deflated entry above 64 MiB rejected before publish.
12. Renderer-supplied deeply nested image path included and exact note snapshot preserved even if the source changes after discovery.
13. Manifest roundtrip preserves entity-escaped image paths and excludes unused front-matter references.
14. Manifest cannot reference parent paths or missing assets; failed import removes staging.

## Required native UI roundtrip (not executed)

- In English, import a folder containing `note.md`, two actual PNG images (`images/a b.png`, `images/c d.png`), inline `![x](images/a%20b.png)` and reference `![y][photo]` with `[photo]: <images/c d.png>`. Add ink and a bookmark; share source and save ZIP. Import that ZIP using Import File. Open the new folder/note: both images must render, ink and bookmark must match. Save screenshots before/after and exported ZIP under this evidence directory.
- Import the same ZIP twice: two separate folders must appear; original hashes unchanged. Cancel the share sheet: no `mdnote-export-*` directory from that operation remains in app temporary storage.
- Import traversal/symlink/corrupt/missing-asset fixtures: localized error appears; no new visible folder and no `.archive-import-*` remains. Try parent-relative image export: localized explanation appears and no ZIP is shared.
- Repeat error and roundtrip controls in Korean; capture screenshots at iPad portrait and landscape. Check UI remains responsive while a large archive is processing off main.

## Implementation limits and safety policy

ZIPs are imported as a new enclosing folder. The note's path and both companions remain unchanged. Export includes the note, present `.inknote`/`.bookmarks`, referenced local image files, and a small versioned `MDNote Archive.json` manifest recording the parser-derived image paths. Remote URLs are not fetched. Parent-relative, absolute, symlink, hidden and ambiguous paths are rejected. Manifest note/image paths are independently validated and must exist; manifests are capped at 4 MiB before decoding. Entry/count/aggregate limits are checked before extraction and actual decompressed bytes are bounded during streaming; CRC and declared size must match. All failure paths after staging creation remove staging. Destination moves never overwrite an existing item.

Export requires all image sources from `MarkdownRenderer.imageSources(markdown:)`, which calls `MDNote.imageSources` through WebKit. That helper uses the same bundled markdown-it parser, options and front-matter handling as rendering, including nested destinations/alt text and all reference forms. It does not recurse into image alt tokens, since those are rendered as text. Raw HTML is disabled by the renderer and excluded. Failure to retrieve the sources is an explicit export error. The parsed note's exact byte snapshot is archived, preventing a source edit between parsing and ZIP writing from silently changing references. Import validates our exported note's assets through the manifest, avoiding scanner disagreements over entities or front matter. Older ZIPs without a manifest retain a conservative scanner as an additional local-image check; entry path/type/CRC/size validation is independent of either path.

## Primary dependency sources inspected

- [ZIPFoundation 0.9.20 README](https://github.com/weichsel/ZIPFoundation/blob/86fc841708997c5bce8545e23845125f4eb28493/README.md): SPM and iOS support.
- [Archive reading API](https://github.com/weichsel/ZIPFoundation/blob/86fc841708997c5bce8545e23845125f4eb28493/Sources/ZIPFoundation/Archive%2BReading.swift): bounded consumer extraction returns CRC32; caller compares it with entry checksum.
- [Entry API](https://github.com/weichsel/ZIPFoundation/blob/86fc841708997c5bce8545e23845125f4eb28493/Sources/ZIPFoundation/Entry.swift): entry type, UInt64 uncompressed size, checksum.
- [Archive writing API](https://github.com/weichsel/ZIPFoundation/blob/86fc841708997c5bce8545e23845125f4eb28493/Sources/ZIPFoundation/Archive%2BWriting.swift): fileURL and streaming provider overloads.

No remote writes, global installs or credentials/configuration changes were made.
