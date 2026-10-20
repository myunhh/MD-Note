import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

function entries(source) {
  return new Map([...source.matchAll(/^"([^"]+)" = ("(?:[^"\\]|\\.)*");$/gm)]
    .map(([, key, value]) => [key, JSON.parse(value)]));
}
for (const language of ['en', 'ko']) {
  const path = `MDNote/Resources/Localization/${language}.lproj/Localizable.strings`;
  const stage = number => entries(execFileSync('git', ['show', `:${number}:${path}`], { encoding: 'utf8' }));
  const base = stage(1), ours = stage(2), theirs = stage(3);
  const source = readFileSync(path, 'utf8').replaceAll('\r\n', '\n');
  assert.doesNotMatch(source, /^(<<<<<<<|=======|>>>>>>>)/m);
  const actual = entries(source);
  const union = new Set([...ours.keys(), ...theirs.keys()]);
  for (const key of union) {
    const old = base.get(key), left = ours.get(key), right = theirs.get(key);
    const expected = left === old ? right : right === old || left === right ? left : undefined;
    assert.notEqual(expected, undefined, `Unresolved value selection ${language}/${key}`);
    assert.equal(actual.get(key), expected, `${language}/${key}`);
  }
  assert.equal(actual.size, union.size);
  console.log(`PASS ${language}: all ${actual.size} union keys retain exact three-way merge values, including intentional archive label changes.`);
}
