import SwiftUI

/// Full-screen document view: the web+PencilKit canvas plus a GoodNotes-style
/// top toolbar (undo/redo, tool palette toggle, orphan tray).
struct DocumentScreen: View {
    let doc: LibraryDoc
    @StateObject private var session = DocumentSession()
    @State private var showTray = false
    @State private var showOutline = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DocumentCanvasView(url: doc.url, session: session)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(doc.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showOutline = true } label: {
                        Image(systemName: "list.bullet")
                    }
                    .disabled(session.outline.isEmpty)
                    .accessibilityLabel("목차")
                    .popover(isPresented: $showOutline) {
                        OutlineList(session: session, dismiss: { showOutline = false })
                    }
                    Button { session.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!session.canUndo)
                    .accessibilityLabel("실행 취소")
                    Button { session.redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!session.canRedo)
                    .accessibilityLabel("다시 실행")
                    Button { session.toggleTools() } label: {
                        Image(systemName: session.toolsVisible
                              ? "pencil.tip.crop.circle.fill"
                              : "pencil.tip.crop.circle")
                    }
                    .accessibilityLabel("펜 도구")
                    Button { showTray = true } label: {
                        Image(systemName: "tray")
                    }
                    .accessibilityLabel(session.orphanCount > 0 ? "보관함, \(session.orphanCount)개" : "보관함")
                    .overlay(alignment: .topTrailing) {
                        if session.orphanCount > 0 {
                            Text("\(session.orphanCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Color.red, in: Circle())
                                .offset(x: 8, y: -8)
                                .accessibilityHidden(true)
                        }
                    }
                    Menu {
                        Picker("종이 배경", selection: Binding(
                            get: { session.paperStyle },
                            set: { session.setPaper($0) }
                        )) {
                            Text("플레인").tag("plain")
                            Text("줄").tag("ruled")
                            Text("모눈").tag("grid")
                            Text("점").tag("dots")
                        }
                        Picker("글자 크기", selection: Binding(
                            get: { session.textScale },
                            set: { session.setTextScale($0) }
                        )) {
                            Text("작게").tag(0.85)
                            Text("보통").tag(1.0)
                            Text("크게").tag(1.2)
                            Text("아주 크게").tag(1.4)
                        }
                        Divider()
                        Toggle(isOn: Binding(
                            get: { session.fingerDrawing },
                            set: { session.setFingerDrawing($0) }
                        )) {
                            Label("손가락으로 그리기", systemImage: "hand.draw")
                        }
                        Divider()
                        Button { session.shareSource() } label: {
                            Label("노트 공유 (.md + 필기)", systemImage: "square.and.arrow.up.on.square")
                        }
                        Button { session.exportPDF() } label: {
                            Label("PDF로 내보내기", systemImage: "arrow.down.doc")
                        }
                        if let s = session.docStats {
                            Section {
                                Label("\(s.words.formatted()) 단어 · 약 \(s.minutes)분",
                                      systemImage: "textformat.size")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("더 보기")
                }
            }
            .overlay(alignment: .top) {
                if let toast = session.toast {
                    HStack(spacing: 7) {
                        toastIcon(toast.kind)
                        Text(toast.text).font(.footnote)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.black.opacity(0.06)))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: session.toast)
            .sensoryFeedback(.selection, trigger: session.selectionTick)
            .sensoryFeedback(.success, trigger: session.successTick)
            .sensoryFeedback(.impact(weight: .light), trigger: session.impactTick)
            .sheet(isPresented: $showTray) {
                OrphanTrayView(session: session)
            }
    }

    @ViewBuilder
    private func toastIcon(_ kind: ToastKind) -> some View {
        switch kind {
        case .progress: ProgressView().controlSize(.small)
        case .success:  Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .info:     Image(systemName: "sparkles").foregroundStyle(.tint)
        }
    }
}

/// Popover listing the document's headings; tapping one scrolls the canvas.
struct OutlineList: View {
    @ObservedObject var session: DocumentSession
    let dismiss: () -> Void

    var body: some View {
        List(session.outline) { item in
            Button {
                session.scroll(to: item)
                dismiss()
            } label: {
                Text(item.text)
                    .font(item.level == 1 ? .body.weight(.semibold) : .subheadline)
                    .foregroundStyle(item.level <= 2 ? .primary : .secondary)
                    .padding(.leading, CGFloat(item.level - 1) * 16)
                    .lineLimit(1)
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("\(item.text), 제목 수준 \(item.level)")
        }
        .listStyle(.plain)
        .frame(minWidth: 280, minHeight: 60, maxHeight: 420)
        .presentationCompactAdaptation(.popover)
    }
}

/// Hosts the UIKit document canvas (web + PencilKit) inside SwiftUI.
struct DocumentCanvasView: UIViewControllerRepresentable {
    let url: URL
    @ObservedObject var session: DocumentSession

    func makeUIViewController(context: Context) -> DocumentCanvasViewController {
        let vc = DocumentCanvasViewController()
        vc.session = session
        session.controller = vc
        vc.open(url: url)
        return vc
    }

    func updateUIViewController(_ vc: DocumentCanvasViewController, context: Context) {
        vc.open(url: url)
    }
}
