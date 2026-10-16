import SwiftUI
import MDNoteCore

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = TrashStore()
    @State private var pendingDeletion: TrashEntry?

    var body: some View {
        NavigationStack {
            List {
                if let error = store.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                        Button(L10n.text("trashRetry")) { store.errorMessage = nil; store.load() }
                    }
                }
                if store.entries.isEmpty {
                    ContentUnavailableView(L10n.text("trashEmpty"), systemImage: "trash",
                                           description: Text(L10n.text("trashEmptyDetail")))
                }
                ForEach(store.entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc.text")
                            .font(.headline)
                        Text(entry.originalPath).font(.subheadline).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(entry.deletedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("trashRestore")) { store.restore(entry) }
                            .frame(minHeight: 44)
                        Button(L10n.text("trashRestoreRoot")) { store.restore(entry, toLibraryRoot: true) }
                            .frame(minHeight: 44)
                        Button(L10n.text("trashDeleteForever"), role: .destructive) { pendingDeletion = entry }
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .navigationTitle(L10n.text("trashTitle"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("trashClose")) { dismiss() }
                }
            }
            .confirmationDialog(L10n.text("trashDeleteTitle"), isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                if let entry = pendingDeletion {
                    Button(L10n.text("trashDeleteForever"), role: .destructive) {
                        store.permanentlyDelete(entry)
                        pendingDeletion = nil
                    }
                }
                Button(L10n.text("cancel"), role: .cancel) { pendingDeletion = nil }
            } message: {
                Text(L10n.format("trashDeleteDetail", pendingDeletion?.name ?? ""))
            }
            .onAppear { store.load() }
        }
    }
}
