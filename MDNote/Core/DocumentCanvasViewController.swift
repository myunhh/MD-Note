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
    private var documentSearchRevision = 0
    private var documentSearchTask: Task<Void, Never>?
    private let canvasView = DocumentInputCanvas()
    private let webContainer = UIView()           // sibling behind the canvas
    private var toolPicker: PKToolPicker?
    private var zoomObservation: NSKeyValueObservation?
    private var offsetObservation: NSKeyValueObservation?

    private var pageWidth: CGFloat { renderer.pageWidth }
    private var contentHeight: CGFloat = 1000
    private var didInitialZoom = false
    private var didRestoreViewState = false
    private var isRestoring = false
    private var toolPickerVisible = UserDefaults.standard.object(forKey: "toolPickerVisible") as? Bool ?? true
    private var paperStyle = UserDefaults.standard.string(forKey: "paperStyle") ?? "plain"
    private var fingerDrawing = UserDefaults.standard.bool(forKey: "fingerDrawing")
    private var textScale = UserDefaults.standard.object(forKey: "textScale") as? Double ?? 1.0

    /// URL the SwiftUI screen asked us to open (stable across this screen).
    private var requestedURL: URL?
    /// URL the document actually lives at now (follows external renames).
    private var currentURL: URL?
    private var documentText = ""
    private var lastDocHash = ""
    private var currentBlocks: [Block] = []
    private var linkRegions: [LinkRegion] = []
    private var inkStore: InkStore?
    private var bookmarkStore: BookmarkStore?
    private var bookmarkRecoveryURL: URL?
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
    /// Serializes loadAndRender so two concurrent loads can't interleave writes
    /// to currentBlocks / lastDocHash / canvasView.drawing. (@MainActor makes a
    /// plain Bool race-free — reentrancy only happens at await suspension.)
    private var loadInFlight = false
    private var reloadPending = false
    /// VoiceOver: one element per block, exposing the document text the opaque
    /// canvas otherwise hides entirely. Rebuilt on load/remeasure; frames track
    /// the current zoom via syncWeb.
    private var accessibilityBlocks: [UIAccessibilityElement] = []
    /// Memoized orphan thumbnails so a tray refresh doesn't re-rasterize every
    /// unchanged scribble.
    private var orphanThumbnails: [UUID: UIImage] = [:]
    private var pencilInteraction: UIPencilInteraction?
    /// The inking tool to restore after a double-tap eraser toggle.
    private var toolBeforeEraser: PKTool?
    /// Guards against overlapping exports clobbering the shared `body.exporting`
    /// paper-off state (which a finishing export would remove mid-capture).
    private var exportInFlight = false
    private var textEditing = false
    private var editorComposing = false
    private var editorCanUndo = false
    private var editorCanRedo = false
    private var markdownSaveFailed = false
    private var editorRevision = -1
    private var layoutRevision = 0
    private var strokeActive = false
    private var deferredLayout = false
    private var attachmentHistory: [String: [UUID: InkStore.Attachment]] = [:]
    private var editorHistoryID = ""
    private var textPan: UIPanGestureRecognizer?
    private var textPinch: UIPinchGestureRecognizer?

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
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panText(_:)))
        pan.minimumNumberOfTouches = 2
        pan.isEnabled = false
        view.addGestureRecognizer(pan)
        textPan = pan
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoomText(_:)))
        pinch.isEnabled = false
        view.addGestureRecognizer(pinch)
        textPinch = pinch

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
        renderer.onDocumentEdited = { [weak self] snapshot in
            guard !snapshot.composing else { return }
            self?.acceptEditorSnapshot(snapshot)
        }
        renderer.onEditorState = { [weak self] state in
            guard let self else { return }
            self.editorComposing = state.composing
            self.editorCanUndo = state.canUndo
            self.editorCanRedo = state.canRedo
            if let error = state.error { self.session?.flash(error, kind: .error, duration: 8) }
            self.refreshUndoState()
        }
        renderer.onStudyInsertionsChanged = { [weak self] insertions in
            self?.replaceStudyInsertions(insertions)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(voiceOverStatusChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)

        // Apple Pencil double-tap (and Pencil Pro squeeze) toggles the eraser —
        // the muscle-memory gesture for handwriting apps.
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        view.addInteraction(pencil)
        pencilInteraction = pencil
    }

    @objc private func voiceOverStatusChanged() {
        rebuildAccessibilityElements()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flushEditorChanges()
        flushPendingSave()       // durable ink write FIRST
        persistViewState()       // persists + cancels stateWorkItem
        reloadWorkItem?.cancel(); reloadWorkItem = nil   // don't reload a closing doc
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
        saveWorkItem?.cancel()
        stateWorkItem?.cancel()
        reloadWorkItem?.cancel()
        zoomObservation?.invalidate()
        offsetObservation?.invalidate()
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
        flushPendingSave()
        layoutRevision += 1
        requestedURL = url
        editorRevision = -1
        markdownSaveFailed = false
        attachmentHistory = [:]
        editorHistoryID = ""
        documentSearchTask?.cancel()
        documentSearchRevision += 1
        session?.searchQuery = ""
        session?.searchCount = 0
        session?.searchIndex = 0
        session?.searchPending = false
        session?.searchFailed = false
        currentURL = url
        bookmarkRecoveryURL = nil
        session?.bookmarkReady = false
        loadBookmarks()
        inkStore = InkStore(documentURL: url)
        inkStore?.onSaveFailure = { [weak self] _ in
            self?.session?.flash(L10n.text("saveInkFailed"), kind: .error, duration: 8)
        }
        // Per-document paper style (falling back to the global default), resolved
        // BEFORE the first render so the initial setPaper uses the right value.
        paperStyle = UserDefaults.standard.string(forKey: LibraryStore.paperKey(for: url))
            ?? UserDefaults.standard.string(forKey: "paperStyle") ?? "plain"
        orphanThumbnails = [:]
        accessibilityBlocks = []
        didInitialZoom = false
        didRestoreViewState = false
        didInitialLoad = false
        canvasView.drawingGestureRecognizer.isEnabled = false
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
        LibraryMetadataStore.shared.move(from: old, to: newURL)
        currentURL = newURL
        inkStore?.relocate(to: newURL)
        do {
            if let store = bookmarkStore { try store.relocate(to: newURL) }
            else { try BookmarkStore.moveCompanion(from: old, to: newURL) }
        }
        catch {
            bookmarkRecoveryURL = bookmarkStore?.documentURL ?? old
            bookmarkStore = nil
            session?.bookmarkError = L10n.text("bookmarkMoveFailed")
            session?.flash(L10n.text("bookmarkMoveFailed"), kind: .error, duration: 8)
        }
        renderer.setAssetBase(newURL.deletingLastPathComponent())
    }

    // MARK: Render pipeline

    private func loadAndRender(initial: Bool) async {
        guard !isPencilDown else { reloadPending = true; return }
        // Reentrancy guard: coalesce a burst (e.g. an external save firing while
        // the initial load is still mid-render) into one trailing reload.
        if loadInFlight { reloadPending = true; return }
        loadInFlight = true
        isLoadingDocument = true
        session?.bookmarkReady = false
        defer {
            isLoadingDocument = false
            loadInFlight = false
            session?.bookmarkReady = didInitialLoad
            if reloadPending {
                reloadPending = false
                // If the first load never completed (zero-block bailout),
                // re-derive initial from didInitialLoad so the sidecar path runs.
                Task { await loadAndRender(initial: !didInitialLoad) }
            }
        }
        guard let url = currentURL, let store = inkStore else { return }
        let openURL = url

        let text: String
        do { text = try MarkdownFileWriter.read(url) }
        catch {
            session?.flash(error.localizedDescription, kind: .error, duration: 8)
            return
        }
        let newHash = Hashing.documentHash(text)
        var loadedSidecar: Sidecar?
        if initial {
            store.adoptStrandedSidecarIfNeeded(documentText: text)
            loadedSidecar = store.load()
        }
        editorRevision = -1

        await renderer.loadAssetsIfNeeded()
        renderer.setAssetBase(url.deletingLastPathComponent())
        let studyIDs = Set(store.studyInsertions.flatMap { [$0.id] + $0.blockIDs })
        let identityBlocks = (loadedSidecar?.blocks ?? currentBlocks.map(BlockSnapshot.init))
            .filter { block in block.blockID.map { !studyIDs.contains($0) } ?? true }
        let unchangedDocument = initial ? loadedSidecar?.documentHash == newHash : lastDocHash == newHash
        await renderer.render(markdown: text, blocks: identityBlocks, documentUnchanged: unchangedDocument)
        await renderer.setStudyInsertions(store.studyInsertions)
        await renderer.setPaper(paperStyle)
        await renderer.setTextScale(textScale)
        let renderedSnapshot = try? await renderer.flushEditor()
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

        // The document may have been swapped (open) or relocated (documentDidMove)
        // during the awaits above. Bail BEFORE writing any shared baseline so a
        // stale render never lands on the wrong document.
        guard currentURL == openURL, inkStore === store else { return }
        guard !isPencilDown else { reloadPending = true; return }

        documentText = text
        editorHistoryID = renderedSnapshot?.historyID ?? ""
        applyContentSize(height)

        if initial {
            if let sidecar = loadedSidecar {
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
            if store.isReadOnly {
                session?.flash(L10n.text("newerInk"), duration: 6)
            }
        } else {
            let result = store.applyExternalEdit(oldBlocks: currentBlocks, newBlocks: newBlocks)
            reportReanchor(result)
        }

        currentBlocks = newBlocks
        lastDocHash = newHash
        didInitialLoad = true
        canvasView.drawingGestureRecognizer.isEnabled = !textEditing && !store.isReadOnly

        await refreshInkProjection(store)
        guard !isPencilDown else { deferredLayout = true; return }
        replaceCanvasDrawing(store.rebuildDrawing(blocks: newBlocks))
        attachmentHistory[editorHistoryID] = store.attachments()

        store.save(blocks: newBlocks, documentText: text)
        session?.paperStyle = paperStyle
        session?.textScale = textScale
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
        guard !isLoadingDocument, didInitialLoad, let store = inkStore else { return }

        // Replacing canvasView.drawing cancels an in-progress stroke — wait
        // for the pen to lift.
        guard !isPencilDown else { deferredLayout = true; return }
        layoutRevision += 1
        let revision = layoutRevision

        let height = await renderer.contentHeight()
        let newBlocks = await renderer.blocks()
        guard (!newBlocks.isEmpty || documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              !isLoadingDocument, revision == layoutRevision else { return }
        guard !isPencilDown else { deferredLayout = true; return }

        // A font load with no reflow fires the notification too — skip the
        // drawing rebuild when nothing actually moved.
        let unchanged = !deferredLayout && !store.ink.contains(where: { $0.behavior != .rigid })
            && height == contentHeight
            && newBlocks.count == currentBlocks.count
            && zip(newBlocks, currentBlocks).allSatisfy { $0 == $1 }
        if unchanged { return }
        deferredLayout = false

        let result = store.applyExternalEdit(oldBlocks: currentBlocks, newBlocks: newBlocks)
        reportReanchor(result)
        store.restoreStudyTargets(in: newBlocks)
        await refreshInkProjection(store)
        guard revision == layoutRevision, !isPencilDown else { deferredLayout = true; return }
        applyContentSize(height)
        currentBlocks = newBlocks
        replaceCanvasDrawing(store.rebuildDrawing(blocks: newBlocks))
        attachmentHistory[editorHistoryID] = store.attachments()
        scheduleSave()
        refreshOrphans()
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
        session?.docStats = await renderer.stats()
        rebuildAccessibilityElements()
        refreshDocumentSearch(navigate: false)
    }

    func refreshDocumentSearch(navigate: Bool) {
        documentSearchTask?.cancel()
        documentSearchRevision += 1
        guard let session else { return }
        let revision = documentSearchRevision
        let query = session.searchQuery
        let index = session.searchIndex
        session.searchFailed = false
        guard didInitialLoad else { return }
        session.searchPending = !query.isEmpty
        documentSearchTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let result = await renderer.search(query: query, index: index, revision: revision)
            guard !Task.isCancelled, revision == documentSearchRevision,
                  session.searchQuery == query else { return }
            session.searchPending = false
            session.searchFailed = result == nil && !query.isEmpty
            session.searchCount = result?.count ?? 0
            session.searchIndex = result?.index ?? 0
            if navigate, let y = result?.y, y.isFinite { scroll(toDocumentY: y) }
        }
    }

    // MARK: VoiceOver

    /// Expose the rendered document text to VoiceOver. The web view sits behind a
    /// transparent, non-interactive canvas, so without this the entire note body
    /// is unreadable. One element per non-empty block, in document order.
    private func rebuildAccessibilityElements() {
        if textEditing {
            view.accessibilityElements = [renderer.webView]
            return
        }
        guard UIAccessibility.isVoiceOverRunning else {
            if !accessibilityBlocks.isEmpty {
                accessibilityBlocks = []
                canvasView.accessibilityElements = nil
            }
            return
        }
        let headings = Set((session?.outline ?? []).map(\.text))
        var elements: [UIAccessibilityElement] = []
        for block in currentBlocks {
            guard let text = accessibilityText(for: block) else { continue }
            let element = UIAccessibilityElement(accessibilityContainer: canvasView)
            element.accessibilityLabel = text
            if headings.contains(text) { element.accessibilityTraits = .header }
            elements.append(element)
        }
        accessibilityBlocks = elements
        canvasView.accessibilityElements = elements
        updateAccessibilityFrames()
    }

    /// The VoiceOver label for a block, or nil if it should be skipped (empty /
    /// hr / image-only). Strips a leading callout marker ("[!NOTE]" etc.) so the
    /// reader hears the body, not the raw marker that CSS hides visually. Both
    /// the element builder and the frame updater use this, so their indices stay
    /// aligned.
    private func accessibilityText(for block: Block) -> String? {
        var text = (block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "^\\[!\\w+\\]\\s*", with: "", options: .regularExpression)
        return text.isEmpty ? nil : text
    }

    /// Keep each VoiceOver element's focus rectangle aligned with its block under
    /// the current zoom. Container space for a scroll view is bounds-relative
    /// (bounds already reflects contentOffset), so only the zoom scale applies.
    private func updateAccessibilityFrames() {
        guard !accessibilityBlocks.isEmpty else { return }
        let z = canvasView.zoomScale
        var i = 0
        for block in currentBlocks {
            guard accessibilityText(for: block) != nil, i < accessibilityBlocks.count else { continue }
            accessibilityBlocks[i].accessibilityFrameInContainerSpace =
                block.frame.applying(CGAffineTransform(scaleX: z, y: z))
            i += 1
        }
    }

    private func reportReanchor(_ result: Reanchor.Result) {
        guard !(result.followed.isEmpty && result.orphaned.isEmpty) else { return }
        var msg = L10n.format("reanchored", result.followed.count)
        if !result.orphaned.isEmpty { msg += L10n.format("orphaned", result.orphaned.count) }
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
        if !accessibilityBlocks.isEmpty { updateAccessibilityFrames() }
    }

    // MARK: Tool picker

    private func activateToolPicker() {
        guard isViewLoaded, view.window != nil, !textEditing, inkStore?.isReadOnly != true else { return }
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
        UserDefaults.standard.set(toolPickerVisible, forKey: "toolPickerVisible")
        _ = canvasView.becomeFirstResponder()
        toolPicker?.setVisible(toolPickerVisible, forFirstResponder: canvasView)
        session?.toolsVisible = toolPickerVisible
        session?.hapticSelection()
    }

    func undo() {
        if textEditing {
            editorCommand("undo")
            return
        }
        canvasView.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        if textEditing {
            editorCommand("redo")
            return
        }
        canvasView.undoManager?.redo()
        refreshUndoState()
    }

    private func refreshUndoState() {
        session?.canUndo = textEditing ? editorCanUndo : (canvasView.undoManager?.canUndo ?? false)
        session?.canRedo = textEditing ? editorCanRedo : (canvasView.undoManager?.canRedo ?? false)
    }

    func setPaper(_ style: String) {
        paperStyle = style
        UserDefaults.standard.set(style, forKey: "paperStyle")   // global default for new notes
        if let url = currentURL {
            UserDefaults.standard.set(style, forKey: LibraryStore.paperKey(for: url))
        }
        session?.paperStyle = style
        Task { await renderer.setPaper(style) }
    }

    /// Change the reading text scale (font-size only — page geometry is fixed).
    /// The reflow re-anchors ink via the existing layoutChanged -> remeasureLayout
    /// path, so no extra plumbing is needed.
    func setTextScale(_ scale: Double) {
        textScale = scale
        UserDefaults.standard.set(scale, forKey: "textScale")
        session?.textScale = scale
        Task { await renderer.setTextScale(scale) }
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
        canvasView.setContentOffset(CGPoint(x: canvasView.contentOffset.x, y: target),
                                    animated: !UIAccessibility.isReduceMotionEnabled)
    }

    func loadBookmarks() {
        guard let url = currentURL else { return }
        do {
            let store = try BookmarkStore(documentURL: bookmarkRecoveryURL ?? url)
            try store.relocate(to: url)
            bookmarkStore = store
            bookmarkRecoveryURL = nil
            session?.bookmarks = store.bookmarks
            session?.bookmarkError = nil
        } catch {
            bookmarkStore = nil
            session?.bookmarkError = L10n.text("bookmarkReadFailed")
        }
    }

    func addCurrentBookmark() {
        guard didInitialLoad, !isLoadingDocument else { return }
        let y = max(0, Double((canvasView.contentOffset.y + canvasView.adjustedContentInset.top + 16)
                             / canvasView.zoomScale))
        let block = currentBlocks.last { Double($0.frame.minY) <= y } ?? currentBlocks.first
        let text = (block?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = text.isEmpty ? L10n.text("bookmarkDefault") : String(text.prefix(80))
        let bookmark = DocumentBookmark(name: name, y: y, height: Double(contentHeight), blocks: currentBlocks)
        updateBookmarks { $0.append(bookmark) }
    }

    func renameBookmark(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateBookmarks { items in
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].name = trimmed }
        }
    }

    func deleteBookmark(_ id: UUID) {
        updateBookmarks { $0.removeAll { $0.id == id } }
    }

    private func updateBookmarks(_ edit: (inout [DocumentBookmark]) -> Void) {
        guard let store = bookmarkStore else { return }
        var items = store.bookmarks
        edit(&items)
        do {
            try store.replace(with: items)
            session?.bookmarks = store.bookmarks
            session?.bookmarkError = nil
        } catch {
            session?.bookmarkError = L10n.text("bookmarkWriteFailed")
        }
    }

    func jumpToBookmark(_ bookmark: DocumentBookmark) {
        guard didInitialLoad, !isLoadingDocument else { return }
        let destination = bookmark.resolve(in: currentBlocks, height: Double(contentHeight))
        scroll(toDocumentY: destination.y)
        if destination.usedFallback {
            session?.flash(L10n.text("bookmarkFallback"), duration: 8)
        }
    }

    func scrollToBeginning() {
        scroll(toDocumentY: 0)
    }

    func scrollToEnd() {
        pendingRestoreFracY = nil
        let minY = -canvasView.adjustedContentInset.top
        let maxY = max(minY, canvasView.contentSize.height - canvasView.bounds.height
                       + canvasView.adjustedContentInset.bottom)
        canvasView.setContentOffset(CGPoint(x: canvasView.contentOffset.x, y: maxY),
                                    animated: !UIAccessibility.isReduceMotionEnabled)
    }

    // MARK: PDF export

    func exportPDF() {
        guard let url = currentURL, !exportInFlight else { return }   // ignore re-taps mid-export
        exportInFlight = true
        let title = url.deletingPathExtension().lastPathComponent
        session?.flash(L10n.text("creatingPDF"), kind: .progress)   // no self-dismiss timer
        Task { [weak self] in
            guard let self else { return }
            defer { self.exportInFlight = false }
            do {
                try await self.prepareForExport()
                let fileURL = try await DocumentExporter.exportPDF(
                    webView: self.renderer.webView,
                    drawing: self.canvasView.drawing,
                    pageWidth: self.pageWidth,
                    contentHeight: self.contentHeight,
                    title: title)
                // Bail if the document was closed/changed mid-export.
                guard self.currentURL == url else { self.session?.clearStatus(); return }
                self.session?.clearStatus()
                self.session?.hapticSuccess()
                self.presentShareSheet(for: fileURL)
            } catch {
                // Don't flash an error onto a now-different/closed document.
                guard self.currentURL == url else { self.session?.clearStatus(); return }
                self.session?.flash(L10n.text("exportPDFFailed"), kind: .error)
            }
        }
    }

    // MARK: Share source archive

    func shareSource() {
        guard !exportInFlight else { return }
        flushPendingSave()                          // write debounced ink before reading the sidecar
        guard let md = currentURL else { return }
        exportInFlight = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.exportInFlight = false }
            do {
                try await self.prepareForExport()
                let noteData = try await Task.detached(priority: .userInitiated) { try NoteArchive.readNote(md) }.value
                guard let markdown = String(data: noteData, encoding: .utf8) else { throw NoteArchive.Failure.damaged }
                let supplements = self.inkStore?.studyInsertions.map(\.markdown).joined(separator: "\n\n") ?? ""
                let sources = try await self.renderer.imageSources(markdown: markdown + "\n\n" + supplements)
                let zip = try await Task.detached(priority: .userInitiated) {
                    try NoteArchive.export(note: md, noteData: noteData, imageSources: sources)
                }.value
                guard self.currentURL == md, self.view.window != nil else {
                    try? FileManager.default.removeItem(at: zip.deletingLastPathComponent())
                    return
                }
                self.presentShareSheet(forItems: [zip], cleanupDirectory: zip.deletingLastPathComponent())
            } catch {
                self.session?.flash(L10n.format("archiveExportFailed", error.localizedDescription), kind: .error)
            }
        }
    }

    private func presentShareSheet(for url: URL) { presentShareSheet(forItems: [url]) }

    private func presentShareSheet(forItems items: [URL], cleanupDirectory: URL? = nil) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let directory = cleanupDirectory {
            controller.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: directory)
            }
        }
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
        guard !isPencilDown, let store = inkStore else { return }
        if store.restoreOrphan(id, in: currentBlocks) {
            isRestoring = true
            canvasView.drawing = store.rebuildDrawing(blocks: currentBlocks)
            isRestoring = false
            session?.hapticImpact()
        } else {
            session?.flash(L10n.text("restoreInkFailed"), kind: .error)
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
        var number = 0
        let items: [OrphanItem] = store.orphans.compactMap { ink in
            let image: UIImage
            if let cached = orphanThumbnails[ink.id] {
                image = cached
            } else {
                guard let drawing = try? PKDrawing(data: ink.strokeData) else { return nil }
                let raw = drawing.bounds
                let bounds = raw.isNull || raw.isEmpty
                    ? CGRect(x: 0, y: 0, width: 1, height: 1)
                    : raw.insetBy(dx: -8, dy: -8)
                image = drawing.image(from: bounds, scale: scale)
                orphanThumbnails[ink.id] = image
            }
            number += 1   // sequential over PRODUCED items (no gaps on decode failure)
            let label: String
            if let y = ink.lastKnownOrigin?.y {
                label = L10n.format("inkPosition", number, Int(y))
            } else {
                label = L10n.format("inkNumber", number)
            }
            return OrphanItem(id: ink.id, image: image, label: label)
        }
        // Prune cache down to the live orphans so it can't grow unbounded.
        let live = Set(store.orphans.map(\.id))
        orphanThumbnails = orphanThumbnails.filter { live.contains($0.key) }
        return items
    }

    // MARK: External change detection

    @objc private func appWillEnterForeground() { reloadIfChanged() }

    @objc private func appDidEnterBackground() {
        flushEditorChanges()
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
            guard !markdownSaveFailed, !editorComposing else {
                session?.flash(MarkdownFileWriter.Failure.externalConflict.localizedDescription, kind: .error, duration: 8)
                return
            }
            // If the very first load never completed (e.g. bridge failure),
            // run the initial path again — the non-initial path assumes the
            // sidecar was already loaded and would save empty ink over it.
            let initial = !didInitialLoad
            Task {
                do {
                    if textEditing {
                        let snapshot = try await renderer.flushEditor()
                        acceptEditorSnapshot(snapshot)
                        guard !markdownSaveFailed else { return }
                    }
                    await loadAndRender(initial: initial)
                } catch {
                    session?.flash(error.localizedDescription, kind: .error, duration: 8)
                }
            }
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        guard !markdownSaveFailed else { return }
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWorkItem = nil
            guard !self.markdownSaveFailed else { return }
            self.inkStore?.save(blocks: self.currentBlocks, documentText: self.documentText)
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// Write any debounced-but-unsaved ink NOW. Called when leaving the screen
    /// or backgrounding — otherwise strokes drawn in the last <0.8s would die
    /// with the view controller.
    private func flushPendingSave() {
        guard !markdownSaveFailed else { return }
        guard saveWorkItem != nil else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        inkStore?.save(blocks: currentBlocks, documentText: documentText)
    }

    private var isPencilDown: Bool {
        let state = canvasView.drawingGestureRecognizer.state
        return strokeActive || state == .began || state == .changed
    }

    private func replaceCanvasDrawing(_ drawing: PKDrawing) {
        guard !isPencilDown else { deferredLayout = true; return }
        isRestoring = true
        canvasView.drawing = drawing
        isRestoring = false
    }

    private func refreshInkProjection(_ store: InkStore) async {
        var rects: [UUID: [CGRect]] = [:]
        for item in store.ink where item.behavior != .rigid {
            if let anchor = item.anchor, let geometry = await renderer.rangeGeometry(anchor), !geometry.isEmpty {
                rects[item.id] = geometry
            } else {
                store.detach(item.id, blocks: currentBlocks)
            }
        }
        store.rangeRects = rects
    }

    private func acceptEditorSnapshot(_ snapshot: EditorSnapshot) {
        guard didInitialLoad, !snapshot.composing, snapshot.revision >= editorRevision,
              let url = currentURL, inkStore?.isReadOnly != true else { return }
        let isNewRevision = snapshot.revision > editorRevision
        editorRevision = snapshot.revision
        if isNewRevision, let store = inkStore {
            layoutRevision += 1
            if attachmentHistory[editorHistoryID] == nil {
                attachmentHistory[editorHistoryID] = store.attachments()
            }
            if snapshot.historyID != editorHistoryID, let previous = attachmentHistory[snapshot.historyID] {
                store.restoreAttachments(previous)
            } else {
                for edit in snapshot.edits {
                    store.applyTextReplacement(blockID: edit.blockID, start: edit.startUTF16,
                                               end: edit.endUTF16, replacement: edit.insertedText,
                                               oldText: edit.oldText, blocks: currentBlocks)
                }
                store.applyBlockMappings(snapshot.mappings, blocks: currentBlocks)
            }
        }
        editorHistoryID = snapshot.historyID
        guard snapshot.markdown != documentText else {
            if isNewRevision { Task { await remeasureLayout() } }
            return
        }
        do {
            try MarkdownFileWriter.write(snapshot.markdown, to: url, expectedText: documentText)
            documentText = snapshot.markdown
            lastDocHash = Hashing.documentHash(snapshot.markdown)
            markdownSaveFailed = false
            Task { await remeasureLayout() }
        } catch {
            markdownSaveFailed = true
            session?.flash(error.localizedDescription, kind: .error, duration: 12)
        }
    }

    func setTextEditing(_ enabled: Bool) {
        guard didInitialLoad, !isPencilDown, inkStore?.isReadOnly != true else { return }
        Task {
            if !enabled {
                do {
                    let snapshot = try await renderer.flushEditor()
                    acceptEditorSnapshot(snapshot)
                    guard !markdownSaveFailed else { return }
                } catch {
                    session?.flash(error.localizedDescription, kind: .error, duration: 8)
                    return
                }
            }
            textEditing = enabled
            session?.textEditing = enabled
            canvasView.textInputActive = enabled
            renderer.webView.isUserInteractionEnabled = enabled
            canvasView.drawingGestureRecognizer.isEnabled = !enabled
            textPan?.isEnabled = enabled
            textPinch?.isEnabled = enabled
            toolPicker?.setVisible(!enabled && toolPickerVisible, forFirstResponder: canvasView)
            await renderer.setTextEditing(enabled)
            rebuildAccessibilityElements()
            if !enabled { activateToolPicker() }
            refreshUndoState()
        }
    }

    @objc private func panText(_ recognizer: UIPanGestureRecognizer) {
        let movement = recognizer.translation(in: view)
        canvasView.contentOffset.x -= movement.x
        canvasView.contentOffset.y -= movement.y
        recognizer.setTranslation(.zero, in: view)
    }

    @objc private func zoomText(_ recognizer: UIPinchGestureRecognizer) {
        let location = recognizer.location(in: view)
        let old = canvasView.zoomScale
        let point = CGPoint(x: (canvasView.contentOffset.x + location.x) / old,
                            y: (canvasView.contentOffset.y + location.y) / old)
        let next = min(canvasView.maximumZoomScale, max(canvasView.minimumZoomScale, old * recognizer.scale))
        canvasView.zoomScale = next
        canvasView.contentOffset = CGPoint(x: point.x * next - location.x, y: point.y * next - location.y)
        recognizer.scale = 1
    }

    func editorCommand(_ command: String) {
        guard didInitialLoad, inkStore?.isReadOnly != true else { return }
        Task { await renderer.editorCommand(command) }
    }

    private func flushEditorChanges() {
        guard didInitialLoad, textEditing else { return }
        Task {
            do {
                let snapshot = try await renderer.flushEditor()
                acceptEditorSnapshot(snapshot)
                await remeasureLayout()
                flushPendingSave()
            } catch {
                session?.flash(error.localizedDescription, kind: .error, duration: 8)
            }
        }
    }

    private func prepareForExport() async throws {
        guard !isPencilDown else { throw MarkdownFileWriter.Failure.unavailable }
        let snapshot = try await renderer.flushEditor()
        acceptEditorSnapshot(snapshot)
        guard !markdownSaveFailed else { throw MarkdownFileWriter.Failure.externalConflict }
        await remeasureLayout()
        guard !isPencilDown else { throw MarkdownFileWriter.Failure.unavailable }
        guard inkStore?.save(blocks: currentBlocks, documentText: documentText) != false else {
            throw MarkdownFileWriter.Failure.unavailable
        }
        saveWorkItem?.cancel()
        saveWorkItem = nil
    }

    func saveRecoveryCopy() {
        guard let url = currentURL else { return }
        Task {
            do {
                let snapshot = try await renderer.flushEditor()
                let recovery = url.deletingLastPathComponent()
                    .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-recovery-" + UUID().uuidString)
                    .appendingPathExtension("md")
                try Data(snapshot.markdown.utf8).write(to: recovery, options: .withoutOverwriting)
                if let store = inkStore {
                    let sidecar = Sidecar(documentHash: Hashing.documentHash(snapshot.markdown),
                                          layoutWidth: store.layoutWidth, blocks: currentBlocks.map(BlockSnapshot.init),
                                          ink: store.ink, orphans: store.orphans, appVersion: InkStore.appVersion,
                                          studyInsertions: store.studyInsertions)
                    try sidecar.encoded().write(to: recovery.appendingPathExtension("inknote"), options: .withoutOverwriting)
                }
                session?.flash("Saved recovery copy: " + recovery.lastPathComponent, duration: 10)
            } catch {
                session?.flash(error.localizedDescription, kind: .error, duration: 10)
            }
        }
    }

    func setInkBehavior(_ behavior: String) {
        guard let mode = AnnotationBehavior(rawValue: behavior), let store = inkStore else { return }
        Task {
            let anchor = await renderer.selectedTextAnchor()
            guard mode == .rigid || anchor != nil else {
                session?.flash("Select text before choosing a follow-text ink behavior.", duration: 8)
                return
            }
            store.captureBehavior = mode
            store.captureAnchor = anchor
        }
    }

    func insertStudySpace(kind: String) {
        guard !isPencilDown, let store = inkStore, !store.isReadOnly else { return }
        Task {
            let anchor = await renderer.selectedTextAnchor()
            let y = canvasView.contentOffset.y / canvasView.zoomScale
            let blockID = anchor?.blockID ?? currentBlocks.last(where: { $0.frame.minY <= y })?.blockID
            let insertion = StudyInsertion(id: UUID().uuidString, afterBlockID: blockID,
                                           kind: kind == "markdown" ? .markdown : .blank)
            await renderer.setStudyInsertions(store.studyInsertions + [insertion], recordUndo: true)
        }
    }

    private func replaceStudyInsertions(_ insertions: [StudyInsertion]) {
        guard let store = inkStore, !store.isReadOnly, insertions != store.studyInsertions else { return }
        if attachmentHistory[editorHistoryID] == nil {
            attachmentHistory[editorHistoryID] = store.attachments()
        }
        store.studyInsertions = insertions
        Task {
            await remeasureLayout()
            scheduleSave()
            refreshUndoState()
        }
    }
}

