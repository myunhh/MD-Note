import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = path => readFileSync(resolve(root, path), "utf8");
const resourceRoot = "MDNote/Resources/Localization";

function table(language) {
  const source = read(`${resourceRoot}/${language}.lproj/Localizable.strings`);
  const values = new Map();
  for (const line of source.split(/\r?\n/).filter(line => line.trim())) {
    const match = line.match(/^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$/);
    assert.ok(match, `Invalid .strings entry: ${line}`);
    const key = JSON.parse(match[1]);
    assert.ok(!values.has(key), `Duplicate key: ${language}/${key}`);
    values.set(key, JSON.parse(match[2]));
  }
  return values;
}

const en = table("en");
const ko = table("ko");
assert.deepEqual([...en.keys()].sort(), [...ko.keys()].sort());
for (const [key, value] of en) {
  assert.ok(value.trim(), `Empty English value: ${key}`);
  assert.ok(ko.get(key).trim(), `Empty Korean value: ${key}`);
  assert.doesNotMatch(value, /[가-힣]/, `Untranslated English value: ${key}`);
  assert.deepEqual(value.match(/%(?:@|ld)/g) ?? [], ko.get(key).match(/%(?:@|ld)/g) ?? [],
    `Format mismatch: ${key}`);
}
let uses = 0;
for (const directory of ["MDNote/App", "MDNote/Core"]) {
  for (const file of readdirSync(resolve(root, directory)).filter(file => file.endsWith(".swift"))) {
    const source = read(`${directory}/${file}`);
    assert.doesNotMatch(source, /"[^"\n]*[가-힣][^"\n]*"/, `Hardcoded Korean UI in ${file}`);
    for (const match of source.matchAll(/L10n\.(text|format)\("([^"]+)"/g)) {
      assert.ok(en.has(match[2]), `Missing resource: ${file}/${match[2]}`);
      const placeholders = en.get(match[2]).match(/%(?:@|ld)/g) ?? [];
      assert.equal(match[1] === "format", placeholders.length > 0,
        `Wrong lookup method: ${file}/${match[2]}`);
      uses++;
    }
  }
}
assert.match(read("project.yml"), /developmentLanguage: en/);
assert.match(read("project.yml"), /path: MDNote\/Resources\/Localization\s+buildPhase: resources/);
assert.doesNotMatch(read("project.yml"), /path: MDNote\/Resources\/Sample.md/);
for (const language of ["en", "ko"]) {
  const sample = read(`${resourceRoot}/${language}.lproj/Sample.md`);
  assert.ok(sample.trim(), `Empty localized sample: ${language}`);
}
assert.doesNotMatch(read(`${resourceRoot}/en.lproj/Sample.md`), /[가-힣]/);
console.log(`Localization checks passed: ${en.size} bilingual keys, ${uses} Swift lookups, both samples and resource configuration.`);
