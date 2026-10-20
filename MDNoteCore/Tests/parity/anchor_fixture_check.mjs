import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const fixtures = JSON.parse(readFileSync(new URL("../Fixtures/anchor-utf16.json", import.meta.url), "utf8"));
const segmenter = new Intl.Segmenter("ko", { granularity: "grapheme" });
let checks = 0;
for (const fixture of fixtures) {
  const boundaries = new Set([...segmenter.segment(fixture.text)].map(part => part.index));
  boundaries.add(fixture.text.length);
  for (const offset of fixture.validBoundaries) {
    assert.ok(boundaries.has(offset), `Expected boundary ${offset} in ${fixture.text}`);
    checks++;
  }
  for (const offset of fixture.invalidBoundaries) {
    assert.ok(!boundaries.has(offset), `Unexpected boundary ${offset} in ${fixture.text}`);
    checks++;
  }
}
console.log(`PASS: ${fixtures.length} shared Unicode fixtures, ${checks} UTF16 boundary assertions using Intl.Segmenter.`);
console.log("Swift implementation is checked by StableAnnotationTests.testSharedUTF16Fixtures on macOS; this invocation does not execute Swift.");
