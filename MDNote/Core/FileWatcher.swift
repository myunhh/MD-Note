import Foundation

/// Watches a single file for external changes via file coordination, so edits
/// made elsewhere (Files app, iCloud, an external editor) are picked up
/// immediately — not only when the app returns to the foreground. Also tracks
/// moves/renames so an open document can follow its file.
///
/// Not main-actor isolated: the coordination machinery touches `presentedItemURL`
/// and `presentedItemOperationQueue` from arbitrary threads. Callbacks are
/// hopped to the main queue.
final class FileWatcher: NSObject, NSFilePresenter {
    private let lock = NSLock()
    private var url: URL
    private let onChange: () -> Void
    private let onMove: ((URL) -> Void)?
    private var active = false

    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(url: URL, onChange: @escaping () -> Void, onMove: ((URL) -> Void)? = nil) {
        self.url = url
        self.onChange = onChange
        self.onMove = onMove
        super.init()
    }

    var presentedItemURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return url
    }

    func start() {
        guard !active else { return }
        active = true
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() {
        guard active else { return }
        active = false
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() {
        let callback = onChange
        DispatchQueue.main.async { callback() }
    }

    func presentedItemDidMove(to newURL: URL) {
        lock.lock()
        url = newURL
        lock.unlock()
        guard let onMove else { return }
        DispatchQueue.main.async { onMove(newURL) }
    }
}
