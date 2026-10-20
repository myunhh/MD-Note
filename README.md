# MD Note

Markdown(.md) 파일을 GoodNotes처럼 예쁘게 렌더링하고, 그 위에 Apple Pencil로 손필기하는 **iPad 앱**. 기존 필기앱과 달리 페이지 분할 없이 **Notion처럼 하나의 긴 페이지로 스크롤하며 필기**한다.

앱 안에서 **렌더링된 Markdown을 키보드로 편집하고 Apple Pencil로 필기**한다. 텍스트는 실제 `.md`에 저장하며, 외부 수정과 충돌하면 덮어쓰지 않고 복구 사본을 저장할 수 있다. MD가 외부에서 수정되면 변경을 감지해 필기를 재배치하고, 대상을 확실히 찾지 못한 필기는 보관함에 남긴다.

## 텍스트 편집과 학습 공간

- 상단의 키보드/펜 버튼으로 텍스트 편집과 필기를 전환한다. 텍스트 모드에서 문단을 탭하면 굵게·기울임 등 서식이 보이는 상태로 편집된다. 두 손가락으로 이동·확대하며, `+` 메뉴에서 서식과 새 문단을 선택한다.
- 표·수식·참조 링크/이미지는 미리보기와 **원문 편집**으로 열린다. 적용/취소를 명시적으로 선택하며, 편집하지 않은 프런트매터·참조 정의·확장 문법은 원문 그대로 유지한다. 일반 여러 줄 문단은 줄바꿈을 보존하며 렌더링 상태로 편집하고, 한글 조합 중에는 저장하지 않는다.
- `+` → **빈 필기 공간 / Markdown 보충 공간**은 선택한 블록 뒤에 실제 높이를 확보한다. 텍스트 모드에서 공간을 선택하고 `+` 메뉴로 크기·위치·삭제를 조정한다. 텍스트 모드의 실행 취소/다시 실행은 본문과 공간을 함께 복원한다.
- 새 잉크는 기본적으로 모양을 유지한다. 텍스트를 선택한 뒤 `+` → **새 잉크 동작**에서 밑줄/강조를 선택하고 펜 모드로 바꾸면, 다음 필기가 선택 범위의 줄을 따라 표시된다. 자유 필기는 **필기 모양 유지**로 돌아간다. 임의의 원·화살표·수식을 자동 인식하는 기능은 아니다.
- 원본 잉크·안정된 블록 ID·학습 공간은 `.md.inknote` v2에 저장한다. v1은 읽을 때 마이그레이션하며 원본 필기와 고아 필기를 보존한다. 더 최신 스키마는 읽기 전용이다. ZIP은 보충 공간의 이미지도 포함하고 PDF는 합성된 레이아웃을 사용한다.

Windows에서 웹 편집·레이아웃·검색·이미지 수집을 검증했다. **Swift/Xcode 빌드, 실제 파일 조정·PencilKit·ZIP/PDF·iPad 한글 IME는 아직 기기 검증이 필요하다.** 실행 명령과 확인 절차는 [Mac/iPad 검증 안내](docs/live-ink-mac-qa.md)에 있다.

## 아키텍처

```
┌─────────────────────────────────────────────┐
│ MDNote (iOS app target, Swift + PencilKit)   │
│  App/   SwiftUI 셸 · 파일 브라우저            │
│  Core/  DocumentCanvasViewController         │  ← 단일 스크롤러 위 web+canvas
│         MarkdownRenderer (WKWebView+JS브리지) │
│         InkStore (PencilKit ↔ Core 브리지)    │
│         FileWatcher (변경 감지)               │
│  Resources/WebAssets  markdown-it·theme·bridge│
└───────────────┬─────────────────────────────┘
                │ depends on
┌───────────────▼─────────────────────────────┐
│ MDNoteCore (SwiftPM, 순수 Swift, 플랫폼 무관) │
│  Block / Hashing / BlockMatcher(LCS) /        │  ← macOS에서 `swift test` 가능
│  Reanchor / AnchoredInk / Sidecar             │     (PencilKit 미사용)
└───────────────────────────────────────────────┘
```

