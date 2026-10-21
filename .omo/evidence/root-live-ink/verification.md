# Leader browser smoke

Reviewed source commit: `310933ac01b671ce98e803eac1181e355a6d1a62`.

PASS: 12/12 combined real browser assertions. Executed `node .omo/evidence/root-live-ink/smoke.mjs` on Node v24.19.0 with the installed omowright loader and a task-owned headless Chrome profile. Tracked files were clean before and after; HEAD stayed identical. Exact assertions and reviewed SHA are in `results.json`; actual composed-page screenshot is `composed-page.png`.

Covered offline editor/layout availability; blank insertion reserves height and has ink identity; insertion undo restores geometry; actual keyboard editing preserves CRLF/frontmatter and untouched source; editor emits stable-ID UTF16 old-text maps; rendered selection creates text anchor; narrow text wraps that range into multiple underline fragments; repeated projection has no drift; supplement state restores with stable child ID; main Markdown remains separate; existing search still works; no browser runtime errors during the combined flow.

This is browser editor/event/layout verification, not native WebKit/PencilKit drawing, native disk persistence, or Xcode compilation. User explicitly owns Mac/iPad acceptance. The earlier interim run and clean `9e03057263b6c6024652019b94722ed681885745` run are superseded by this repaired clean-commit run; the old commit was rejected by the independent review for additional uncovered issues.

Root visually inspected the composed page capture and the earlier C line-fragment fixture. No screenshot is represented as an actual iPad/Pencil capture.
