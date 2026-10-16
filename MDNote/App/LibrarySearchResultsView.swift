import SwiftUI
import MDNoteCore

enum LibrarySearchScope: Hashable {
    case currentFolder
    case entireLibrary
}

struct LibrarySearchRequest: Equatable {
    let query: String
    let scope: LibrarySearchScope
    let revision: Int
}

@MainActor
final class LibrarySearchModel: ObservableObject {
    @Published private(set) var report = LibrarySearchReport()
    @Published private(set) var query = ""
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var requestID = UUID()

    func search(query: String, root: URL) async {
        let id = UUID()
        requestID = id
        self.query = query
        report = LibrarySearchReport()
        failed = false
        isLoading = !query.isEmpty
        guard !query.isEmpty else { return }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            let work = Task.detached(priority: .userInitiated) {
                try LibrarySearch.search(root: root, query: query)
            }
            let result = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            try Task.checkCancellation()
            guard requestID == id else { return }
            report = result
            isLoading = false
        } catch is CancellationError {
            // A canceled request must never publish results over its replacement.
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            failed = true
            isLoading = false
        }
    }
}

struct LibrarySearchResultsView: View {
    @ObservedObject var model: LibrarySearchModel
    @ObservedObject private var metadata = LibraryMetadataStore.shared
    let query: String
    let matches: [LibrarySearchMatch]
    @Binding var favoritesOnly: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.isLoading || model.query != query {
                ProgressView(L10n.text("librarySearchLoading"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else if model.failed {
                ContentUnavailableView {
                    Label(L10n.text("librarySearchFailed"), systemImage: "exclamationmark.magnifyingglass")
                } description: {
                    Text(L10n.text("librarySearchFailedDetail"))
                } actions: {
                    Button(L10n.text("librarySearchRetry"), action: retry)
                        .buttonStyle(.bordered)
                }
            } else {
                Text(L10n.format("librarySearchCount", matches.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if model.report.unreadableCount > 0 {
                    Text(L10n.format("librarySearchUnreadable", model.report.unreadableCount))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if model.report.oversizedCount > 0 {
                    Text(L10n.format("librarySearchLarge", model.report.oversizedCount))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if matches.isEmpty {
                    if favoritesOnly {
                        ContentUnavailableView {
                            Label(L10n.text("libraryMetadataNoFavorites"), systemImage: "star")
                        } description: {
                            Text(L10n.text("libraryMetadataFavoritesHint"))
                        } actions: {
                            Button(L10n.text("libraryMetadataShowAll")) { favoritesOnly = false }
                        }
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(matches) { match in
                            NavigationLink(value: LibraryDoc(
                                url: match.url, name: match.name, preview: match.snippet,
                                modified: match.modified, searchText: ""
                            )) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 5) {
                                        Text(match.name).font(.headline).foregroundStyle(.primary)
                                        if metadata.isFavorite(match.url) {
                                            Image(systemName: "star.fill")
                                                .foregroundStyle(Color.mdAccent)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    Text(match.relativePath).font(.caption).foregroundStyle(.secondary)
                                    Text(match.snippet.isEmpty ? L10n.text("librarySearchNameMatch") : match.snippet)
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(metadata.isFavorite(match.url) ? L10n.text("libraryMetadataFavorite") : "")
                            .contextMenu {
                                Button { metadata.toggleFavorite(match.url) } label: {
                                    Label(metadata.isFavorite(match.url)
                                          ? L10n.text("libraryMetadataRemoveFavorite")
                                          : L10n.text("libraryMetadataAddFavorite"),
                                          systemImage: metadata.isFavorite(match.url) ? "star.slash" : "star")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}
