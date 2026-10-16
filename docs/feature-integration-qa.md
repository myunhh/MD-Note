# 기능 통합 검증 / Feature integration QA

여섯 기능의 사용법은 [README](../README.md#여섯-가지-기능--six-features)를 참고한다. 아래 명령은 저장소 루트에서 실행한다. All commands below run from the repository root.

이번 Windows 환경에는 Swift/Xcode/iPad 시뮬레이터가 없어 Swift 테스트, 네이티브 빌드·UI·VoiceOver·Apple Pencil 검증은 **미실행**이다. Native checks are **unrun on Windows**; Node and Chrome evidence does not establish native persistence, ZIP round trips, or Pencil behavior. Record the tested commit, command, exit code, and output/capture paths for each run.

## 명령 / Commands

Node가 있으면 다음 검사를 실행할 수 있다. These checks need Node; the archive parser uses the bundled Markdown parser.

```bash
node scripts/check-localization.mjs
node MDNoteCore/Tests/parity/hash_parity.mjs
node scripts/check-archive-contract.mjs
node scripts/check-archive-renderer.mjs
node --check MDNote/Resources/WebAssets/app/bridge.js
git diff --check
```

`check-archive-contract` checks export path unescaping, the dependency pin and archive error resources; it does not execute Swift or ZIPFoundation. `check-archive-renderer` executes `MDNote.imageSources` with bundled markdown-it, including indented and nested code examples. Hash parity checks JavaScript against the shared golden values; run Swift tests separately.

### 실제 브라우저 / Real browser

`scripts/check-document-search.mjs` requires Chrome and the installed OmO browser skill’s `scripts/omowright.mjs`. Set the two required environment variables to existing absolute paths; no repository dependency installation is required. `MDNOTE_EVIDENCE_DIR` optionally chooses an evidence directory, relative to the repository root or absolute; default: `.omo/evidence/document-search`.

PowerShell example; replace the two machine-specific paths before running:

```powershell
$env:MDNOTE_OMOWRIGHT_LOADER = 'C:/path/to/installed/browser/scripts/omowright.mjs'
$env:MDNOTE_CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe'
$env:MDNOTE_EVIDENCE_DIR = '.omo/evidence/integration-document-search'
node scripts/check-document-search.mjs
```

On macOS, set the same variables with `export NAME='/absolute/path'`, then run the same Node command. The script owns a temporary headless Chrome profile, checks real DOM ranges/highlights, literal queries, wrapping, stale results, fallback geometry and unchanged block identities, and writes `dom-results.json`, `highlight.png`, and `fallback.png`. Chrome success does not replace WKWebView testing on iPad.

### Swift와 Xcode / Swift and Xcode

Use a Swift 6 toolchain for `MDNoteCore/Package.swift`. On macOS:

```bash
swift test --package-path MDNoteCore
```

This includes hashing, reanchoring, trash, bookmarks and recursive library search. The search tests include a root symlink alias case to ensure folder browsing and global search use the same document URL identity.

For the app and archive tests, use macOS, Xcode with an iOS 17-or-newer SDK/simulator, and XcodeGen. `project.yml` pins ZIPFoundation to `0.9.20`; dependency resolution needs access to the package or a populated local cache.

```bash
xcodegen generate
xcodebuild build -project MDNote.xcodeproj -scheme MDNote \
  -destination 'generic/platform=iOS Simulator'
xcodebuild -showdestinations -project MDNote.xcodeproj -scheme MDNote
```

Choose an available iPad simulator from the destination output and set `MDNOTE_SIMULATOR_ID` to its UUID. Tests require a concrete simulator, not the generic build destination:

```bash
xcodebuild test -project MDNote.xcodeproj -scheme MDNote \
  -destination "platform=iOS Simulator,id=$MDNOTE_SIMULATOR_ID" \
  -only-testing:MDNoteArchiveTests
```

`MDNoteArchiveTests` is the iOS unit-test target in the **MDNote scheme**, not a standalone scheme. It covers note/image/ink/bookmark round trips, unsafe paths, symlinks, collisions, CRC failures, bounds and staging cleanup. These tests have not been run in this Windows environment.

## 기기 시나리오 / Native integration scenarios

Run in English and Korean on iPad portrait/landscape, with large Dynamic Type and VoiceOver. The app currently declares a light-only interface. Capture real screens and record failures; do not mark a scenario passed from source inspection.

| Scenario / 시나리오 | Expected observation / 확인 결과 |
|---|---|
| Favorite two notes, open A then B without editing, restart the app. 노트 두 개를 즐겨찾기하고 A, B 순서로 연 뒤 재시작. | Stars and Favorites Only persist; Recently Opened places B first. Changing search/filter/UI state does not record an open. Empty favorites can return to all notes. |
| Search a duplicate name in nested folders; change query/scope rapidly. 중첩 폴더 검색과 빠른 검색어·범위 변경. | Paths distinguish results; latest query wins; favorites and name/modified/recent sorting work in both scopes. No stale results replace the current query. |
| Favorite in folder browsing, open the same note through global search, then rename it and its folder. 같은 노트를 폴더·전체 검색에서 열고 이름 변경. | One favorite/open-date identity survives, including `/var` versus `/private/var` aliases. No extra absolute-path preference entry appears. Note, ink and bookmarks remain paired. |
| Trash a favorite note or folder with ink/bookmarks, recreate its old name, restore, then permanently delete a separate trash item. 즐겨찾기·필기·북마크가 있는 항목의 삭제·충돌 복원·영구 삭제. | New same-name note does not inherit old preferences; restore uses a safe destination and carries metadata/companions. Missing parent offers Documents restore. Permanent deletion requires confirmation. |
| Restore into a nested folder or import a folder/ZIP while a library query is active. 검색 중 중첩 복원 또는 폴더·ZIP 가져오기. | Returning from Trash or finishing import refreshes recursive results without retyping. Navigate away/back and foreground the app to verify refresh. |
| Find English/Korean text and literal punctuation; move previous/next, clear, resize text, then edit Markdown externally. 문서 찾기와 외부 수정. | Matches/count/navigation update, clearing removes paint, and existing ink/block positions are unaffected by highlighting. |
| Save a named bookmark, restart, rename the note/folder, then edit or remove its anchor text. 북마크 저장·재시작·이름 변경·앵커 삭제. | Bookmark remains editable/navigable; missing anchor reports fallback. External Files rename keeps bookmark/ink companions or reports recovery failure without overwriting them. |
| Add ink/bookmarks and referenced local images, export ZIP, import elsewhere, open offline. 필기·북마크·이미지 ZIP 왕복. | Export includes current saved ink, actual `.bookmarks` and referenced local images; imported note renders and bookmarks navigate. After pending ink saves complete, archive creation preserves source note/sidecar bytes. Favorites/history are local preferences, not archive payload. |
| Import malformed/traversal/symlink/collision/oversized ZIPs; export with missing or parent-relative images. 잘못된 ZIP과 이미지 경로. | Clear error; no partial visible import, overwritten notes or lost originals. Limits: 2,000 entries, 64 MB per file, 256 MB total. Local images must be inside the note folder. |
| Import a generic ZIP with indented/fenced/nested image examples or unresolved image links; then import an MD Note archive whose manifest declares a missing asset. 일반 ZIP의 코드 예제·미해결 이미지 링크와 필수 이미지가 빠진 MD Note 압축 파일. | Generic ZIP preserves the note bytes without guessing required assets from Markdown. MD Note manifest imports reject missing declared assets and clean staging. Both retain path, symlink, collision, size and CRC checks. |

Apple Pencil input, undo/redo and ink durability after backgrounding require a physical iPad. Compare note and sidecar bytes around favorite/search operations and capture restart/rename/restore outcomes; native verification remains open until these scenarios are executed.
