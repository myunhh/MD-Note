import Foundation
import CoreGraphics
import MDNoteCore

/// Decodes the per-block geometry that `bridge.js` (`MDNote.layout()`) returns,
/// and converts it into the platform-agnostic `MDNoteCore.Block`.
struct BlockGeometryDTO: Decodable {
    let blockHash: String
    let blockSeq: Int
    let sourceLineStart: Int
    let sourceLineEnd: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let text: String

    var block: Block {
        Block(
            hash: blockHash,
            seq: blockSeq,
            sourceLineStart: sourceLineStart,
            sourceLineEnd: sourceLineEnd,
            frame: CGRect(x: x, y: y, width: width, height: height),
            text: text
        )
    }
}