핵심 설계 두 가지:
1. **스크롤 소유자는 PKCanvasView 하나** — 뒤쪽의 단일 WKWebView에 같은 오프셋·확대율을 적용한다. 텍스트 모드도 이 캔버스의 위치를 유지한다. 펜이 닿아 있는 동안 필기 레이어를 교체하지 않는다.
2. **안정된 블록 ID와 UTF-16 텍스트 범위** — 앱 안의 수정·분할·합치기는 명시적 편집 매핑과 undo 스냅샷을 사용한다. 외부 변경은 고유한 내용으로만 재연결하며, 삭제되거나 모호한 대상은 보관함에 남긴다. 자유 필기는 평행 이동하고 밑줄/강조는 현재 줄 조각에서 파생한다.

잉크를 지키는 안전장치: 화면 이탈/백그라운드 시 즉시 저장(실패 시 사용자 경고), 동시 로드 직렬화로 베이스라인 경쟁 차단, 외부 이름변경 추적(NSFilePresenter) + 좌초된 sidecar 해시 입양, 더 최신 버전이 쓴 sidecar는 덮어쓰지 않음(읽기 전용 전환), 손상된 sidecar는 타임스탬프로 보존 백업(`.corrupt-*`), 비유한 좌표 클램프, 이미지/폰트 늦은 로드 시 지오메트리 재측정. JS↔Swift 블록 해시 동일성은 골든 픽스처 + Node 교차검증으로 잠가둠.

그 외: GitHub/Notion 스타일 콜아웃(`> [!NOTE]`), YAML 프런트매터 자동 숨김, 글자 크기 조절 · 문서별 종이 배경(4종) · 스크롤/줌 복원, 제목 아웃라인 내비게이션, 링크 탭 열기(Pencil 전용 모드 — 손가락 그리기 켜면 비활성), Apple Pencil 더블탭 지우개, 노트 공유(.md+필기+북마크+로컬 이미지 ZIP) · 잉크 합성 PDF 내보내기(긴 문서 다중 페이지, 깨끗한 종이), 라이브러리 전문 검색 · 정렬, VoiceOver 본문 읽기, KaTeX 수식, 코드 하이라이트(언어 배지), 앱 아이콘 · 테라코타 액센트, 햅틱 피드백.

## 언어와 문서 탐색

영어와 한국어를 지원한다. iPad의 선호 언어 또는 설정의 MD Note 앱별 언어 선택을 따른다. 지원 언어가 없으면 영어를 사용한다. 메뉴·안내·VoiceOver 레이블과 첫 실행 샘플이 번역되며, 언어를 바꿔도 기존 노트 내용과 파일 이름은 바뀌지 않는다. 샘플은 최초 설치 때만 복사된다.

문서의 더 보기 메뉴에서 **문서 처음으로 / 문서 끝으로** 이동할 수 있다. 현재 확대 비율과 가로 위치를 유지하며, 제목이 없는 문서에서도 사용할 수 있다. 목차 팝오버의 검색창에서는 제목을 대소문자 구분 없이 검색하고 검색어를 지워 전체 목차로 돌아갈 수 있다.

## 여섯 가지 기능 / Six features

| 기능 / Feature | 사용법 / Usage |
|---|---|
| 휴지통 / Trash | 노트·폴더 메뉴에서 휴지통으로 이동하고, 보관함의 `+` → 휴지통에서 복원하거나 확인 후 영구 삭제한다. Move a note or folder to Trash from its menu; open `+` → Trash to restore or confirm permanent deletion. |
| 문서에서 찾기 / Find in Document | 열린 문서의 더 보기 메뉴에서 검색을 열고 이전·다음 결과로 이동한다. Open Find in Document from the document’s More menu; use previous/next to navigate matches. |
| 북마크 / Bookmarks | 더 보기 → 북마크에서 현재 위치를 저장하고 이름 변경·이동·삭제한다. Open Bookmarks from More to save the current position, rename, jump, or delete. |
| 즐겨찾기·최근 열어본 순 / Favorites and recents | 노트 메뉴에서 별을 추가하고 정렬 및 필터 메뉴에서 즐겨찾기만 또는 최근 열어본 순을 선택한다. Star notes from their menu, then select Favorites Only or Recently Opened from Sort and Filter. |
| 전체 보관함 검색 / Entire-library search | 검색창에 입력하고 전체 보관함·현재 폴더 범위를 선택한다. 전체 결과에는 상대 경로가 표시되며 즐겨찾기와 정렬도 적용된다. Choose Entire library or Current folder while searching; global results show paths and honor favorites and sorting. |
| 노트 ZIP / Note archives | 문서 더 보기에서 노트 압축 파일을 내보내고 `+` → 파일 가져오기로 ZIP을 가져온다. Export a note archive from More and import ZIP through `+` → Import File; archives carry local images, ink, and bookmark companions. |

