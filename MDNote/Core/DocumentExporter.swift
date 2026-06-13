import UIKit
import PDFKit
import PencilKit
import WebKit

/// Exports the current document (rendered markdown + handwriting) as a PDF.
///
/// The output is sliced into A-series-ratio pages; each page composites its
/// slice of the ink drawing on top of the rendered text. Short documents capture
/// the whole web layer as one tall vector page (crisper, one call); documents
/// past the PDF page-dimension ceiling capture the web layer per output page and
/// assemble with PDFKit, so a long single-scroll note isn't silently truncated.
@MainActor
enum DocumentExporter {

    enum ExportError: Error {
        case webRenderFailed
    }

    /// PDF page dimensions are capped (~200in / 14400pt). WKWebView.pdf() clips a
    /// taller rect, which would blank the text layer on long notes.
    private static let pdfCeiling: CGFloat = 14_400
    private static let paperColor = UIColor(red: 251/255, green: 250/255, blue: 247/255, alpha: 1)

    static func exportPDF(
        webView: WKWebView,
        drawing: PKDrawing,
        pageWidth: CGFloat,
        contentHeight: CGFloat,
        title: String
    ) async throws -> URL {
        let pageHeight = (pageWidth * 2.0.squareRoot()).rounded()   // A-series ratio
        let pageBounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        // Ink can extend below the web layer (the user can write in the bottom
        // writing margin past the last block), so size the export to cover it.
        let inkMaxY = drawing.bounds.isNull ? 0 : drawing.bounds.maxY
        let exportHeight = max(contentHeight, inkMaxY)
        // Cap pages so a single stray far-down stroke can't balloon the PDF.
        let pageCount = max(1, min(Int(ceil(exportHeight / pageHeight)), 500))

        // Drop the on-screen paper ruling/grid/divider so the shared PDF is clean
        // white-ish paper. Restore on EVERY exit (pdf() can throw).
        _ = try? await webView.evaluateJavaScript("document.body.classList.add('exporting')")
        defer {
            Task { @MainActor in
                _ = try? await webView.evaluateJavaScript("document.body.classList.remove('exporting')")
            }
        }

        if contentHeight <= pdfCeiling {
            return try await exportSingleCapture(
                webView: webView, drawing: drawing, pageWidth: pageWidth,
                contentHeight: contentHeight, pageBounds: pageBounds,
                pageHeight: pageHeight, pageCount: pageCount, title: title)
        } else {
            return try await exportPerSlice(
                webView: webView, drawing: drawing, pageWidth: pageWidth,
                contentHeight: contentHeight, pageBounds: pageBounds,
                pageHeight: pageHeight, pageCount: pageCount, title: title)
        }
    }

    // MARK: Fast path — one tall vector capture, sliced into pages

    private static func exportSingleCapture(
        webView: WKWebView, drawing: PKDrawing, pageWidth: CGFloat,
        contentHeight: CGFloat, pageBounds: CGRect, pageHeight: CGFloat,
        pageCount: Int, title: String
    ) async throws -> URL {
        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: pageWidth, height: contentHeight)
        let webData = try await webView.pdf(configuration: config)
        guard let webPage = PDFDocument(data: webData)?.page(at: 0) else {
            throw ExportError.webRenderFailed
        }

        let data = UIGraphicsPDFRenderer(bounds: pageBounds).pdfData { context in
            for pageIndex in 0..<pageCount {
                context.beginPage()
                let sliceTop = CGFloat(pageIndex) * pageHeight
                let cg = context.cgContext
                autoreleasepool {
                    cg.setFillColor(paperColor.cgColor)
                    cg.fill(pageBounds)
                    // Web layer: draw the tall page shifted so this slice shows.
                    // PDF pages draw in bottom-left-origin space, so flip first.
                    cg.saveGState()
                    cg.translateBy(x: 0, y: pageBounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    cg.translateBy(x: 0, y: -(contentHeight - sliceTop - pageHeight))
                    webPage.draw(with: .mediaBox, to: cg)
                    cg.restoreGState()
                    compositeInk(drawing, pageBounds: pageBounds, pageWidth: pageWidth,
                                 sliceTop: sliceTop, pageHeight: pageHeight)
                }
            }
        }
        return try write(data, title: title)
    }

