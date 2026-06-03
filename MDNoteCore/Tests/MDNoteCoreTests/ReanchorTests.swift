import XCTest
import CoreGraphics
@testable import MDNoteCore

final class ReanchorTests: XCTestCase {

    private func ink(on block: Block, offset: CGPoint, size: CGSize = .init(width: 30, height: 20)) -> AnchoredInk {
        AnchoredInk(blockHash: block.hash, blockSeq: block.seq,
                    offset: offset, size: size, strokeData: Data([0x01]))
    }

    // MARK: Ink follows content pushed down by an inserted block

    func testInkFollowsBlockPushedDown() {
        let old = [Block].from(textsAndFrames: [
            ("Intro heading", CGRect(x: 0, y: 0, width: 600, height: 40)),
            ("The body paragraph", CGRect(x: 0, y: 50, width: 600, height: 100)),
        ])
        let mark = ink(on: old[1], offset: CGPoint(x: 10, y: 20))
        XCTAssertEqual(mark.resolvedOrigin(in: old), CGPoint(x: 10, y: 70))

        // A new paragraph is inserted above the body, pushing it 40pt down.
        let new = [Block].from(textsAndFrames: [
            ("Intro heading", CGRect(x: 0, y: 0, width: 600, height: 40)),
            ("A freshly inserted note", CGRect(x: 0, y: 50, width: 600, height: 30)),
            ("The body paragraph", CGRect(x: 0, y: 90, width: 600, height: 100)),
        ])

        let result = Reanchor.reanchor(ink: [mark], oldBlocks: old, newBlocks: new)
        XCTAssertEqual(result.orphaned.count, 0)
        XCTAssertEqual(result.followed.count, 1)

        // Ink resolves to the body's NEW position, offset preserved.
        let moved = result.followed[0]
        XCTAssertEqual(moved.resolvedOrigin(in: new), CGPoint(x: 10, y: 110))
    }

    // MARK: Deleted anchor block -> orphaned, never dropped

    func testDeletedBlockOrphansInk() {
        let old = [Block].from(textsAndFrames: [
            ("Intro heading", CGRect(x: 0, y: 0, width: 600, height: 40)),
            ("The body paragraph", CGRect(x: 0, y: 50, width: 600, height: 100)),
        ])
        let mark = ink(on: old[1], offset: CGPoint(x: 10, y: 20))

        // Body deleted entirely.
        let new = [Block].from(textsAndFrames: [
            ("Intro heading", CGRect(x: 0, y: 0, width: 600, height: 40)),
        ])

        let result = Reanchor.reanchor(ink: [mark], oldBlocks: old, newBlocks: new)
        XCTAssertEqual(result.followed.count, 0)
        XCTAssertEqual(result.orphaned.count, 1)
        XCTAssertEqual(result.orphaned[0].id, mark.id)
    }

    // MARK: Duplicate blocks keep ink on the right occurrence

    func testInkFollowsWhenDistinctBlockInsertedAboveDuplicates() {
        // Two identical "note" blocks; ink is on the SECOND (seq 1).
        let old = [Block].from(textsAndFrames: [
            ("note", CGRect(x: 0, y: 0, width: 600, height: 20)),
            ("note", CGRect(x: 0, y: 30, width: 600, height: 20)),
            ("tail", CGRect(x: 0, y: 60, width: 600, height: 20)),
        ])
        XCTAssertEqual(old[1].seq, 1)
        let mark = ink(on: old[1], offset: CGPoint(x: 5, y: 5))

        // A DISTINCT block ("header") is inserted at the top. Because it differs
        // from "note", the relative order of the two notes is unambiguous: the
        // 2nd note (our anchor) is pushed down and stays the 2nd note.
        let new = [Block].from(textsAndFrames: [
            ("header", CGRect(x: 0, y: 0, width: 600, height: 20)),
            ("note", CGRect(x: 0, y: 30, width: 600, height: 20)),   // seq 0
            ("note", CGRect(x: 0, y: 60, width: 600, height: 20)),   // seq 1  <- anchor
            ("tail", CGRect(x: 0, y: 90, width: 600, height: 20)),
        ])

        let result = Reanchor.reanchor(ink: [mark], oldBlocks: old, newBlocks: new)
        XCTAssertEqual(result.followed.count, 1)
        let moved = result.followed[0]
        XCTAssertEqual(moved.blockSeq, 1, "still the 2nd note")
        XCTAssertEqual(moved.resolvedOrigin(in: new), CGPoint(x: 5, y: 65), "followed down by 30pt")
    }

