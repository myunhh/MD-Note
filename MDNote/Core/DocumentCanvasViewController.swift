import UIKit
import PencilKit
import SafariServices
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
    private var didRestoreViewState = false
    private var isRestoring = false
    private var toolPickerVisible = true
    private var paperStyle = UserDefaults.standard.string(forKey: "paperStyle") ?? "plain"
    private var fingerDrawing = UserDefaults.standard.bool(forKey: "fingerDrawing")

    /// URL the SwiftUI screen asked us to open (stable across this screen).
    private var requestedURL: URL?
    /// URL the document actually lives at now (follows external renames).
    private var currentURL: URL?
    private var documentText = ""
    private var lastDocHash = ""
    private var currentBlocks: [Block] = []
    private var linkRegions: [LinkRegion] = []
    private var inkStore: InkStore?
    private var saveWorkItem: DispatchWorkItem?
    private var stateWorkItem: DispatchWorkItem?
    private var fileWatcher: FileWatcher?
    private var reloadWorkItem: DispatchWorkItem?
    private var isLoadingDocument = false
    private var didInitialLoad = false
    private var renderRetryCount = 0
    /// Saved scroll fraction still being honored — cleared once the user
    /// scrolls, so late image loads can correct the restored position.
    private var pendingRestoreFracY: Double?

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
        applyDrawingPolicy()                          // pencil draws; finger per setting
        canvasView.alwaysBounceVertical = true
        canvasView.backgroundColor = .clear           // show the web behind
        canvasView.isOpaque = false
        canvasView.contentInsetAdjustmentBehavior = .always
        canvasView.minimumZoomScale = 1.0             // refined in updateZoomLimits()
        canvasView.maximumZoomScale = 5.0
        view.addSubview(canvasView)

        // Finger taps open links (pencil touches never reach this recognizer).
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleLinkTap(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        canvasView.addGestureRecognizer(tap)

        // Mirror the canvas's scroll + zoom onto the web layer.
        zoomObservation = canvasView.observe(\.zoomScale, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.syncWeb()
                self?.scheduleViewStatePersist()
            }
        }
        offsetObservation = canvasView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.canvasView.isTracking { self.pendingRestoreFracY = nil }
                self.syncWeb()
                self.scheduleViewStatePersist()
            }
        }

        // Images/web fonts finishing after the first measurement shift the
        // layout; re-measure so blocks (and the ink anchored to them) match.
        renderer.onLayoutChanged = { [weak self] in
            guard let self else { return }
            Task { await self.remeasureLayout() }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flushPendingSave()
        persistViewState()
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
        // Compare against the URL the screen originally asked for, not
        // currentURL: after an external rename currentURL moves with the file,
        // and SwiftUI's update pass re-sends the (stale) original — reopening
        // it would detach from the live document.
        guard url != requestedURL else { return }
        requestedURL = url
        currentURL = url
        inkStore = InkStore(documentURL: url)
        didInitialZoom = false
        didRestoreViewState = false
        didInitialLoad = false
        renderRetryCount = 0
        pendingRestoreFracY = nil
        fileWatcher?.stop()
        fileWatcher = FileWatcher(
            url: url,
            onChange: { [weak self] in self?.scheduleReloadCheck() },
            onMove: { [weak self] newURL in self?.documentDidMove(to: newURL) })
        fileWatcher?.start()
        Task { await loadAndRender(initial: true) }
    }

    /// Follow an external rename/move (Files app, Finder) so the open session —
    /// and its sidecar — stays attached to the file.
    private func documentDidMove(to newURL: URL) {
        guard let old = currentURL, old != newURL else { return }
        currentURL = newURL
        inkStore?.relocate(to: newURL)
        renderer.setAssetBase(newURL.deletingLastPathComponent())
    }

    // MARK: Render pipeline

    private func loadAndRender(initial: Bool) async {
        guard let url = currentURL, let store = inkStore else { return }
        isLoadingDocument = true
        defer { isLoadingDocument = false }

        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "# 파일을 읽을 수 없습니다\n"
        let newHash = Hashing.documentHash(text)

        await renderer.loadAssetsIfNeeded()
        renderer.setAssetBase(url.deletingLastPathComponent())
        await renderer.render(markdown: text)
        await renderer.setPaper(paperStyle)
        let height = await renderer.contentHeight()
        let newBlocks = await renderer.blocks()

        // A non-empty document that yields zero blocks means the web bridge
        // failed, not that every block vanished — bail out rather than
        // orphaning all ink and blanking the canvas. lastDocHash stays stale,
        // so the retry (and any later change notification) re-runs the load.
        if newBlocks.isEmpty,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if renderRetryCount < 2 {
                renderRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.reloadIfChanged()
                }
            }
            return
        }
        renderRetryCount = 0

        documentText = text
        applyContentSize(height)

        if initial {
            store.adoptStrandedSidecarIfNeeded(documentText: text)
            if let sidecar = store.load() {
                // Ink saved under an older hashing scheme re-keys in place
                // first; anything still unresolved goes through a re-anchor so
                // it lands in the orphan tray instead of becoming invisible.
                store.migrateLegacyAnchors(to: newBlocks)
                let unresolved = store.ink.contains {
                    newBlocks.block(hash: $0.blockHash, seq: $0.blockSeq) == nil
                }
                if sidecar.documentHash != newHash || unresolved {
                    let result = store.applyExternalEdit(
                        oldBlocks: sidecar.blocks.map(\.block), newBlocks: newBlocks)
                    reportReanchor(result)
                }
            }
        } else {
            let result = store.applyExternalEdit(oldBlocks: currentBlocks, newBlocks: newBlocks)
            reportReanchor(result)
        }

        currentBlocks = newBlocks
        lastDocHash = newHash
        didInitialLoad = true

        isRestoring = true
        canvasView.drawing = store.rebuildDrawing(blocks: newBlocks)
        isRestoring = false

        store.save(blocks: newBlocks, documentText: text)
        session?.paperStyle = paperStyle
        session?.fingerDrawing = fingerDrawing
        refreshOrphans()
        refreshUndoState()
        await refreshNavigationAids()
        activateToolPicker()
    }

    /// Re-read geometry after a late layout shift (image/web font finished
    /// loading). Block identities are unchanged — only frames move — so the
    /// stored block-relative ink re-renders at the right spots.
    private func remeasureLayout() async {
        // loadAndRender refreshes geometry itself — interleaving here would
        // overwrite currentBlocks and corrupt its re-anchor baseline.
        guard !isLoadingDocument, let store = inkStore, !currentBlocks.isEmpty else { return }

        // Replacing canvasView.drawing cancels an in-progress stroke — wait
        // for the pen to lift.
        let gesture = canvasView.drawingGestureRecognizer.state
        if gesture == .began || gesture == .changed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                Task { await self.remeasureLayout() }
            }
            return
        }

        let height = await renderer.contentHeight()
        let newBlocks = await renderer.blocks()
        guard !newBlocks.isEmpty, !isLoadingDocument else { return }

        // A font load with no reflow fires the notification too — skip the
        // drawing rebuild when nothing actually moved.
        let unchanged = height == contentHeight
            && newBlocks.count == currentBlocks.count
            && zip(newBlocks, currentBlocks).allSatisfy { $0.frame == $1.frame }
        if unchanged { return }

        applyContentSize(height)
        currentBlocks = newBlocks
        isRestoring = true
        canvasView.drawing = store.rebuildDrawing(blocks: newBlocks)
        isRestoring = false
        refreshUndoState()

        // If the user hasn't scrolled since the saved position was restored,
        // re-apply it against the corrected content height.
        if let frac = pendingRestoreFracY {
            let z = canvasView.zoomScale
            let minY = -canvasView.adjustedContentInset.top
            let maxY = max(minY, contentHeight * z - canvasView.bounds.height
                           + canvasView.adjustedContentInset.bottom)
            canvasView.contentOffset.y = min(max(CGFloat(frac) * contentHeight * z, minY), maxY)
        }
        await refreshNavigationAids()
    }

    private func refreshNavigationAids() async {
        linkRegions = await renderer.links()
        session?.outline = await renderer.outline()
    }

    private func reportReanchor(_ result: Reanchor.Result) {
        guard !(result.followed.isEmpty && result.orphaned.isEmpty) else { return }
        var msg = "문서 변경 감지 · 필기 \(result.followed.count)개 따라옴"
        if !result.orphaned.isEmpty { msg += " · \(result.orphaned.count)개 보관함" }
        session?.flash(msg)
    }

    // MARK: Layout / zoom / web sync

    private func applyContentSize(_ height: CGFloat) {
        contentHeight = max(height, 1)
        webContainer.transform = .identity
        webContainer.bounds = CGRect(x: 0, y: 0, width: pageWidth, height: contentHeight)
        renderer.webView.frame = webContainer.bounds
        canvasView.contentSize = CGSize(width: pageWidth, height: contentHeight)
        updateZoomLimits()
        if !didRestoreViewState, contentHeight > 1, canvasView.bounds.width > 0 {
            didRestoreViewState = true
            restoreViewState()
        }
        syncWeb()
    }

    // MARK: Per-document view state (zoom + scroll position)

    /// Restore the last zoom/scroll for this document. The vertical position is
    /// stored as a fraction of the content height, so it still lands near the
    /// right spot after external edits changed the document's length.
    private func restoreViewState() {
        guard let url = currentURL else { return }
        let key = LibraryStore.viewStateKey(for: url)
        guard let state = UserDefaults.standard.dictionary(forKey: key) as? [String: Double],
              let zoom = state["zoom"], let fracY = state["fracY"] else {
            canvasView.zoomScale = canvasView.minimumZoomScale
            return
        }
        let z = max(canvasView.minimumZoomScale, min(CGFloat(zoom), canvasView.maximumZoomScale))
        canvasView.zoomScale = z
        let minY = -canvasView.adjustedContentInset.top
        let maxY = max(minY, contentHeight * z - canvasView.bounds.height + canvasView.adjustedContentInset.bottom)
        let maxX = max(0, pageWidth * z - canvasView.bounds.width)
        canvasView.contentOffset = CGPoint(
            x: min(max(CGFloat(state["x"] ?? 0), 0), maxX),
            y: min(max(CGFloat(fracY) * contentHeight * z, minY), maxY))
        pendingRestoreFracY = fracY
    }

    private func scheduleViewStatePersist() {
        guard didRestoreViewState else { return }
        stateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistViewState() }
        stateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func persistViewState() {
        stateWorkItem?.cancel()
        stateWorkItem = nil
        guard didRestoreViewState, let url = currentURL, contentHeight > 1 else { return }
        let state: [String: Double] = [
            "zoom": Double(canvasView.zoomScale),
            "fracY": Double(canvasView.contentOffset.y / max(contentHeight * canvasView.zoomScale, 1)),
            "x": Double(canvasView.contentOffset.x),
        ]
        UserDefaults.standard.set(state, forKey: LibraryStore.viewStateKey(for: url))
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

    func undo() {
        canvasView.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        canvasView.undoManager?.redo()
        refreshUndoState()
    }

    private func refreshUndoState() {
        session?.canUndo = canvasView.undoManager?.canUndo ?? false
        session?.canRedo = canvasView.undoManager?.canRedo ?? false
    }

    func setPaper(_ style: String) {
        paperStyle = style
        UserDefaults.standard.set(style, forKey: "paperStyle")
        session?.paperStyle = style
        Task { await renderer.setPaper(style) }
    }

    /// Allow/disallow drawing with a finger. With finger drawing on, PencilKit
    /// moves scrolling to two fingers, so the single-scroll-owner setup holds.
    func setFingerDrawing(_ enabled: Bool) {
        fingerDrawing = enabled
        UserDefaults.standard.set(enabled, forKey: "fingerDrawing")
        applyDrawingPolicy()
        session?.fingerDrawing = enabled
    }

    private func applyDrawingPolicy() {
        canvasView.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
    }

    // MARK: Links & outline

    @objc private func handleLinkTap(_ recognizer: UITapGestureRecognizer) {
        // With finger drawing on, a finger tap is a (dot) stroke — don't also
        // open links from it.
        guard canvasView.drawingPolicy == .pencilOnly, !linkRegions.isEmpty else { return }
        let location = recognizer.location(in: canvasView)
        let z = canvasView.zoomScale
        let docPoint = CGPoint(x: location.x / z, y: location.y / z)
        guard let region = linkRegions.first(where: {
            $0.rect.insetBy(dx: -6, dy: -6).contains(docPoint)
        }) else { return }
        open(linkHref: region.href)
    }

    private func open(linkHref: String) {
        guard let url = URL(string: linkHref) else { return }
        switch url.scheme?.lowercased() {
        case "http", "https":
            present(SFSafariViewController(url: url), animated: true)
        case "mailto":
            UIApplication.shared.open(url)
        default:
            break
        }
    }

    /// Scroll so the given document-coordinate y (e.g. an outline heading)
    /// sits near the top of the viewport.
    func scroll(toDocumentY y: Double) {
        pendingRestoreFracY = nil
        let z = canvasView.zoomScale
        let minY = -canvasView.adjustedContentInset.top
        let maxY = max(minY, canvasView.contentSize.height - canvasView.bounds.height
                       + canvasView.adjustedContentInset.bottom)
        let target = min(max(CGFloat(y) * z + minY - 16, minY), maxY)
        canvasView.setContentOffset(CGPoint(x: canvasView.contentOffset.x, y: target), animated: true)
    }

    // MARK: PDF export

    func exportPDF() {
        guard let url = currentURL else { return }
        let title = url.deletingPathExtension().lastPathComponent
        session?.flash("PDF 만드는 중…", duration: 60)
        Task {
            do {
                let fileURL = try await DocumentExporter.exportPDF(
                    webView: renderer.webView,
                    drawing: canvasView.drawing,
                    pageWidth: pageWidth,
                    contentHeight: contentHeight,
                    title: title)
                session?.status = nil
                presentShareSheet(for: fileURL)
            } catch {
                session?.flash("PDF 내보내기에 실패했어요")
            }
        }
    }

    private func presentShareSheet(for url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top + 8,
                                        width: 1, height: 1)
        }
        present(controller, animated: true)
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

    @objc private func appDidEnterBackground() {
        flushPendingSave()
        persistViewState()
    }

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
            // If the very first load never completed (e.g. bridge failure),
            // run the initial path again — the non-initial path assumes the
            // sidecar was already loaded and would save empty ink over it.
            let initial = !didInitialLoad
            Task { await loadAndRender(initial: initial) }
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWorkItem = nil
            self.inkStore?.save(blocks: self.currentBlocks, documentText: self.documentText)
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// Write any debounced-but-unsaved ink NOW. Called when leaving the screen
    /// or backgrounding — otherwise strokes drawn in the last <0.8s would die
    /// with the view controller.
    private func flushPendingSave() {
        guard saveWorkItem != nil else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        inkStore?.save(blocks: currentBlocks, documentText: documentText)
    }
}

// MARK: - PKCanvasViewDelegate

extension DocumentCanvasViewController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        enforceContentSize()
        guard !isRestoring, let store = inkStore, !currentBlocks.isEmpty else { return }
        pendingRestoreFracY = nil   // the user is writing here — don't yank the view
        store.capture(drawing: canvasView.drawing, blocks: currentBlocks)
        scheduleSave()
        refreshUndoState()
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
