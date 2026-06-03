import Foundation

/// Watches a single file for external changes via file coordination, so edits
/// made elsewhere (Files app, iCloud, an external editor) are picked up
/// immediately — not only when the app returns to the foreground.
///
/// Not main-actor isolated: the coordination machinery touches `presentedItemURL`
/// and `presentedItemOperationQueue` from arbitrary threads. The change callback
/// is hopped to the main queue.
final class FileWatcher: NSObject, NSFilePresenter {
    private let url: URL
    private let onChange: () -> Void
    private var active = false

    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        super.init()
    }

    var presentedItemURL: URL? { url }

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
}
