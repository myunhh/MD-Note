import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = name => readFileSync(new URL(`../MDNote/Core/${name}.swift`, import.meta.url), "utf8");
const controller = source("DocumentCanvasViewController");
const store = source("InkStore");
const writer = source("MarkdownFileWriter");
const checks = [
  ["save comparison is inside coordinated accessor", () => {
    const accessor = writer.slice(writer.indexOf("coordinate(writingItemAt:"));
    assert.ok(accessor.indexOf("current == expectedText") < accessor.indexOf(".atomic"));
    assert.match(accessor, /throw Failure.externalConflict/);
  }],
  ["read errors cannot become document text", () => {
    assert.match(controller, /text = try MarkdownFileWriter.read\(url\)/);
    assert.doesNotMatch(controller, /\?\? L10n.text\("readFileFailed"\)/);
  }],
  ["self-save baseline advances only after coordinated write", () => {
    const accept = controller.slice(controller.indexOf("private func acceptEditorSnapshot"));
    assert.ok(accept.indexOf("MarkdownFileWriter.write") < accept.indexOf("lastDocHash ="));
  }],
  ["original ink and stable identities survive recapture", () => {
    assert.match(store, /renderedSources\[signature\]/);
    assert.match(store, /originals\[id\]/);
    assert.match(store, /items.append\(item\)/);
    assert.match(store, /InkStrokeIdentity.fingerprint/);
  }],
  ["range projection is separate from original payload", () => {
    const rebuild = store.slice(store.indexOf("func rebuildDrawing"), store.indexOf("// MARK: External edit"));
    assert.match(rebuild, /rangeRects\[item.id\]/);
    assert.doesNotMatch(rebuild, /item.strokeData\s*=/);
  }],
  ["Pencil-down checks guard loading, layout and replacement", () => {
    assert.match(controller, /private func loadAndRender[\s\S]*?guard !isPencilDown/);
    assert.match(controller, /private func remeasureLayout[\s\S]*?guard !isPencilDown/);
    assert.match(controller, /private func replaceCanvasDrawing[\s\S]*?guard !isPencilDown/);
  }],
  ["native edit maps and undo attachments wired", () => {
    assert.match(controller, /snapshot.edits/);
    assert.match(controller, /snapshot.mappings/);
    assert.match(controller, /store.restoreAttachments/);
    assert.match(store, /applyingReplacement/);
    assert.match(store, /anchor.remapped/);
  }],
  ["study persistence and shared editor undo wired", () => {
    assert.match(store, /studyInsertions: studyInsertions/);
    assert.match(controller, /recordUndo: true/);
    assert.match(controller, /store.restoreStudyTargets/);
    assert.doesNotMatch(controller, /studyUndoManager/);
  }],
  ["archive includes supplement asset scan", () => {
    assert.match(controller, /studyInsertions.map\(\\\.markdown\)/);
    assert.match(controller, /markdown \+ "\\n\\n" \+ supplements/);
  }],
  ["future sidecar mutation guards remain", () => {
    assert.match(store, /guard !isReadOnly, !blocks.isEmpty/);
    assert.match(store, /case \.newerVersion, \.unsupportedVersion: isReadOnly = true/);
  }],
  ["text input preserves existing canvas", () => {
    assert.match(controller, /canvasView.textInputActive = enabled/);
    assert.match(source("DocumentInputCanvas"), /!textInputActive && super.point/);
    assert.match(controller, /canvasView.zoomScale = next/);
  }],
  ["native regression scenarios are present", () => {
    const tests = readFileSync(new URL("../Tests/ArchiveTests/NativeInkTests.swift", import.meta.url), "utf8");
    assert.equal((tests.match(/func test\w+\(/g) ?? []).length, 10);
    assert.match(tests, /testDeleteMarkedRangeThenRestoreUndoAttachment/);
    assert.match(tests, /testInkedStudyRemovalAndUndoPreservePayload/);
  }],
];
for (const [name, check] of checks) {
  check();
  console.log(`PASS static contract: ${name}`);
}
console.log(`PASS ${checks.length} source contract checks. LIMITATION: no Swift/UIKit/PencilKit runtime execution; native XCTest and iPad acceptance are required.`);
