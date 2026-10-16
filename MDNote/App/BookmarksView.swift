import SwiftUI
import MDNoteCore

struct BookmarksView: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dismiss) private var dismiss
    @State private var editing: DocumentBookmark?
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                if let error = session.bookmarkError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button(L10n.text("bookmarkReload")) { session.controller?.loadBookmarks() }
                    }
                }
                Section {
                    Button {
                        session.controller?.addCurrentBookmark()
                    } label: {
                        Label(L10n.text("bookmarkAdd"), systemImage: "bookmark.badge.plus")
                    }
                    .disabled(!session.bookmarkReady || session.bookmarkError != nil)
                }
                if session.bookmarks.isEmpty {
                    Text(L10n.text("bookmarkEmpty"))
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(session.bookmarks) { bookmark in
                            HStack {
                                Button {
                                    session.controller?.jumpToBookmark(bookmark)
                                    dismiss()
                                } label: {
                                    Text(bookmark.name).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .disabled(!session.bookmarkReady)
                                .accessibilityHint(L10n.text("bookmarkJumpHint"))
                                Menu {
                                    Button(L10n.text("bookmarkRename")) {
                                        name = bookmark.name
                                        editing = bookmark
                                    }
                                    Button(L10n.text("bookmarkDelete"), role: .destructive) {
                                        session.controller?.deleteBookmark(bookmark.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                                }
                                .disabled(session.bookmarkError != nil)
                                .accessibilityLabel(L10n.format("bookmarkActions", bookmark.name))
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("bookmarkTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("close")) { dismiss() }
                }
            }
            .alert(L10n.text("bookmarkRename"), isPresented: Binding(
                get: { editing != nil }, set: { if !$0 { editing = nil } }
            )) {
                TextField(L10n.text("bookmarkName"), text: $name)
                Button(L10n.text("bookmarkSave")) {
                    if let editing { session.controller?.renameBookmark(editing.id, name: name) }
                    editing = nil
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L10n.text("cancel"), role: .cancel) { editing = nil }
            }
        }
    }
}
