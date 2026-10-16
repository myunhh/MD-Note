# Archive transfer implementation evidence

Scope: member F, portable source ZIP export and direct safe ZIP import. Worktree branch `team/team-7dc35eaa/F`. Product implementation and test cases are present; native compilation, XCTest execution, and iPad UI acceptance are **not verified** on this Windows host.

## Executed checks

| Scenario | Exact invocation | Binary observable | Artifact |
| --- | --- | --- | --- |
| Inline/reference/HTML destinations, spaces, encoding, title and balanced parentheses | `node scripts/check-archive-contract.mjs` | Exit 0; 11 fixture assertions plus pin/picker/error contracts pass | `pattern-contract.log` |
| English/Korean keys and placeholders | `node scripts/check-localization.mjs` | Exit 0; all localization checks pass | `localization.log` |
| Whitespace errors in changed files | `git diff --check` | Exit 0 | `diff-check.log` |
| Pinned dependency exists | `git ls-remote https://github.com/weichsel/ZIPFoundation.git refs/tags/0.9.20` | Exact tag resolves to `86fc841708997c5bce8545e23845125f4eb28493` | `dependency-tag.log` |
| Swift availability | `swift --version` | Command not found; native tests BLOCKED | `swift-availability.log` |
| Xcode availability | `xcodebuild -list` | Command not found; UI/build BLOCKED | `xcode-availability.log` |
| Requested pre-commit npm audit | `npm audit` | ENOLOCK: this Swift project has no npm lockfile; NOT an audit pass | `npm-audit.log` |

The JavaScript check executes regex patterns extracted directly from Swift source. It does not execute Foundation or the archive engine and is not represented as native behavioral proof.

## Native deterministic tests (written, not executed)

On macOS with Xcode and XcodeGen: `xcodegen generate`, then `xcodebuild test -project MDNote.xcodeproj -scheme MDNote -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath .omo/evidence/archive-transfer/NativeArchiveTests.xcresult`. Select an installed iPad simulator name if that device is absent. A passing XCTest result bundle is the required observable/artifact; none exists on this host.

`Tests/ArchiveTests/NoteArchiveTests.swift` contains 11 cases:

1. Roundtrip: exact five ZIP members, opaque ink/bookmark byte identity, images with spaces/encoding, no unused asset or remote asset, duplicate import preserves first folder.
2. Path policy: traversal, absolute, drive, backslash, empty component, hidden and control-character paths rejected; encoded traversal rejected.
3. Full/collapsed/shortcut reference images and quoted HTML image path extraction.
4. Export rejects parent-folder image and symlink file.
5. Import rejects traversal, absolute and symlink entries; no staging remains.
6. Import rejects case-insensitive duplicate and file-as-parent paths.
7. Missing local asset fails after extraction with staging cleaned; archive with no note rejected.
8. Entry count above 2,000 rejected before publish.
9. Fenced/inline code image examples excluded.
10. Changed stored payload fails CRC and removes staging.
11. Deflated entry above 64 MiB rejected before publish.

## Required native UI roundtrip (not executed)

- In English, import a folder containing `note.md`, two actual PNG images (`images/a b.png`, `images/c d.png`), inline `![x](images/a%20b.png)` and reference `![y][photo]` with `[photo]: <images/c d.png>`. Add ink and a bookmark; share source and save ZIP. Import that ZIP using Import File. Open the new folder/note: both images must render, ink and bookmark must match. Save screenshots before/after and exported ZIP under this evidence directory.
- Import the same ZIP twice: two separate folders must appear; original hashes unchanged. Cancel the share sheet: no `mdnote-export-*` directory from that operation remains in app temporary storage.
- Import traversal/symlink/corrupt/missing-asset fixtures: localized error appears; no new visible folder and no `.archive-import-*` remains. Try parent-relative image export: localized explanation appears and no ZIP is shared.
- Repeat error and roundtrip controls in Korean; capture screenshots at iPad portrait and landscape. Check UI remains responsive while a large archive is processing off main.

## Implementation limits and safety policy

ZIPs are imported as a new enclosing folder. The note's path and both companions remain unchanged. Export includes only the note, present `.inknote`/`.bookmarks`, and referenced local image files. Remote URLs are not fetched. Parent-relative, absolute, symlink, hidden and ambiguous paths are rejected. Import rejects escaping image references as well as malicious entry paths. Entry/count/aggregate limits are checked before extraction and actual decompressed bytes are bounded during streaming; CRC and declared size must match. All failure paths after staging creation remove staging. Destination moves never overwrite an existing item.

Image discovery supports common inline/reference/HTML syntax, including one balanced parenthesis pair, angle destinations, spaces and percent encoding. It is a constrained scanner, not a complete CommonMark parser; deeply nested inline destinations and complex nested alt text still require native renderer parity work if expanded support is desired.

## Primary dependency sources inspected

- [ZIPFoundation 0.9.20 README](https://github.com/weichsel/ZIPFoundation/blob/86fc841708997c5bce8545e23845125f4eb28493/README.md): SPM and iOS support.
- [Archive reading API](https://github.com/weichsel/ZIPFoundation/blob/86fc841708997c5bce8545e23845125f4eb28493/Sources/ZIPFoundation/Archive%2BReading.swift): bounded consumer extraction returns CRC32; caller compares it with entry checksum.
- [Entry API](https://github.com/weichsel/ZIPFoundation/blob/86fc841708997c5bce8545e23845125f4eb28493/Sources/ZIPFoundation/Entry.swift): entry type, UInt64 uncompressed size, checksum.
- [Archive writing API](https://github.com/weichsel/ZIPFoundation/blob/86fc841708997c5bce8545e23845125f4eb28493/Sources/ZIPFoundation/Archive%2BWriting.swift): fileURL and streaming provider overloads.

No remote writes, global installs or credentials/configuration changes were made.
