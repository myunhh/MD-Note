import Foundation

/// Re-attaches ink to blocks after an external markdown edit.
///
/// Strategy (never destructive):
///   - If an ink item's anchor block still exists (matched via LCS), the ink is
///     *followed*: its anchor is updated to the new block's occurrence index so
///     it resolves to the block's new position. Relative offset is preserved.
///   - If the anchor block disappeared, the ink is *orphaned* — kept aside for
///     the user to re-attach or delete, never silently removed.
public enum Reanchor {

    public struct Result: Equatable, Sendable {
        /// Ink whose anchor block survived. Anchors already updated to new seq.
        public var followed: [AnchoredInk]
        /// Ink whose anchor block is gone.
        public var orphaned: [AnchoredInk]

        public init(followed: [AnchoredInk] = [], orphaned: [AnchoredInk] = []) {
            self.followed = followed
            self.orphaned = orphaned
        }
    }

    public static func reanchor(
        ink: [AnchoredInk],
        oldBlocks: [Block],
        newBlocks: [Block]
    ) -> Result {
        let pairs = BlockMatcher.match(old: oldBlocks, new: newBlocks)

        // Map a surviving old block identity -> its new identity.
        // Key: "hash#seq" of the OLD block. Value: the matched NEW block.
        var survivors: [String: Block] = [:]
        var matchedOld = Set<Int>()
        var matchedNew = Set<Int>()
        for pair in pairs {
            let oldB = oldBlocks[pair.oldIndex]
            let newB = newBlocks[pair.newIndex]
            survivors[key(oldB.hash, oldB.seq)] = newB
            matchedOld.insert(pair.oldIndex)
            matchedNew.insert(pair.newIndex)
        }

        // Second pass: a block MOVED elsewhere in the document falls off the
        // LCS (which only matches in-order subsequences) even though identical
        // content survives. Pair the leftover old/new blocks that share a hash,
        // in document order, so ink follows a relocated section instead of
        // orphaning.
        var movedTargets: [String: [Int]] = [:]
        for (index, block) in newBlocks.enumerated() where !matchedNew.contains(index) {
            movedTargets[block.hash, default: []].append(index)
        }
        for (index, oldB) in oldBlocks.enumerated() where !matchedOld.contains(index) {
            guard let targets = movedTargets[oldB.hash], !targets.isEmpty else { continue }
            // Pick the surviving duplicate NEAREST in source order rather than
            // the first in document order: deleting one of several identical
            // blocks must not fling its ink to an unrelated copy in a distant
            // section. Tie-break on the smaller new index for determinism.
            let pick = targets.min { a, b in
                let da = abs(newBlocks[a].sourceLineStart - oldB.sourceLineStart)
                let db = abs(newBlocks[b].sourceLineStart - oldB.sourceLineStart)
                return da != db ? da < db : a < b
            }!
            survivors[key(oldB.hash, oldB.seq)] = newBlocks[pick]
            movedTargets[oldB.hash] = targets.filter { $0 != pick }
        }

        var result = Result()
        for item in ink {
            if let newBlock = survivors[key(item.blockHash, item.blockSeq)] {
                var moved = item
                // hash is identical for an LCS match; only the occurrence index
                // can shift when duplicates are inserted/removed above it.
                moved.blockSeq = newBlock.seq
                result.followed.append(moved)
            } else {
                result.orphaned.append(item)
            }
        }
        return result
    }

    /// For an orphaned ink item, suggest a new anchor block whose text closely
    /// matches the orphan's original block text (i.e. the block was *edited*,
    /// not deleted). Default behaviour does NOT auto-move — this only proposes.
    public static func suggestTarget(
        orphanBlockText: String,
        among blocks: [Block],
        threshold: Double = 0.6
    ) -> (block: Block, score: Double)? {
        var best: (Block, Double)?
        for block in blocks {
            guard let text = block.text else { continue }
            let score = Hashing.similarity(orphanBlockText, text)
            if score >= threshold, best == nil || score > best!.1 {
                best = (block, score)
            }
        }
        guard let best else { return nil }
        return (best.0, best.1)
    }

    private static func key(_ hash: String, _ seq: Int) -> String { "\(hash)#\(seq)" }
}
