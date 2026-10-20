import Foundation

/// Re-attaches ink to blocks after an external markdown edit.
///
/// Stable IDs take precedence. Legacy external matching requires unique exact
/// content on both sides; identical paragraphs cannot be disambiguated by order.
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
        newBlocks: [Block],
        trustedTextRanges: Bool = false
    ) -> Result {
        var result = Result()
        for item in ink {
            let target: Block?
            if let stableID = item.anchor?.blockID ?? item.blockID {
                let candidates = newBlocks.filter { $0.blockID == stableID }
                target = candidates.count == 1 ? candidates[0] : nil
            } else {
                let oldMatches = oldBlocks.filter { $0.hash == item.blockHash }
                let candidates = newBlocks.filter {
                    $0.hash == item.blockHash && $0.text == oldMatches.first?.text
                }
                target = oldMatches.count == 1 && candidates.count == 1 ? candidates[0] : nil
            }
            if let newBlock = target {
                var moved = item
                moved.blockID = newBlock.blockID
                moved.blockHash = newBlock.hash
                moved.blockSeq = newBlock.seq
                if let anchor = item.anchor, item.behavior != .rigid {
                    let oldTargets = oldBlocks.filter { $0.blockID == anchor.blockID }
                    let unchanged = oldTargets.count == 1 && oldTargets[0].text == newBlock.text
                    let exact = newBlock.text.flatMap {
                        TextAnchor.capture(blockID: anchor.blockID, text: $0,
                                           startUTF16: anchor.startUTF16, endUTF16: anchor.endUTF16)
                    }
                    let reconciled = (unchanged || trustedTextRanges) && exact?.quote == anchor.quote
                        ? exact : newBlock.text.flatMap { anchor.reconciled(in: $0) }
                    guard let reconciled else {
                        result.orphaned.append(stamped(item, oldBlocks: oldBlocks))
                        continue
                    }
                    moved.anchor = reconciled
                }
                moved.lastKnownOrigin = nil
                result.followed.append(moved)
            } else {
                result.orphaned.append(stamped(item, oldBlocks: oldBlocks))
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

    private static func stamped(_ item: AnchoredInk, oldBlocks: [Block]) -> AnchoredInk {
        var result = item
        if result.lastKnownOrigin == nil {
            result.lastKnownOrigin = item.resolvedOrigin(in: oldBlocks)
        }
        return result
    }
}
