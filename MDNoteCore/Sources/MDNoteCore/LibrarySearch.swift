import Foundation

public struct LibrarySearchMatch: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let relativePath: String
    public let snippet: String
    public let modified: Date
}

public struct LibrarySearchReport: Sendable {
    public var matches: [LibrarySearchMatch] = []
    public var unreadableCount = 0
    public var oversizedCount = 0

    public init() {}
}

public enum LibrarySearchError: Error {
    case unavailableRoot
}

/// Synchronous filesystem work. Call from a background task and forward cancellation.
public enum LibrarySearch {
    public static let documentExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]
    public static let maximumBodyBytes = 8 * 1_024 * 1_024

    public static func search(
        root: URL,
        query: String,
        maximumBodyBytes: Int = LibrarySearch.maximumBodyBytes,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> LibrarySearchReport {
        try checkCancellation()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return LibrarySearchReport() }
        let resultRoot = root.standardizedFileURL
        let root = resultRoot.resolvingSymlinksInPath()
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            throw LibrarySearchError.unavailableRoot
        }
        let manager = FileManager.default
        // A failed root listing is an error, not a successful empty search.
        _ = try manager.contentsOfDirectory(atPath: root.path)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey,
            .fileSizeKey, .contentModificationDateKey,
        ]
        var report = LibrarySearchReport()
        guard let entries = manager.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
            errorHandler: { _, _ in report.unreadableCount += 1; return true }
        ) else { throw LibrarySearchError.unavailableRoot }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let byteLimit = max(0, min(maximumBodyBytes, Self.maximumBodyBytes))
        for case let url as URL in entries {
            try checkCancellation()
            let values: URLResourceValues
            do { values = try url.resourceValues(forKeys: keys) }
            catch { report.unreadableCount += 1; entries.skipDescendants(); continue }
            let component = url.lastPathComponent.lowercased()
            let excluded = component.hasPrefix(".") || component.hasSuffix(".inknote")
                || component.hasSuffix(".bookmarks")
            // Skip all links, including directory links, to avoid cycles and escaping the library.
            guard !excluded, values.isHidden != true, values.isSymbolicLink != true,
                  url.resolvingSymlinksInPath().path.hasPrefix(rootPrefix) else {
                entries.skipDescendants()
                continue
            }
            guard values.isRegularFile == true,
                  documentExtensions.contains(url.pathExtension.lowercased()) else { continue }

            let name = url.deletingPathExtension().lastPathComponent
            let nameMatches = name.range(of: query, options: .caseInsensitive) != nil
            var body: String?
            if (values.fileSize ?? 0) > byteLimit {
                report.oversizedCount += 1
            } else {
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: byteLimit + 1) ?? Data()
                    if bytes.count > byteLimit {
                        report.oversizedCount += 1
                    } else if let text = String(data: bytes, encoding: .utf8) {
                        body = text
                    } else {
                        report.unreadableCount += 1
                    }
                } catch {
                    report.unreadableCount += 1
                }
            }
            try checkCancellation()
            let bodyRange = body?.range(of: query, options: .caseInsensitive)
            guard nameMatches || bodyRange != nil else { continue }
            let relativePath = String(url.path.dropFirst(rootPrefix.count))
            report.matches.append(LibrarySearchMatch(
                url: resultRoot.appendingPathComponent(relativePath), name: name,
                relativePath: relativePath,
                snippet: body.map { snippet(in: $0, around: bodyRange) } ?? "",
                modified: values.contentModificationDate ?? .distantPast
            ))
        }
        try checkCancellation()
        report.matches.sort { $0.relativePath < $1.relativePath }
        return report
    }

    private static func snippet(in text: String, around match: Range<String.Index>?) -> String {
        let anchor = match?.lowerBound ?? text.startIndex
        let start = text.index(anchor, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(start, offsetBy: 200, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = text[start..<end].split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return (start == text.startIndex ? "" : "…") + excerpt + (end == text.endIndex ? "" : "…")
    }
}
