import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidence = resolve(root, process.env.MDNOTE_EVIDENCE_DIR || ".omo/evidence/document-search");
assert.ok(process.env.MDNOTE_OMOWRIGHT_LOADER, "Set MDNOTE_OMOWRIGHT_LOADER to the installed browser skill's scripts/omowright.mjs");
assert.ok(process.env.MDNOTE_CHROME, "Set MDNOTE_CHROME to Chrome's executable");
const { loadOmowright } = await import(pathToFileURL(process.env.MDNOTE_OMOWRIGHT_LOADER).href);
const { omowright } = await loadOmowright();
mkdirSync(evidence, { recursive: true });
const profile = mkdtempSync(join(evidence, "chrome-profile-"));
let browser;
try {
  browser = await omowright.connectPipe({
    browserPath: process.env.MDNOTE_CHROME,
    browserArgs: ["--headless", "--no-first-run", `--user-data-dir=${profile}`, "--window-size=1390,1000"],
    storageRoot: profile,
  });
  const page = await browser.newTab(pathToFileURL(resolve(root, "MDNote/Resources/WebAssets/index.html")).href);
  const results = await page.evaluate(() => {
    const cases = [];
    function check(name, condition) {
      cases.push({ name, passed: !!condition });
      if (!condition) throw new Error(name);
    }
    let revision = 0;
    const find = (query, index = 0) => MDNote.search(query, index, ++revision);
    const markdown = '# Search fixture\n\nAlpha **beta** ALPHA 한글 한글\n\n`[.*+?^${}()|\\] <tag> &`\n\nİx xx\n\n' + 'filler paragraph\n\n'.repeat(20) + 'alpha ending';
    MDNote.render(markdown);
    const before = JSON.stringify(MDNote.layout());
    const html = document.getElementById('content').innerHTML;
    const height = MDNote.contentHeight();
    check('case insensitive count', find('aLpHa').count === 3);
    check('next wrap', find('alpha', 3).index === 0);
    check('previous wrap', find('alpha', -1).index === 2);
    check('native navigation coordinate returned without web scroll', find('alpha', 2).y > 500 && window.scrollY === 0);
    check('across inline text nodes', find('Alpha beta').count === 1);
    check('Korean matches', find('한글').count === 2);
    check('literal regex metacharacters', find('[.*+?^${}()|\\]').count === 1);
    check('literal HTML metacharacters', find('<tag> &').count === 1);
    check('Unicode offset after expanding lowercase character', find('xx').count === 1);
    check('no matches', find('absent').count === 0);
    find('alpha');
    const active = CSS.highlights.get('document-search-active');
    check('CSS Highlight holds matching range', active && [...active][0].toString() === 'Alpha');
    check('stale request ignored', MDNote.search('absent', 0, revision - 1).count === 3);
    check('hash geometry parity during highlights', JSON.stringify(MDNote.layout()) === before);
    check('source DOM unchanged during highlights', document.getElementById('content').innerHTML === html);
    check('height unchanged during highlights', MDNote.contentHeight() === height);
    find('');
    check('clear removes CSS highlights', !CSS.highlights.has('document-search') && !CSS.highlights.has('document-search-active'));
    const highlight = window.Highlight;
    window.Highlight = undefined;
    find('alpha', 1);
    check('fallback contains active paint', document.querySelectorAll('#document-search-overlay .search-active').length > 0);
    check('fallback excluded from content and accessibility', !document.querySelector('#content #document-search-overlay') && document.getElementById('document-search-overlay').getAttribute('aria-hidden') === 'true');
    check('fallback preserves hash geometry and height', JSON.stringify(MDNote.layout()) === before && MDNote.contentHeight() === height);
    find('');
    check('clear removes fallback', !document.getElementById('document-search-overlay'));
    window.Highlight = highlight;
    find('alpha');
    MDNote.render('alpha replacement');
    check('rerender reapplies query to new DOM', CSS.highlights.get('document-search').size === 1 && [...CSS.highlights.get('document-search')][0].toString() === 'alpha');
    MDNote.render('removed result');
    check('rerender clears missing matches', !CSS.highlights.has('document-search'));
    MDNote.render('');
    check('empty document', find('alpha').count === 0);
    MDNote.render('first  \nsecond\n\nthird\n\nfourth');
    check('hard line breaks do not concatenate words', find('firstsecond').count === 0);
    check('paragraph boundaries do not concatenate words', find('thirdfourth').count === 0);
    MDNote.render('🦊 café CAFÉ `";window.injected=true;//`');
    check('astral and accented text', find('🦊').count === 1 && find('café').count === 2);
    check('query treated only as literal text', find('";window.injected=true;//').count === 1 && window.injected === undefined);
    MDNote.render('alpha\n\nalpha');
    window.Highlight = undefined;
    find('alpha', 1);
    MDNote.setTextScale(1.4);
    const scaled = JSON.stringify(MDNote.layout());
    find('alpha', 1);
    const painted = document.querySelector('#document-search-overlay .search-active');
    check('fallback refresh after text scaling', JSON.stringify(MDNote.layout()) === scaled && Math.abs(parseFloat(painted.style.top) - MDNote.search('alpha', 1, ++revision).y) < 1);
    MDNote.setTextScale(1);
    window.Highlight = highlight;
    MDNote.render(markdown);
    find('alpha', 1);
    return cases;
  });
  writeFileSync(join(evidence, "dom-results.json"), JSON.stringify(results, null, 2));
  writeFileSync(join(evidence, "highlight.png"), await page.screenshot());
  await page.evaluate(() => { window.Highlight = undefined; MDNote.search('alpha', 1, 10000); });
  writeFileSync(join(evidence, "fallback.png"), await page.screenshot());
  assert.ok(results.every(result => result.passed));
  console.log(`Document search real DOM checks passed: ${results.length}/${results.length}. Evidence: ${evidence}`);
} finally {
  if (browser) await browser.close();
  assert.ok(profile.startsWith(evidence + '\\') || profile.startsWith(evidence + '/'));
  rmSync(profile, { recursive: true, force: true });
}
