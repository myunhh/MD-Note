import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const read = path => readFileSync(fileURLToPath(new URL(`../${path}`, import.meta.url)), "utf8");
const source = read("MDNote/Core/NoteArchive.swift");
const patterns = [...source.matchAll(/(#+)"(.*?)"\1/g)].map(match => match[2]);
const unescape = patterns.find(pattern => pattern.startsWith("\\\\(["));
assert.equal("images/a\\ b.png".replace(new RegExp(unescape, "g"), "$1"), "images/a b.png");
assert.match(read("project.yml"), /ZIPFoundation:\s+url: https:\/\/github.com\/weichsel\/ZIPFoundation.git\s+exactVersion: 0.9.20/);
for (const key of [...source.matchAll(/= "(archive\w+)"/g)].map(match => match[1])) {
    for (const language of ["en", "ko"]) assert.ok(read(`MDNote/Resources/Localization/${language}.lproj/Localizable.strings`).includes(`"${key}" = `));
}
console.log("PASS: export path-unescape fixture, dependency pin, and archive error localization contracts.");
console.log("LIMITATION: JavaScript regex compatibility checks do not execute Swift, Foundation, ZIPFoundation, or UIKit. Native XCTest remains required.");