    func testIdenticalDuplicateInsertIsAmbiguousButStable() {
        // Inserting a block IDENTICAL to existing duplicates is inherently
        // ambiguous — there's no content to tell which "note" is the user's.
        // Defined behaviour: ink stays on the same ORDINAL occurrence (the Nth
        // "note" from the top), which LCS resolves by treating the insertion as
        // the trailing duplicate. This pins that contract.
        let old = [Block].from(textsAndFrames: [
            ("note", CGRect(x: 0, y: 0, width: 600, height: 20)),
            ("note", CGRect(x: 0, y: 30, width: 600, height: 20)),   // seq 1 <- anchor
            ("tail", CGRect(x: 0, y: 60, width: 600, height: 20)),
        ])
        let mark = ink(on: old[1], offset: CGPoint(x: 5, y: 5))

        let new = [Block].from(textsAndFrames: [
            ("note", CGRect(x: 0, y: 0, width: 600, height: 20)),
            ("note", CGRect(x: 0, y: 30, width: 600, height: 20)),
            ("note", CGRect(x: 0, y: 60, width: 600, height: 20)),
            ("tail", CGRect(x: 0, y: 90, width: 600, height: 20)),
        ])

        let result = Reanchor.reanchor(ink: [mark], oldBlocks: old, newBlocks: new)
        XCTAssertEqual(result.followed.count, 1)
        // Stays the 2nd note (ordinal preserved), not pushed to the 3rd.
        XCTAssertEqual(result.followed[0].blockSeq, 1)
        XCTAssertEqual(result.followed[0].resolvedOrigin(in: new), CGPoint(x: 5, y: 35))
    }

    func testDuplicateDeletionOrphansSecondOccurrence() {
        let old = [Block].from(textsAndFrames: [
            ("dup", CGRect(x: 0, y: 0, width: 600, height: 20)),
            ("dup", CGRect(x: 0, y: 30, width: 600, height: 20)),
        ])
        let onFirst = ink(on: old[0], offset: .zero)
        let onSecond = ink(on: old[1], offset: .zero)

        // One "dup" removed.
        let new = [Block].from(textsAndFrames: [
            ("dup", CGRect(x: 0, y: 0, width: 600, height: 20)),
        ])

        let result = Reanchor.reanchor(ink: [onFirst, onSecond], oldBlocks: old, newBlocks: new)
        XCTAssertEqual(Set(result.followed.map(\.id)), [onFirst.id])
        XCTAssertEqual(Set(result.orphaned.map(\.id)), [onSecond.id])
    }

    // MARK: Edited block -> orphan, but similarity can suggest re-attach

    func testEditedBlockOrphansThenSuggests() {
        let old = [Block].from(textsAndFrames: [
            ("The quick brown fox", CGRect(x: 0, y: 0, width: 600, height: 40)),
        ])
        let mark = ink(on: old[0], offset: .zero)

        // Block edited (a word appended) -> different hash.
        let new = [Block].from(textsAndFrames: [
            ("The quick brown fox jumps", CGRect(x: 0, y: 0, width: 600, height: 40)),
        ])

        let result = Reanchor.reanchor(ink: [mark], oldBlocks: old, newBlocks: new)
        XCTAssertEqual(result.orphaned.count, 1, "edited block is treated as gone")

        // But we can propose where it likely moved.
        let suggestion = Reanchor.suggestTarget(orphanBlockText: "The quick brown fox", among: new)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.block.hash, new[0].hash)
        XCTAssertGreaterThanOrEqual(suggestion?.score ?? 0, 0.6)
    }

    func testNoSuggestionBelowThreshold() {
        let new = [Block].from(textsAndFrames: [
            ("completely unrelated content here", CGRect(x: 0, y: 0, width: 600, height: 40)),
        ])
        let suggestion = Reanchor.suggestTarget(orphanBlockText: "alpha beta gamma", among: new)
        XCTAssertNil(suggestion)
    }

    // MARK: Reordering

    func testReorderKeepsLongerRunMatched() {
        let old = [Block].from(textsAndFrames: [
            ("alpha", CGRect(x: 0, y: 0, width: 600, height: 20)),
            ("beta", CGRect(x: 0, y: 30, width: 600, height: 20)),
            ("gamma", CGRect(x: 0, y: 60, width: 600, height: 20)),
        ])
        let onAlpha = ink(on: old[0], offset: .zero)
        let onGamma = ink(on: old[2], offset: CGPoint(x: 0, y: 5))

        // gamma moved to the top: [gamma, alpha, beta]
        let new = [Block].from(textsAndFrames: [
            ("gamma", CGRect(x: 0, y: 0, width: 600, height: 20)),
            ("alpha", CGRect(x: 0, y: 30, width: 600, height: 20)),
            ("beta", CGRect(x: 0, y: 60, width: 600, height: 20)),
        ])

        let result = Reanchor.reanchor(ink: [onAlpha, onGamma], oldBlocks: old, newBlocks: new)
        // LCS([alpha,beta,gamma],[gamma,alpha,beta]) = [alpha,beta]; gamma drops.
        XCTAssertEqual(Set(result.followed.map(\.id)), [onAlpha.id])
        XCTAssertEqual(Set(result.orphaned.map(\.id)), [onGamma.id])

        // Followed alpha still resolves correctly at its new position.
        let movedAlpha = result.followed.first { $0.id == onAlpha.id }!
        XCTAssertEqual(movedAlpha.resolvedOrigin(in: new), CGPoint(x: 0, y: 30))
    }
}
