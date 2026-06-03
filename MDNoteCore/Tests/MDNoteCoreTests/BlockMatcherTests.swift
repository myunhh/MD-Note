import XCTest
@testable import MDNoteCore

final class BlockMatcherTests: XCTestCase {

    func testLCSIdenticalSequences() {
        let a = ["x", "y", "z"]
        let pairs = BlockMatcher.lcs(a, a)
        XCTAssertEqual(pairs.map(\.oldIndex), [0, 1, 2])
        XCTAssertEqual(pairs.map(\.newIndex), [0, 1, 2])
    }

    func testLCSInsertionInMiddle() {
        // "y" inserted between x and z
        let pairs = BlockMatcher.lcs(["x", "z"], ["x", "y", "z"])
        XCTAssertEqual(pairs, [
            .init(oldIndex: 0, newIndex: 0),
            .init(oldIndex: 1, newIndex: 2),
        ])
    }

    func testLCSDeletion() {
        let pairs = BlockMatcher.lcs(["x", "y", "z"], ["x", "z"])
        XCTAssertEqual(pairs, [
            .init(oldIndex: 0, newIndex: 0),
            .init(oldIndex: 2, newIndex: 1),
        ])
    }

    func testLCSDuplicatesKeepOrder() {
        // two identical blocks, one prepended -> originals shift right
        let pairs = BlockMatcher.lcs(["a", "a", "b"], ["a", "a", "a", "b"])
        // The two old "a"s align to the first two new "a"s (greedy front match),
        // and "b" aligns to the last.
        XCTAssertEqual(pairs, [
            .init(oldIndex: 0, newIndex: 0),
            .init(oldIndex: 1, newIndex: 1),
            .init(oldIndex: 2, newIndex: 3),
        ])
    }

    func testLCSEmpty() {
        XCTAssertTrue(BlockMatcher.lcs([], ["a"]).isEmpty)
        XCTAssertTrue(BlockMatcher.lcs(["a"], []).isEmpty)
    }
}
