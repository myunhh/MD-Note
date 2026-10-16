import Combine
import Foundation

@MainActor
final class LibraryMetadataStore: ObservableObject {
    static let shared = LibraryMetadataStore()
    static let defaultsPrefix = "docLibraryMetadata:"

    private struct Entry: Codable {
        var isFavorite = false
        var lastOpened: Date?
    }

    @Published private var entries: [String: Entry] = [:]
    private let defaults: UserDefaults
    private var changeSubscription: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
        changeSubscription = NotificationCenter.default.publisher(
            for: Notification.Name("libraryMetadataDidChange"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
    }

    func isFavorite(_ url: URL) -> Bool {
        entries[LibraryStore.relativeKey(for: url)]?.isFavorite ?? false
    }

    func toggleFavorite(_ url: URL) {
        let key = LibraryStore.relativeKey(for: url)
        var entry = entries[key] ?? Entry()
        entry.isFavorite.toggle()
        save(entry, for: key)
    }

    func lastOpenedDate(_ url: URL) -> Date? {
        entries[LibraryStore.relativeKey(for: url)]?.lastOpened
    }

    func recordOpened(_ url: URL) {
        let key = LibraryStore.relativeKey(for: url)
        var entry = entries[key] ?? Entry()
        entry.lastOpened = Date()
        save(entry, for: key)
    }

    /// Includes descendants without requiring the old path to still exist.
    func move(from oldURL: URL, to newURL: URL) {
        let old = LibraryStore.relativeKey(for: oldURL)
        let new = LibraryStore.relativeKey(for: newURL)
        guard old != new else { return }
        let moved = entries.filter { isWithin($0.key, root: old) }
        for (key, entry) in moved {
            let destination = new + key.dropFirst(old.count)
            save(entry, for: destination)
            defaults.removeObject(forKey: Self.defaultsPrefix + key)
            entries.removeValue(forKey: key)
        }
    }

    func remove(_ url: URL) {
        let root = LibraryStore.relativeKey(for: url)
        for key in entries.keys.filter({ isWithin($0, root: root) }) {
            defaults.removeObject(forKey: Self.defaultsPrefix + key)
            entries.removeValue(forKey: key)
        }
    }

    /// Trash snapshots restore the encoded preferences before posting a change.
    func reload() {
        let decoder = PropertyListDecoder()
        var loaded: [String: Entry] = [:]
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix(Self.defaultsPrefix) {
            guard let data = value as? Data,
                  let entry = try? decoder.decode(Entry.self, from: data) else { continue }
            loaded[String(key.dropFirst(Self.defaultsPrefix.count))] = entry
        }
        entries = loaded
    }

    private func save(_ entry: Entry, for key: String) {
        guard let data = try? PropertyListEncoder().encode(entry) else { return }
        defaults.set(data, forKey: Self.defaultsPrefix + key)
        entries[key] = entry
    }

    private func isWithin(_ key: String, root: String) -> Bool {
        key == root || key.hasPrefix(root + "/")
    }
}