// MARK: - PKCanvasViewDelegate

extension DocumentCanvasViewController: PKCanvasViewDelegate {
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        strokeActive = true
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        strokeActive = false
        if reloadPending {
            reloadPending = false
            Task { await loadAndRender(initial: !didInitialLoad) }
        } else if deferredLayout {
            Task { await remeasureLayout() }
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        enforceContentSize()
        guard !isRestoring, let store = inkStore, !currentBlocks.isEmpty else { return }
        pendingRestoreFracY = nil   // the user is writing here — don't yank the view
        let needsProjection = store.captureBehavior != .rigid || store.ink.contains { $0.behavior != .rigid }
        store.capture(drawing: canvasView.drawing, blocks: currentBlocks)
        if needsProjection {
            deferredLayout = true
            if !isPencilDown { Task { await remeasureLayout() } }
        }
        attachmentHistory[editorHistoryID] = store.attachments()
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

// MARK: - Apple Pencil double-tap / squeeze

extension DocumentCanvasViewController: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        switch UIPencilInteraction.preferredTapAction {
        case .showColorPalette:
            toggleToolPicker()
        default:
            // switchEraser / switchPrevious / anything else -> eraser toggle,
            // the muscle-memory action for a handwriting app.
            toggleEraser()
        }
    }

    /// Toggle between the eraser and the previously selected inking tool.
    private func toggleEraser() {
        if canvasView.tool is PKEraserTool {
            // Always switch AWAY from the eraser. Fall back to a default pen when
            // there's no saved inking tool (e.g. the user picked the eraser
            // straight from the picker), so the gesture can never trap them.
            canvasView.tool = (toolBeforeEraser as? PKInkingTool) ?? PKInkingTool(.pen, color: .black, width: 6)
            toolBeforeEraser = nil
        } else {
            toolBeforeEraser = canvasView.tool
            canvasView.tool = PKEraserTool(.vector)
        }
        session?.hapticSelection()
    }
}
