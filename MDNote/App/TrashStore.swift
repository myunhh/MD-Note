import Foundation
import SwiftUI
import MDNoteCore

@MainActor
final class TrashStore: ObservableObject {
    @Published private(set) var entries: [TrashEntry] = []
    @Published var errorMessage: String?
    private let repository = TrashRepository(root: LibraryStore.documentsURL)
    private static let prefixes = ["docViewState:", "docPaper:", "docLibraryMetadata:"]

    func load() {
        do { entries = try repository.entries(); errorMessage = nil }
        catch { errorMessage = Self.message(for: error) }
    }

    static func discard(_ url: URL) throws {
        let key = LibraryStore.relativeKey(for: url)
        let defaults = UserDefaults.standard
        let snapshot = defaults.dictionaryRepresentation().filter { item in
            prefixes.contains { prefix in
                item.key == prefix + key || item.key.hasPrefix(prefix + key + "/")
            }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        try TrashRepository(root: LibraryStore.documentsURL).discard(url, metadata: data)
        for key in snapshot.keys { defaults.removeObject(forKey: key) }
        NotificationCenter.default.post(name: Notification.Name("libraryMetadataDidChange"), object: nil)
    }

    func restore(_ entry: TrashEntry, toLibraryRoot: Bool = false) {
        do {
            guard let snapshot = try PropertyListSerialization.propertyList(from: entry.metadata, format: nil) as? [String: Any] else {
                throw TrashError.invalidEntry
            }
            let oldKey = LibraryStore.relativeKey(for: LibraryStore.documentsURL.appendingPathComponent(entry.originalPath))
            guard snapshot.keys.allSatisfy({ key in
                Self.prefixes.contains { key == $0 + oldKey || key.hasPrefix($0 + oldKey + "/") }
            }) else { throw TrashError.invalidEntry }
            let destination = try repository.restore(entry, toLibraryRoot: toLibraryRoot)
            let newKey = LibraryStore.relativeKey(for: destination)
            for (key, value) in snapshot {
                guard let prefix = Self.prefixes.first(where: { key.hasPrefix($0) }) else { continue }
                let suffix = key.dropFirst(prefix.count + oldKey.count)
                UserDefaults.standard.set(value, forKey: prefix + newKey + suffix)
            }
            NotificationCenter.default.post(name: Notification.Name("libraryMetadataDidChange"), object: nil)
            load()
        } catch { errorMessage = Self.message(for: error) }
    }

    func permanentlyDelete(_ entry: TrashEntry) {
        do { try repository.permanentlyDelete(entry); load() }
        catch { errorMessage = Self.message(for: error) }
    }

    static func message(for error: Error) -> String {
        switch error as? TrashError {
        case .missingParent: return L10n.text("trashMissingParent")
        case .rollbackFailed: return L10n.text("trashRecoveryFailed")
        case .invalidEntry, .invalidPath: return L10n.text("trashInvalidItem")
        default: return L10n.format("trashOperationFailed", error.localizedDescription)
        }
    }
}
