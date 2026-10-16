import assert from "node:assert/strict";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const markdownit = require("../MDNote/Resources/WebAssets/vendor/markdown-it.min.js");
const noop = () => {};
globalThis.window = { markdownit };
globalThis.document = {
    body: {}, fonts: null, getElementById: () => ({ textContent: "" }),
    documentElement: { style: { setProperty: noop } },
};
await import("../MDNote/Resources/WebAssets/app/bridge.js");
const sources = window.MDNote.imageSources;
const fixtures = [
    ["inline", "![x](images/image.png)", ["images/image.png"]],
    ["nested-alt", "![outer [inner]](images/nested.png)", ["images/nested.png"]],
    ["deep-parentheses", "![x](images/a(b(c)).png)", ["images/a(b(c)).png"]],
    ["angle-spaces", "![x](<images/a b.png>)", ["images/a%20b.png"]],
    ["encoding", "![x](images/a%20b.png)", ["images/a%20b.png"]],
    ["reference", "![x][photo]\n\n[photo]: <images/a b.png>", ["images/a%20b.png"]],
    ["collapsed", "![photo][]\n\n[photo]: images/photo.png", ["images/photo.png"]],
    ["shortcut", "![photo]\n\n[photo]: images/photo.png", ["images/photo.png"]],
    ["code", "```md\n![x](secret.png)\n```\n`![x](private.png)`", []],
    ["raw-html-disabled", '<img src="secret.png">', []],
    ["unused-definition", "[unused]: private.png", []],
    ["frontmatter", "---\nimage: '![x](private.png)'\n---\n![x](real.png)", ["real.png"]],
    ["image-alt-inner-image", "![![inner](private.png)](outer.png)", ["outer.png"]],
    ["entities", "![x](images/a&amp;b.png)", ["images/a&b.png"]],
];
for (const [name, markdown, expected] of fixtures) assert.deepEqual(sources(markdown), expected, name);
console.log(`PASS: ${fixtures.length} fixtures execute the real bridge.imageSources and bundled markdown-it parser, including deeply nested destinations/alt text, references, code, raw HTML and front matter.`);
console.log("LIMITATION: Native Swift/WebKit transport and ZIP roundtrip require Xcode execution.");
