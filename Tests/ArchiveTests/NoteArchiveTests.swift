import XCTest
import ZIPFoundation
@testable import MDNote

final class NoteArchiveTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func write(_ path: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func zip(_ entries: [(String, Data, Entry.EntryType)]) throws -> URL {
        let url = root.appendingPathComponent("input.zip")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, bytes, type) in entries {
            try archive.addEntry(with: path, type: type, uncompressedSize: Int64(bytes.count)) { position, size in
                bytes.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        return url
    }

    private func export(_ note: URL, imageSources: [String]) throws -> URL {
        let data = try NoteArchive.readNote(note)
        return try NoteArchive.export(note: note, noteData: data, imageSources: imageSources)
    }

    func testRoundTripIncludesOnlyReferencedImagesAndCompanions() throws {
        let note = try write("original/note.md", "![inline](images/a%20b.png)\n![ref][photo]\n[photo]: <images/c d.png>\n![remote](https://example.com/image.png)\n[unused]: private.png")
        let ink = try write("original/note.md.inknote", "opaque ink")
        let bookmarks = try write("original/note.md.bookmarks", "opaque bookmarks")
        _ = try write("original/images/a b.png", "image one")
        _ = try write("original/images/c d.png", "image two")
        _ = try write("original/private.png", "private unrelated data")
        let exported = try export(note, imageSources: ["images/a%20b.png", "images/c%20d.png", "https://example.com/image.png"])
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        let archive = try Archive(url: exported, accessMode: .read)
        XCTAssertEqual(Set(archive.map(\.path)), ["note.md", "note.md.inknote", "note.md.bookmarks", "images/a b.png", "images/c d.png", NoteArchive.manifestPath])
        let imported = try NoteArchive.importZIP(exported, into: root)
        for source in [note, ink, bookmarks] {
            XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: imported.appendingPathComponent(source.lastPathComponent)))
        }
        XCTAssertEqual(try String(contentsOf: imported.appendingPathComponent("images/a b.png")), "image one")
        let second = try NoteArchive.importZIP(exported, into: root)
        XCTAssertNotEqual(imported, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.appendingPathComponent("note.md").path))
    }

    func testPathPolicy() throws {
        for path in ["../secret", "/absolute", "C:/secret", "a\\b", "a/../b", "a//b", ".hidden", "a/./b", "x\u{0}y"] {
            XCTAssertThrowsError(try NoteArchive.validatedPath(path), path)
        }
        XCTAssertEqual(try NoteArchive.localImagePath("./images/a%20b.png#preview"), "images/a b.png")
        XCTAssertEqual(try NoteArchive.localImagePath("images/a b.png"), "images/a b.png")
        XCTAssertThrowsError(try NoteArchive.localImagePath("%2e%2e/private.png"))
        XCTAssertNil(try NoteArchive.localImagePath("https://example.com/a.png"))
        XCTAssertThrowsError(try NoteArchive.localImagePath("file:///private/image.png"))
    }

    func testRejectsParentRelativeAndSymlinkExport() throws {
        let note = try write("note.md", "![secret](../secret.png)")
        XCTAssertThrowsError(try export(note, imageSources: ["../secret.png"]))
        try "![secret](link.png)".write(to: note, atomically: true, encoding: .utf8)
        let secret = try write("secret.png", "private")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: secret)
        XCTAssertThrowsError(try export(note, imageSources: ["link.png"]))
    }

    func testRejectsTraversalAndSymlinkZIPBeforePublishing() throws {
        for (path, type) in [("../outside.md", Entry.EntryType.file), ("/absolute.md", .file), ("link.md", .symlink)] {
            let source = try zip([(path, Data("note".utf8), type)])
            XCTAssertThrowsError(try NoteArchive.importZIP(source, into: root))
            try FileManager.default.removeItem(at: source)
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".archive-import-") })
    }

    func testRejectsCaseCollisionAndFileParentCollision() throws {
        for names in [["note.md", "NOTE.md"], ["note.md", "note.md/image.png"]] {
            let source = try zip(names.map { ($0, Data("body".utf8), .file) })
            XCTAssertThrowsError(try NoteArchive.importZIP(source, into: root))
            try FileManager.default.removeItem(at: source)
        }
    }

    func testGenericArchiveRequiresNote() throws {
        let noNote = try zip([("image.png", Data([1]), .file)])
        XCTAssertThrowsError(try NoteArchive.importZIP(noNote, into: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["input.zip"])
    }

    func testRejectsEntryCountBomb() throws {
        let source = try zip((0...NoteArchive.maximumEntries).map { ("\($0).md", Data(), .file) })
        XCTAssertThrowsError(try NoteArchive.importZIP(source, into: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["input.zip"])
    }

    func testGenericArchivePreservesMarkdownWithoutInferringRequiredAssets() throws {
        let cases = [
            "    ![example](missing.png)",
            "\t![example](missing.png)",
            "```md\n![example](missing.png)\n```",
            "> ```md\n> ![example](missing.png)\n> ```",
            "- Example:\n\n        ![example](missing.png)",
            "![outer [inner]](missing(a(b)).png)",
            "![real missing image](missing.png)\n![remote](https://example.com/missing.png)",
        ]
        for markdown in cases {
            let bytes = Data(markdown.utf8)
            let source = try zip([("note.md", bytes, .file)])
            let imported = try NoteArchive.importZIP(source, into: root)
            XCTAssertEqual(try Data(contentsOf: imported.appendingPathComponent("note.md")), bytes)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".archive-import-") })
            try FileManager.default.removeItem(at: source)
            try FileManager.default.removeItem(at: imported)
        }
    }

    func testCRCFailureCleansStaging() throws {
        let source = try zip([("note.md", Data("unique note payload".utf8), .file)])
        var bytes = try Data(contentsOf: source)
        let range = try XCTUnwrap(bytes.range(of: Data("unique note payload".utf8)))
        bytes[range.lowerBound] ^= 1
        try bytes.write(to: source)
        XCTAssertThrowsError(try NoteArchive.importZIP(source, into: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["input.zip"])
    }

    func testRejectsOversizedEntry() throws {
        let source = root.appendingPathComponent("large.zip")
        let archive = try Archive(url: source, accessMode: .create)
        try archive.addEntry(with: "note.md", type: .file,
                             uncompressedSize: Int64(NoteArchive.maximumFileBytes + 1),
                             compressionMethod: .deflate) { _, size in Data(repeating: 65, count: size) }
        XCTAssertThrowsError(try NoteArchive.importZIP(source, into: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["large.zip"])
    }

    func testRendererSuppliedNestedImageAndExactNoteSnapshot() throws {
        let note = try write("original/note.md", "![outer [inner]](images/a(b(c)).png)")
        let snapshot = try NoteArchive.readNote(note)
        _ = try write("original/images/a(b(c)).png", "nested image")
        try "changed after parser snapshot".write(to: note, atomically: true, encoding: .utf8)
        let exported = try NoteArchive.export(note: note, noteData: snapshot, imageSources: ["images/a(b(c)).png"])
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        let imported = try NoteArchive.importZIP(exported, into: root)
        XCTAssertEqual(try Data(contentsOf: imported.appendingPathComponent("note.md")), snapshot)
        XCTAssertEqual(try String(contentsOf: imported.appendingPathComponent("images/a(b(c)).png")), "nested image")
    }

    func testManifestPreservesEntityPathsAndUnusedFrontMatter() throws {
        let note = try write("original/note.md", "---\nimage: '![x](../private.png)'\n---\n![x](images/a&amp;b.png)")
        _ = try write("original/images/a&b.png", "image")
        let exported = try NoteArchive.export(note: note, noteData: NoteArchive.readNote(note), imageSources: ["images/a&b.png"])
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        let imported = try NoteArchive.importZIP(exported, into: root)
        XCTAssertEqual(try String(contentsOf: imported.appendingPathComponent("images/a&b.png")), "image")
    }

    func testManifestCannotEscapeOrHideMissingAssets() throws {
        for image in ["../private.png", "missing.png"] {
            let manifest = try JSONSerialization.data(withJSONObject: ["version": 1, "note": "note.md", "images": [image]])
            let source = try zip([("note.md", Data("body".utf8), .file), (NoteArchive.manifestPath, manifest, .file)])
            XCTAssertThrowsError(try NoteArchive.importZIP(source, into: root)) { error in
                XCTAssertEqual(error as? NoteArchive.Failure, image == "missing.png" ? .missingAsset : .unsafePath)
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["input.zip"])
            try FileManager.default.removeItem(at: source)
        }
    }
}
