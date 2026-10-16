import SwiftUI

struct DocumentSearchView: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    @FocusState private var focused: Bool

    private var status: String {
        if session.searchQuery.isEmpty { return L10n.text("documentSearch.prompt") }
        if session.searchPending { return L10n.text("documentSearch.searching") }
        if session.searchFailed { return L10n.text("documentSearch.failed") }
        if session.searchCount == 0 { return L10n.text("documentSearch.noMatches") }
        return L10n.format("documentSearch.count", session.searchIndex + 1, session.searchCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(L10n.text("documentSearch.title"), text: Binding(
                    get: { session.searchQuery }, set: { session.updateSearch($0) }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { session.moveSearch(1) }
                    .accessibilityLabel(L10n.text("documentSearch.title"))
                Button { session.updateSearch(""); focused = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(session.searchQuery.isEmpty)
                .accessibilityLabel(L10n.text("documentSearch.clear"))
            }
            HStack {
                Text(status).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("documentSearch.status")
                Spacer(minLength: 0)
                Button { session.moveSearch(-1) } label: {
                    Image(systemName: "chevron.up").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(session.searchCount == 0 || session.searchPending)
                .accessibilityLabel(L10n.text("documentSearch.previous"))
                Button { session.moveSearch(1) } label: {
                    Image(systemName: "chevron.down").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(session.searchCount == 0 || session.searchPending)
                .accessibilityLabel(L10n.text("documentSearch.next"))
                Button(action: close) {
                    Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(L10n.text("documentSearch.close"))
            }
            Divider()
        }
        .padding(.horizontal)
        .background(.regularMaterial)
        .onAppear { focused = true }
    }
}
