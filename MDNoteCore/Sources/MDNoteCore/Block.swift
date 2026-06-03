import Foundation
import CoreGraphics

/// A rendered markdown block (paragraph, heading, list item, code block, …)
/// together with its on-screen geometry in *document coordinates*.
///
/// `hash` + `seq` form the stable identity used to anchor ink:
///   - `hash` is the normalized content hash (see `Hashing.blockHash`)
///   - `seq` disambiguates blocks with identical content (0-based occurrence)
public struct Block: Codable, Equatable, Sendable {
    public var hash: String
    public var seq: Int
    public var sourceLineStart: Int
    public var sourceLineEnd: Int
    /// Frame in document coordinates (origin at document top-left).
    public var frame: CGRect
    /// Optional plain text of the block, kept only when needed for similarity
    /// suggestions on orphaned ink. Not required for normal matching.
    public var text: String?

    public init(
        hash: String,
        seq: Int,
        sourceLineStart: Int = 0,
        sourceLineEnd: Int = 0,
        frame: CGRect = .zero,
        text: String? = nil
    ) {
        self.hash = hash
        self.seq = seq
        self.sourceLineStart = sourceLineStart
        self.sourceLineEnd = sourceLineEnd
        self.frame = frame
        self.text = text
    }
}

public extension Array where Element == Block {
    /// Build a block list from raw `(text, frame)` pairs, auto-assigning content
    /// hashes and per-hash occurrence sequence numbers.
    static func from(textsAndFrames pairs: [(String, CGRect)], startLine: Int = 0) -> [Block] {
        var counts: [String: Int] = [:]
        var line = startLine
        return pairs.map { text, frame in
            let hash = Hashing.blockHash(text)
            let seq = counts[hash, default: 0]
            counts[hash] = seq + 1
            let block = Block(
                hash: hash,
                seq: seq,
                sourceLineStart: line,
                sourceLineEnd: line,
                frame: frame,
                text: text
            )
            line += 1
            return block
        }
    }

    /// Find the block matching a given identity.
    func block(hash: String, seq: Int) -> Block? {
        first { $0.hash == hash && $0.seq == seq }
    }
}
