import Foundation

public struct TrashEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let originalPath: String
    public let isDirectory: Bool
    public let deletedAt: Date
    public let companionExtensions: [String]
    public let metadata: Data
    public var name: String { URL(fileURLWithPath: originalPath).lastPathComponent }
}

public enum TrashError: Error, Equatable {
    case invalidPath
    case invalidEntry
    case missingParent
    case rollbackFailed
}

/// Each item owns a manifest and payload directory. Sidecars move as a single
/// reversible operation; a failed rollback leaves its manifest for recovery.
public final class TrashRepository {
    public let root: URL
    private let files: FileManager
    private let move: (URL, URL) throws -> Void
    private var trash: URL { root.appendingPathComponent(".Trash", isDirectory: true) }

    public init(root: URL, files: FileManager = .default,
                move: ((URL, URL) throws -> Void)? = nil) {
        self.root = root.standardizedFileURL
        self.files = files
        self.move = move ?? { try files.moveItem(at: $0, to: $1) }
    }

    public func entries() throws -> [TrashEntry] {
        guard files.fileExists(atPath: trash.path) else { return [] }
        try validate(trash)
        return try files.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
            .map { directory in
                guard UUID(uuidString: directory.lastPathComponent) != nil else { throw TrashError.invalidEntry }
                return try read(directory)
            }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    @discardableResult
    public func discard(_ source: URL, metadata: Data = Data()) throws -> TrashEntry {
        let source = source.standardizedFileURL
        try validate(source)
        guard source.path != trash.path, !source.path.hasPrefix(trash.path + "/") else {
            throw TrashError.invalidPath
        }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values.isDirectory == true
        let companions = isDirectory ? [] : ["inknote", "bookmarks"].filter {
            files.fileExists(atPath: source.appendingPathExtension($0).path)
        }
        let entry = TrashEntry(id: UUID(), originalPath: String(source.path.dropFirst(root.path.count + 1)),
                               isDirectory: isDirectory, deletedAt: Date(),
                               companionExtensions: companions, metadata: metadata)
        try validate(trash)
        let directory = bucket(entry)
        try files.createDirectory(at: payload(entry), withIntermediateDirectories: true)
        do {
            try JSONEncoder().encode(entry).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            let pairs = paths(source, companions: companions).map { ($0, payload(entry).appendingPathComponent($0.lastPathComponent)) }
            try transfer(pairs)
        } catch {
            // A rollback failure must retain every remaining payload and its manifest.
            if (error as? TrashError) != .rollbackFailed { try? files.removeItem(at: directory) }
            throw error
        }
        return entry
    }

    /// Missing parents are never silently recreated. The caller may explicitly
    /// choose the library root instead; collisions always keep all companions.
    @discardableResult
    public func restore(_ entry: TrashEntry, toLibraryRoot: Bool = false) throws -> URL {
        let stored = try read(bucket(entry))
        guard stored == entry else { throw TrashError.invalidEntry }
        let bucketNames = try files.contentsOfDirectory(atPath: bucket(entry).path)
        let payloadNames = try files.contentsOfDirectory(atPath: payload(entry).path)
        let expectedNames = paths(URL(fileURLWithPath: entry.name), companions: entry.companionExtensions).map(\.lastPathComponent)
        guard Set(bucketNames) == ["manifest.json", "payload"], Set(payloadNames) == Set(expectedNames) else {
            throw TrashError.invalidEntry
        }
        let original = root.appendingPathComponent(entry.originalPath).standardizedFileURL
        try validate(original)
        let parent = toLibraryRoot ? root : original.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TrashError.missingParent
        }
        let destination = unique(parent.appendingPathComponent(entry.name), entry: entry)
        let source = payload(entry).appendingPathComponent(entry.name)
        let pairs = Array(zip(paths(source, companions: entry.companionExtensions),
                              paths(destination, companions: entry.companionExtensions)))
        try transfer(pairs)
        do {
            try files.removeItem(at: bucket(entry))
        } catch {
            // Restore the manifest too if a partial cleanup removed it.
            do {
                try files.createDirectory(at: payload(entry), withIntermediateDirectories: true)
                try JSONEncoder().encode(entry).write(to: bucket(entry).appendingPathComponent("manifest.json"), options: .atomic)
                try transfer(pairs.map { ($0.1, $0.0) })
            } catch { throw TrashError.rollbackFailed }
            throw error
        }
        return destination
    }

    public func permanentlyDelete(_ entry: TrashEntry) throws {
        guard try read(bucket(entry)) == entry else { throw TrashError.invalidEntry }
        try files.removeItem(at: bucket(entry))
    }

    private func read(_ directory: URL) throws -> TrashEntry {
        try validate(directory)
        let manifest = directory.appendingPathComponent("manifest.json")
        try validate(manifest)
        let entry = try JSONDecoder().decode(TrashEntry.self, from: Data(contentsOf: manifest))
        guard entry.id.uuidString == directory.lastPathComponent,
              !entry.originalPath.isEmpty, !entry.originalPath.hasPrefix("/"),
              !entry.originalPath.split(separator: "/").contains(".."),
              entry.originalPath.split(separator: "/").first != ".Trash",
              Set(entry.companionExtensions).isSubset(of: ["inknote", "bookmarks"]),
              Set(entry.companionExtensions).count == entry.companionExtensions.count,
              !entry.isDirectory || entry.companionExtensions.isEmpty else { throw TrashError.invalidEntry }
        return entry
    }

    private func bucket(_ entry: TrashEntry) -> URL { trash.appendingPathComponent(entry.id.uuidString, isDirectory: true) }
    private func payload(_ entry: TrashEntry) -> URL { bucket(entry).appendingPathComponent("payload", isDirectory: true) }

    private func paths(_ note: URL, companions: [String]) -> [URL] {
        [note] + companions.map { note.appendingPathExtension($0) }
    }

    private func validate(_ url: URL) throws {
        let resolvedRoot = root.resolvingSymlinksInPath().path
        let relative = String(url.standardizedFileURL.path.dropFirst(root.path.count))
        guard url.standardizedFileURL.path.hasPrefix(root.path + "/"),
              url.resolvingSymlinksInPath().path == resolvedRoot + relative else {
            throw TrashError.invalidPath
        }
    }

    private func unique(_ requested: URL, entry: TrashEntry) -> URL {
        var candidate = requested
        var index = 2
        // Also reserve absent companions so an orphan sidecar cannot attach.
        while paths(candidate, companions: ["inknote", "bookmarks"]).contains(where: { files.fileExists(atPath: $0.path) }) {
            let ext = entry.isDirectory ? "" : requested.pathExtension
            let base = ext.isEmpty ? requested.lastPathComponent : requested.deletingPathExtension().lastPathComponent
            candidate = requested.deletingLastPathComponent().appendingPathComponent("\(base) \(index)")
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            index += 1
        }
        return candidate
    }

    private func transfer(_ pairs: [(URL, URL)]) throws {
        var completed: [(URL, URL)] = []
        do {
            for (source, destination) in pairs {
                try validate(source)
                try validate(destination)
                try move(source, destination)
                completed.append((source, destination))
            }
        } catch {
            var failed = false
            for (source, destination) in completed.reversed() {
                do { try move(destination, source) } catch { failed = true }
            }
            if failed { throw TrashError.rollbackFailed }
            throw error
        }
    }
}
