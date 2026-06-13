# MD Note

Markdown(.md) 파일을 GoodNotes처럼 예쁘게 렌더링하고, 그 위에 Apple Pencil로 손필기하는 **iPad 앱**. 기존 필기앱과 달리 페이지 분할 없이 **Notion처럼 하나의 긴 페이지로 스크롤하며 필기**한다.

MD는 앱 밖(VSCode 등)에서 편집하고, 앱은 **보기 + 필기 전용**이다. MD가 외부에서 수정되면 변경을 감지해 **필기를 원래 내용 옆으로 재정렬(re-anchor)** 한다.

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
1. **스크롤러는 단 하나** — WKWebView·PKCanvasView를 동기화하지 않고, 바깥 UIScrollView 하나만 스크롤/줌. 안쪽 두 레이어는 문서 전체 높이로 펼쳐 한 덩어리로 움직임. 펜=그리기/손가락=스크롤 (설정으로 손가락 그리기 가능).
2. **필기를 좌표가 아닌 MD 블록에 앵커** — 글이 밀려도 블록을 따라 필기가 이동. 섹션을 통째로 옮겨도 따라감(LCS + 이동 블록 2차 매칭). 블록이 사라지면 보관함(orphan)으로 (자동 삭제 없음).

잉크를 지키는 안전장치: 화면 이탈/백그라운드 시 즉시 저장(실패 시 사용자 경고), 동시 로드 직렬화로 베이스라인 경쟁 차단, 외부 이름변경 추적(NSFilePresenter) + 좌초된 sidecar 해시 입양, 더 최신 버전이 쓴 sidecar는 덮어쓰지 않음(읽기 전용 전환), 손상된 sidecar는 타임스탬프로 보존 백업(`.corrupt-*`), 비유한 좌표 클램프, 이미지/폰트 늦은 로드 시 지오메트리 재측정. JS↔Swift 블록 해시 동일성은 골든 픽스처 + Node 교차검증으로 잠가둠.

그 외: GitHub/Notion 스타일 콜아웃(`> [!NOTE]`), YAML 프런트매터 자동 숨김, 글자 크기 조절 · 문서별 종이 배경(4종) · 스크롤/줌 복원, 제목 아웃라인 내비게이션, 링크 탭 열기(Pencil 전용 모드 — 손가락 그리기 켜면 비활성), Apple Pencil 더블탭 지우개, 노트 공유(.md+필기 zip) · 잉크 합성 PDF 내보내기(긴 문서 다중 페이지, 깨끗한 종이), 라이브러리 전문 검색 · 정렬, VoiceOver 본문 읽기, KaTeX 수식, 코드 하이라이트(언어 배지), 앱 아이콘 · 테라코타 액센트, 햅틱 피드백.

## 빌드 / 테스트

> 필요: `xcodegen` (`brew install xcodegen`) — `.xcodeproj`와 생성된 Info.plist는 `.gitignore` 대상이라 필수다.

```bash
# 핵심 로직 테스트 (macOS, 시뮬레이터 불필요)
cd MDNoteCore && swift test
# JS↔Swift 블록 해시 동일성 교차검증 (Node, 불변식 #3)
node MDNoteCore/Tests/parity/hash_parity.mjs

# iOS 앱 프로젝트 생성 + 컴파일 (SDK는 destination이 자동 해석)
xcodegen generate            # project.yml → MDNote.xcodeproj
xcodebuild build -scheme MDNote \
  -destination 'generic/platform=iOS Simulator'
```

> Apple Pencil 입력은 시뮬레이터에서 재현되지 않으므로, 필기 동작의 최종 검증은 실제 iPad에서 한다.

## 상태

진행 중. 마일스톤: M0 레이아웃 spike → M1 뷰어 → M2 필기 → M3 앵커링 → M4 변경감지/재정렬 → M5 폴리시.
