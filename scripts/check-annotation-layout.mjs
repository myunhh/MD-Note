import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidence = resolve(root, process.env.MDNOTE_EVIDENCE_DIR || ".omo/evidence/annotation-layout");
assert.ok(process.env.MDNOTE_OMOWRIGHT_LOADER, "Set MDNOTE_OMOWRIGHT_LOADER");
assert.ok(process.env.MDNOTE_CHROME, "Set MDNOTE_CHROME");
const { loadOmowright } = await import(pathToFileURL(process.env.MDNOTE_OMOWRIGHT_LOADER).href);
const { omowright } = await loadOmowright();
mkdirSync(evidence, { recursive: true });
const profile = mkdtempSync(join(evidence, "chrome-profile-"));
let browser;
try {
  browser = await omowright.connectPipe({
    browserPath: process.env.MDNOTE_CHROME,
    browserArgs: ["--headless", "--no-first-run", `--user-data-dir=${profile}`, "--window-size=1440,1000"],
    storageRoot: profile,
  });
  const fixture = join(evidence, "fixture.html");
  const moduleSource = readFileSync(join(root, "MDNote/Resources/WebAssets/app/annotation-layout.js"), "utf8");
  writeFileSync(fixture, `<!doctype html><meta charset="utf-8"><title>Annotation layout regression</title>
    <style>body{font:20px/1.6 system-ui;margin:32px}main{width:600px}section{background:#e8edf2}p{margin:16px 0}
    .projection{position:absolute;background:#ffd76866;pointer-events:none}</style>
    <main id="content"><p data-block-id="alpha" data-block-hash="legacy" data-block-seq="2" data-source-line="0">A <strong>stable range</strong> follows this long paragraph across multiple lines when the page is narrow. Korean 한글 and emoji 👨‍👩‍👧‍👦 remain intact.</p>
    <p data-block-id="lower">Following content remains below inserted writing space.</p>
    <p data-block-id="math"><span class="katex"><span class="katex-mathml">x^2</span><span>x²</span></span></p>
    <p data-block-id="image"><img width="80" height="40" alt="diagram" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='80' height='40'%3E%3Crect width='80' height='40' fill='gray'/%3E%3C/svg%3E"></p></main>
    <script>${moduleSource}</script>`);
  const page = await browser.newTab(pathToFileURL(fixture).href);
  const results = await page.evaluate(() => {
    const api = MDNoteAnnotationLayout, root = document.querySelector("main"), cases = [];
    function check(name, ok, observed) { cases.push({ name, passed: !!ok, observed }); }
    const snapshot = api.snapshot(root);
    check("legacy identity retained", snapshot[0].blockHash === "legacy" && snapshot[0].blockSeq === 2);
    const text = snapshot[0].rangeText;
    const anchor = { blockID: "alpha", startUTF16: 0, endUTF16: text.length, quote: text };
    const wide = api.rangeGeometry(root, anchor);
    root.style.width = "260px";
    const narrow = api.rangeGeometry(root, anchor);
    check("multiline range reflows", narrow.rects.length > wide.rects.length, { wide: wide.rects.length, narrow: narrow.rects.length });
    root.style.fontSize = "28px";
    const scaled = api.rangeGeometry(root, anchor);
    check("text scale reflows fragments", scaled.rects.length > narrow.rects.length, scaled.rects.length);
    root.style.fontSize = "";
    const highlight = api.project(root, { anchor, behavior: "highlight" });
    const underline = api.project(root, { anchor, behavior: "underline" });
    check("underline and highlight map every line", highlight.fragments.length === narrow.rects.length && underline.fragments.every((r, i) => r.y === narrow.rects[i].y + narrow.rects[i].height));
    const before = api.snapshot(root).find(b => b.blockID === "lower");
    const ink = { anchor: { blockID: "lower" }, behavior: "rigid", originalBounds: before, originalPoints: [{ x: before.x + 5, y: before.y + 7, pressure: .6 }] };
    const original = JSON.stringify(ink);
    const studies = [{ id: "blank", afterBlockID: "alpha", kind: "blank", height: 160, order: 0, placement: "flow" }];
    api.applyInsertions(root, studies);
    const after = api.snapshot(root).find(b => b.blockID === "lower");
    check("blank insertion reserves height", after.y - before.y >= 160, after.y - before.y);
    check("blank is ink target", api.snapshot(root).some(b => b.blockID === "blank" && b.height >= 160));
    const placed = api.project(root, ink);
    for (let i = 0; i < 20; i++) { api.applyInsertions(root, studies); api.project(root, ink); }
    check("repeated placement has zero accumulated drift", JSON.stringify(placed) === JSON.stringify(api.project(root, ink)) && JSON.stringify(ink) === original);
    check("rigid shape and pressure preserved", placed.points[0].x === ink.originalPoints[0].x && placed.points[0].y - ink.originalPoints[0].y === after.y - before.y && placed.points[0].pressure === .6);
    api.applyInsertions(root, [{ ...studies[0], height: 240 }]);
    check("resize pushes downstream by delta", api.snapshot(root).find(b => b.blockID === "lower").y - after.y === 80);
    api.applyInsertions(root, []);
    check("removal restores downstream geometry", api.snapshot(root).find(b => b.blockID === "lower").y === before.y);
    const render = () => "<p>Supplement text</p><p>Second block</p>";
    const supplements = [{ ...studies[0], id: "supplement", kind: "markdown", markdown: "fixture" }];
    api.applyInsertions(root, supplements, render);
    const childIDs = api.snapshot(root).filter(b => b.studyID === "supplement").map(b => b.blockID);
    api.applyInsertions(root, supplements, render);
    check("supplement blocks identifiable across reopen", childIDs.length === 3 && JSON.stringify(childIDs) === JSON.stringify(api.snapshot(root).filter(b => b.studyID === "supplement").map(b => b.blockID)));
    api.applyInsertions(root, [{ ...supplements[0], blockIDs: ["persisted-child"] }], (markdown, item) => '<p data-block-id="' + item.blockIDs[0] + '">Edited supplement</p>');
    check("renderer receives persisted supplement block IDs", api.snapshot(root).some(b => b.blockID === "persisted-child"));
    api.applyInsertions(root, [{ ...studies[0], afterBlockID: "lower" }]);
    check("move follows selected boundary", document.querySelector("[data-block-id=lower]").nextElementSibling.dataset.studyId === "blank");
    api.applyInsertions(root, [{ ...studies[0], afterBlockID: null }]);
    check("null boundary inserts at start", root.firstElementChild.dataset.studyId === "blank");
    const emojiText = "a👨‍👩‍👧‍👦e\u0301한";
    check("UTF16 splits inside emoji rejected", api.resolveRange(emojiText, { startUTF16: 2, endUTF16: 3 }).status === "detached");
    check("combining grapheme splits rejected", api.resolveRange(emojiText, { startUTF16: 12, endUTF16: 13 }).status === "detached");
    check("whole emoji grapheme accepted", api.resolveRange(emojiText, { startUTF16: 1, endUTF16: 12 }).status === "attached");
    check("unique edited quote reattaches", api.resolveRange("new hello world", { startUTF16: 0, endUTF16: 5, quote: "hello" }).range.startUTF16 === 4);
    check("ambiguous quote preserved detached", api.resolveRange("hello hello", { startUTF16: 2, endUTF16: 7, quote: "hello" }).status === "ambiguous");
    check("deleted quote preserved detached", api.resolveRange("gone", { startUTF16: 0, endUTF16: 5, quote: "hello" }).status === "detached");
    check("rigid range deletion detaches without losing originals", api.project(root, { ...ink, anchor: { blockID: "lower", quote: "deleted text", startUTF16: 0, endUTF16: 12 } }).status === "detached" && JSON.stringify(ink) === original);
    check("math and image retain rigid targets", ["math", "image"].every(id => api.project(root, { anchor: { blockID: id }, originalBounds: { x: 0, y: 0 } }).status === "attached"));
    check("math range refuses glyph/source mismatch", api.rangeGeometry(root, { blockID: "math", startUTF16: 0, endUTF16: 1 }).reason === "atomic-content");
    const duplicate = root.querySelector("[data-block-id=lower]").cloneNode(true);
    root.appendChild(duplicate);
    check("duplicate block IDs ambiguous", api.project(root, ink).status === "ambiguous");
    duplicate.remove();
    root.querySelector("[data-block-id=lower]").remove();
    check("deleted rigid target preserves original", api.project(root, ink).status === "detached" && JSON.stringify(ink) === original);
    api.applyInsertions(root, [{ ...studies[0], afterBlockID: "deleted" }]);
    check("missing insertion boundary preserved visibly", document.querySelector("[data-study-id=blank]").dataset.anchorStatus === "detached");
    const old = root.innerHTML;
    let rejected = false;
    try { api.applyInsertions(root, [studies[0], studies[0]]); } catch { rejected = true; }
    check("invalid insertions do not mutate live content", rejected && old === root.innerHTML);
    api.applyInsertions(root, studies);
    for (const r of api.project(root, { anchor, behavior: "highlight" }).fragments) {
      const mark = document.createElement("div"); mark.className = "projection";
      Object.assign(mark.style, { left: r.x + "px", top: r.y + "px", width: r.width + "px", height: r.height + "px" });
      document.body.appendChild(mark);
    }
    return cases;
  });
  writeFileSync(join(evidence, "dom-results.json"), JSON.stringify(results, null, 2));
  writeFileSync(join(evidence, "narrow-highlight.png"), await page.screenshot());
  assert.ok(results.every(result => result.passed), JSON.stringify(results.filter(result => !result.passed)));
  console.log(`Annotation layout real DOM checks passed: ${results.length}/${results.length}. Evidence: ${evidence}`);
} finally {
  if (browser) await browser.close();
  assert.ok(profile.startsWith(evidence + "\\") || profile.startsWith(evidence + "/"));
  rmSync(profile, { recursive: true, force: true });
}
