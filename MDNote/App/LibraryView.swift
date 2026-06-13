import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension Color {
    /// The app's brand accent — the same terracotta as the web theme's
    /// `--accent` (#c2410c), so native chrome matches the rendered page.
    static let mdAccent = Color(red: 0.7608, green: 0.2549, blue: 0.0471)
}

/// Subtle press-down feedback for library cards (which otherwise hard-cut to the
/// document with no tactility).
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A markdown document in the app's library.
struct LibraryDoc: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let preview: String
    let modified: Date
    /// Lowercased full body, for in-library full-text search. Excluded from
    /// Equatable/Hashable below so navigation/diffing stays cheap.
    let searchText: String

    static func == (a: LibraryDoc, b: LibraryDoc) -> Bool {
        a.url == b.url && a.modified == b.modified
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(modified)
    }
}

/// A folder in the library.
struct LibraryFolder: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
}

/// Owns one directory's contents. The app keeps its files in its own Documents
/// tree (like GoodNotes), so everything is writable and ink sidecars save next
/// to each note.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var folders: [LibraryFolder] = []
    @Published var documents: [LibraryDoc] = []
    @Published var errorMessage: String?
    private(set) var directory: URL = LibraryStore.documentsURL

    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// A document's path relative to the library root. Keying UserDefaults on
    /// this (not the absolute container path, which changes across
    /// reinstall/restore) keeps per-document settings attached across restores.
    nonisolated static func relativeKey(for url: URL) -> String {
        let root = documentsURL.standardizedFileURL.path
        var path = url.standardizedFileURL.path
        if path.hasPrefix(root + "/") { path = String(path.dropFirst(root.count)) }
        return path
    }

    /// UserDefaults key for a document's saved scroll/zoom.
    nonisolated static func viewStateKey(for url: URL) -> String { "docViewState:\(relativeKey(for: url))" }

    /// UserDefaults key for a document's paper style (per-document, not global).
    nonisolated static func paperKey(for url: URL) -> String { "docPaper:\(relativeKey(for: url))" }

    /// Extensions shown in the library. Matches what the importer accepts so
    /// imported plain-text/markdown-variant files don't silently vanish.
    nonisolated static let documentExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]

    func load(directory: URL) {
        self.directory = directory
        if directory == Self.documentsURL { SampleDocument.installIfNeeded() }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []

        var fs: [LibraryFolder] = []
        var ds: [LibraryDoc] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                fs.append(LibraryFolder(url: url, name: url.lastPathComponent))
            } else if Self.documentExtensions.contains(url.pathExtension.lowercased()) {
                ds.append(makeDoc(url))
            }
        }
        folders = fs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        documents = ds.sorted { $0.modified > $1.modified }
    }

    // MARK: Mutations

    @discardableResult
    func createNote(named name: String) -> LibraryDoc? {
        let cleaned = sanitizedNoteName(name)
        let base = cleaned.isEmpty ? "새 노트" : cleaned
        let url = uniqueURL(directory.appendingPathComponent(base).appendingPathExtension("md"))
        let template = "# \(url.deletingPathExtension().lastPathComponent)\n\n"
        do { try template.write(to: url, atomically: true, encoding: .utf8) }
        catch { errorMessage = "노트를 만들지 못했어요."; return nil }
        load(directory: directory)
        return makeDoc(url)
    }

    func createFolder(named name: String) {
        let base = sanitized(name).isEmpty ? "새 폴더" : sanitized(name)
        let url = uniqueURL(directory.appendingPathComponent(base), isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        load(directory: directory)
    }

    func rename(_ doc: LibraryDoc, to newName: String) {
        let base = sanitizedNoteName(newName)
        guard !base.isEmpty, base != doc.name else { return }
        let dst = uniqueURL(doc.url.deletingLastPathComponent()
            .appendingPathComponent(base).appendingPathExtension(doc.url.pathExtension))
        // Move the sidecar only if the note itself moved — otherwise the ink
        // would detach from a note that stayed in place.
        guard (try? FileManager.default.moveItem(at: doc.url, to: dst)) != nil else { return }
        let oldSidecar = doc.url.appendingPathExtension("inknote")
        if FileManager.default.fileExists(atPath: oldSidecar.path) {
            try? FileManager.default.moveItem(at: oldSidecar, to: dst.appendingPathExtension("inknote"))
        }
        migrateDocDefaults(from: doc.url, to: dst)   // keep paper + scroll/zoom across rename
        load(directory: directory)
    }

    /// Move a renamed note's per-document UserDefaults (paper style, view state)
    /// to its new relative-path key so they aren't silently reset on rename.
    private func migrateDocDefaults(from old: URL, to new: URL) {
        let d = UserDefaults.standard
        let pairs = [
            (Self.viewStateKey(for: old), Self.viewStateKey(for: new)),
            (Self.paperKey(for: old), Self.paperKey(for: new)),
        ]
        for (oldKey, newKey) in pairs where d.object(forKey: oldKey) != nil {
            d.set(d.object(forKey: oldKey), forKey: newKey)
            d.removeObject(forKey: oldKey)
        }
    }

    func rename(_ folder: LibraryFolder, to newName: String) {
        let base = sanitized(newName)
        guard !base.isEmpty, base != folder.name else { return }
        let dst = uniqueURL(folder.url.deletingLastPathComponent().appendingPathComponent(base),
                            isDirectory: true)
        guard (try? FileManager.default.moveItem(at: folder.url, to: dst)) != nil else { return }
        // Every contained note moved to a new relative path; carry its per-doc
        // defaults (paper + scroll/zoom) along so they aren't silently reset.
        let dstPath = dst.standardizedFileURL.path
        let oldBase = folder.url.standardizedFileURL.path
        for newURL in containedDocURLs(in: dst) {
            let np = newURL.standardizedFileURL.path
            guard np.hasPrefix(dstPath) else { continue }
            let rel = String(np.dropFirst(dstPath.count))
            migrateDocDefaults(from: URL(fileURLWithPath: oldBase + rel), to: newURL)
        }
        load(directory: directory)
    }

    /// All document files (recursively) inside a folder.
    private func containedDocURLs(in folder: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var urls: [URL] = []
        for case let url as URL in en
        where Self.documentExtensions.contains(url.pathExtension.lowercased()) {
            urls.append(url)
        }
        return urls
    }

    func delete(_ doc: LibraryDoc) {
        try? FileManager.default.removeItem(at: doc.url)
        try? FileManager.default.removeItem(at: doc.url.appendingPathExtension("inknote"))
        UserDefaults.standard.removeObject(forKey: Self.viewStateKey(for: doc.url))
        UserDefaults.standard.removeObject(forKey: Self.paperKey(for: doc.url))
        load(directory: directory)
    }

    func delete(_ folder: LibraryFolder) {
        // Clear per-document defaults for every contained note before removing.
        for url in containedDocURLs(in: folder.url) {
            UserDefaults.standard.removeObject(forKey: Self.viewStateKey(for: url))
            UserDefaults.standard.removeObject(forKey: Self.paperKey(for: url))
        }
        try? FileManager.default.removeItem(at: folder.url)
        load(directory: directory)
    }

    func importFile(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = uniqueURL(directory.appendingPathComponent(url.lastPathComponent))
        do { try FileManager.default.copyItem(at: url, to: dest) }
        catch { errorMessage = "가져오기에 실패했어요: \(url.lastPathComponent)" }
        load(directory: directory)
    }

    /// Import a whole folder (e.g. a note plus its `images/` subfolder) so local
    /// images come along. Picking the folder grants access to its contents,
    /// which picking a single file does not.
    func importFolder(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = uniqueURL(directory.appendingPathComponent(url.lastPathComponent), isDirectory: true)
        do { try FileManager.default.copyItem(at: url, to: dest) }
        catch { errorMessage = "폴더 가져오기에 실패했어요: \(url.lastPathComponent)" }
        load(directory: directory)
    }

    // MARK: Helpers

    private func makeDoc(_ url: URL) -> LibraryDoc {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return LibraryDoc(url: url,
                          name: url.deletingPathExtension().lastPathComponent,
                          preview: Self.preview(from: text),
                          modified: modified,
                          searchText: text.lowercased())
    }

    private static func preview(from text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { line in
                var s = line
                while let f = s.first, "#>-*`".contains(f) { s.removeFirst() }
                return s.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }

    private func sanitized(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        // Strip leading dots (a leading-dot name is a HIDDEN file that would
        // vanish from the .skipsHiddenFiles listing) and trailing dots/spaces,
        // then cap the length so a pasted paragraph can't become a filename.
        s = s.replacingOccurrences(of: "^\\.+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ .]+$", with: "", options: .regularExpression)
        if s.count > 120 { s = String(s.prefix(120)) }
        return s
    }

    /// Note names additionally drop a typed document extension, so entering
    /// "Foo.md" (or renaming "note.txt" to "memo.txt") doesn't double-extend.
    private func sanitizedNoteName(_ name: String) -> String {
        var s = sanitized(name)
        for ext in Self.documentExtensions where s.lowercased().hasSuffix("." + ext) {
            s = String(s.dropLast(ext.count + 1))
            break
        }
        // Re-strip a trailing dot/space exposed by dropping the extension
        // (e.g. "note..md" -> "note." -> "note").
        s = s.replacingOccurrences(of: "[ .]+$", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func uniqueURL(_ url: URL, isDirectory: Bool = false) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var i = 2
        while true {
            let name = "\(base) \(i)"
            let candidate = ext.isEmpty
                ? dir.appendingPathComponent(name)
                : dir.appendingPathComponent(name).appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}

/// Bundled sample copied into Documents on first launch so it's writable.
/// Installed exactly once — deleting the sample must not resurrect it.
enum SampleDocument {
    private static let installedKey = "didInstallSampleDocument"

    @discardableResult
    static func installIfNeeded() -> URL? {
        guard let bundled = Bundle.main.url(forResource: "Sample", withExtension: "md") else { return nil }
        let dest = LibraryStore.documentsURL.appendingPathComponent("Sample.md")
        if !UserDefaults.standard.bool(forKey: installedKey) {
            // Only seed a genuinely fresh library. A user updating from a
            // build without the flag may have deleted the sample already —
            // existing content means this isn't a first launch.
            if libraryIsEmpty(), !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: bundled, to: dest)
            }
            UserDefaults.standard.set(true, forKey: installedKey)
        }
        return dest
    }

    private static func libraryIsEmpty() -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: LibraryStore.documentsURL, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        return !entries.contains { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return isDir || LibraryStore.documentExtensions.contains(url.pathExtension.lowercased())
        }
    }
}

struct LibraryView: View {
    let directory: URL
    @Binding var path: NavigationPath
    @StateObject private var store = LibraryStore()

    @State private var showImporter = false
    @State private var importIsFolder = false
    @State private var showPrompt = false
    @State private var promptTitle = ""
    @State private var promptPlaceholder = ""
    @State private var promptText = ""
    @State private var promptAction: (String) -> Void = { _ in }
    @State private var searchText = ""
    @AppStorage("librarySort") private var sortOrder = "modified"

    private let columns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 22)]
    private var isRoot: Bool { directory.standardizedFileURL == LibraryStore.documentsURL.standardizedFileURL }

    private var visibleFolders: [LibraryFolder] {
        guard !searchText.isEmpty else { return store.folders }
        return store.folders.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var visibleDocuments: [LibraryDoc] {
        var docs = store.documents
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            docs = docs.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) || $0.searchText.contains(q)
            }
        }
        if sortOrder == "name" {
            docs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return docs
    }

    var body: some View {
        ScrollView {
            if store.folders.isEmpty && store.documents.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Color.mdAccent.gradient)
                    Text("첫 노트를 만들어 볼까요?")
                        .font(.title3.weight(.semibold))
                    Text("마크다운을 예쁘게 펼쳐 두고 그 위에 Apple Pencil로 필기하세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                    Button { askNewNote() } label: {
                        Label("새 노트 만들기", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mdAccent)
                    .padding(.top, 4)
                }
                .padding(.top, 96)
                .frame(maxWidth: .infinity)
            } else if visibleFolders.isEmpty && visibleDocuments.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(visibleFolders) { folder in
                        NavigationLink(value: folder) { FolderCard(folder: folder) }
                            .buttonStyle(CardButtonStyle())
                            .contextMenu {
                                Button { askRename(folder) } label: { Label("이름 변경", systemImage: "pencil") }
                                Button(role: .destructive) { store.delete(folder) } label: { Label("삭제", systemImage: "trash") }
                            }
                    }
                    ForEach(visibleDocuments) { doc in
                        NavigationLink(value: doc) { DocumentCard(doc: doc) }
                            .buttonStyle(CardButtonStyle())
                            .contextMenu {
                                Button { askRename(doc) } label: { Label("이름 변경", systemImage: "pencil") }
                                Button(role: .destructive) { store.delete(doc) } label: { Label("삭제", systemImage: "trash") }
                            }
                    }
                }
                .padding(24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isRoot ? "내 문서" : directory.lastPathComponent)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .searchable(text: $searchText, prompt: "노트 검색")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("정렬", selection: $sortOrder) {
                        Label("최근 수정순", systemImage: "clock").tag("modified")
                        Label("이름순", systemImage: "textformat").tag("name")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("정렬")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { askNewNote() } label: { Label("새 노트", systemImage: "doc.badge.plus") }
                    Button { askNewFolder() } label: { Label("새 폴더", systemImage: "folder.badge.plus") }
                    Divider()
                    Button { importIsFolder = false; showImporter = true } label: { Label("파일 가져오기", systemImage: "doc") }
                    Button { importIsFolder = true; showImporter = true } label: { Label("폴더 가져오기 (이미지 포함)", systemImage: "folder") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("추가")
            }
        }
        .alert(promptTitle, isPresented: $showPrompt) {
            TextField(promptPlaceholder, text: $promptText)
            Button("확인") { promptAction(promptText) }
            Button("취소", role: .cancel) {}
        }
        .alert("문제가 생겼어요", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importIsFolder ? [.folder] : markdownTypes,
                      allowsMultipleSelection: !importIsFolder) { result in
            guard case .success(let urls) = result else { return }
            if importIsFolder { urls.forEach(store.importFolder) }
            else { urls.forEach(store.importFile) }
        }
        .onAppear { store.load(directory: directory) }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            store.load(directory: directory)
        }
    }

    // MARK: Prompts

    private func askName(title: String, placeholder: String, initial: String,
                         action: @escaping (String) -> Void) {
        promptTitle = title
        promptPlaceholder = placeholder
        promptText = initial
        promptAction = action
        showPrompt = true
    }

    private func askNewNote() {
        askName(title: "새 노트", placeholder: "노트 이름", initial: "") { name in
            if let doc = store.createNote(named: name) { path.append(doc) }
        }
    }

    private func askNewFolder() {
        askName(title: "새 폴더", placeholder: "폴더 이름", initial: "") { store.createFolder(named: $0) }
    }

    private func askRename(_ doc: LibraryDoc) {
        askName(title: "이름 변경", placeholder: "새 이름", initial: doc.name) { store.rename(doc, to: $0) }
    }

    private func askRename(_ folder: LibraryFolder) {
        askName(title: "폴더 이름 변경", placeholder: "새 이름", initial: folder.name) { store.rename(folder, to: $0) }
    }

    private var markdownTypes: [UTType] {
        var types: [UTType] = []
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        types.append(contentsOf: [.plainText, .text])
        return types
    }
}

struct DocumentCard: View {
    let doc: LibraryDoc

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.06)))
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                Text(doc.preview.isEmpty ? "빈 문서" : doc.preview)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }
            .aspectRatio(0.77, contentMode: .fit)
            Text(doc.name).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(doc.modified, style: .date).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct FolderCard: View {
    let folder: LibraryFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
                Image(systemName: "folder.fill").font(.system(size: 46)).foregroundStyle(.tint)
            }
            .aspectRatio(0.77, contentMode: .fit)
            Text(folder.name).font(.subheadline.weight(.medium)).lineLimit(1)
            Text("폴더").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
