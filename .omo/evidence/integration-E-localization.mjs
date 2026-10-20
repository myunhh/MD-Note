import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const approvedCopyChanges = new Set(['libraryMetadataFavoritesOnly', 'libraryMetadataFavoritesHint']);
function entries(source) {
  return new Map([...source.matchAll(/^"([^"]+)" = ("(?:[^"\\]|\\.)*");$/gm)]
    .map(([, key, value]) => [key, JSON.parse(value)]));
}
for (const language of ['en', 'ko']) {
  const path = `MDNote/Resources/Localization/${language}.lproj/Localizable.strings`;
  const ours = entries(execFileSync('git', ['show', `:2:${path}`], { encoding: 'utf8' }));
  const theirs = entries(execFileSync('git', ['show', `:3:${path}`], { encoding: 'utf8' }));
  const source = readFileSync(path, 'utf8').replaceAll('\r\n', '\n');
  assert.doesNotMatch(source, /^(<<<<<<<|=======|>>>>>>>)/m);
  const actual = entries(source);
  for (const [key, value] of [...ours, ...theirs]) {
    assert.ok(actual.has(key), `${language}/${key}`);
    if (!approvedCopyChanges.has(key)) assert.equal(actual.get(key), value, `${language}/${key}`);
  }
  assert.equal(actual.size, new Set([...ours.keys(), ...theirs.keys()]).size);
  console.log(`PASS ${language}: all ${actual.size} union keys retained; values unchanged except two authorized scope-copy keys; no markers.`);
}
for (const path of ['MDNote/App/LibraryView.swift', 'MDNote/App/LibrarySearchResultsView.swift']) {
  assert.doesNotMatch(readFileSync(path, 'utf8'), /^(<<<<<<<|=======|>>>>>>>)/m);
  console.log(`PASS no conflict markers: ${path}`);
}
