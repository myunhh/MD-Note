import Foundation
import ZIPFoundation

/// Portable source bundles. Imported contents become visible only after every entry validates.
enum NoteArchive {
    static let maximumEntries = 2_000
    static let maximumFileBytes: UInt64 = 64 * 1_024 * 1_024
    static let maximumTotalBytes: UInt64 = 256 * 1_024 * 1_024
    static let documentExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]
    static let manifestPath = "MDNote Archive.json"
    private static let maximumManifestBytes: UInt64 = 4 * 1_024 * 1_024
    private struct Manifest: Codable {
        let version: Int
        let note: String
        let images: [String]
    }

    enum Failure: String, LocalizedError {
        case unsafePath = "archiveUnsafePath"
        case limitExceeded = "archiveLimitExceeded"
        case missingNote = "archiveMissingNote"
        case damaged = "archiveDamaged"
        case missingAsset = "archiveMissingAsset"
        var errorDescription: String? { NSLocalizedString(rawValue, comment: "") }
    }

    /// Reject ambiguous separators, hidden paths and aliases before touching the filesystem.
    static func validatedPath(_ path: String, directory: Bool = false) throws -> String {
        let value = directory && path.hasSuffix("/") ? String(path.dropLast()) : path
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty, value.utf8.count <= 1_024,
              !value.contains("\\"), !value.contains(":"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasSuffix(" ") && !$0.hasSuffix(".") })
        else { throw Failure.unsafePath }
        return value
    }

    private static func identity(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Every component must be a real directory/file, never a symlink (even one pointing inward).
    private static func regularFile(_ path: String, in root: URL) throws -> URL {
        let fm = FileManager.default
        var current = root
        let parts = path.split(separator: "/")
        for (index, part) in parts.enumerated() {
            current.appendPathComponent(String(part))
            let attributes: [FileAttributeKey: Any]
            do { attributes = try fm.attributesOfItem(atPath: current.path) }
            catch { throw Failure.missingAsset }
            let required: FileAttributeType = index == parts.count - 1 ? .typeRegular : .typeDirectory
            guard attributes[.type] as? FileAttributeType == required else { throw Failure.unsafePath }
        }
        guard current.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/")
        else { throw Failure.unsafePath }
        return current
    }

    /// Conservative import validation; export uses the renderer's complete Markdown parser.
    /// Unused reference definitions are deliberately excluded from the archive.
    static func imageDestinations(in markdown: String) -> [String] {
        func matches(_ pattern: String, in text: String) -> [[String]] {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
            let source = text as NSString
            return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
                (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
            }
        }
        func label(_ value: String) -> String {
            value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        }
        func destination(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<"), let end = trimmed.firstIndex(of: ">") {
                return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
            }
            // A quoted title is not part of a local filename. Bare spaces are accepted.
            return trimmed.replacingOccurrences(of: #"\s+["'].*["']\s*$"#, with: "", options: .regularExpression)
        }
        var fence: Character?
        var fenceLength = 0
        let visibleLines = markdown.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let length = trimmed.prefix(while: { $0 == first }).count
                if length >= 3 {
                    if fence == nil { fence = first; fenceLength = length }
                    else if fence == first && length >= fenceLength { fence = nil }
                    return ""
                }
            }
            return fence == nil ? line : ""
        }
        let visible = visibleLines.joined(separator: "\n")
            .replacingOccurrences(of: #"(?s)<!--.*?-->|(`+).*?\1"#, with: "", options: .regularExpression)
        var definitions: [String: String] = [:]
        for match in matches(#"^ {0,3}\[([^\]]+)\]:\s*(.+)$"#, in: visible) {
            if definitions[label(match[1])] == nil { definitions[label(match[1])] = destination(match[2]) }
        }
        var result = matches(#"!\[(?:\\.|[^\]\\])*\]\(\s*(<[^>]*>|(?:\\.|[^()\\\n]|\([^()\\\n]*\))*)\s*\)"#, in: visible)
            .map { destination($0[1]) }
        for match in matches(#"!\[([^\]]*)\](?:\[([^\]]*)\])?(?!\()"#, in: visible) {
            let key = label(match[2].isEmpty ? match[1] : match[2])
            if let value = definitions[key] { result.append(value) }
        }
        return result
    }

    static func localImagePath(_ destination: String) throws -> String? {
        let raw = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("//") { return nil }
        if let scheme = URLComponents(string: raw)?.scheme {
            if ["http", "https", "data"].contains(scheme.lowercased()) { return nil }
            throw Failure.unsafePath
        }
        let withoutFragment = String(raw.prefix(while: { $0 != "#" && $0 != "?" }))
        guard !withoutFragment.isEmpty else { return nil }
        guard let decoded = withoutFragment.removingPercentEncoding else { throw Failure.unsafePath }
        let unescaped = decoded.replacingOccurrences(of: ##"\\([ !"#$%&'()*+,\-./:;<=>?@\[\]^_`{|}~])"##, with: "$1", options: .regularExpression)
        let relative = unescaped.hasPrefix("./") ? String(unescaped.dropFirst(2)) : unescaped
        return try validatedPath(relative)
    }

    static func readNote(_ note: URL) throws -> Data {
        let root = note.deletingLastPathComponent().resolvingSymlinksInPath()
        let source = try regularFile(note.lastPathComponent, in: root)
        let noteSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard UInt64(noteSize) <= maximumFileBytes else { throw Failure.limitExceeded }
        let data = try Data(contentsOf: source)
        guard UInt64(data.count) <= maximumFileBytes else { throw Failure.limitExceeded }
        return data
    }

    static func export(note: URL, noteData: Data, imageSources: [String]) throws -> URL {
        let fm = FileManager.default
        let root = note.deletingLastPathComponent().resolvingSymlinksInPath()
        var paths: Set<String> = [try validatedPath(note.lastPathComponent)]
        guard UInt64(noteData.count) <= maximumFileBytes else { throw Failure.limitExceeded }
        var images = Set<String>()
        for destination in imageSources {
            if let path = try localImagePath(destination) { paths.insert(path); images.insert(path) }
        }
        for suffix in ["inknote", "bookmarks"] {
            let companion = note.appendingPathExtension(suffix)
            if fm.fileExists(atPath: companion.path) { paths.insert(try validatedPath(companion.lastPathComponent)) }
        }
        guard !paths.contains(where: { identity($0) == identity(manifestPath) }) else { throw Failure.unsafePath }
        guard paths.count < maximumEntries else { throw Failure.limitExceeded }
        let manifest = try JSONEncoder().encode(Manifest(version: 1, note: note.lastPathComponent, images: images.sorted()))
        var total: UInt64 = 0
        var seen = Set<String>()
        let files = try paths.sorted().map { path -> (String, URL) in
            guard seen.insert(identity(path)).inserted else { throw Failure.unsafePath }
            let file = try regularFile(path, in: root)
            let size = path == note.lastPathComponent ? UInt64(noteData.count)
                : UInt64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard size <= maximumFileBytes, size <= maximumTotalBytes - total else { throw Failure.limitExceeded }
            total += size
            return (path, file)
        }
        guard UInt64(manifest.count) <= maximumManifestBytes,
              UInt64(manifest.count) <= maximumTotalBytes - total else { throw Failure.limitExceeded }
        let output = fm.temporaryDirectory.appendingPathComponent("mdnote-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            let zip = output.appendingPathComponent(note.deletingPathExtension().lastPathComponent + ".zip")
            let archive = try Archive(url: zip, accessMode: .create)
            for (path, file) in files {
                if path == note.lastPathComponent {
                    try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(noteData.count),
                                         compressionMethod: .deflate) { position, size in
                        noteData.subdata(in: Int(position)..<(Int(position) + size))
                    }
                } else {
                    try archive.addEntry(with: path, fileURL: file, compressionMethod: .deflate)
                }
            }
            try archive.addEntry(with: manifestPath, type: .file, uncompressedSize: Int64(manifest.count),
                                 compressionMethod: .deflate) { position, size in
                manifest.subdata(in: Int(position)..<(Int(position) + size))
            }
            return zip
        } catch {
            try? fm.removeItem(at: output)
            throw error
        }
    }

    @discardableResult
    static func importZIP(_ source: URL, into directory: URL) throws -> URL {
        let fm = FileManager.default
        let archiveSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard UInt64(archiveSize) <= maximumTotalBytes else { throw Failure.limitExceeded }
        let archive = try Archive(url: source, accessMode: .read)
        var entries: [(Entry, String)] = []
        var names = Set<String>()
        var fileNames = Set<String>()
        var declaredTotal: UInt64 = 0
        for entry in archive {
            guard entries.count < maximumEntries else { throw Failure.limitExceeded }
            guard entry.type != .symlink else { throw Failure.unsafePath }
            let path = try validatedPath(entry.path, directory: entry.type == .directory)
            guard names.insert(identity(path)).inserted else { throw Failure.unsafePath }
            let size = entry.uncompressedSize
            if path == manifestPath && size > maximumManifestBytes { throw Failure.limitExceeded }
            guard size <= maximumFileBytes, size <= maximumTotalBytes - declaredTotal else { throw Failure.limitExceeded }
            declaredTotal += size
            if entry.type == .file { fileNames.insert(identity(path)) }
            entries.append((entry, path))
        }
        for (_, path) in entries {
            var components = path.split(separator: "/")
            while components.count > 1 {
                components.removeLast()
                guard !fileNames.contains(identity(components.joined(separator: "/"))) else { throw Failure.unsafePath }
            }
        }
        guard entries.contains(where: { $0.0.type == .file && documentExtensions.contains(($0.1 as NSString).pathExtension.lowercased()) })
        else { throw Failure.missingNote }

        let staging = directory.appendingPathComponent(".archive-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        var actualTotal: UInt64 = 0
        for (entry, path) in entries {
            let target = staging.appendingPathComponent(path)
            if entry.type == .directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil) else { throw Failure.damaged }
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            var actualSize: UInt64 = 0
            let checksum = try archive.extract(entry, bufferSize: 32_768) { data in
                let count = UInt64(data.count)
                guard count <= maximumFileBytes - actualSize,
                      count <= maximumTotalBytes - actualTotal else { throw Failure.limitExceeded }
                actualSize += count
                actualTotal += count
                try handle.write(contentsOf: data)
            }
            guard actualSize == entry.uncompressedSize, checksum == entry.checksum else { throw Failure.damaged }
        }
        var manifestedNote: String?
        if entries.contains(where: { $0.1 == manifestPath }) {
            let manifestURL = try regularFile(manifestPath, in: staging)
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.version == 1, manifest.images.count < maximumEntries else { throw Failure.damaged }
            let notePath = try validatedPath(manifest.note)
            guard documentExtensions.contains((notePath as NSString).pathExtension.lowercased()) else { throw Failure.missingNote }
            let note = try regularFile(notePath, in: staging)
            for image in manifest.images {
                _ = try regularFile(validatedPath(image), in: note.deletingLastPathComponent())
            }
            manifestedNote = notePath
        }
        for (entry, path) in entries where entry.type == .file && path != manifestedNote && documentExtensions.contains((path as NSString).pathExtension.lowercased()) {
            let note = staging.appendingPathComponent(path)
            let markdown = try String(contentsOf: note, encoding: .utf8)
            for destination in imageDestinations(in: markdown) {
                if let image = try localImagePath(destination) {
                    _ = try regularFile(image, in: note.deletingLastPathComponent())
                }
            }
        }
        // A fresh enclosing folder preserves all relative paths and makes commit atomic.
        var stem = source.deletingPathExtension().lastPathComponent
        if (try? validatedPath(stem)) == nil { stem = NSLocalizedString("archiveImportedFolder", comment: "") }
        var destination = directory.appendingPathComponent(stem, isDirectory: true)
        var number = 2
        while fm.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(stem) \(number)", isDirectory: true)
            number += 1
        }
        try fm.moveItem(at: staging, to: destination)
        return destination
    }
}
