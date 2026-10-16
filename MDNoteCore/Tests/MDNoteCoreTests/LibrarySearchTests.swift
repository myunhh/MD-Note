import Foundation
import XCTest
@testable import MDNoteCore

final class LibrarySearchTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ path: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testDescendantBodyMatchesHaveDistinctPathsAndOpenableURLs() throws {
        try write("One/Duplicate.md", "The NeEdLe is here.")
        try write("Two/Deep/Duplicate.txt", "Another needle.")
        try write("Other.md", "Unrelated content.")
        let report = try LibrarySearch.search(root: root, query: "NEEDLE")
        XCTAssertEqual(report.matches.map(\.relativePath), ["One/Duplicate.md", "Two/Deep/Duplicate.txt"])
        XCTAssertEqual(Set(report.matches.map(\.id)).count, 2)
        for match in report.matches {
            XCTAssertTrue(match.snippet.lowercased().contains("needle"))
            XCTAssertTrue(try String(contentsOf: match.url, encoding: .utf8).lowercased().contains("needle"))
        }
    }

    func testKoreanNamesAndCanonicallyEquivalentBodyText() throws {
        try write("수업/시험 계획.MD", "복습할 내용")
        try write("수업/노트.markdown", "오늘은 한글 검색을 연습합니다")
        XCTAssertEqual(try LibrarySearch.search(root: root, query: "시험").matches.map(\.name), ["시험 계획"])
        XCTAssertEqual(try LibrarySearch.search(root: root, query: "한글".decomposedStringWithCanonicalMapping)
            .matches.map(\.name), ["노트"])
    }

    func testOnlySupportedVisibleDocumentsAreSearched() throws {
        for ext in ["md", "markdown", "mdown", "mkd", "txt"] {
            try write("visible.\(ext)", "needle")
        }
        for path in [".hidden.md", ".Trash/id/deleted.md", ".folder/nested.md",
                     "note.inknote/ink.md", "note.bookmarks/bookmark.md",
                     "image.png", "archive.zip", "note.md.inknote", "note.md.bookmarks"] {
            try write(path, "needle")
        }
        let report = try LibrarySearch.search(root: root, query: "needle")
        XCTAssertEqual(report.matches.count, 5)
        XCTAssertTrue(report.matches.allSatisfy { $0.relativePath.hasPrefix("visible.") })
    }

    func testSymlinkFilesDirectoriesAndCyclesAreNotFollowed() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let outsideFile = outside.appendingPathComponent("secret.md")
        try "needle".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("secret.md"), withDestinationURL: outsideFile)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cycle"), withDestinationURL: root)
        try write("safe.md", "needle")
        XCTAssertEqual(try LibrarySearch.search(root: root, query: "needle").matches.map(\.relativePath), ["safe.md"])
    }

    func testLargeBodiesAreSkippedButNamesStillMatch() throws {
        try write("needle.md", "needle beyond body limit")
        try write("large.txt", "needle beyond body limit")
        let report = try LibrarySearch.search(root: root, query: "needle", maximumBodyBytes: 4)
        XCTAssertEqual(report.oversizedCount, 2)
        XCTAssertEqual(report.matches.map(\.name), ["needle"])
        XCTAssertEqual(report.matches.first?.snippet, "")
    }

    func testSearchResultsPreserveRequestedRootAliasForDocumentPreferences() throws {
        try write("Folder/Note.md", "needle")
        let alias = root.appendingPathComponent("library-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let report = try LibrarySearch.search(root: alias, query: "needle")
        let match = try XCTUnwrap(report.matches.first)
        XCTAssertEqual(report.matches.count, 1)
        XCTAssertEqual(match.relativePath, "Folder/Note.md")
        XCTAssertEqual(match.url.standardizedFileURL, alias.appendingPathComponent("Folder/Note.md").standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: match.url, encoding: .utf8), "needle")
    }

    func testUnreadableUTF8IsReportedAndCanStillMatchByName() throws {
        let url = try write("needle.md", "")
        try Data([0xff, 0xfe, 0xfd]).write(to: url)
        let report = try LibrarySearch.search(root: root, query: "needle")
        XCTAssertEqual(report.unreadableCount, 1)
        XCTAssertEqual(report.matches.map(\.name), ["needle"])
        XCTAssertEqual(report.matches.first?.snippet, "")
    }

    func testSnippetShowsBodyMatchBeyondBeginningAndCompactsWhitespace() throws {
        try write("note.md", String(repeating: "앞부분 ", count: 100) + "needle\n\t뒷부분")
        let match = try XCTUnwrap(LibrarySearch.search(root: root, query: "needle").matches.first)
        XCTAssertTrue(match.snippet.hasPrefix("…"))
        XCTAssertTrue(match.snippet.contains("needle 뒷부분"))
        XCTAssertFalse(match.snippet.contains("\n"))
        XCTAssertLessThanOrEqual(match.snippet.count, 202)
    }

    func testBlankQueryAndNoMatchReturnEmptyResults() throws {
        try write("note.md", "some text")
        XCTAssertTrue(try LibrarySearch.search(root: root, query: " \n ").matches.isEmpty)
        XCTAssertTrue(try LibrarySearch.search(root: root, query: "absent").matches.isEmpty)
        XCTAssertEqual(try LibrarySearch.search(root: root, query: " text ").matches.count, 1)
    }

    func testMissingRootThrowsInsteadOfReportingNoMatches() throws {
        XCTAssertThrowsError(try LibrarySearch.search(root: root.appendingPathComponent("missing"), query: "needle"))
    }

    func testCancellationInterruptsTraversalWithoutPartialSuccess() throws {
        for index in 0..<12 { try write("folder/\(index).md", "needle") }
        var checks = 0
        XCTAssertThrowsError(try LibrarySearch.search(root: root, query: "needle", checkCancellation: {
            checks += 1
            if checks == 5 { throw CancellationError() }
        })) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(checks, 5)
    }

    @MainActor
    func testCanceledTaskUsesDefaultCancellationCheck() async throws {
        try write("note.md", "needle")
        let searchRoot = try XCTUnwrap(root)
        let work = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LibrarySearch.search(root: searchRoot, query: "needle")
        }
        do {
            _ = try await work.value
            XCTFail("Canceled search returned a report")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
