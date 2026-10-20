# Library search implementation evidence

Worktree: `C:/Users/picom/orca/MD-Note/.omo/teams/team-7dc35eaa/worktrees/E`
Branch: `team/team-7dc35eaa/E`
Base: `4ad8a7c`
Scope: member E, recursive library search only.

The implementation is ready for integration. Native compilation, XCTest execution, and iPad visual/interaction validation remain UNVERIFIED because this Windows environment has no Swift, SourceKit, Xcode, or iOS simulator. No substitute UI or mirrored engine was used to claim native results.

## Executed checks

| Scenario | Exact invocation | Binary observable | Captured artifact |
|---|---|---|---|
| English/Korean key parity and lookup correctness | `node scripts/check-localization.mjs` | PASS, exit 0; 80 bilingual keys, 93 Swift lookups | `localization.log` |
| Existing renderer hash regression | `node MDNoteCore/Tests/parity/hash_parity.mjs` | PASS, exit 0; 8/8 golden cases | `hash-parity.log` |
| Native search scenarios | `swift test --package-path MDNoteCore --filter LibrarySearchTests` | BLOCKED, exit 127; `swift: command not found` | `swift-tests.log` |
| Pre-commit dependency audit | `npm audit --json` | BLOCKED, exit 1; ENOLOCK, repository has no package manifest/lockfile | `npm-audit.json` |
| Whitespace errors | `git diff --cached --check` | PASS, exit 0 | `diff-check.log` |
| Scope and source review | `git diff --cached` | Reviewed all six staged files, no peer implementation changes | `staged.patch` |

No active attempt directory was discoverable: the direct toolkit CLI status returned `ULW_LOOP_SESSION_SCOPE_REQUIRED` with `existingSessionIds: []`; the installed CMD wrapper failed with a syntax error. Evidence therefore uses this worktree's `.omo/evidence/library-search` directory. SourceKit installation was not requested, and the `lsp_install_decision` tool is unavailable. No global configuration was changed.

## Acceptance ledger

Each test below is in `MDNoteCore/Tests/MDNoteCoreTests/LibrarySearchTests.swift`. Invoke all with the native search command above. The expected binary observable is an XCTest PASS for the named case; none has been observed on this host. `swift-tests.log` captures the common execution blocker; `staged.patch` captures the actual tests and implementation.

| Criterion | Exact deterministic scenario | Expected binary observable | State |
|---|---|---|---|
| Recursive body search, duplicate disambiguation, openable result URL | `testDescendantBodyMatchesHaveDistinctPathsAndOpenableURLs` creates same-name notes two levels apart, searches uppercase query, reads returned URLs | Exactly two relative paths, unique IDs, matching snippets and readable contents | Native test pending |
| Korean name/body matching and canonical equivalence | `testKoreanNamesAndCanonicallyEquivalentBodyText` searches Korean filename and decomposed Hangul body query | One correct match per query | Native test pending |
| Supported document types only; hidden/trash/sidecars excluded | `testOnlySupportedVisibleDocumentsAreSearched` creates five accepted extensions, hidden notes/folders, `.Trash`, `.inknote`, `.bookmarks`, ZIP/PNG | Exactly five visible supported documents | Native test pending |
| Symlinks cannot escape library or cycle | `testSymlinkFilesDirectoriesAndCyclesAreNotFollowed` creates external file/directory links and self-cycle | Only safe local file returned | Native test pending |
| Bounded large-file work with name fallback | `testLargeBodiesAreSkippedButNamesStillMatch` uses a deterministic 4-byte test limit | Two oversized counts; name match retained without body | Native test pending |
| Unreadable content retains name matches and warns | `testUnreadableUTF8IsReportedAndCanStillMatchByName` writes invalid UTF-8 | One unreadable count; matching name retained | Native test pending |
| Useful snippet around a late match | `testSnippetShowsBodyMatchBeyondBeginningAndCompactsWhitespace` places match after 100 Korean phrases | Snippet includes match, compacts whitespace, fits 202 characters | Native test pending |
| Empty/no-match/trimmed queries | `testBlankQueryAndNoMatchReturnEmptyResults` | Blank/no-match empty, trimmed query matches | Native test pending |
| Unavailable root is an error | `testMissingRootThrowsInsteadOfReportingNoMatches` | Throws instead of empty success | Native test pending |
| Cancellation aborts traversal | `testCancellationInterruptsTraversalWithoutPartialSuccess` throws at fifth cancellation checkpoint | CancellationError, five checks, no partial success | Native test pending |
| Default engine cancellation | `testCanceledTaskUsesDefaultCancellationCheck` self-cancels a real detached task | CancellationError from default checker | Native test pending |

