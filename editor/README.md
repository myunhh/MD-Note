# Offline rich editor

`npm ci && npm run build` reproduces `vendor/editor.js` from exact package-lock
versions. The app loads only bundled files. `npm audit` checks the build inputs.
ProseMirror's CommonMark editor is mounted into a selected rendered block.
Untouched source slices, frontmatter and unsupported extensions are retained
byte-for-byte. Unsupported blocks offer an explicit source editor.

The source bundle uses ProseMirror (MIT); package source and license files are
installed by `npm ci`. Bundled dependency licenses are in `vendor/editor-LICENSES.txt`.
Native saves receive only complete, noncomposing document snapshots.
