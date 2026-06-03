import UIKit
import PencilKit
import WebKit
import MDNoteCore

/// The document canvas.
///
/// ARCHITECTURE (two facts learned the hard way):
///   1. PencilKit's live-ink + zoom only render correctly when **PKCanvasView
///      itself owns the scrolling/zooming**. So the canvas is the scroll view.
///   2. A WKWebView placed *inside* a PKCanvasView does not render. So the web
///      view lives as a **sibling behind a transparent canvas**, and we mirror
///      the canvas's contentOffset + zoomScale onto it so text and ink stay
///      pixel-aligned while scrolling and zooming.
@MainActor
final class DocumentCanvasViewController: UIViewController {

    /// Matches the web theme's --paper so the area around/beyond the page reads
    /// as one continuous (writable) sheet rather than dead gray space.
    private static let paperColor = UIColor(red: 251/255, green: 250/255, blue: 247/255, alpha: 1)

    weak var session: DocumentSession?

    private let renderer = MarkdownRenderer()
    private let canvasView = PKCanvasView()
    private let webContainer = UIView()           // sibling behind the canvas
    private var toolPicker: PKToolPicker?
    private var zoomObservation: NSKeyValueObservation?
    private var offsetObservation: NSKeyValueObservation?

    private var pageWidth: CGFloat { renderer.pageWidth }
    private var contentHeight: CGFloat = 1000
    private var didInitialZoom = false
    private var isRestoring = false
    private var toolPickerVisible = true
    private var paperStyle = UserDefaults.standard.string(forKey: "paperStyle") ?? "plain"

    private var currentURL: URL?
    private var documentText = ""
    private var lastDocHash = ""
    private var currentBlocks: [Block] = []
    private var inkStore: InkStore?
    private var saveWorkItem: DispatchWorkItem?
    private var fileWatcher: FileWatcher?
    private var reloadWorkItem: DispatchWorkItem?

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.paperColor

        // Web view behind, in a plain container we transform to follow the canvas.
        view.addSubview(webContainer)
        let web = renderer.webView
        web.isUserInteractionEnabled = false
        webContainer.addSubview(web)

        // Transparent PKCanvasView on top — the scroll/zoom owner.
        canvasView.frame = view.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.delegate = self
        canvasView.drawingPolicy = .pencilOnly        // finger scrolls/zooms, pencil draws
        canvasView.alwaysBounceVertical = true
        canvasView.backgroundColor = .clear           // show the web behind
        canvasView.isOpaque = false
        canvasView.contentInsetAdjustmentBehavior = .always
        canvasView.minimumZoomScale = 1.0             // refined in updateZoomLimits()
        canvasView.maximumZoomScale = 5.0
        view.addSubview(canvasView)

