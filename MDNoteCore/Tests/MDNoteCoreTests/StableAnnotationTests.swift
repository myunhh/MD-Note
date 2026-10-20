import XCTest
import Foundation
import CoreGraphics
@testable import MDNoteCore

final class StableAnnotationTests: XCTestCase {
    func testTrustedLiveMappingKeepsRepeatedQuoteWhileExternalMatchingDetaches() throws {
        let text = String(repeating: "note ", count: 40)
        let old = Block(hash: "old", seq: 0, text: text, blockID: "b")
        let anchor = try XCTUnwrap(TextAnchor.capture(blockID: "b", text: text, startUTF16: 50, endUTF16: 54))
        let mapped = try XCTUnwrap(anchor.applyingReplacement(startUTF16: 0, endUTF16: 0,
                                                            replacement: "prefix ", oldText: text))
        let updated = Block(hash: "new", seq: 0, text: "prefix " + text, blockID: "b")
        let ink = AnchoredInk(blockHash: "old", blockSeq: 0, offset: .zero, size: .zero,
                              strokeData: Data([1, 2]), blockID: "b", anchor: mapped, behavior: .highlight)
        let live = Reanchor.reanchor(ink: [ink], oldBlocks: [old], newBlocks: [updated], trustedTextRanges: true)
        XCTAssertEqual(live.followed.first?.anchor, mapped)
        XCTAssertTrue(live.orphaned.isEmpty)
        XCTAssertEqual(Reanchor.reanchor(ink: [ink], oldBlocks: [old], newBlocks: [updated]).orphaned.count, 1)
    }

    func testExplicitSplitMergeMappingAndUndoUseOriginalRange() throws {
        let anchor = try XCTUnwrap(TextAnchor.capture(blockID: "original", text: "left right",
                                                     startUTF16: 5, endUTF16: 10))
        let split = try XCTUnwrap(anchor.remapped(blockID: "split", text: "right", offsetDeltaUTF16: -5))
        XCTAssertEqual(split.startUTF16, 0)
        XCTAssertEqual(split.blockID, "split")
        XCTAssertEqual(split.remapped(blockID: "original", text: "left right", offsetDeltaUTF16: 5), anchor)
        XCTAssertNil(anchor.remapped(blockID: "left", text: "left", offsetDeltaUTF16: 0))
        XCTAssertNil(anchor.remapped(blockID: "bad", text: "left right", offsetDeltaUTF16: Int.max))
    }

    func testSharedUTF16Fixtures() throws {
        struct Fixture: Decodable {
            var text: String
            var validBoundaries: [Int]
            var invalidBoundaries: [Int]
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/anchor-utf16.json")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        for fixture in fixtures {
            for offset in fixture.validBoundaries {
                XCTAssertNotNil(TextAnchor.stringRange(in: fixture.text, startUTF16: offset, endUTF16: offset))
            }
            for offset in fixture.invalidBoundaries {
                XCTAssertNil(TextAnchor.stringRange(in: fixture.text, startUTF16: offset, endUTF16: offset))
            }
        }
    }

    func testUTF16RejectsSurrogateCombiningAndJoinedEmojiInteriors() {
        let text = "가👩‍💻e\u{301}끝"
        XCTAssertEqual(text.utf16.count, 9)
        for invalid in [2, 3, 4, 5, 7] {
            XCTAssertNil(TextAnchor.capture(blockID: "a", text: text, startUTF16: invalid, endUTF16: 9))
        }
        let anchor = TextAnchor.capture(blockID: "a", text: text, startUTF16: 1, endUTF16: 8)
        XCTAssertEqual(anchor?.quote, "👩‍💻e\u{301}")
        XCTAssertNil(TextAnchor.stringRange(in: text, startUTF16: -1, endUTF16: 0))
        XCTAssertNil(TextAnchor.stringRange(in: text, startUTF16: 0, endUTF16: Int.max))
    }

    func testKnownReplacementMovesAndExpandsRangeWithoutChangingGraphemes() throws {
        let anchor = try XCTUnwrap(TextAnchor.capture(blockID: "a", text: "hello world", startUTF16: 6, endUTF16: 11))
        let moved = try XCTUnwrap(anchor.applyingReplacement(startUTF16: 0, endUTF16: 0, replacement: "한 ", oldText: "hello world"))
        XCTAssertEqual(moved.startUTF16, 8)
        XCTAssertEqual(moved.quote, "world")
        let expanded = anchor.applyingReplacement(startUTF16: 8, endUTF16: 8, replacement: "한", oldText: "hello world")
        XCTAssertEqual(expanded?.quote, "wo한rld")
        XCTAssertNil(anchor.applyingReplacement(startUTF16: 6, endUTF16: 11, replacement: "", oldText: "hello world"))
    }

