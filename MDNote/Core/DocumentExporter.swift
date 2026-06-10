import UIKit
import PDFKit
import PencilKit
import WebKit

/// Exports the current document (rendered markdown + handwriting) as a PDF.
///
/// The web layer is captured once as a single tall vector PDF page, then sliced
/// into A-series-ratio output pages; each page composites its slice of the ink
/// drawing on top. Slicing per page keeps the rasterized ink memory bounded on
/// long documents.
@MainActor
enum DocumentExporter {

    enum ExportError: Error {
        case webRenderFailed
    }

    static func exportPDF(
        webView: WKWebView,
        drawing: PKDrawing,
        pageWidth: CGFloat,
        contentHeight: CGFloat,
        title: String
    ) async throws -> URL {
        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: pageWidth, height: contentHeight)
        let webData = try await webView.pdf(configuration: config)
        guard let webDocument = PDFDocument(data: webData),
              let webPage = webDocument.page(at: 0) else {
            throw ExportError.webRenderFailed
        }

        let pageHeight = (pageWidth * 2.0.squareRoot()).rounded()   // A-series ratio
        let pageCount = max(1, Int(ceil(contentHeight / pageHeight)))
        let pageBounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            for pageIndex in 0..<pageCount {
                context.beginPage()
                let sliceTop = CGFloat(pageIndex) * pageHeight
                let cg = context.cgContext

                autoreleasepool {
                    // Background paper, in case the web render leaves margins.
                    cg.setFillColor(UIColor(red: 251/255, green: 250/255, blue: 247/255, alpha: 1).cgColor)
                    cg.fill(pageBounds)

                    // Web layer: draw the tall page shifted so this slice shows.
                    // PDF pages draw in bottom-left-origin space, so flip first.
                    cg.saveGState()
                    cg.translateBy(x: 0, y: pageBounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    cg.translateBy(x: 0, y: -(contentHeight - sliceTop - pageHeight))
                    webPage.draw(with: .mediaBox, to: cg)
                    cg.restoreGState()

                    // Ink layer: rasterize only this page's slice.
                    let sliceRect = CGRect(x: 0, y: sliceTop, width: pageWidth, height: pageHeight)
                    let inkBounds = drawing.bounds
                    if !inkBounds.isNull, !inkBounds.isEmpty, inkBounds.intersects(sliceRect) {
                        drawing.image(from: sliceRect, scale: 2).draw(in: pageBounds)
                    }
                }
            }
        }

        let safeTitle = title.replacingOccurrences(of: "/", with: "-")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeTitle.isEmpty ? "Note" : safeTitle)
            .appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: fileURL)
        try data.write(to: fileURL)
        return fileURL
    }
}