        // Mirror the canvas's scroll + zoom onto the web layer.
        zoomObservation = canvasView.observe(\.zoomScale, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.syncWeb() }
        }
        offsetObservation = canvasView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.syncWeb() }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        activateToolPicker()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateZoomLimits()
        enforceContentSize()
        syncWeb()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        fileWatcher?.stop()
    }

    // MARK: Public

    func open(url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        inkStore = InkStore(documentURL: url)
        didInitialZoom = false
        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url) { [weak self] in self?.scheduleReloadCheck() }
        fileWatcher?.start()
        Task { await loadAndRender(initial: true) }
    }

    // MARK: Render pipeline

    private func loadAndRender(initial: Bool) async {
        guard let url = currentURL, let store = inkStore else { return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "# 파일을 읽을 수 없습니다\n"
        documentText = text
        let newHash = Hashing.documentHash(text)

        await renderer.loadAssetsIfNeeded()
        await renderer.render(markdown: text)
        await renderer.setPaper(paperStyle)
        let height = await renderer.contentHeight()
        let newBlocks = await renderer.blocks()
        applyContentSize(height)

        if initial {
            if let sidecar = store.load(), sidecar.documentHash != newHash {
                let result = store.applyExternalEdit(
                    oldBlocks: sidecar.blocks.map(\.block), newBlocks: newBlocks)
                reportReanchor(result)
            }
        } else {
            let result = store.applyExternalEdit(oldBlocks: currentBlocks, newBlocks: newBlocks)
            reportReanchor(result)
        }

        currentBlocks = newBlocks
        lastDocHash = newHash

        isRestoring = true
        canvasView.drawing = store.rebuildDrawing(blocks: newBlocks)
        isRestoring = false

        store.save(blocks: newBlocks, documentText: text)
        session?.paperStyle = paperStyle
        refreshOrphans()
        activateToolPicker()
    }

    private func reportReanchor(_ result: Reanchor.Result) {
        guard !(result.followed.isEmpty && result.orphaned.isEmpty) else { return }
        var msg = "문서 변경 감지 · 필기 \(result.followed.count)개 따라옴"
        if !result.orphaned.isEmpty { msg += " · \(result.orphaned.count)개 보관함" }
        session?.status = msg
    }

    // MARK: Layout / zoom / web sync

    private func applyContentSize(_ height: CGFloat) {
        contentHeight = max(height, 1)
        webContainer.transform = .identity
        webContainer.bounds = CGRect(x: 0, y: 0, width: pageWidth, height: contentHeight)
        renderer.webView.frame = webContainer.bounds
        canvasView.contentSize = CGSize(width: pageWidth, height: contentHeight)
        updateZoomLimits()
        syncWeb()
    }

    /// PencilKit may shrink the scroll content toward the drawing's bounds, which
    /// can leave the right writing margin unreachable/undrawable. Keep the full
    /// page (text column + writing margin) drawable by enforcing the page size.
    private func enforceContentSize() {
        guard contentHeight > 1 else { return }
        if canvasView.contentSize.width < pageWidth || canvasView.contentSize.height < contentHeight {
            canvasView.contentSize = CGSize(
                width: max(canvasView.contentSize.width, pageWidth),
                height: max(canvasView.contentSize.height, contentHeight))
        }
    }

    /// Min zoom = "fit the full page width" (whole width incl. the right writing
    /// margin visible); max zoom = 5× for detail.
    private func updateZoomLimits() {
        guard canvasView.bounds.width > 0 else { return }
        let fit = canvasView.bounds.width / pageWidth
        canvasView.minimumZoomScale = min(fit, 1.0)
        canvasView.maximumZoomScale = 5.0
        if !didInitialZoom, contentHeight > 1 {
            didInitialZoom = true
            canvasView.zoomScale = canvasView.minimumZoomScale
        }
    }

    /// Position + scale the (sibling) web container so its content maps to the
    /// exact same on-screen rect as the canvas's scrolled/zoomed content.
    private func syncWeb() {
        let s = canvasView.zoomScale
        let o = canvasView.contentOffset
        webContainer.transform = CGAffineTransform(scaleX: s, y: s)
        webContainer.center = CGPoint(x: -o.x + pageWidth * s / 2,
                                      y: -o.y + contentHeight * s / 2)
    }

    // MARK: Tool picker

    private func activateToolPicker() {
        guard isViewLoaded, view.window != nil else { return }
        if toolPicker == nil {
            let picker = PKToolPicker()
            picker.addObserver(canvasView)
            picker.addObserver(self)
            toolPicker = picker
        }
        _ = canvasView.becomeFirstResponder()
        toolPicker?.setVisible(toolPickerVisible, forFirstResponder: canvasView)
        session?.toolsVisible = toolPickerVisible
    }

    func toggleToolPicker() {
        toolPickerVisible.toggle()
        _ = canvasView.becomeFirstResponder()
        toolPicker?.setVisible(toolPickerVisible, forFirstResponder: canvasView)
        session?.toolsVisible = toolPickerVisible
    }

    func undo() { canvasView.undoManager?.undo() }
    func redo() { canvasView.undoManager?.redo() }

    func setPaper(_ style: String) {
        paperStyle = style
        UserDefaults.standard.set(style, forKey: "paperStyle")
        session?.paperStyle = style
        Task { await renderer.setPaper(style) }
    }

    // MARK: Orphan tray

    func deleteOrphan(_ id: UUID) {
        inkStore?.removeOrphan(id)
        persistAndRefresh()
    }

    func restoreOrphan(_ id: UUID) {
        guard let store = inkStore else { return }
        if store.restoreOrphan(id, in: currentBlocks) {
            isRestoring = true
            canvasView.drawing = store.rebuildDrawing(blocks: currentBlocks)
            isRestoring = false
        }
        persistAndRefresh()
    }

    private func persistAndRefresh() {
        inkStore?.save(blocks: currentBlocks, documentText: documentText)
        refreshOrphans()
    }

    private func refreshOrphans() {
        session?.orphans = makeOrphanItems()
    }

    private func makeOrphanItems() -> [OrphanItem] {
        guard let store = inkStore else { return [] }
        let scale: CGFloat = 3.0
        return store.orphans.compactMap { ink in
            guard let drawing = try? PKDrawing(data: ink.strokeData) else { return nil }
            let raw = drawing.bounds
            let bounds = raw.isNull || raw.isEmpty
                ? CGRect(x: 0, y: 0, width: 1, height: 1)
                : raw.insetBy(dx: -8, dy: -8)
            return OrphanItem(id: ink.id, image: drawing.image(from: bounds, scale: scale))
        }
    }

    // MARK: External change detection

    @objc private func appWillEnterForeground() { reloadIfChanged() }

    /// Debounce rapid file-coordination notifications (an atomic save can fire
    /// several) before checking whether to reload.
    private func scheduleReloadCheck() {
        reloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadIfChanged() }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func reloadIfChanged() {
        guard let url = currentURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        if Hashing.documentHash(text) != lastDocHash {
            Task { await loadAndRender(initial: false) }
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let store = self.inkStore else { return }
            store.save(blocks: self.currentBlocks, documentText: self.documentText)
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}

// MARK: - PKCanvasViewDelegate

extension DocumentCanvasViewController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        enforceContentSize()
        guard !isRestoring, let store = inkStore, !currentBlocks.isEmpty else { return }
        store.capture(drawing: canvasView.drawing, blocks: currentBlocks)
        scheduleSave()
    }
}

// MARK: - PKToolPickerObserver

extension DocumentCanvasViewController: PKToolPickerObserver {
    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) {
        let obscured = toolPicker.frameObscured(in: view)
        let bottom = obscured.isNull ? 0 : max(0, view.bounds.maxY - obscured.minY)
        canvasView.contentInset.bottom = bottom
        canvasView.verticalScrollIndicatorInsets.bottom = bottom
    }
}