    func testExternalQuoteResolutionDoesNotTrustOldOffset() throws {
        let anchor = TextAnchor(blockID: "a", startUTF16: 0, endUTF16: 4, quote: "note")
        XCTAssertNil(anchor.reconciled(in: "note note"))
        XCTAssertEqual(anchor.reconciled(in: "new note")?.startUTF16, 4)
        XCTAssertNil(anchor.reconciled(in: "deleted"))
        let contextual = try XCTUnwrap(TextAnchor.capture(blockID: "a", text: "left note right", startUTF16: 5, endUTF16: 9))
        XCTAssertEqual(contextual.reconciled(in: "note left note right")?.startUTF16, 10)
    }

    func testStableIDSurvivesTextEditMoveAndDuplicateContent() {
        let old = Block(hash: "old", seq: 0, text: "old", blockID: "persist")
        let target = Block(hash: "new", seq: 1, frame: CGRect(x: 10, y: 100, width: 50, height: 50),
                           text: "edited", blockID: "persist")
        let duplicate = Block(hash: "new", seq: 0, text: "edited", blockID: "other")
        let ink = AnchoredInk(blockHash: "old", blockSeq: 0, offset: CGPoint(x: 2, y: 3),
                              size: CGSize(width: 4, height: 5), strokeData: Data([1, 2, 3]),
                              blockID: "persist")
        let result = Reanchor.reanchor(ink: [ink], oldBlocks: [old], newBlocks: [duplicate, target])
        XCTAssertTrue(result.orphaned.isEmpty)
        XCTAssertEqual(result.followed.first?.resolvedOrigin(in: [duplicate, target]), CGPoint(x: 12, y: 103))
        XCTAssertEqual(result.followed.first?.strokeData, ink.strokeData)
        XCTAssertNil(ink.resolvedOrigin(in: [Block(hash: "old", seq: 0)]))
        XCTAssertEqual(Reanchor.reanchor(ink: [ink], oldBlocks: [old], newBlocks: [duplicate]).orphaned.first?.id, ink.id)
    }

    func testIdentityRestorationUsesSnapshotAndNotHashAlone() {
        let old = [Block(hash: "h", seq: 0, text: "same", blockID: "one"),
                   Block(hash: "h", seq: 1, text: "same", blockID: "two")]
        let fresh = old.map { block -> Block in var copy = block; copy.blockID = nil; return copy }
        XCTAssertEqual(StableBlockIdentity.reconcile(old: old, new: fresh, documentUnchanged: true).map(\.blockID), ["one", "two"])
        let changed = StableBlockIdentity.reconcile(old: old, new: fresh)
        XCTAssertFalse(changed.contains { $0.blockID == "one" || $0.blockID == "two" })
        XCTAssertEqual(Set(changed.compactMap(\.blockID)).count, 2)
        let collision = [Block(hash: "h", seq: 0, text: "different")]
        XCTAssertNotEqual(StableBlockIdentity.reconcile(old: [old[0]], new: collision)[0].blockID, "one")
    }

    func testFollowingTextPreservesOriginalBytesAndDetachesDeletedQuote() throws {
        let old = Block(hash: "old", seq: 0, text: "a word", blockID: "stable")
        let anchor = try XCTUnwrap(TextAnchor.capture(blockID: "stable", text: "a word", startUTF16: 2, endUTF16: 6))
        let ink = AnchoredInk(blockHash: "old", blockSeq: 0, offset: .zero, size: .zero,
                              strokeData: Data([42, 43]), blockID: "stable", anchor: anchor, behavior: .underline)
        let changed = Block(hash: "changed", seq: 0, text: "prefix a word", blockID: "stable")
        let followed = Reanchor.reanchor(ink: [ink], oldBlocks: [old], newBlocks: [changed])
        XCTAssertEqual(followed.followed.first?.anchor?.startUTF16, 9)
        XCTAssertEqual(followed.followed.first?.strokeData, ink.strokeData)
        let deleted = Block(hash: "deleted", seq: 0, text: "a", blockID: "stable")
        let detached = Reanchor.reanchor(ink: [ink], oldBlocks: [old], newBlocks: [deleted])
        XCTAssertTrue(detached.followed.isEmpty)
        XCTAssertEqual(detached.orphaned.first?.strokeData, ink.strokeData)
        XCTAssertEqual(detached.orphaned.first?.anchor, ink.anchor)
    }

    func testDuplicateStableIDsNeverResolve() {
        let block = Block(hash: "h", seq: 0, text: "text", blockID: "duplicated")
        let ink = AnchoredInk(blockHash: "h", blockSeq: 0, offset: .zero, size: .zero,
                              strokeData: Data([9]), blockID: "duplicated")
        XCTAssertNil(ink.resolvedOrigin(in: [block, block]))
        XCTAssertEqual(Reanchor.reanchor(ink: [ink], oldBlocks: [block], newBlocks: [block, block]).orphaned.first?.id, ink.id)
    }

