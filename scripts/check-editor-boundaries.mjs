import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidence = resolve(root, process.env.MDNOTE_EVIDENCE_DIR || ".omo/evidence/editor-boundaries");
const { loadOmowright } = await import(pathToFileURL(process.env.MDNOTE_OMOWRIGHT_LOADER).href);
const { omowright } = await loadOmowright();
mkdirSync(evidence, { recursive: true });
const profile = mkdtempSync(join(evidence, "chrome-profile-"));
const results = [];
let browser;
function check(name, condition) {
  results.push({ name, passed: !!condition });
  assert.ok(condition, name);
}
try {
  browser = await omowright.connectPipe({
    browserPath: process.env.MDNOTE_CHROME,
    browserArgs: ["--headless", "--no-first-run", `--user-data-dir=${profile}`, "--window-size=1390,1000"],
    storageRoot: profile,
  });
  const page = await browser.newTab(pathToFileURL(resolve(root, "MDNote/Resources/WebAssets/index.html")).href);
  await page.evaluate(() => {
    MDNote.render("Hello world\n\nTail\n", [{ blockID: "adapter-paragraph" }, { blockID: "adapter-tail" }], true);
    window.boundaryEvents = [];
    addEventListener("mdnote:documentEdited", event => boundaryEvents.push(event.detail));
  });
  const layout = await page.evaluate(() => MDNote.layout());
  writeFileSync(join(evidence, "layout-adapter-fixture.json"), JSON.stringify(layout, null, 2));
  check("actual JS layout emits stable identities for the native adapter fixture",
    layout.map(block => block.blockID).join(",") === "adapter-paragraph,adapter-tail");

  for (const fixture of [
    { name: "shortcut link", source: "Read [guide] here.\n\n[guide]: https://example.org\n",
      expected: "Read [guide] here.!\n\n[guide]: https://example.org\n", selector: "a", attribute: "href", target: "https://example.org" },
    { name: "shortcut image", source: "![image]\n\n[image]: images/photo.png\n",
      expected: "![image]!\n\n[image]: images/photo.png\n", selector: "img", attribute: "src", target: "images/photo.png" },
  ]) {
    await page.evaluate(source => { MDNote.setTextEditing(false); MDNote.render(source); MDNote.setTextEditing(true); }, fixture.source);
    await page.click("#content p");
    const fallback = await page.evaluate(() => !!document.querySelector(".source-editor textarea"));
    check(`${fixture.name} requires source-preserving editor`, fallback);
    await page.keyboard.press("Control+Home");
    await page.keyboard.press("End");
    await page.keyboard.type("!");
    await page.click(".source-editor button");
    check(`${fixture.name} Apply preserves exact source and reference definition`,
      await page.evaluate(() => MDNote.flushEditor().markdown) === fixture.expected);
    check(`${fixture.name} remains rendered after unrelated keyboard insertion`,
      await page.evaluate(({ selector, attribute, target }) =>
        document.querySelector(`#content ${selector}`)?.getAttribute(attribute)?.endsWith(target), fixture));
  }

  for (const fixture of [
    { name: "English softbreak", source: "First line\nsecond line\n", quote: "second" },
    { name: "Korean Unicode softbreak", source: "첫 줄 👩‍💻\n둘째 e\u0301 문장\n", quote: "둘째" },
    { name: "multiple softbreaks", source: "첫 줄\nmiddle 👩‍💻\nlast line\n", quote: "middle 👩‍💻" },
  ]) {
    await page.evaluate(source => {
      MDNote.setTextEditing(false);
      MDNote.render(source, [{ blockID: "softbreak-target" }], true);
      boundaryEvents = [];
      MDNote.setTextEditing(true);
    }, fixture.source);
    const before = await page.evaluate(quote => {
      const text = MDNote.layout()[0].rangeText;
      const start = text.indexOf(quote);
      return { text, anchor: { blockID: "softbreak-target", startUTF16: start, endUTF16: start + quote.length,
        quote, prefix: "", suffix: "" } };
    }, fixture.quote);
    await page.click("#content p");
    check(`${fixture.name} still uses a rendered rich editor`, await page.evaluate(() => !!document.querySelector(".ProseMirror")));
    check(`${fixture.name} entering editor preserves range coordinate text`,
      await page.evaluate(() => MDNote.layout()[0].rangeText) === before.text);
    await page.keyboard.press("Control+End");
    await page.keyboard.type("!");
    const events = await page.evaluate(() => boundaryEvents);
    writeFileSync(join(evidence, fixture.name.replaceAll(" ", "-") + "-events.json"), JSON.stringify(events, null, 2));
    const edits = events.flatMap(event => event.edits);
    check(`${fixture.name} emitted map is only the actual append, never a target deletion`,
      edits.length === 1 && edits[0].oldText === before.text && edits[0].startUTF16 === before.text.length &&
      edits[0].endUTF16 === before.text.length && edits[0].insertedText === "!");
    check(`${fixture.name} untouched annotation still resolves at original UTF16 range`,
      await page.evaluate(anchor => {
        const geometry = MDNote.rangeGeometry(anchor);
        return geometry.status === "attached" && geometry.rects.length > 0 &&
          geometry.range.startUTF16 === anchor.startUTF16 && geometry.range.endUTF16 === anchor.endUTF16;
      }, before.anchor));
    check(`${fixture.name} save preserves soft line breaks`,
      await page.evaluate(() => MDNote.flushEditor().markdown) === fixture.source.replace(/\n$/, "!\n"));
    await page.evaluate(() => MDNote.editorCommand("undo"));
    check(`${fixture.name} undo restores exact original source`, await page.evaluate(() => MDNote.flushEditor().markdown) === fixture.source);
  }
  writeFileSync(join(evidence, "multiline-editor.png"), await page.screenshot());
  console.log(`Editor boundary checks passed: ${results.length}/${results.length}. Evidence: ${evidence}`);
} finally {
  writeFileSync(join(evidence, "results.json"), JSON.stringify(results, null, 2));
  if (browser) await browser.close();
  assert.ok(profile.startsWith(evidence + "\\") || profile.startsWith(evidence + "/"));
  rmSync(profile, { recursive: true, force: true });
}
