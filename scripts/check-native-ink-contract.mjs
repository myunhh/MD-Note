import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = name => readFileSync(new URL(`../MDNote/Core/${name}.swift`, import.meta.url), "utf8");
const controller = source("DocumentCanvasViewController");
const store = source("InkStore");
const writer = source("MarkdownFileWriter");
const checks = [
  ["save comparison is inside coordinated accessor", () => {
    const accessor = writer.slice(writer.indexOf("coordinate(writingItemAt:"));
    assert.ok(accessor.indexOf("current == expectedText") >= 0);
    assert.ok(accessor.indexOf(".atomic") >= 0);
    assert.ok(accessor.indexOf("current == expectedText") < accessor.indexOf(".atomic"));
    assert.match(accessor, /throw Failure.externalConflict/);
  }],
  ["read errors cannot become document text", () => {
    assert.match(controller, /text = try MarkdownFileWriter.read\(url\)/);
    assert.doesNotMatch(controller, /\?\? L10n.text\("readFileFailed"\)/);
  }],
  ["self-save baseline advances only after coordinated write", () => {
    const accept = controller.slice(controller.indexOf("private func acceptEditorSnapshot"));
    assert.ok(accept.indexOf("MarkdownFileWriter.write") >= 0);
    assert.ok(accept.indexOf("lastDocHash =") >= 0);
    assert.ok(accept.indexOf("MarkdownFileWriter.write") < accept.indexOf("lastDocHash ="));
  }],
  ["range projection is separate from original payload", () => {
    const rebuild = store.slice(store.indexOf("func rebuildDrawing"), store.indexOf("// MARK: External edit"));
    assert.ok(rebuild.length > 0);
    assert.doesNotMatch(rebuild, /item.strokeData\s*=/);
  }],
  ["Pencil-down checks guard loading, layout and replacement", () => {
    assert.match(controller, /private func loadAndRender[\s\S]*?guard !isPencilDown/);
    assert.match(controller, /private func remeasureLayout[\s\S]*?guard !isPencilDown/);
    assert.match(controller, /private func replaceCanvasDrawing[\s\S]*?guard !isPencilDown/);
  }],
  ["archive includes supplement asset scan", () => {
    assert.match(controller, /studyInsertions.map\(\\\.markdown\)/);
    assert.match(controller, /imageSources\(fragments: \[markdown\] \+ supplements\)/);
    assert.match(source("MarkdownRenderer"), /MDNote.composedImageSources/);
  }],
  ["future sidecar mutation guards remain", () => {
    assert.match(store, /guard !isReadOnly, !blocks.isEmpty/);
    assert.match(store, /case \.newerVersion, \.unsupportedVersion: isReadOnly = true/);
  }],
  ["incomplete load cannot schedule a sidecar save or export", () => {
    assert.match(controller, /private func scheduleSave\(\) \{\s*guard didInitialLoad, !isLoadingDocument, !markdownSaveFailed/);
    assert.match(controller, /private func prepareForExport\(\) async throws \{\s*guard didInitialLoad, !isLoadingDocument, !isPencilDown/);
    assert.match(controller, /func insertStudySpace\(kind: String\) \{\s*guard didInitialLoad, !isLoadingDocument, !markdownSaveFailed/);
  }],
  ["ink behavior reflects an accepted nonempty selection", () => {
    assert.match(controller, /!\$0.quote.isEmpty && \$0.endUTF16 > \$0.startUTF16/);
    assert.match(controller, /session\?\.inkBehavior = behavior/);
    assert.match(controller, /store.captureAnchor = mode == \.rigid \? nil : anchor/);
  }],
  ["live range trust is limited to remeasurement and projection publication is guarded", () => {
    const remeasure = controller.slice(controller.indexOf("private func remeasureLayout"), controller.indexOf("private func refreshNavigationAids"));
    assert.match(remeasure, /trustedTextRanges: true/);
    const load = controller.slice(controller.indexOf("private func loadAndRender"), controller.indexOf("private func remeasureLayout"));
    assert.doesNotMatch(load, /trustedTextRanges: true/);
    const projection = controller.slice(controller.indexOf("private func refreshInkProjection"), controller.indexOf("private func acceptEditorSnapshot"));
    assert.match(projection, /guard revision == layoutRevision, inkStore === store, !isPencilDown/);
    assert.ok(projection.indexOf("guard revision") < projection.indexOf("store.detach"));
  }],
];
for (const [name, check] of checks) {
  check();
  console.log(`PASS static contract: ${name}`);
}
console.log(`PASS ${checks.length} source boundary checks. These checks inspect ordering/guards only, not working behavior. Geometry decoding and its ink consumer are covered by native XCTest, which requires Xcode and is not executed by this script.`);
