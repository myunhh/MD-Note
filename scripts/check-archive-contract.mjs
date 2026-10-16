import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const read = path => readFileSync(fileURLToPath(new URL(`../${path}`, import.meta.url)), "utf8");
const source = read("MDNote/Core/NoteArchive.swift");
const patterns = [...source.matchAll(/(#+)"(.*?)"\1/g)].map(match => match[2]);
const inline = patterns.find(pattern => pattern.startsWith("!\\[(?:"));
const reference = patterns.find(pattern => pattern.startsWith("!\\[([^"));
const definition = patterns.find(pattern => pattern.startsWith("^ {0,3}"));
for (const pattern of patterns) new RegExp(pattern.replace(/\(\?[is]\)/g, ""), "gms");
const captures = (pattern, text, flags = "gm") => [...text.matchAll(new RegExp(pattern, flags))];
assert.equal(captures(inline, "![x](images/a%20b.png)")[0][1], "images/a%20b.png");
assert.equal(captures(inline, "![x](images/a b.png)")[0][1], "images/a b.png");
assert.equal(captures(inline, "![x](<images/a b.png> \"caption\")")[0][1], '<images/a b.png> "caption"');
assert.equal(captures(inline, "![x](images/a(b).png)")[0][1], "images/a(b).png");
assert.equal(captures(reference, "![alt][photo]")[0][2], "photo");
assert.equal(captures(reference, "![photo][]")[0][1], "photo");
assert.equal(captures(reference, "![short]")[0][1], "short");
assert.equal(captures(reference, "![x](images/image.png)").length, 0);
assert.equal(captures(definition, "[photo]: <images/a b.png>")[0][2], "<images/a b.png>");
const unescape = patterns.find(pattern => pattern.startsWith("\\\\(["));
assert.equal("images/a\\ b.png".replace(new RegExp(unescape, "g"), "$1"), "images/a b.png");
assert.match(read("project.yml"), /ZIPFoundation:\s+url: https:\/\/github.com\/weichsel\/ZIPFoundation.git\s+exactVersion: 0.9.20/);
assert.match(read("MDNote/App/LibraryView.swift"), /\.plainText, \.text, \.zip/);
for (const key of [...source.matchAll(/= "(archive\w+)"/g)].map(match => match[1])) {
    for (const language of ["en", "ko"]) assert.ok(read(`MDNote/Resources/Localization/${language}.lproj/Localizable.strings`).includes(`"${key}" = `));
}
console.log("PASS: 10 import image-pattern fixtures extracted from Swift source; dependency pin, ZIP picker, archive error localization contracts.");
console.log("LIMITATION: JavaScript regex compatibility checks do not execute Swift, Foundation, ZIPFoundation, or UIKit. Native XCTest remains required.");
