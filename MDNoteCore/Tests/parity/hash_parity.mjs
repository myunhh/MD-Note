// Cross-language tripwire for invariant #3: run the REAL bridge.js fnv1a +
// normalize + blockHash over the SAME golden table asserted in
// HashParityTests.swift. Exits non-zero on any mismatch so a JS-side drift
// (a "tidied" whitespace split, a changed FNV constant, a blockIdentityText
// regression) fails loudly before it can silently detach saved ink.
//
//   node MDNoteCore/Tests/parity/hash_parity.mjs
//
// Keep these hex values identical to HashParityTests.golden. The duplication is
// the point: both languages must independently reproduce the frozen value.

const GOLDEN = [
  ["empty", "", "cbf29ce484222325"],
  ["single", "a", "af63dc4c8601ec8c"],
  ["wrapped-whitespace", "The  quick\nbrown   fox", "2374316b9b449782"],
  ["nbsp-is-content", " a b ", "7eceb45d77cb6896"],
  ["crlf-grapheme", "line\r\nline", "71a1002c25fbdf27"],
  ["tab", "a\tb c", "69cf480885ad45af"],
  ["emoji-accent", "café 🦊", "684bc87c3c68e35a"],
  ["hangul", "한글  글자\ttest", "d511b87bfe331621"],
];

// Minimal DOM/markdown-it shim so the bridge.js IIFE can load headlessly. It
// only needs enough to reach the `window.MDNote` export; the hashing functions
// are pure (TextEncoder is a Node global).
const noop = () => {};
globalThis.window = {
  markdownit: () => ({ core: { ruler: { push: noop } }, render: () => "" }),
};
globalThis.document = {
  body: {},
  fonts: null,
  getElementById: () => ({ textContent: "" }),
  documentElement: { style: { setProperty: noop } },
};

const bridgeURL = new URL("../../../MDNote/Resources/WebAssets/app/bridge.js", import.meta.url);
await import(bridgeURL.href);

const MDNote = globalThis.window.MDNote;
if (!MDNote || typeof MDNote.blockHash !== "function") {
  console.error("FAIL: bridge.js did not export MDNote.blockHash");
  process.exit(1);
}

let failures = 0;
for (const [label, input, expected] of GOLDEN) {
  const got = MDNote.blockHash(input);
  if (got !== expected) {
    failures++;
    console.error(`FAIL [${label}]: expected ${expected}, got ${got}`);
  }
}

if (failures > 0) {
  console.error(`\nhash parity: ${failures}/${GOLDEN.length} cases drifted — invariant #3 broken.`);
  process.exit(1);
}
console.log(`hash parity OK: ${GOLDEN.length}/${GOLDEN.length} cases match Swift golden values.`);
