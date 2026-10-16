import XCTest
import Foundation
@testable import MDNoteCore

final class TrashRepositoryTests: XCTestCase {
    private var root: URL!
    private let files = FileManager.default

    override func setUpWithError() throws {
        root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try files.removeItem(at: root) }

    private func write(_ path: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testNoteAndCompanionsRoundTripWithMetadataAcrossRepositoryReload() throws {
        let note = try write("class/lecture.md", "# Lecture")
        _ = try write("class/lecture.md.inknote", "ink bytes")
        _ = try write("class/lecture.md.bookmarks", "bookmark bytes")
        let metadata = Data("saved preferences".utf8)
        let entry = try TrashRepository(root: root).discard(note, metadata: metadata)
        XCTAssertFalse(files.fileExists(atPath: note.path))
        XCTAssertFalse(files.fileExists(atPath: note.appendingPathExtension("inknote").path))
        let repository = TrashRepository(root: root)
        XCTAssertEqual(try repository.entries(), [entry])
        XCTAssertEqual(entry.metadata, metadata)
        XCTAssertEqual(entry.originalPath, "class/lecture.md")
        XCTAssertEqual(try repository.restore(entry), note)
        XCTAssertEqual(try text(note), "# Lecture")
        XCTAssertEqual(try text(note.appendingPathExtension("inknote")), "ink bytes")
        XCTAssertEqual(try text(note.appendingPathExtension("bookmarks")), "bookmark bytes")
        XCTAssertTrue(try repository.entries().isEmpty)
    }

    func testFolderKeepsNestedImagesAndCompanions() throws {
        _ = try write("course/sub/note.md", "![image](../images/a.png)")
        _ = try write("course/images/a.png", "image bytes")
        _ = try write("course/sub/note.md.bookmarks", "bookmarks")
        let repository = TrashRepository(root: root)
        let entry = try repository.discard(root.appendingPathComponent("course"))
        XCTAssertTrue(entry.isDirectory)
        _ = try repository.restore(entry)
        XCTAssertEqual(try text(root.appendingPathComponent("course/images/a.png")), "image bytes")
        XCTAssertEqual(try text(root.appendingPathComponent("course/sub/note.md.bookmarks")), "bookmarks")
    }

    func testCollisionReservesOrphanCompanionsAndNeverOverwrites() throws {
        let original = try write("note.md", "deleted note")
        _ = try write("note.md.inknote", "deleted ink")
        _ = try write("note.md.bookmarks", "deleted bookmarks")
        let repository = TrashRepository(root: root)
        let entry = try repository.discard(original)
        _ = try write("note.md", "new note")
        _ = try write("note 2.md.bookmarks", "orphan")
        let restored = try repository.restore(entry)
        XCTAssertEqual(restored.lastPathComponent, "note 3.md")
        XCTAssertEqual(try text(original), "new note")
        XCTAssertEqual(try text(root.appendingPathComponent("note 2.md.bookmarks")), "orphan")
        XCTAssertEqual(try text(restored.appendingPathExtension("inknote")), "deleted ink")
        XCTAssertEqual(try text(restored.appendingPathExtension("bookmarks")), "deleted bookmarks")
    }

    func testMissingParentRequiresExplicitRootRestore() throws {
        let note = try write("old/note.txt", "note")
        let repository = TrashRepository(root: root)
        let entry = try repository.discard(note)
        try files.removeItem(at: root.appendingPathComponent("old"))
        XCTAssertThrowsError(try repository.restore(entry)) { XCTAssertEqual($0 as? TrashError, .missingParent) }
        XCTAssertEqual(try repository.entries(), [entry])
        XCTAssertEqual(try repository.restore(entry, toLibraryRoot: true), root.appendingPathComponent("note.txt"))
    }

    func testFailedCompanionMoveRollsBackNote() throws {
        let note = try write("note.md", "note")
        let ink = try write("note.md.inknote", "ink")
        let repository = TrashRepository(root: root, move: { [files] source, destination in
            if source == ink { throw CocoaError(.fileWriteNoPermission) }
            try files.moveItem(at: source, to: destination)
        })
        XCTAssertThrowsError(try repository.discard(note))
        XCTAssertEqual(try text(note), "note")
        XCTAssertEqual(try text(ink), "ink")
        XCTAssertTrue(try repository.entries().isEmpty)
    }

    func testFailedRestoreRollsBackToTrash() throws {
        let note = try write("note.md", "note")
        _ = try write("note.md.bookmarks", "bookmarks")
        let entry = try TrashRepository(root: root).discard(note)
        let repository = TrashRepository(root: root, move: { [files] source, destination in
            if destination == note.appendingPathExtension("bookmarks") { throw CocoaError(.fileWriteNoPermission) }
            try files.moveItem(at: source, to: destination)
        })
        XCTAssertThrowsError(try repository.restore(entry))
        XCTAssertFalse(files.fileExists(atPath: note.path))
        XCTAssertEqual(try repository.entries(), [entry])
        XCTAssertEqual(try TrashRepository(root: root).restore(entry), note)
    }

    func testRollbackFailureRetainsRecoveryPayload() throws {
        let note = try write("note.md", "note")
        let ink = try write("note.md.inknote", "ink")
        let repository = TrashRepository(root: root, move: { [files] source, destination in
            if source == ink || destination == note { throw CocoaError(.fileWriteNoPermission) }
            try files.moveItem(at: source, to: destination)
        })
        XCTAssertThrowsError(try repository.discard(note)) { XCTAssertEqual($0 as? TrashError, .rollbackFailed) }
        let entry = try XCTUnwrap(repository.entries().first)
        XCTAssertEqual(try text(root.appendingPathComponent(".Trash/\(entry.id.uuidString)/payload/note.md")), "note")
        XCTAssertEqual(try text(ink), "ink")
    }

    func testPermanentDeletionRemovesOnlySelectedEntry() throws {
        let repository = TrashRepository(root: root)
        let first = try repository.discard(write("first.md", "first"))
        let second = try repository.discard(write("second.md", "second"))
        try repository.permanentlyDelete(first)
        XCTAssertEqual(try repository.entries(), [second])
        XCTAssertFalse(files.fileExists(atPath: root.appendingPathComponent(".Trash/\(first.id.uuidString)").path))
    }

    func testRejectsOutsideRoot() throws {
        XCTAssertThrowsError(try TrashRepository(root: root).discard(root.deletingLastPathComponent())) {
            XCTAssertEqual($0 as? TrashError, .invalidPath)
        }
    }

    func testRejectsSymlinkedTrashDirectory() throws {
        _ = try write("kept.md", "keep")
        try files.createSymbolicLink(at: root.appendingPathComponent(".Trash"), withDestinationURL: root)
        XCTAssertThrowsError(try TrashRepository(root: root).discard(root.appendingPathComponent("kept.md"))) {
            XCTAssertEqual($0 as? TrashError, .invalidPath)
        }
        XCTAssertEqual(try text(root.appendingPathComponent("kept.md")), "keep")
    }

    func testCorruptManifestReportsErrorWithoutDeletingPayload() throws {
        let repository = TrashRepository(root: root)
        let entry = try repository.discard(write("kept.md", "keep"))
        _ = try write(".Trash/\(entry.id.uuidString)/manifest.json", "invalid json")
        XCTAssertThrowsError(try repository.entries())
        XCTAssertThrowsError(try repository.permanentlyDelete(entry))
        XCTAssertEqual(try text(root.appendingPathComponent(".Trash/\(entry.id.uuidString)/payload/kept.md")), "keep")
    }

    func testFolderNamedManifestDoesNotCollideWithRecoveryManifest() throws {
        _ = try write("manifest.json/note.md", "keep")
        let repository = TrashRepository(root: root)
        let entry = try repository.discard(root.appendingPathComponent("manifest.json"))
        _ = try repository.restore(entry)
        XCTAssertEqual(try text(root.appendingPathComponent("manifest.json/note.md")), "keep")
    }

    func testRestoreDoesNotDeleteUnexpectedRecoveryFiles() throws {
        let repository = TrashRepository(root: root)
        let entry = try repository.discard(write("kept.md", "keep"))
        let extra = try write(".Trash/\(entry.id.uuidString)/payload/extra.md", "extra")
        XCTAssertThrowsError(try repository.restore(entry)) { XCTAssertEqual($0 as? TrashError, .invalidEntry) }
        XCTAssertEqual(try text(extra), "extra")
        XCTAssertEqual(try repository.entries(), [entry])
    }
}
