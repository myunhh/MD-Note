# A handoff

Commit: `b401faa6ad20af7b80f33b7975375d4bf3a3dc4d`
Message: Add offline rendered Markdown editing and study controls
Branch: mdnote-live-ink/rendered-editor

Implemented offline ProseMirror block editing, rich formatting, keyboard
split/ordinary-paragraph merge, joint text/study undo, source fallback,
frontmatter/reference/untouched byte preservation, IME save suppression,
grapheme-aligned UTF16 edit events, segment mappings, persisted study child IDs,
empty supplement editing, resize/move/remove controls, external identity safety,
native renderer DTOs and bilingual SwiftUI controls/recovery action.

Changed owned files:
- MDNote/App/DocumentScreen.swift
- MDNote/Core/DocumentSession.swift
- MDNote/Core/MarkdownRenderer.swift
- MDNote/Resources/Localization/{en,ko}.lproj/Localizable.strings
- MDNote/Resources/WebAssets/app/{bridge.js,theme.css}
- MDNote/Resources/WebAssets/index.html
- MDNote/Resources/WebAssets/vendor/{editor.js,editor-LICENSES.txt}
- editor/{.gitignore,DESIGN.md,README.md,build.mjs,editor.js,package.json,package-lock.json}
- scripts/check-rich-editor.mjs

Exact event and integration API: [A-api.md](A-api.md).

Executed:
- node scripts/check-rich-editor.mjs: 28/28 real Chrome cases
- node scripts/check-document-search.mjs: 28/28 real Chrome cases
- node scripts/check-archive-renderer.mjs: 18/18 parser fixtures
- node scripts/check-localization.mjs: 165 bilingual keys / 169 Swift lookups
- npm ci --ignore-scripts + npm run build: byte-identical bundle
- npm audit --json: zero vulnerabilities
- check-accent-stripes.ts: no stripe findings
- git diff --check and staged diff check: exit 0

Evidence directory:
`C:/Users/picom/orca/MD-Note/.omo/teams/team-e43dac36/worktrees/A/.omo/evidence/rich-editor/`
contains verification.md, results.json, events.json, rich-editor.png,
source-applied.png, run.log, search.log, archive.log, localization.log,
build.log, npm-audit.json, checks.txt.
Search's raw DOM results and captures live in sibling document-search/.

Only those two evidence directories remain untracked. No merges, pushes,
global configuration edits, or other worker changes performed.

Limitations: no native Xcode build or actual iPad/Pencil/physical IME test on
Windows. The source fallback is deliberate for unsupported Markdown extensions;
rich adjacent merging is for ordinary paragraphs. Synthetic composition events
verify save suppression, not OS input behavior. Native compact toolbar, zoom,
accessibility, performance, file-save conflict/export/archive are integration/
device acceptance. Independent review remains I/root responsibility.
