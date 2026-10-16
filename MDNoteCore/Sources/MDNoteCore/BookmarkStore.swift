import Foundation

public struct DocumentBookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var blockHash: String?
    public var blockSeq: Int
    public var offset: Double
    public var lastY: Double
    public var fraction: Double

    public init(name: String, y: Double, height: Double, blocks: [Block]) {
        id = UUID()
        self.name = name
        let position = max(0, y.isFinite ? y : 0)
        let block = blocks.last { Double($0.frame.minY) <= position } ?? blocks.first
        blockHash = block?.hash
        blockSeq = block?.seq ?? 0
        offset = position - Double(block?.frame.minY ?? 0)
        lastY = position
        fraction = height > 0 ? min(1, position / height) : 0
    }

    public func resolve(in blocks: [Block], height: Double) -> (y: Double, usedFallback: Bool) {
        if let hash = blockHash, let block = blocks.block(hash: hash, seq: blockSeq) {
            return (max(0, Double(block.frame.minY) + offset), false)
        }
        return (height > 0 ? min(1, max(0, fraction)) * height : max(0, lastY), true)
    }

    fileprivate var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        blockSeq >= 0 && offset.isFinite && lastY.isFinite && lastY >= 0 &&
        fraction.isFinite && (0...1).contains(fraction)
    }
}

public enum BookmarkStoreError: Error {
    case unsupportedVersion, invalidData, changedOnDisk
}

/// A separate, versioned companion. Failed reads never turn into empty writable state.
public final class BookmarkStore {
    private struct File: Codable {
        var version = 1
        var bookmarks: [DocumentBookmark]
    }

    public private(set) var documentURL: URL
    public private(set) var bookmarks: [DocumentBookmark]
    private var loadedBytes: Data?
    public var sidecarURL: URL { documentURL.appendingPathExtension("bookmarks") }

    public init(documentURL: URL) throws {
        self.documentURL = documentURL
        let bytes = try Self.readIfPresent(documentURL.appendingPathExtension("bookmarks"))
        if let bytes {
            let file = try JSONDecoder().decode(File.self, from: bytes)
            guard file.version == 1 else { throw BookmarkStoreError.unsupportedVersion }
            guard file.bookmarks.allSatisfy(\.isValid),
                  Set(file.bookmarks.map(\.id)).count == file.bookmarks.count else {
                throw BookmarkStoreError.invalidData
            }
            bookmarks = file.bookmarks
        } else {
            bookmarks = []
        }
        loadedBytes = bytes
    }

    public func replace(with items: [DocumentBookmark]) throws {
        guard items.allSatisfy(\.isValid), Set(items.map(\.id)).count == items.count else {
            throw BookmarkStoreError.invalidData
        }
        let encoded = try JSONEncoder().encode(File(bookmarks: items))
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: sidecarURL, options: .forReplacing,
                                       error: &coordinationError) { url in
            do {
                guard try Self.readIfPresent(url) == loadedBytes else {
                    throw BookmarkStoreError.changedOnDisk
                }
                try encoded.write(to: url, options: .atomic)
            } catch { operationError = error }
        }
        if let error = coordinationError { throw error }
        if let error = operationError { throw error }
        loadedBytes = encoded
        bookmarks = items
    }

    /// A folder move may already have carried the companion to the destination.
    public func relocate(to newURL: URL) throws {
        guard newURL != documentURL else { return }
        let destination = newURL.appendingPathExtension("bookmarks")
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            try Self.moveCompanion(from: documentURL, to: newURL)
        } else {
            guard try Self.readIfPresent(destination) == loadedBytes else {
                throw BookmarkStoreError.changedOnDisk
            }
        }
        documentURL = newURL
    }

    public static func moveCompanion(from old: URL, to new: URL) throws {
        let source = old.appendingPathExtension("bookmarks")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try FileManager.default.moveItem(at: source, to: new.appendingPathExtension("bookmarks"))
    }

    private static func readIfPresent(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            error.code == NSFileReadNoSuchFileError { return nil }
    }
}