즐겨찾기와 열람 기록은 기기에 저장된다. ZIP은 노트와 동반 파일을 옮기며 즐겨찾기·열람 기록은 포함하지 않는다. 이미지 파일은 노트 폴더 안에 있어야 한다. Favorites and reading history persist locally and are not included in archives. Local images must remain inside the note’s folder.

일반 ZIP은 코드 예제나 미해결 이미지 링크가 있어도 노트 내용을 그대로 가져온다. MD Note 압축 파일은 매니페스트에 선언한 이미지가 없으면 가져오기를 거부한다. Generic ZIP imports preserve Markdown with code examples or unresolved image links; MD Note archives require every manifest-declared asset. Both enforce ZIP path, symlink, checksum and size protections.

## 빌드 / 테스트

> 필요: `xcodegen` (`brew install xcodegen`) — `.xcodeproj`와 생성된 Info.plist는 `.gitignore` 대상이라 필수다.

```bash
# 모든 명령은 저장소 루트에서 실행한다. Swift 6 도구 체인이 필요하다.
# 핵심 로직 테스트 (macOS, 시뮬레이터 불필요)
swift test --package-path MDNoteCore
# JS↔Swift 블록 해시 동일성 교차검증 (Node, 불변식 #3)
node MDNoteCore/Tests/parity/hash_parity.mjs
# 영어·한국어 리소스, 서식 인자, 번역 누락 검사 (저장소 루트에서)
node scripts/check-localization.mjs
# ZIP 경로/리소스 계약과 실제 Markdown 이미지 파서 검사
node scripts/check-archive-contract.mjs
node scripts/check-archive-renderer.mjs
node MDNoteCore/Tests/parity/anchor_fixture_check.mjs
node scripts/check-native-ink-contract.mjs # 소스 계약 검사; 네이티브 실행을 대신하지 않음
node --check MDNote/Resources/WebAssets/app/bridge.js

# iOS 앱 프로젝트 생성 + 컴파일 (SDK는 destination이 자동 해석)
xcodegen generate            # project.yml → MDNote.xcodeproj
xcodebuild build -scheme MDNote \
  -destination 'generic/platform=iOS Simulator'
```

오프라인 편집 번들은 저장소에 포함되어 런타임 CDN이 필요 없다. 번들을 다시 만들 때는 `cd editor && npm ci && npm run build && npm audit`를 사용한다. 의존성 버전은 lockfile로 고정한다. 실제 브라우저의 `check-rich-editor.mjs`, `check-annotation-layout.mjs`, `check-document-search.mjs` 실행 환경은 [검증 안내](docs/live-ink-mac-qa.md#브라우저-회귀-검사)에 있다.

> Apple Pencil 입력은 시뮬레이터에서 재현되지 않으므로, 필기 동작의 최종 검증은 실제 iPad에서 한다.

언어 전환과 탐색 기능의 기기별 확인 항목은 [검증 안내](docs/localization-navigation-qa.md)를 참고한다.

여섯 기능을 함께 사용하는 시나리오, 실제 브라우저 검사 환경 변수, `MDNote` 스킴의 `MDNoteArchiveTests` 실행법은 [통합 검증 안내 / Integration QA](docs/feature-integration-qa.md)에 있다. 이번 Windows 환경에서는 Swift 테스트, Xcode 빌드·테스트와 iPad UI·Apple Pencil 검증을 실행하지 못했다. Node 검사만으로 네이티브 동작을 검증했다고 판단하지 않는다.

## 상태

진행 중. 마일스톤: M0 레이아웃 spike → M1 뷰어 → M2 필기 → M3 앵커링 → M4 변경감지/재정렬 → M5 폴리시.
