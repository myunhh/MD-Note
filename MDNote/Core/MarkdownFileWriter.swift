import Foundation

/// The comparison and replacement share one file-coordination accessor. A watcher
/// notification is not permission to overwrite a newer external revision.
enum MarkdownFileWriter {
    enum Failure: LocalizedError {
        case externalConflict
        case invalidUTF8
        case unavailable

        var errorDescription: String? {
            switch self {
            case .externalConflict:
                return "This file changed outside MD Note. Your edit is still open; save a recovery copy before reopening the external version."
            case .invalidUTF8: return "The Markdown file is not valid UTF-8."
            case .unavailable: return "The Markdown file could not be coordinated."
            }
        }
    }

    static func read(_ url: URL) throws -> String {
        var result: Result<String, Error> = .failure(Failure.unavailable)
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                let data = try Data(contentsOf: coordinatedURL)
                guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalidUTF8 }
                return text
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func write(_ text: String, to url: URL, expectedText: String) throws {
        var result: Result<Void, Error> = .failure(Failure.unavailable)
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            result = Result {
                let data = try Data(contentsOf: coordinatedURL)
                guard let current = String(data: data, encoding: .utf8) else { throw Failure.invalidUTF8 }
                guard current == expectedText else { throw Failure.externalConflict }
                try Data(text.utf8).write(to: coordinatedURL, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}
