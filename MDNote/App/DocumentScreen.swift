import SwiftUI

/// Full-screen document view: the web+PencilKit canvas plus a GoodNotes-style
/// top toolbar (undo/redo, tool palette toggle, orphan tray).
struct DocumentScreen: View {
    let doc: LibraryDoc
    @StateObject private var session = DocumentSession()
    @State private var showTray = false

    var body: some View {
        DocumentCanvasView(url: doc.url, session: session)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(doc.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
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
                    } label: {
                        Image(systemName: "square.grid.3x3")
                    }
                    Button { session.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    Button { session.redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    Button { session.toggleTools() } label: {
                        Image(systemName: session.toolsVisible
                              ? "pencil.tip.crop.circle.fill"
                              : "pencil.tip.crop.circle")
                    }
                    Button { showTray = true } label: {
                        Image(systemName: "tray")
                    }
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
