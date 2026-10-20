import XCTest
import PencilKit
import MDNoteCore
@testable import MDNote

@MainActor
final class NativeInkTests: XCTestCase {
    private func temporaryNote() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("note.md")
        try Data("Hello world".utf8).write(to: url)
        return url
    }

    private func block(y: CGFloat = 100, id: String = "paragraph", text: String = "Hello world") -> Block {
        Block(hash: Hashing.blockHash(text), seq: 0,
              frame: CGRect(x: 20, y: y, width: 400, height: 90), text: text, blockID: id)
    }

    private func stroke(x: CGFloat = 30, y: CGFloat = 130) -> PKStroke {
        let points = [CGPoint(x: x, y: y), CGPoint(x: x + 70, y: y + 3)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1,
                          force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
                        path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 100)))
    }

    func testCoordinatedSaveRejectsExternalChangeWithoutOverwriting() throws {
        let url = try temporaryNote()
        try MarkdownFileWriter.write("Local first", to: url, expectedText: "Hello world")
        XCTAssertEqual(try MarkdownFileWriter.read(url), "Local first")
        try Data("External revision".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try MarkdownFileWriter.write("Stale local edit", to: url, expectedText: "Local first"))
        XCTAssertEqual(try MarkdownFileWriter.read(url), "External revision")
    }

    func testInvalidUTF8IsNeverReplacedByPlaceholder() throws {
        let url = try temporaryNote()
        let original = Data([0xff, 0xfe, 0xff])
        try original.write(to: url)
        XCTAssertThrowsError(try MarkdownFileWriter.read(url))
        XCTAssertThrowsError(try MarkdownFileWriter.write("replacement", to: url, expectedText: ""))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testRigidReflowAndRecapturePreserveIdentityAndOriginalBytes() throws {
        let store = InkStore(documentURL: try temporaryNote())
        store.capture(drawing: PKDrawing(strokes: [stroke()]), blocks: [block()])
        let saved = try XCTUnwrap(store.ink.first)
        let movedBlock = block(y: 300)
        for _ in 0..<20 {
            let displayed = store.rebuildDrawing(blocks: [movedBlock])
            store.capture(drawing: displayed, blocks: [movedBlock])
            XCTAssertEqual(store.ink.first?.id, saved.id)
            XCTAssertEqual(store.ink.first?.strokeData, saved.strokeData)
            XCTAssertEqual(displayed.bounds.minY, CGFloat(130 + 200) - 1.5, accuracy: 5)
        }
    }

    func testUnderlineFragmentsNeverReplaceOriginalInk() throws {
        let store = InkStore(documentURL: try temporaryNote())
        store.captureBehavior = .underline
        store.captureAnchor = TextAnchor.capture(blockID: "paragraph", text: "Hello world", startUTF16: 0, endUTF16: 5)
        store.capture(drawing: PKDrawing(strokes: [stroke()]), blocks: [block()])
        let saved = try XCTUnwrap(store.ink.first)
        store.rangeRects[saved.id] = [
            CGRect(x: 20, y: 100, width: 120, height: 22),
            CGRect(x: 20, y: 125, width: 60, height: 22)
        ]
        for _ in 0..<20 {
            let displayed = store.rebuildDrawing(blocks: [block()])
            XCTAssertEqual(displayed.strokes.count, 2)
            store.capture(drawing: displayed, blocks: [block()])
            XCTAssertEqual(store.ink.count, 1)
            XCTAssertEqual(store.ink.first?.id, saved.id)
            XCTAssertEqual(store.ink.first?.strokeData, saved.strokeData)
        }
    }

    func testErasingOneRigidStrokeDoesNotResurrectItOnReflow() throws {
        let store = InkStore(documentURL: try temporaryNote())
        store.capture(drawing: PKDrawing(strokes: [stroke(), stroke(x: 150)]), blocks: [block()])
        let displayed = store.rebuildDrawing(blocks: [block()])
        store.capture(drawing: PKDrawing(strokes: [displayed.strokes[1]]), blocks: [block()])
        let moved = store.rebuildDrawing(blocks: [block(y: 300)])
        XCTAssertEqual(moved.strokes.count, 1)
        store.capture(drawing: moved, blocks: [block(y: 300)])
        XCTAssertEqual(store.rebuildDrawing(blocks: [block(y: 400)]).strokes.count, 1)
        store.capture(drawing: displayed, blocks: [block()])
        XCTAssertEqual(store.rebuildDrawing(blocks: [block()]).strokes.count, 2)
    }

    func testDeleteMarkedRangeThenRestoreUndoAttachment() throws {
        let store = InkStore(documentURL: try temporaryNote())
        store.captureBehavior = .underline
        store.captureAnchor = TextAnchor.capture(blockID: "paragraph", text: "Hello world", startUTF16: 0, endUTF16: 5)
        store.capture(drawing: PKDrawing(strokes: [stroke()]), blocks: [block()])
        let original = try XCTUnwrap(store.ink.first)
        let before = store.attachments()
        store.applyTextReplacement(blockID: "paragraph", start: 0, end: 5, replacement: "",
                                   oldText: "Hello world", blocks: [block()])
        XCTAssertTrue(store.ink.isEmpty)
        XCTAssertEqual(store.orphans.first?.strokeData, original.strokeData)
        store.restoreAttachments(before)
        XCTAssertTrue(store.orphans.isEmpty)
        XCTAssertEqual(store.ink.first?.anchor, original.anchor)
        XCTAssertEqual(store.ink.first?.strokeData, original.strokeData)
    }

    func testTypingInsideMarkedRangeUpdatesTrustedAnchor() throws {
        let store = InkStore(documentURL: try temporaryNote())
        store.captureBehavior = .underline
        store.captureAnchor = TextAnchor.capture(blockID: "paragraph", text: "Hello world", startUTF16: 0, endUTF16: 5)
        store.capture(drawing: PKDrawing(strokes: [stroke()]), blocks: [block()])
        let bytes = store.ink.first?.strokeData
        store.applyTextReplacement(blockID: "paragraph", start: 2, end: 2, replacement: "한",
                                   oldText: "Hello world", blocks: [block()])
        XCTAssertEqual(store.ink.first?.anchor?.quote, "He한llo")
        XCTAssertEqual(store.ink.first?.anchor?.endUTF16, 6)
        XCTAssertEqual(store.ink.first?.strokeData, bytes)
    }

    func testInkedStudyRemovalAndUndoPreservePayload() throws {
        let store = InkStore(documentURL: try temporaryNote())
        let insertion = StudyInsertion(id: "study", afterBlockID: "paragraph", height: 200)
        store.studyInsertions = [insertion]
        let study = block(y: 200, id: "study", text: "")
        store.capture(drawing: PKDrawing(strokes: [stroke(y: 220)]), blocks: [study])
        let original = try XCTUnwrap(store.ink.first)
        store.studyInsertions = []
        store.applyExternalEdit(oldBlocks: [study], newBlocks: [block()])
        XCTAssertTrue(store.ink.isEmpty)
        XCTAssertEqual(store.orphans.first?.strokeData, original.strokeData)
        store.studyInsertions = [insertion]
        store.restoreStudyTargets(in: [block(), study])
        XCTAssertTrue(store.orphans.isEmpty)
        XCTAssertEqual(store.ink.first?.id, original.id)
        XCTAssertEqual(store.ink.first?.strokeData, original.strokeData)
    }

    func testStudyAndOriginalInkSurviveSidecarAndArchiveRoundTrip() throws {
        let url = try temporaryNote()
        let store = InkStore(documentURL: url)
        store.studyInsertions = [StudyInsertion(id: "study", afterBlockID: "paragraph",
                                               kind: .markdown, markdown: "![study](study.png)", height: 180)]
        store.capture(drawing: PKDrawing(strokes: [stroke()]), blocks: [block()])
        XCTAssertTrue(store.save(blocks: [block()], documentText: "Hello world"))
        try Data("image bytes".utf8).write(to: url.deletingLastPathComponent().appendingPathComponent("study.png"))
        let zip = try NoteArchive.export(note: url, noteData: Data("Hello world".utf8), imageSources: ["study.png"])
        defer { try? FileManager.default.removeItem(at: zip.deletingLastPathComponent()) }
        let imported = try NoteArchive.importZIP(zip, into: url.deletingLastPathComponent())
        let restored = InkStore(documentURL: imported.appendingPathComponent("note.md"))
        XCTAssertNotNil(restored.load())
        XCTAssertEqual(restored.studyInsertions, store.studyInsertions)
        XCTAssertEqual(restored.ink, store.ink)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.appendingPathComponent("study.png").path))
    }

    func testFutureSidecarIsReadOnlyAndBytePreserved() throws {
        let url = try temporaryNote()
        let bytes = Data("{\"version\":999}".utf8)
        try bytes.write(to: url.appendingPathExtension("inknote"))
        let store = InkStore(documentURL: url)
        XCTAssertNil(store.load())
        XCTAssertTrue(store.isReadOnly)
        store.capture(drawing: PKDrawing(strokes: [stroke()]), blocks: [block()])
        XCTAssertTrue(store.ink.isEmpty)
        XCTAssertTrue(store.save(blocks: [block()], documentText: "Hello world"))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("inknote")), bytes)
    }
}
