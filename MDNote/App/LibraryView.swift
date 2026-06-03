import SwiftUI
import UniformTypeIdentifiers

/// A markdown document in the app's own library (its Documents directory).
struct LibraryDoc: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let preview: String
    let modified: Date
}

/// Owns the app's document library — like GoodNotes, the app keeps its files in
/// its own Documents directory. Imports copy the picked file in, so everything
/// is writable (ink sidecars save cleanly next to each note).
@MainActor
final class LibraryStore: ObservableObject {
    @Published var documents: [LibraryDoc] = []

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func reload() {
        SampleDocument.installIfNeeded()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        documents = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map(makeDoc)
            .sorted { $0.modified > $1.modified }
    }

    func importFile(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var dest = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            let base = url.deletingPathExtension().lastPathComponent
            dest = documentsDirectory.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970)).md")
        }
        try? FileManager.default.copyItem(at: url, to: dest)
        reload()
    }

    func delete(_ doc: LibraryDoc) {
        try? FileManager.default.removeItem(at: doc.url)
        try? FileManager.default.removeItem(at: doc.url.appendingPathExtension("inknote"))
        reload()
    }

    private func makeDoc(_ url: URL) -> LibraryDoc {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return LibraryDoc(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            preview: Self.preview(from: text),
            modified: modified
        )
    }

    private static func preview(from text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { line in
                var s = line
                while let f = s.first, f == "#" || f == ">" || f == "-" || f == "*" || f == "`" {
                    s.removeFirst()
                }
                return s.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }
}

/// Bundled sample is copied into Documents on first launch so it's writable.
enum SampleDocument {
    @discardableResult
    static func installIfNeeded() -> URL? {
        guard let bundled = Bundle.main.url(forResource: "Sample", withExtension: "md") else { return nil }
        let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sample.md")
        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.copyItem(at: bundled, to: dest)
        }
        return dest
    }
}

struct LibraryView: View {
    @StateObject private var store = LibraryStore()
    @State private var showImporter = false

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)]

    var body: some View {
        ScrollView {
            if store.documents.isEmpty {
                ContentUnavailableView(
                    "문서가 없어요",
                    systemImage: "doc.text",
                    description: Text("우측 상단 ＋로 마크다운 파일을 가져오세요.")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(store.documents) { doc in
                        NavigationLink(value: doc) {
                            DocumentCard(doc: doc)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { store.delete(doc) } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(28)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 문서")
        .navigationDestination(for: LibraryDoc.self) { doc in
            DocumentScreen(doc: doc)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: {
                    Label("가져오기", systemImage: "plus")
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: markdownTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                urls.forEach(store.importFile)
            }
        }
        .onAppear { store.reload() }
    }

    private var markdownTypes: [UTType] {
        var types: [UTType] = []
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        types.append(contentsOf: [.plainText, .text])
        return types
    }
}

/// A paper-like card showing a text preview of the document.
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
            Text(doc.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(doc.modified, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