    // MARK: Long path — capture the web layer per page, assemble with PDFKit

    private static func exportPerSlice(
        webView: WKWebView, drawing: PKDrawing, pageWidth: CGFloat,
        contentHeight: CGFloat, pageBounds: CGRect, pageHeight: CGFloat,
        pageCount: Int, title: String
    ) async throws -> URL {
        let out = PDFDocument()
        for pageIndex in 0..<pageCount {
            let sliceTop = CGFloat(pageIndex) * pageHeight

            // Capture only this page's slice of the web layer (well under the
            // ceiling). Skip pages that are entirely below the web content
            // (trailing-ink-only pages) — they need no web capture.
            var slicePage: PDFPage?
            if sliceTop < contentHeight {
                let cfg = WKPDFConfiguration()
                cfg.rect = CGRect(x: 0, y: sliceTop, width: pageWidth, height: pageHeight)
                let sliceData = try await webView.pdf(configuration: cfg)
                slicePage = PDFDocument(data: sliceData)?.page(at: 0)
            }

            // Drain the per-page transients (a ~5500×2780px ink UIImage, two
            // PDFDocuments, the page Data) every iteration — across up to 500
            // pages they'd otherwise pile up with no autorelease drain point.
            try autoreleasepool {
                let pageData = UIGraphicsPDFRenderer(bounds: pageBounds).pdfData { context in
                    context.beginPage()
                    let cg = context.cgContext
                    cg.setFillColor(paperColor.cgColor)
                    cg.fill(pageBounds)
                    if let slicePage {
                        // The slice page is exactly pageHeight tall, so only the
                        // bottom-left flip is needed (no extra vertical translate).
                        cg.saveGState()
                        cg.translateBy(x: 0, y: pageBounds.height)
                        cg.scaleBy(x: 1, y: -1)
                        slicePage.draw(with: .mediaBox, to: cg)
                        cg.restoreGState()
                    }
                    compositeInk(drawing, pageBounds: pageBounds, pageWidth: pageWidth,
                                 sliceTop: sliceTop, pageHeight: pageHeight)
                }
                // A page that fails to re-parse must abort the export, not be
                // silently dropped (which would ship a PDF missing a middle page).
                guard let page = PDFDocument(data: pageData)?.page(at: 0) else {
                    throw ExportError.webRenderFailed
                }
                out.insert(page, at: out.pageCount)
            }
        }
        guard let data = out.dataRepresentation() else { throw ExportError.webRenderFailed }
        return try write(data, title: title)
    }

    // MARK: Helpers

    /// Rasterize and draw only this page's slice of the ink, bounded so long
    /// documents don't rasterize the whole drawing per page.
    private static func compositeInk(_ drawing: PKDrawing, pageBounds: CGRect,
                                     pageWidth: CGFloat, sliceTop: CGFloat, pageHeight: CGFloat) {
        let sliceRect = CGRect(x: 0, y: sliceTop, width: pageWidth, height: pageHeight)
        let inkBounds = drawing.bounds
        guard !inkBounds.isNull, !inkBounds.isEmpty, inkBounds.intersects(sliceRect) else { return }
        drawing.image(from: sliceRect, scale: 2).draw(in: pageBounds)
    }

    /// Write the PDF to a temp file with a defensively normalized name (no
    /// dotfile/overlong/control-char/path-confusing stems).
    private static func write(_ data: Data, title: String) throws -> URL {
        var safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        safe = safe.components(separatedBy: .controlCharacters).joined()
        safe = safe.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if safe.isEmpty { safe = "Note" }
        if safe.count > 120 { safe = String(safe.prefix(120)) }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe).appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: fileURL)
        try data.write(to: fileURL)
        return fileURL
    }
}
