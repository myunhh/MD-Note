import UIKit
import WebKit
import MDNoteCore

/// Wraps a WKWebView that renders markdown via the bundled web assets and
/// exposes the per-block geometry needed to anchor ink.
@MainActor
final class MarkdownRenderer: NSObject {
    let webView: WKWebView
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var didLoadAssets = false

    /// Total page width the web layer lays out at (must match theme.css / bridge.js):
    /// a 1080pt text column on the left + a blank right writing margin = 1390pt.
    let pageWidth: CGFloat = 1390

    override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
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
        _ = try? await webView.evaluateJavaScript("MDNote.setPaper('\(style)')")
    }

    func contentHeight() async -> CGFloat {
        let any = (try? await webView.evaluateJavaScript("MDNote.contentHeight()")) ?? nil
        if let n = any as? NSNumber { return CGFloat(truncating: n) }
        return 1000
    }

    /// Per-block geometry in document coordinates, after layout.
    func blocks() async -> [Block] {
        let any = (try? await webView.evaluateJavaScript("JSON.stringify(MDNote.layout())")) ?? nil
        guard let json = any as? String, let data = json.data(using: .utf8) else { return [] }
        guard let dtos = try? JSONDecoder().decode([BlockGeometryDTO].self, from: data) else { return [] }
        return dtos.map(\.block)
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
