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
1. **스크롤러는 단 하나** — WKWebView·PKCanvasView를 동기화하지 않고, 바깥 UIScrollView 하나만 스크롤/줌. 안쪽 두 레이어는 문서 전체 높이로 펼쳐 한 덩어리로 움직임. 펜=그리기/손가락=스크롤.
2. **필기를 좌표가 아닌 MD 블록에 앵커** — 글이 밀려도 블록을 따라 필기가 이동. 블록이 사라지면 보관함(orphan)으로 (자동 삭제 없음).

## 빌드 / 테스트

```bash
# 핵심 로직 테스트 (macOS, 시뮬레이터 불필요)
cd MDNoteCore && swift test

# iOS 앱 프로젝트 생성 + 컴파일
xcodegen generate            # project.yml → MDNote.xcodeproj
xcodebuild build -scheme MDNote -sdk iphonesimulator26.5 \
  -destination 'generic/platform=iOS Simulator'
```

> Apple Pencil 입력은 시뮬레이터에서 재현되지 않으므로, 필기 동작의 최종 검증은 실제 iPad에서 한다.

## 상태

진행 중. 마일스톤: M0 레이아웃 spike → M1 뷰어 → M2 필기 → M3 앵커링 → M4 변경감지/재정렬 → M5 폴리시.
