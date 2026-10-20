import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidence = resolve(root, process.env.MDNOTE_EVIDENCE_DIR || ".omo/evidence/rich-editor");
const { loadOmowright } = await import(pathToFileURL(process.env.MDNOTE_OMOWRIGHT_LOADER).href);
const { omowright } = await loadOmowright();
mkdirSync(evidence, { recursive: true });
const profile = mkdtempSync(join(evidence, "chrome-profile-"));
let browser;
const results = [];
async function check(name, condition) {
  assert.ok(condition, name);
  results.push({ name, passed: true });
}
try {
  browser = await omowright.connectPipe({
    browserPath: process.env.MDNOTE_CHROME,
    browserArgs: ["--headless", "--no-first-run", `--user-data-dir=${profile}`, "--window-size=1390,1000"],
    storageRoot: profile
  });
  const page = await browser.newTab(pathToFileURL(resolve(root, "MDNote/Resources/WebAssets/index.html")).href);
  if (process.env.MDNOTE_LAYOUT_MODULE) {
    await page.evaluate(new Function(readFileSync(process.env.MDNOTE_LAYOUT_MODULE, "utf8")));
  }
  const fixture = "---\r\ntitle: 보존\r\n---\r\n\r\n# Heading\r\n\r\nOriginal **bold** text\r\n\r\n![ref][asset]\r\n\r\n[asset]: image.png\r\n\r\n| A | B |\r\n| - | - |\r\n| 1 | 2 |\r\n";
  await page.evaluate((markdown) => {
    window.editorEvents = [];
    addEventListener("mdnote:documentEdited", event => editorEvents.push(event.detail));
    MDNote.render(markdown);
    MDNote.setTextEditing(true);
  }, fixture);
  await page.click("#content p");
  await page.keyboard.press("End");
  await page.keyboard.type(" 한글");
  await check("real rich DOM keyboard edit", await page.evaluate(() => document.querySelector(".ProseMirror strong").textContent === "bold"));
  const edited = await page.evaluate(() => MDNote.flushEditor().markdown);
  await check("frontmatter CRLF references and table remain exact", edited === fixture.replace("Original **bold** text", "Original **bold** text 한글"));
  await check("text edit DTO includes old UTF16 text", await page.evaluate(() =>
    editorEvents.some(e => e.edits.some(x => x.oldText === "Original bold text" && x.startUTF16 === 18 && x.insertedText === " "))));
  await page.evaluate(() => MDNote.editorCommand("undo"));
  await check("rich undo restores source", (await page.evaluate(() => MDNote.flushEditor().markdown)) === fixture);
  await page.evaluate(() => MDNote.editorCommand("redo"));
  await check("rich redo reapplies source", (await page.evaluate(() => MDNote.flushEditor().markdown)) === edited);
  const composition = await page.evaluate(async () => {
    const el = document.querySelector(".ProseMirror");
    const before = editorEvents.length;
    el.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true, data: "ㅎ" }));
    let blocked = false;
    try { MDNote.flushEditor(); } catch { blocked = true; }
    const count = editorEvents.length;
    const completed = new Promise(resolve => {
      const listener = event => {
        if (!event.detail.composing) {
          removeEventListener("mdnote:editorState", listener);
          resolve();
        }
      };
      addEventListener("mdnote:editorState", listener);
    });
    el.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true, data: "한" }));
    await completed;
    return { blocked, quiet: count === before };
  });
  await check("composition blocks flush and emits no save", composition.blocked && composition.quiet);
  await page.evaluate(() => MDNote.setTextEditing(false));
  await page.evaluate(() => MDNote.setTextEditing(true));
  const tableIdentity = await page.evaluate(() => {
    const table = document.querySelector("#content table");
    return { id: table.dataset.blockId, hash: table.dataset.blockHash, text: table.dataset.blockText };
  });
  await page.click("#content table");
  await check("unsupported table uses deliberate source fallback", await page.evaluate(() => !!document.querySelector(".source-editor textarea")));
  await check("source fallback retains ink target identity and text", await page.evaluate(({ id, hash, text }) =>
    MDNote.layout().some(block => block.blockID === id && block.blockHash === hash && block.text === text), tableIdentity));
  await page.click(".source-editor button:last-child");
  await check("cancel fallback preserves source", (await page.evaluate(() => MDNote.flushEditor().markdown)) === edited);
  await page.evaluate(() => { MDNote.render("First\n\nSecond", [{blockID:"first"}, {blockID:"second"}], true); MDNote.setTextEditing(true); });
  await page.click('[data-block-id="second"]');
  await page.keyboard.press("Home");
  await page.keyboard.press("Backspace");
  await check("Backspace joins adjacent rendered paragraphs", await page.evaluate(() => MDNote.flushEditor().markdown.trim() === "FirstSecond"));
  await check("join emits right-to-left anchor mapping", await page.evaluate(() => editorEvents.some(e => e.mappings.some(m => m.fromBlockID === "second" && m.toBlockID === "first" && m.offsetDeltaUTF16 === 5))));
  await page.keyboard.press("Enter");
  await page.evaluate(() => MDNote.setTextEditing(false));
  await check("split emits segment anchor mapping", await page.evaluate(() => editorEvents.some(e => e.mappings.length === 2 && e.mappings[1].offsetDeltaUTF16 === -5)));
  await check("split retains first stable identity", await page.evaluate(() => MDNote.layout()[0].blockID === "first" && MDNote.layout().length === 2));
  await page.evaluate(() => {
    MDNote.setStudyInsertions([{id:"study",afterBlockID:"first",kind:"markdown",markdown:"Study **bold**",height:160,placement:"flow",order:0,blockIDs:["study-child"]}], true);
    MDNote.setTextEditing(true);
  });
  await page.click('[data-block-id="study-child"]');
  await page.keyboard.press("End");
  await page.keyboard.type(" edited");
  await page.evaluate(() => MDNote.setTextEditing(false));
  await check("supplement remains rendered and keeps child identity after editing", await page.evaluate(() => document.querySelector('[data-block-id="study-child"]').textContent === "Study bold edited"));
  await page.evaluate(() => MDNote.setTextEditing(true));
  await page.click('[data-block-id="study-child"]');
  await page.evaluate(() => MDNote.editorCommand("studyGrow"));
  await check("study resize reserves actual height", await page.evaluate(() => document.querySelector('[data-study-id="study"]').getBoundingClientRect().height >= 240));
  await page.evaluate(() => MDNote.editorCommand("studyRemove"));
  await check("study remove changes layout", await page.evaluate(() => !document.querySelector('[data-study-id="study"]')));
  await page.evaluate(() => MDNote.editorCommand("undo"));
  await check("study undo restores content and identity", await page.evaluate(() => document.querySelector('[data-block-id="study-child"]').textContent === "Study bold edited"));
  await page.evaluate(() => { MDNote.setTextEditing(true); MDNote.editorCommand("newParagraph"); });
  await page.keyboard.type("새 문단");
  await check("new paragraph supports real keyboard input", await page.evaluate(() => MDNote.flushEditor().markdown.includes("새 문단")));
  writeFileSync(join(evidence, "rich-editor.png"), await page.screenshot());
  await page.evaluate(() => {
    MDNote.setTextEditing(false);
    MDNote.render("Before\n\nTarget", [{blockID:"before"}, {blockID:"target"}], true);
    window.savedBlocks = MDNote.layout().map(b => ({blockID:b.blockID,hash:b.blockHash,text:b.text}));
    MDNote.render("New\n\nTarget\n\nBefore", savedBlocks, false);
  });
  await check("external move uses unique identity instead of ordinal", await page.evaluate(() =>
    MDNote.layout()[1].blockID === "target" && MDNote.layout()[2].blockID === "before" && MDNote.layout()[0].blockID !== "before"));
  await page.evaluate(() => MDNote.render("Target\n\nTarget", savedBlocks, false));
  await check("external duplicate refuses ambiguous identity", await page.evaluate(() => MDNote.layout().every(b => b.blockID !== "target")));
  await page.evaluate(() => {
    MDNote.render("Main");
    MDNote.setStudyInsertions([{id:"empty-study",afterBlockID:null,kind:"markdown",markdown:"",height:160,placement:"flow",order:0,blockIDs:[]}], true);
    MDNote.setTextEditing(true);
  });
  await page.click('[data-study-id="empty-study"] p');
  await page.keyboard.type("보충 설명");
  await page.evaluate(() => MDNote.setTextEditing(false));
  await check("new empty supplement accepts rich text", await page.evaluate(() => document.querySelector('[data-study-id="empty-study"]').textContent.trim() === "보충 설명"));
  await check("every layout block decodes legacy required hash fields", await page.evaluate(() => MDNote.layout().every(b => typeof b.blockHash === "string" && Number.isInteger(b.blockSeq))));
  await page.evaluate(() => {
    MDNote.setStudyInsertions([]);
    MDNote.render("_Original_");
    MDNote.setTextEditing(true);
  });
  await page.click("#content p");
  await page.keyboard.press("End");
  await page.keyboard.type(" appended");
  await page.evaluate(() => MDNote.editorCommand("undo"));
  await check("undo restores original noncanonical Markdown bytes", await page.evaluate(() => MDNote.flushEditor().markdown === "_Original_"));
  await page.evaluate(() => { MDNote.setTextEditing(false); MDNote.render("| A |\n| - |\n| B |"); MDNote.setTextEditing(true); });
  await page.click("#content table");
  await page.fill(".source-editor textarea", "| A |\n| - |\n| Changed |");
  await page.click(".source-editor button");
  await check("explicit source apply preserves supported table extension", await page.evaluate(() => MDNote.flushEditor().markdown.includes("| Changed |") && document.querySelector("td").textContent === "Changed"));
  writeFileSync(join(evidence, "source-applied.png"), await page.screenshot());
  await page.evaluate(() => {
    MDNote.render("target text", [{blockID:"range"}], true);
    window.initialHistory = MDNote.flushEditor().historyID;
    MDNote.setTextEditing(true);
  });
  await page.click("#content p");
  await page.keyboard.press("Home");
  await page.keyboard.type("X");
  await check("insertion before target emits exact UTF16 map", await page.evaluate(() => {
    const edit = editorEvents.at(-1).edits[0];
    return edit.blockID === "range" && edit.startUTF16 === 0 && edit.endUTF16 === 0 && edit.insertedText === "X" && edit.oldText === "target text";
  }));
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowRight");
  await page.keyboard.type("Y");
  await check("insertion inside target emits exact UTF16 map", await page.evaluate(() => {
    const edit = editorEvents.at(-1).edits[0];
    return edit.startUTF16 === 3 && edit.endUTF16 === 3 && edit.insertedText === "Y" && edit.oldText === "Xtarget text";
  }));
  await page.evaluate(() => {
    MDNote.editorCommand("undo");
    if (MDNote.flushEditor().markdown !== "target text") MDNote.editorCommand("undo");
  });
  await check("undo returns exact stable history identity", await page.evaluate(() => MDNote.flushEditor().markdown === "target text" && MDNote.flushEditor().historyID === initialHistory));
  await page.evaluate(() => {
    MDNote.setTextEditing(false);
    MDNote.render("First\n\nSecond", [{blockID:"first"}, {blockID:"second"}], true);
    MDNote.setTextEditing(true);
  });
  await page.click('[data-block-id="first"]');
  await page.keyboard.press("End");
  await page.keyboard.press("Delete");
  await check("Delete joins next ordinary paragraph", await page.evaluate(() => MDNote.flushEditor().markdown.trim() === "FirstSecond"));
  await page.keyboard.press("Control+z");
  await check("keyboard undo restores merged paragraph identities", await page.evaluate(() => MDNote.layout().map(b => b.blockID).join(",") === "first,second"));
  await page.evaluate(() => {
    MDNote.setTextEditing(false);
    MDNote.render("Target", [{ blockID: "delete-target" }], true);
    window.beforeDeletion = MDNote.flushEditor().historyID;
    MDNote.setTextEditing(true);
  });
  await page.click("#content p");
  await page.keyboard.press("Control+a");
  await page.keyboard.press("Backspace");
  await check("complete target deletion emits an exact deletion map", await page.evaluate(() => {
    const edit = editorEvents.at(-1).edits[0];
    return edit?.blockID === "delete-target" && edit.oldText === "Target" &&
      edit.startUTF16 === 0 && edit.endUTF16 === 6 && edit.insertedText === "";
  }));
  await page.evaluate(() => MDNote.editorCommand("undo"));
  await check("delete undo restores attachment history key and block identity", await page.evaluate(() =>
    MDNote.flushEditor().historyID === beforeDeletion && MDNote.layout()[0].blockID === "delete-target"));
  await page.evaluate(() => {
    MDNote.setTextEditing(false);
    const node = document.querySelector("#content p").firstChild;
    const range = document.createRange();
    range.selectNodeContents(node);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    window.previewAnchor = MDNote.selectedTextAnchor();
    MDNote.setTextEditing(true);
    MDNote.editorCommand("source");
  });
  await check("source preview retains follow-text range geometry", await page.evaluate(() =>
    MDNote.rangeGeometry(previewAnchor).status === "attached" && MDNote.rangeGeometry(previewAnchor).rects.length > 0));
  writeFileSync(join(evidence, "source-preview.png"), await page.screenshot());
  await page.click(".source-editor button:last-child");
  await check("cancel source preview preserves target source", await page.evaluate(() => MDNote.flushEditor().markdown === "Target"));
  writeFileSync(join(evidence, "events.json"), JSON.stringify(await page.evaluate(() => editorEvents), null, 2));
  writeFileSync(join(evidence, "results.json"), JSON.stringify(results, null, 2));
  console.log(`Rich editor browser checks passed: ${results.length}/${results.length}. Evidence: ${evidence}`);
} finally {
  writeFileSync(join(evidence, "results.json"), JSON.stringify(results, null, 2));
  if (browser) await browser.close();
  assert.ok(profile.startsWith(evidence + "\\") || profile.startsWith(evidence + "/"));
  rmSync(profile, { recursive: true, force: true });
}