## Native surface scenarios still required

Invocation: generate the app with the existing XcodeGen project, build/run on an iPad simulator/device, then exercise `LibraryView`. No runnable native surface exists here, so all following observations and screenshots remain pending:

1. Open a nested folder, search `needle` under Entire library: notes from sibling folders appear with relative paths and readable snippets; tapping a row opens that exact note.
2. Rapidly type two different queries: the progress state appears during the 250 ms debounce/background scan; only the final query's results appear. Clear query during a scan: normal folders/cards return and old results never reappear.
3. Select Current folder: existing local folder/name/body search remains available. Clear/whitespace query restores ordinary browsing and folder navigation.
4. Search absent text: localized empty state and zero result count. Make library root unavailable: localized error and retry action. Add oversized/invalid UTF-8 notes: partial-search warnings and retained name matches.
5. Verify English/Korean scope controls, result rows, loading, empty, retry, and warnings at portrait/landscape iPad widths and accessibility text sizes; native screenshot/VoiceOver review remains pending.
6. Change name/modified sort: result ordering follows selection with deterministic name/path ties. Parent integration must decide recursive recent/favorites behavior as described below.

Source review found the background task is explicitly detached; cancellation forwards to it; both `Task.checkCancellation()` and a request UUID guard protect result publication. The visible result view also checks the displayed query before showing matches. These are source observations, not runtime evidence.

## Integration contract

- `LibraryView` adds `@StateObject librarySearch`, `searchScope`, `searchRevision`, `trimmedSearchText`, `searchRequest`, and `visibleSearchResults`; these are the principal merge points with D/A/F.
- `LibraryStore.documentExtensions` now aliases `MDNoteCore.LibrarySearch.documentExtensions` so browsing and recursive search cannot diverge on accepted extensions.
- Search defaults to Entire library. Both scopes are visible when search is presented. A nonblank Entire library query renders `LibrarySearchResultsView`; empty queries use the existing grid.
- `LibrarySearchMatch` has `url`, `name`, `relativePath`, `snippet`, and `modified`; IDs are full file paths. `LibrarySearchReport` has matches and unreadable/oversized counts. Root is always `LibraryStore.documentsURL`, even when initiated inside a child folder.
- D confirmed favorites copy is explicitly current-folder scoped. Therefore E does not apply that filter to global results. If parent elects global favorites, change D's copy and filter `librarySearch.report.matches` with `!favoritesOnly || metadata.isFavorite($0.url)`.
- To apply D's recent sort globally, add the `sortOrder == "recent"` comparator branch to `visibleSearchResults`, compare `metadata.lastOpenedDate(match.url) ?? .distantPast`, and fall back to name/relativePath ties. E currently implements name/modified sorting only.
- Result links use the existing `NavigationLink(value: LibraryDoc(...))` route, so D's centralized recent-open tracking applies. There is no new document-session or renderer path.
- A confirmed trash location is `Documents/.Trash`; it is excluded as hidden. Sidecar directories named `*.inknote` or `*.bookmarks` are also pruned.
- All resource keys use the `librarySearch` prefix; append all ten keys in both localization files when resolving merge conflicts.
- No dependencies or project.yml changes. XcodeGen's existing source directory discovery and the Swift package target include the new files.

## Review limitations

No Swift compilation, XCTest PASS, screenshot, simulator interaction, stale-result runtime experiment, or accessibility validation is claimed. The existing current-folder store still reads its local bodies on the main actor; the new recursive path performs its traversal/body reads off-main and caps body reads at 8 MiB. Files above that cap remain searchable by name, with a visible partial-search notice. All symlinks are excluded, including safe internal links.
