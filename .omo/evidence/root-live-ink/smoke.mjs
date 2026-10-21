import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";

const evidence = dirname(fileURLToPath(import.meta.url));
const root = resolve(evidence, "../../..");
const sha = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
const { loadOmowright } = await import(pathToFileURL(process.env.MDNOTE_OMOWRIGHT_LOADER).href);
const { omowright } = await loadOmowright();
mkdirSync(evidence, { recursive: true });
const profile = mkdtempSync(join(evidence, "chrome-profile-"));
const checks = [];
let browser;
async function check(name, observed) {
  checks.push({ name, passed: Boolean(observed) });
  assert.ok(observed, name);
}
try {
  browser = await omowright.connectPipe({
    browserPath: process.env.MDNOTE_CHROME,
    browserArgs: ["--headless", "--no-first-run", `--user-data-dir=${profile}`, "--window-size=1390,1000"],
    storageRoot: profile,
  });
  const page = await browser.newTab(pathToFileURL(resolve(root, "MDNote/Resources/WebAssets/index.html")).href);
  const phrase = "target passage tracks the original concept across several wrapped lines";
  const markdown = `---\r\ntitle: preserve\r\n---\r\n\r\n# Study\r\n\r\nThe **${phrase}** without losing its meaning.\r\n\r\nTail paragraph.\r\n`;
  await page.evaluate(source => {
    window.rootEdits = [];
    window.rootStudies = [];
    window.rootErrors = [];
    addEventListener("error", e => rootErrors.push(e.message));
    addEventListener("unhandledrejection", e => rootErrors.push(String(e.reason)));
    addEventListener("mdnote:documentEdited", e => rootEdits.push(e.detail));
    addEventListener("mdnote:studyInsertionsChanged", e => { rootStudies = structuredClone(e.detail); });
    MDNote.render(source, [{ blockID: "heading" }, { blockID: "target" }, { blockID: "tail" }], true);
  }, markdown);
  await check("offline editor and geometry globals available", await page.evaluate(() => Boolean(MDNote.flushEditor && MDNoteAnnotationLayout.project)));
  const initialY = await page.evaluate(() => MDNote.layout().find(b => b.blockID === "target").y);
  await page.evaluate(() => MDNote.setStudyInsertions([{ id: "blank", afterBlockID: "heading", kind: "blank", markdown: "", height: 200, placement: "flow", order: 0, blockIDs: [] }], true));
  await check("blank insertion shifts existing target and is ink anchor", await page.evaluate(y => {
    const blocks = MDNote.layout();
    return blocks.find(b => b.blockID === "target").y >= y + 200 && blocks.some(b => b.blockID === "blank");
  }, initialY));
  await page.evaluate(() => MDNote.editorCommand("undo"));
  await check("insertion undo restores original target geometry", await page.evaluate(y => Math.abs(MDNote.layout().find(b => b.blockID === "target").y - y) < 1, initialY));
  await page.evaluate(() => MDNote.setTextEditing(true));
  await page.click('[data-block-id="target"]');
  await page.keyboard.press("Home");
  await page.keyboard.type("한글 ");
  const edited = await page.evaluate(() => MDNote.flushEditor());
  await check("actual keyboard edits preserve frontmatter and untouched CRLF source", edited.markdown === markdown.replace("The **", "한글 The **"));
  await check("native edit payload has old text and stable target identity", await page.evaluate(() => rootEdits.some(e => e.edits.some(x => x.blockID === "target" && x.startUTF16 === 0 && x.oldText.startsWith("The target passage")))));
  await page.evaluate(() => MDNote.setTextEditing(false));
  const anchor = await page.evaluate(() => {
    const node = document.querySelector('[data-block-id="target"] strong');
    const range = document.createRange();
    range.selectNodeContents(node);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    return MDNote.selectedTextAnchor();
  });
  await check("rendered selection resolves to target text anchor", anchor.blockID === "target" && anchor.quote === phrase);
  await page.evaluate(() => { document.querySelector('[data-block-id="target"]').style.width = "280px"; });
  const projected = await page.evaluate(a => MDNoteAnnotationLayout.project(document.getElementById("content"), { anchor: a, behavior: "underline" }), anchor);
  await check("same text anchor projects into multiple current wrapped lines", projected.status === "attached" && projected.fragments.length > 1);
  await check("projection has no repeated-layout drift", await page.evaluate(a => {
    const root = document.getElementById("content");
    return JSON.stringify(MDNoteAnnotationLayout.project(root, { anchor: a, behavior: "underline" })) === JSON.stringify(MDNoteAnnotationLayout.project(root, { anchor: a, behavior: "underline" }));
  }, anchor));
  await page.evaluate(() => MDNote.setStudyInsertions([{ id: "study", afterBlockID: "target", kind: "markdown", markdown: "Supplement **note**.", height: 160, placement: "flow", order: 0, blockIDs: ["study-child"] }], true));
  const saved = await page.evaluate(() => ({ source: MDNote.flushEditor().markdown, studies: structuredClone(rootStudies), blocks: MDNote.layout().filter(b => !b.studyID).map(b => ({ blockID: b.blockID, hash: b.blockHash, text: b.text })) }));
  await page.evaluate(s => { MDNote.render(s.source, s.blocks, true); MDNote.setStudyInsertions(s.studies, false); }, saved);
  await check("composed page restore retains supplement and stable child ID", await page.evaluate(() => document.querySelector('[data-block-id="study-child"]').textContent === "Supplement note."));
  await check("main Markdown stays separate from supplemental Markdown", saved.source === edited.markdown && !saved.source.includes("Supplement"));
  await check("restored source search remains functional", await page.evaluate(() => MDNote.search("target passage", 0, 1000).count === 1));
  await check("no browser runtime errors during combined smoke", await page.evaluate(() => rootErrors.length === 0));
  writeFileSync(join(evidence, "composed-page.png"), await page.screenshot());
  console.log(`Root browser smoke PASS: ${checks.length}/${checks.length}; SHA ${sha}`);
} finally {
  writeFileSync(join(evidence, "results.json"), JSON.stringify({ sha, checks, limitation: "Browser editor/events/layout only; native WebKit/PencilKit/disk persistence not executed." }, null, 2));
  if (browser) await browser.close();
  assert.ok(profile.startsWith(evidence + "\\") || profile.startsWith(evidence + "/"));
  rmSync(profile, { recursive: true, force: true });
}
