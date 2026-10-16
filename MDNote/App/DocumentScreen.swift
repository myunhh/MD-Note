import SwiftUI

/// Full-screen document view: the web+PencilKit canvas plus a GoodNotes-style
/// top toolbar (undo/redo, tool palette toggle, orphan tray).
struct DocumentScreen: View {
    let doc: LibraryDoc
    @StateObject private var session = DocumentSession()
    @State private var showTray = false
    @State private var showOutline = false
    @State private var showDocumentSearch = false
    @State private var showBookmarks = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DocumentCanvasView(url: doc.url, session: session)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(doc.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                if showDocumentSearch {
                    DocumentSearchView(session: session) {
                        session.updateSearch("")
                        showDocumentSearch = false
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showOutline = true } label: {
                        Image(systemName: "list.bullet")
                    }
                    .disabled(session.outline.isEmpty)
                    .accessibilityLabel(L10n.text("outline"))
                    .popover(isPresented: $showOutline) {
                        OutlineList(session: session, dismiss: { showOutline = false })
                    }
                    Button { session.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!session.canUndo)
                    .accessibilityLabel(L10n.text("undo"))
                    Button { session.redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!session.canRedo)
                    .accessibilityLabel(L10n.text("redo"))
                    Button { session.toggleTools() } label: {
                        Image(systemName: session.toolsVisible
                              ? "pencil.tip.crop.circle.fill"
                              : "pencil.tip.crop.circle")
                    }
                    .accessibilityLabel(L10n.text("penTools"))
                    Button { showTray = true } label: {
                        Image(systemName: "tray")
                    }
                    .accessibilityLabel(session.orphanCount > 0 ? L10n.format("trayCount", session.orphanCount) : L10n.text("tray"))
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
                        Button { showDocumentSearch = true } label: {
                            Label(L10n.text("documentSearch.title"), systemImage: "magnifyingglass")
                        }
                        Button { showBookmarks = true } label: {
                            Label(L10n.text("bookmarkTitle"), systemImage: "bookmark")
                        }
                        Divider()
                        Button { session.scrollToBeginning() } label: {
                            Label(L10n.text("goToBeginning"), systemImage: "arrow.up.to.line")
                        }
                        Button { session.scrollToEnd() } label: {
                            Label(L10n.text("goToEnd"), systemImage: "arrow.down.to.line")
                        }
                        Divider()
                        Picker(L10n.text("paper"), selection: Binding(
                            get: { session.paperStyle },
                            set: { session.setPaper($0) }
                        )) {
                            Text(L10n.text("plain")).tag("plain")
                            Text(L10n.text("ruled")).tag("ruled")
                            Text(L10n.text("grid")).tag("grid")
                            Text(L10n.text("dots")).tag("dots")
                        }
                        Picker(L10n.text("textSize"), selection: Binding(
                            get: { session.textScale },
                            set: { session.setTextScale($0) }
                        )) {
                            Text(L10n.text("small")).tag(0.85)
                            Text(L10n.text("medium")).tag(1.0)
                            Text(L10n.text("large")).tag(1.2)
                            Text(L10n.text("extraLarge")).tag(1.4)
                        }
                        Divider()
                        Toggle(isOn: Binding(
                            get: { session.fingerDrawing },
                            set: { session.setFingerDrawing($0) }
                        )) {
                            Label(L10n.text("fingerDrawing"), systemImage: "hand.draw")
                        }
                        Divider()
                        Button { session.shareSource() } label: {
                            Label(L10n.text("shareNote"), systemImage: "square.and.arrow.up.on.square")
                        }
                        Button { session.exportPDF() } label: {
                            Label(L10n.text("exportPDF"), systemImage: "arrow.down.doc")
                        }
                        if let s = session.docStats {
                            Section {
                                Label(L10n.format("docStats", s.words.formatted(), s.minutes),
                                      systemImage: "textformat.size")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L10n.text("more"))
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
            .sheet(isPresented: $showBookmarks) {
                BookmarksView(session: session)
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
    @State private var searchText = ""

    private var filteredOutline: [OutlineItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return session.outline }
        return session.outline.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.text("searchHeadings"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(L10n.text("searchHeadings"))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(L10n.text("clearSearch"))
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal)
            Divider()
            List(filteredOutline) { item in
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
                .accessibilityLabel(L10n.format("headingLevel", item.text, item.level))
            }
            .listStyle(.plain)
            .overlay {
                if filteredOutline.isEmpty {
                    ContentUnavailableView(L10n.text("noHeadings"), systemImage: "magnifyingglass",
                        description: Text(L10n.text("tryOutlineSearch")))
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 360, minHeight: 240, idealHeight: 420, maxHeight: 420)
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
        LibraryMetadataStore.shared.recordOpened(url)
        return vc
    }

    func updateUIViewController(_ vc: DocumentCanvasViewController, context: Context) {
        vc.open(url: url)
    }
}