    func testUnchangedRepeatedTextKeepsExactRangeOnReopen() throws {
        let text = String(repeating: "note ", count: 40)
        let block = Block(hash: "h", seq: 0, text: text, blockID: "b")
        let anchor = try XCTUnwrap(TextAnchor.capture(blockID: "b", text: text, startUTF16: 50, endUTF16: 54))
        XCTAssertNil(anchor.reconciled(in: text))
        let ink = AnchoredInk(blockHash: "h", blockSeq: 0, offset: .zero, size: .zero,
                              strokeData: Data([2]), blockID: "b", anchor: anchor, behavior: .highlight)
        let result = Reanchor.reanchor(ink: [ink], oldBlocks: [block], newBlocks: [block])
        XCTAssertTrue(result.orphaned.isEmpty)
        XCTAssertEqual(result.followed.first?.anchor, anchor)
    }

    func testV1MigrationPreservesOrphansAndNewIDsAcrossSecondLoad() throws {
        let ink = AnchoredInk(blockHash: "h", blockSeq: 0, offset: .zero, size: .zero, strokeData: Data([255, 0]))
        let orphan = AnchoredInk(blockHash: "gone", blockSeq: 9, offset: .zero, size: .zero, strokeData: Data([7, 8]))
        let v1 = Sidecar(version: 1, documentHash: "doc", layoutWidth: 720,
                         blocks: [BlockSnapshot(hash: "h", seq: 0, sourceLineStart: 0, sourceLineEnd: 0)],
                         ink: [ink], orphans: [orphan], appVersion: "legacy")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: v1.encoded()) as? [String: Any])
        json.removeValue(forKey: "studyInsertions")
        var legacyInk = try XCTUnwrap(json["ink"] as? [[String: Any]])
        legacyInk[0].removeValue(forKey: "behavior")
        json["ink"] = legacyInk
        let migrated = try Sidecar.decoded(from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.version, 2)
        XCTAssertNotNil(migrated.blocks[0].blockID)
        XCTAssertEqual(migrated.ink[0].blockID, migrated.blocks[0].blockID)
        XCTAssertEqual(migrated.ink[0].behavior, .rigid)
        XCTAssertEqual(migrated.ink[0].strokeData, ink.strokeData)
        XCTAssertEqual(migrated.orphans, [orphan])
        XCTAssertEqual(try Sidecar.decoded(from: migrated.encoded()), migrated)
    }

    func testV1UnresolvedLiveInkMovesToOrphansWithoutPayloadLoss() throws {
        let missing = AnchoredInk(blockHash: "missing", blockSeq: 1, offset: .zero, size: .zero,
                                  strokeData: Data([4, 5, 6]))
        let sidecar = Sidecar(version: 1, documentHash: "d", layoutWidth: 720, blocks: [],
                              ink: [missing], appVersion: "old")
        let migrated = try Sidecar.decoded(from: sidecar.encoded())
        XCTAssertTrue(migrated.ink.isEmpty)
        XCTAssertEqual(migrated.orphans, [missing])
    }

    func testFutureVersionRejectedEvenByDirectDecoderAndEncoder() throws {
        let data = Data("{\"version\":999}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Sidecar.self, from: data)) {
            XCTAssertEqual($0 as? SidecarError, .newerVersion(999))
        }
        let future = Sidecar(version: 999, documentHash: "", layoutWidth: 0, blocks: [], ink: [], appVersion: "")
        XCTAssertThrowsError(try future.encoded())
    }

    func testStudyRoundTripAndValueUndoPreserveInk() throws {
        let original: [StudyInsertion] = []
        var study = StudyInsertion(id: "study", afterBlockID: "block")
        let inserted = try XCTUnwrap(StudyInsertions.upserting(study, in: original))
        study.kind = .markdown
        study.markdown = "## 추가\n\n한글 👩‍💻"
        study.height = 240
        study.afterBlockID = "moved"
        study.blockIDs = ["child-one", "child-two"]
        let edited = try XCTUnwrap(StudyInsertions.upserting(study, in: inserted))
        XCTAssertEqual(inserted[0].height, 160)
        XCTAssertEqual(edited.count, 1)
        XCTAssertEqual(StudyInsertions.removing(id: "study", from: edited), original)
        let spaceBlock = Block(hash: "space", seq: 0, blockID: "study")
        let ink = AnchoredInk(blockHash: "space", blockSeq: 0, offset: .zero, size: .zero,
                              strokeData: Data([77]), blockID: "study")
        let detached = Reanchor.reanchor(ink: [ink], oldBlocks: [spaceBlock], newBlocks: [])
        XCTAssertEqual(detached.orphaned.first?.strokeData, ink.strokeData)
        let sidecar = Sidecar(documentHash: "", layoutWidth: 720, blocks: [], ink: [],
                              orphans: detached.orphaned, appVersion: "test",
                              studyInsertions: edited)
        XCTAssertEqual(try Sidecar.decoded(from: sidecar.encoded()), sidecar)
        study.height = .nan
        XCTAssertNil(StudyInsertions.upserting(study, in: edited))
    }
}
