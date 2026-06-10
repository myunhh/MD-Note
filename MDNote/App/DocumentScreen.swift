import SwiftUI

/// Full-screen document view: the web+PencilKit canvas plus a GoodNotes-style
/// top toolbar (undo/redo, tool palette toggle, orphan tray).
struct DocumentScreen: View {
    let doc: LibraryDoc
    @StateObject private var session = DocumentSession()
    @State private var showTray = false
    @State private var showOutline = false

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
                    .accessibilityLabel("보관함")
                    .overlay(alignment: .topTrailing) {
                        if session.orphanCount > 0 {
                            Text("\(session.orphanCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Color.red, in: Circle())
                                .offset(x: 8, y: -8)
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
                        Divider()
                        Toggle(isOn: Binding(
                            get: { session.fingerDrawing },
                            set: { session.setFingerDrawing($0) }
                        )) {
                            Label("손가락으로 그리기", systemImage: "hand.draw")
                        }
                        Divider()
                        Button { session.exportPDF() } label: {
                            Label("PDF로 내보내기", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("더 보기")
                }
            }
            .overlay(alignment: .top) {
                if let status = session.status {
                    Text(status)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: session.status)
            .sheet(isPresented: $showTray) {
                OrphanTrayView(session: session)
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
