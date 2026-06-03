import XCTest
import CoreGraphics
@testable import MDNoteCore

final class SidecarTests: XCTestCase {

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
}
