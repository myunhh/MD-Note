# Trash implementation evidence

Scope: member A, branch `team/team-7dc35eaa/A`, reversible library deletion and safe restoration. Root authorized BEGIN and local commit. No merge, push, publication, installation, or global configuration change.

## Executed verification

| Criterion / scenario | Exact invocation | Binary observable | Captured artifact | Result |
|---|---|---|---|---|
| Bilingual resources and valid lookup formats | `node scripts/check-localization.mjs` | Exit 0, 85 bilingual keys and 100 Swift lookups accepted | `localization.log` | PASS |
| Existing hash parity regression | `node MDNoteCore/Tests/parity/hash_parity.mjs` | Exit 0, 8/8 cases match | `hash-parity.log` | PASS |
| Patch whitespace | `git diff --check` | Exit 0 | `diff-check.log` | PASS |
| Native filesystem fixtures | `swift test --package-path MDNoteCore --filter TrashRepositoryTests` | Swift unavailable, command not found | `swift-tests.log` | BLOCKED |
| Native build/visual surface | `xcodebuild -version` | Xcode unavailable, command not found | `xcode.log` | BLOCKED |

No relevant npm or Python package manifests are present in this worktree (`rg --files -g 'package*.json' -g '*requirements*.txt' -g 'pyproject.toml' -g 'Pipfile*'` returned no matches). npm/pip audit: N/A; no dependency installed. `omo-agent-toolkit ulw-loop status --json` was unavailable, so evidence is under `.omo/evidence/trash/`. No local Graphify artifact or AGENTS.md was found; supplied team and user guidance governed this work.

## Implementation and acceptance mapping

- `MDNoteCore/Sources/MDNoteCore/TrashRepository.swift`: UUID manifests under Documents/.Trash; original relative filename preserved; note .inknote/.bookmarks companions kept together; entire folders moved intact; safe name allocation reserves companion paths; missing parent requires explicit root restoration; failed move attempts reverse completed moves; rollback failure preserves remaining recovery files. Root/path/symlink checks and manifest checks reject unsafe inputs. Unknown payload files prevent restoration cleanup from deleting them.
- `MDNoteCore/Tests/MDNoteCoreTests/TrashRepositoryTests.swift`: 13 deterministic XCTest fixtures covering the criteria listed in native-qa.md. These tests were authored, not executed; no runtime PASS is claimed.
- `MDNote/App/TrashStore.swift`: snapshots UserDefaults docViewState:, docPaper:, docLibraryMetadata: entries and descendants into a binary plist in the manifest; removes active metadata after successful trash; remaps it after restore; posts libraryMetadataDidChange. Property-list keys are validated before replay.
- `MDNote/App/TrashView.swift`: system list/sheet with empty state, original path/date, original/root restore actions, inline errors/reload, Close, and named destructive confirmation with cancellation. Real rendering and accessibility remain BLOCKED.
- `MDNote/App/LibraryView.swift`: minimal deletion and Add-menu sheet hooks; existing skipsHiddenFiles keeps .Trash out of normal listing. Recursive search worker explicitly excludes .Trash.
- English/Korean Localizable.strings: 15 keys prefixed trash, all validated by localization checker.

## Integration notes

Keep member C's .bookmarks rename hooks and member D's metadata notification observer. D confirmed docLibraryMetadata: uses relative paths and PropertyListEncoder Data; it reloads on libraryMetadataDidChange. Keep member E's .Trash exclusion. LibraryView and localization tail hunks overlap peer branches and need intent-preserving integration. project.yml already includes App and the MDNoteCore package automatically; no project configuration change is needed.

Necessary comments explain rollback retention, missing-parent policy, manifest cleanup recovery, and orphan-sidecar collision reservation. Source review found and fixed the folder named manifest.json collision by moving payloads into a dedicated payload subdirectory, then added a regression fixture. Source review is not runtime proof.

Before product acceptance, complete every native scenario in `native-qa.md`. Native compilation, fixture behavior, preferences restoration, VoiceOver, and visual layout have not been verified on this host.
