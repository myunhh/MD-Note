import Foundation
import CoreGraphics

/// One unit of handwriting anchored to a markdown block.
///
/// The ink payload (`strokeData`) is opaque to the core — on iOS it is a
/// `PKDrawing.dataRepresentation()`. The core only reasons about *where* the ink
/// lives relative to its anchor block, never about its visual content.
public struct AnchoredInk: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Identity of the anchor block.
    public var blockHash: String
    public var blockSeq: Int
    /// Top-left of the ink's bounding box, relative to the anchor block's
    /// top-left at anchor time.
    public var offset: CGPoint
    /// Bounding-box size of the ink (for orphan thumbnails / overlap checks).
    public var size: CGSize
    /// Opaque stroke payload (PKDrawing data on iOS).
    public var strokeData: Data
    /// Last known absolute document origin of the ink's bounding box. Set when
    /// the ink becomes an orphan (its anchor block was deleted), so it can be
    /// restored near where the user last saw it. nil for live, anchored ink.
    public var lastKnownOrigin: CGPoint?

    public init(
        id: UUID = UUID(),
        blockHash: String,
        blockSeq: Int,
        offset: CGPoint,
        size: CGSize,
        strokeData: Data,
        lastKnownOrigin: CGPoint? = nil
    ) {
        self.id = id
        self.blockHash = blockHash
        self.blockSeq = blockSeq
        self.offset = offset
        self.size = size
        self.strokeData = strokeData
        self.lastKnownOrigin = lastKnownOrigin
    }

    /// Resolve the absolute document-coordinate origin of this ink given the
    /// current block layout. Returns nil if the anchor block is absent
    /// (i.e. the ink is orphaned).
    public func resolvedOrigin(in blocks: [Block]) -> CGPoint? {
        guard let block = blocks.block(hash: blockHash, seq: blockSeq) else { return nil }
        return CGPoint(x: block.frame.origin.x + offset.x,
                       y: block.frame.origin.y + offset.y)
    }

    /// Resolve the absolute document-coordinate frame of this ink.
    public func resolvedFrame(in blocks: [Block]) -> CGRect? {
        guard let origin = resolvedOrigin(in: blocks) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
