import SwiftUI
import UniformTypeIdentifiers

/// A markdown document in the app's library.
struct LibraryDoc: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let preview: String
    let modified: Date
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
    private(set) var directory: URL = LibraryStore.documentsURL

    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

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
            } else if url.pathExtension.lowercased() == "md" {
                ds.append(makeDoc(url))
            }
        }
        folders = fs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        documents = ds.sorted { $0.modified > $1.modified }
    }

    // MARK: Mutations

    @discardableResult
    func createNote(named name: String) -> LibraryDoc? {
        let base = sanitized(name).isEmpty ? "새 노트" : sanitized(name)
        let url = uniqueURL(directory.appendingPathComponent(base).appendingPathExtension("md"))
        let template = "# \(url.deletingPathExtension().lastPathComponent)\n\n"
        guard (try? template.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
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
        let base = sanitized(newName)
        guard !base.isEmpty, base != doc.name else { return }
        let dst = uniqueURL(doc.url.deletingLastPathComponent()
            .appendingPathComponent(base).appendingPathExtension("md"))
        try? FileManager.default.moveItem(at: doc.url, to: dst)
        let oldSidecar = doc.url.appendingPathExtension("inknote")
        if FileManager.default.fileExists(atPath: oldSidecar.path) {
            try? FileManager.default.moveItem(at: oldSidecar, to: dst.appendingPathExtension("inknote"))
        }
        load(directory: directory)
    }

    func rename(_ folder: LibraryFolder, to newName: String) {
        let base = sanitized(newName)
        guard !base.isEmpty, base != folder.name else { return }
        let dst = uniqueURL(folder.url.deletingLastPathComponent().appendingPathComponent(base),
                            isDirectory: true)
        try? FileManager.default.moveItem(at: folder.url, to: dst)
        load(directory: directory)
    }

    func delete(_ doc: LibraryDoc) {
        try? FileManager.default.removeItem(at: doc.url)
        try? FileManager.default.removeItem(at: doc.url.appendingPathExtension("inknote"))
        load(directory: directory)
    }

    func delete(_ folder: LibraryFolder) {
        try? FileManager.default.removeItem(at: folder.url)
        load(directory: directory)
    }

    func importFile(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = uniqueURL(directory.appendingPathComponent(url.lastPathComponent))
        try? FileManager.default.copyItem(at: url, to: dest)
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
                          modified: modified)
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
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
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
enum SampleDocument {
    @discardableResult
    static func installIfNeeded() -> URL? {
        guard let bundled = Bundle.main.url(forResource: "Sample", withExtension: "md") else { return nil }
        let dest = LibraryStore.documentsURL.appendingPathComponent("Sample.md")
        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.copyItem(at: bundled, to: dest)
        }
        return dest
    }
}

struct LibraryView: View {
    let directory: URL
    @Binding var path: NavigationPath
    @StateObject private var store = LibraryStore()

    @State private var showImporter = false
    @State private var showPrompt = false
    @State private var promptTitle = ""
    @State private var promptPlaceholder = ""
    @State private var promptText = ""
    @State private var promptAction: (String) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 22)]
    private var isRoot: Bool { directory.standardizedFileURL == LibraryStore.documentsURL.standardizedFileURL }

    var body: some View {
        ScrollView {
            if store.folders.isEmpty && store.documents.isEmpty {
                ContentUnavailableView(
                    "비어 있어요",
                    systemImage: "folder",
                    description: Text("우측 상단 ＋로 노트·폴더를 만들거나 파일을 가져오세요.")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(store.folders) { folder in
                        NavigationLink(value: folder) { FolderCard(folder: folder) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { askRename(folder) } label: { Label("이름 변경", systemImage: "pencil") }
                                Button(role: .destructive) { store.delete(folder) } label: { Label("삭제", systemImage: "trash") }
                            }
                    }
                    ForEach(store.documents) { doc in
                        NavigationLink(value: doc) { DocumentCard(doc: doc) }
                            .buttonStyle(.plain)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { askNewNote() } label: { Label("새 노트", systemImage: "doc.badge.plus") }
                    Button { askNewFolder() } label: { Label("새 폴더", systemImage: "folder.badge.plus") }
                    Divider()
                    Button { showImporter = true } label: { Label("가져오기", systemImage: "square.and.arrow.down") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(promptTitle, isPresented: $showPrompt) {
            TextField(promptPlaceholder, text: $promptText)
            Button("확인") { promptAction(promptText) }
            Button("취소", role: .cancel) {}
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: markdownTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(store.importFile) }
        }
        .onAppear { store.load(directory: directory) }
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
