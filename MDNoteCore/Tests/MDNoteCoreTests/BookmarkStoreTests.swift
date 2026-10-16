import XCTest
import Foundation
import CoreGraphics
@testable import MDNoteCore

final class BookmarkStoreTests: XCTestCase {
    private func withDocument(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Note.md")
        try Data("# Heading".utf8).write(to: url)
        try body(url)
    }

    func testMultipleBookmarksRenameDeleteAndReopen() throws {
        try withDocument { url in
            let store = try BookmarkStore(documentURL: url)
            let first = DocumentBookmark(name: "One", y: 20, height: 200, blocks: [])
            var second = DocumentBookmark(name: "Two", y: 100, height: 200, blocks: [])
            try store.replace(with: [first, second])
            XCTAssertEqual(try BookmarkStore(documentURL: url).bookmarks, [first, second])
            second.name = "Renamed"
            try store.replace(with: [second])
            XCTAssertEqual(try BookmarkStore(documentURL: url).bookmarks, [second])
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("inknote").path))
        }
    }

    func testStableAnchorFollowsReflowAndDuplicateSequence() {
        let blocks = [Block(hash: "same", seq: 0, frame: CGRect(x: 0, y: 10, width: 200, height: 40)),
                      Block(hash: "same", seq: 1, frame: CGRect(x: 0, y: 100, width: 200, height: 40))]
        let bookmark = DocumentBookmark(name: "Second", y: 112, height: 200, blocks: blocks)
        var reflowed = blocks
        reflowed[1].frame.origin.y = 400
        let result = bookmark.resolve(in: reflowed, height: 600)
        XCTAssertEqual(result.y, 412)
        XCTAssertFalse(result.usedFallback)
        let fallback = bookmark.resolve(in: [], height: 1000)
        XCTAssertEqual(fallback.y, 560, accuracy: 0.001)
        XCTAssertTrue(fallback.usedFallback)
        XCTAssertEqual(bookmark.resolve(in: [], height: 0).y, 112)
    }

    func testCorruptAndNewerFilesArePreserved() throws {
        try withDocument { url in
            let sidecar = url.appendingPathExtension("bookmarks")
            for bytes in [Data("broken".utf8), Data("{\"version\":2,\"bookmarks\":[]}".utf8)] {
                try bytes.write(to: sidecar)
                XCTAssertThrowsError(try BookmarkStore(documentURL: url))
                XCTAssertEqual(try Data(contentsOf: sidecar), bytes)
            }
        }
    }

    func testExternalReplacementOrDeletionCannotBeOverwritten() throws {
        try withDocument { url in
            let store = try BookmarkStore(documentURL: url)
            let bookmark = DocumentBookmark(name: "Saved", y: 10, height: 100, blocks: [])
            try store.replace(with: [bookmark])
            let foreign = Data("external edit".utf8)
            try foreign.write(to: store.sidecarURL)
            XCTAssertThrowsError(try store.replace(with: []))
            XCTAssertEqual(try Data(contentsOf: store.sidecarURL), foreign)
            XCTAssertEqual(store.bookmarks, [bookmark])
            try FileManager.default.removeItem(at: store.sidecarURL)
            XCTAssertThrowsError(try store.replace(with: []))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.sidecarURL.path))
        }
    }

    func testDocumentAndFolderRelocationPreserveBytes() throws {
        try withDocument { url in
            let store = try BookmarkStore(documentURL: url)
            try store.replace(with: [DocumentBookmark(name: "Keep", y: 10, height: 100, blocks: [])])
            let bytes = try Data(contentsOf: store.sidecarURL)
            let renamed = url.deletingLastPathComponent().appendingPathComponent("Renamed.md")
            try FileManager.default.moveItem(at: url, to: renamed)
            try store.relocate(to: renamed)
            XCTAssertEqual(try Data(contentsOf: store.sidecarURL), bytes)
            let folder = url.deletingLastPathComponent().appendingPathComponent("Folder")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let moved = folder.appendingPathComponent(renamed.lastPathComponent)
            try FileManager.default.moveItem(at: renamed, to: moved)
            try FileManager.default.moveItem(at: store.sidecarURL, to: moved.appendingPathExtension("bookmarks"))
            try store.relocate(to: moved)
            XCTAssertEqual(try BookmarkStore(documentURL: moved).bookmarks, store.bookmarks)
        }
    }

    func testRelocationCollisionPreservesBothFiles() throws {
        try withDocument { url in
            let store = try BookmarkStore(documentURL: url)
            try store.replace(with: [DocumentBookmark(name: "Keep", y: 10, height: 100, blocks: [])])
            let oldBytes = try Data(contentsOf: store.sidecarURL)
            let destination = url.deletingLastPathComponent().appendingPathComponent("Other.md")
            let foreign = Data("other bookmarks".utf8)
            try foreign.write(to: destination.appendingPathExtension("bookmarks"))
            XCTAssertThrowsError(try store.relocate(to: destination))
            XCTAssertEqual(store.documentURL, url)
            XCTAssertEqual(try Data(contentsOf: store.sidecarURL), oldBytes)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathExtension("bookmarks")), foreign)
        }
    }

    func testCompetingWriterCannotOverwriteFirstSave() throws {
        try withDocument { url in
            let first = try BookmarkStore(documentURL: url)
            let second = try BookmarkStore(documentURL: url)
            let bookmark = DocumentBookmark(name: "First", y: 10, height: 100, blocks: [])
            try first.replace(with: [bookmark])
            XCTAssertThrowsError(try second.replace(with: []))
            XCTAssertEqual(try BookmarkStore(documentURL: url).bookmarks, [bookmark])
        }
    }

    func testInvalidValuesDoNotReplaceSavedBytes() throws {
        try withDocument { url in
            let store = try BookmarkStore(documentURL: url)
            var bookmark = DocumentBookmark(name: "Valid", y: 10, height: 100, blocks: [])
            try store.replace(with: [bookmark])
            let bytes = try Data(contentsOf: store.sidecarURL)
            bookmark.fraction = .infinity
            XCTAssertThrowsError(try store.replace(with: [bookmark]))
            XCTAssertEqual(try Data(contentsOf: store.sidecarURL), bytes)
        }
    }
}
