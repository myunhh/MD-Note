import SwiftUI

struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(directory: LibraryStore.documentsURL, path: $path)
                .navigationDestination(for: LibraryFolder.self) { folder in
                    LibraryView(directory: folder.url, path: $path)
                }
                .navigationDestination(for: LibraryDoc.self) { doc in
                    DocumentScreen(doc: doc)
                }
        }
        .tint(.mdAccent)   // unify native chrome with the paper theme's accent
    }
}
