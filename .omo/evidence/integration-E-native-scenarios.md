# Pending native integration verification

These scenarios are not executed in this Windows environment; Swift/Xcode/iPad simulation is unavailable.

1. `cd MDNoteCore && swift test --filter LibrarySearchTests`: new `testSearchResultsPreserveRequestedRootAliasForDocumentPreferences` must return exactly one openable `Folder/Note.md` using the symlink root alias supplied by the caller. Expected binary observable: XCTest exit 0. Canonical traversal still skips the alias cycle inside the test root.
2. On iPad, favorite/open a note through folder browsing, then find it in Entire library. The favorite indicator and recent time must agree. Open through the search result, return, and verify no absolute `/private/var/...` metadata key is created alongside the existing relative key. Rename the note and containing folder and verify the same preferences follow.
3. Repeat current-folder and Entire library search with Favorites Only selected. Toggle an unselected result favorite through its menu, verify star and VoiceOver value, remove the last matching favorite, and turn the filter off using the empty-state button. Both scopes must sort using actual open timestamps, localized name/path ties, and modified date when selected.
4. Enter a query, immediately replace it, then switch scope or leave the screen. Only the latest query may render results; existing 250 ms debounce and detached-worker cancellation remain unchanged by integration.

Source trace: `LibrarySearch.search` retains `resultRoot` separately, enumerates and checks containment using canonical `root`, then reconstructs result URLs from `resultRoot` and the checked relative path. This is a code inspection, not native execution evidence.
