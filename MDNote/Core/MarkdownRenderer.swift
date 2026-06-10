import UIKit
import WebKit
import MDNoteCore

/// A clickable link region in document coordinates, as reported by bridge.js.
struct LinkRegion: Decodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let href: String

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// A heading in the document, for outline (TOC) navigation.
struct OutlineItem: Decodable, Identifiable, Equatable {
    let level: Int
    let text: String
    let y: Double

    var id: Double { y }
}

/// Wraps a WKWebView that renders markdown via the bundled web assets and
/// exposes the per-block geometry needed to anchor ink.
@MainActor
final class MarkdownRenderer: NSObject {
    let webView: WKWebView
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var didLoadAssets = false
    private let assetHandler = LocalAssetSchemeHandler()

    /// Fired (on the main actor) when the web layer's geometry changed after
    /// the initial measurement — e.g. an image or web font finished loading and
    /// pushed content down. The owner should re-query height + blocks.
    var onLayoutChanged: (() -> Void)?

    /// Total page width the web layer lays out at (must match theme.css / bridge.js):
    /// a 1080pt text column on the left + a blank right writing margin = 1390pt.
    let pageWidth: CGFloat = 1390

    override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.setURLSchemeHandler(assetHandler, forURLScheme: "mdasset")
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(WeakScriptHandler(self), name: "layoutChanged")
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false        // outer scroll view owns scrolling
        webView.scrollView.bounces = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
    }

    /// Load index.html once. Resumes when the web view finishes navigation.
    func loadAssetsIfNeeded() async {
        guard !didLoadAssets else { return }
        guard
            let dir = Bundle.main.url(forResource: "WebAssets", withExtension: nil),
            let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebAssets")
        else {
            assertionFailure("WebAssets bundle missing")
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            readyContinuation = cont
            webView.loadFileURL(index, allowingReadAccessTo: dir)
        }
        didLoadAssets = true
    }

    func render(markdown: String) async {
        let literal = Self.jsStringLiteral(markdown)
        _ = try? await webView.evaluateJavaScript("MDNote.render(\(literal))")
    }

    /// Set the paper background style ("plain" / "ruled" / "grid" / "dots").
    func setPaper(_ style: String) async {
        _ = try? await webView.evaluateJavaScript("MDNote.setPaper(\(Self.jsStringLiteral(style)))")
    }

    /// Folder that relative image paths in the document resolve against.
    func setAssetBase(_ directory: URL) {
        assetHandler.baseDirectory = directory
    }

    func contentHeight() async -> CGFloat {
        let any = (try? await webView.evaluateJavaScript("MDNote.contentHeight()")) ?? nil
        if let n = any as? NSNumber { return CGFloat(truncating: n) }
        return 1000
    }

    /// Per-block geometry in document coordinates, after layout.
    func blocks() async -> [Block] {
        await decodeJSON("MDNote.layout()", as: [BlockGeometryDTO].self).map(\.block)
    }

    /// Clickable link regions in document coordinates.
    func links() async -> [LinkRegion] {
        await decodeJSON("MDNote.links()", as: [LinkRegion].self)
    }

    /// Document headings (h1–h3) for outline navigation.
    func outline() async -> [OutlineItem] {
        await decodeJSON("MDNote.outline()", as: [OutlineItem].self)
    }

    private func decodeJSON<T: Decodable>(_ expression: String, as type: [T].Type) async -> [T] {
        let any = (try? await webView.evaluateJavaScript("JSON.stringify(\(expression))")) ?? nil
        guard let json = any as? String, let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([T].self, from: data) else { return [] }
        return items
    }

    /// Encode a Swift string as a safe JS string literal (handles quotes,
    /// newlines, unicode). Encoding `[s]` then trimming the brackets avoids
    /// top-level-fragment quirks of JSONEncoder.
    static func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode([s]),
              var literal = String(data: data, encoding: .utf8), literal.count >= 2 else {
            return "\"\""
        }
        literal.removeFirst()  // [
        literal.removeLast()   // ]
        return literal
    }
}

extension MarkdownRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        readyContinuation?.resume()
        readyContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        readyContinuation?.resume()
        readyContinuation = nil
    }
}

extension MarkdownRenderer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "layoutChanged" else { return }
        onLayoutChanged?()
    }
}

/// WKUserContentController retains its message handlers; this wrapper keeps the
/// renderer weakly referenced so the handler doesn't create a retain cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Serves a markdown document's local assets (images, etc.) from the document's
/// own folder via a custom `mdasset://` scheme. We read the file in Swift and
/// return the bytes, which sidesteps WKWebView's file-access scoping (the page
/// itself is loaded from the app bundle, so relative file URLs can't reach the
/// document folder).
final class LocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    var baseDirectory: URL?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let base = baseDirectory else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        var relative = url.path
        if relative.hasPrefix("/") { relative.removeFirst() }
        relative = relative.removingPercentEncoding ?? relative

        let fileURL = base.appendingPathComponent(relative).standardizedFileURL
        // Never let a path escape the document's folder. Compare with a
        // trailing separator so a sibling like "notes-private" can't pass a
        // plain string-prefix check against base "notes".
        let basePath = base.standardizedFileURL.path
        guard fileURL.path == basePath || fileURL.path.hasPrefix(basePath + "/"),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let response = URLResponse(url: url,
                                   mimeType: Self.mimeType(forExtension: fileURL.pathExtension),
                                   expectedContentLength: data.count,
                                   textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
