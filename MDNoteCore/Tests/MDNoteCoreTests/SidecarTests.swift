import XCTest
import Foundation
import CoreGraphics
@testable import MDNoteCore

final class SidecarTests: XCTestCase {

    func testNewerVersionThrowsInsteadOfDecodingAsCorrupt() throws {
        let blocks = [Block].from(textsAndFrames: [
            ("Title", CGRect(x: 0, y: 0, width: 600, height: 40)),
        ])
        let sidecar = Sidecar(
            documentHash: "abc", layoutWidth: 720,
            blocks: blocks.map(BlockSnapshot.init), ink: [], appVersion: "test"
        )
        let data = try sidecar.encoded()

        // A normal current-version file still decodes cleanly.
        XCTAssertNoThrow(try Sidecar.decoded(from: data))

        // Bump the on-disk version to simulate a file written by a newer build.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["version"] = Sidecar.currentVersion + 1
        let bumped = try JSONSerialization.data(withJSONObject: obj)

        XCTAssertThrowsError(try Sidecar.decoded(from: bumped)) { error in
            XCTAssertEqual(error as? SidecarError, .newerVersion(Sidecar.currentVersion + 1),
                           "a newer sidecar must surface as newerVersion, not be treated as corrupt")
        }
    }

    func testRoundTrip() throws {
        let blocks = [Block].from(textsAndFrames: [
            ("Title", CGRect(x: 0, y: 0, width: 600, height: 40)),
            ("Body text here", CGRect(x: 0, y: 50, width: 600, height: 80)),
        ])
        let ink = AnchoredInk(
            blockHash: blocks[1].hash, blockSeq: blocks[1].seq,
            offset: CGPoint(x: 12, y: 8), size: CGSize(width: 40, height: 25),
            strokeData: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        let sidecar = Sidecar(
            documentHash: Hashing.documentHash("# Title\n\nBody text here"),
            layoutWidth: 720,
            blocks: blocks.map(BlockSnapshot.init),
            ink: [ink],
            appVersion: "test"
        )

        let data = try sidecar.encoded()
        let restored = try Sidecar.decoded(from: data)
        XCTAssertEqual(restored, sidecar)
        XCTAssertEqual(restored.ink.first?.strokeData, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(restored.version, Sidecar.currentVersion)
    }

    func testHashStabilityAcrossWhitespace() {
        // Re-wrapping the source should not change a block's identity.
        XCTAssertEqual(
            Hashing.blockHash("The  quick\nbrown   fox"),
            Hashing.blockHash("The quick brown fox")
        )
        XCTAssertNotEqual(
            Hashing.blockHash("The quick brown fox"),
            Hashing.blockHash("The quick brown foxes")
        )
    }

    func testNormalizeMatchesJSSemantics() {
        // bridge.js: text.split(/[ \t\n\r]+/).filter(Boolean).join(" ").
        // ASCII whitespace collapses (including at the edges)…
        XCTAssertEqual(Hashing.normalize("  a \t b\r\nc  "), "a b c")
        // …but Unicode spaces are CONTENT on both sides (NBSP here), so the
        // Swift side must not trim them away.
        XCTAssertEqual(Hashing.normalize("\u{00A0}a b\u{00A0}"), "\u{00A0}a b\u{00A0}")
        XCTAssertEqual(Hashing.normalize(""), "")
        XCTAssertEqual(Hashing.normalize(" \n\t "), "")
    }
}
