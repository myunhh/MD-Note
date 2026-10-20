import Foundation
import PencilKit
import MDNoteCore

/// Bridges PencilKit drawings to/from `MDNoteCore` block anchors and persists
/// them in a `<name>.md.inknote` sidecar.
///
/// Original strokes stay block-relative; display projections never replace them.
@MainActor
final class InkStore {
    private(set) var documentURL: URL
    private(set) var ink: [AnchoredInk] = []
    private(set) var orphans: [AnchoredInk] = []
    var studyInsertions: [StudyInsertion] = []
    var captureBehavior: AnnotationBehavior = .rigid
    var captureAnchor: TextAnchor?
    var rangeRects: [UUID: [CGRect]] = [:]
    private var renderedSources: [Data: (UUID, Int)] = [:]
    private var originals: [UUID: AnchoredInk] = [:]
    private var renderedCounts: [UUID: Int] = [:]
    var layoutWidth: CGFloat = 1390

    /// Set when load() found a sidecar written by a NEWER app version. Its bytes
    /// are intact, so we refuse to overwrite it — every save() becomes a no-op
    /// rather than clobbering the user's ink with this build's older schema.
    private(set) var isReadOnly = false

    /// Surfaced when a save fails (encode/coordination/write) so the UI can warn
    /// the user instead of silently losing the last strokes.
    var onSaveFailure: ((Error) -> Void)?

    /// `Foo.md` -> `Foo.md.inknote`
    var sidecarURL: URL { documentURL.appendingPathExtension("inknote") }

    init(documentURL: URL) { self.documentURL = documentURL }

    /// Follow an external move/rename of the document: point at the new URL
    /// and bring the sidecar file along so future saves stay paired.
    func relocate(to newURL: URL) {
        guard newURL != documentURL else { return }
        let oldSidecar = sidecarURL
        documentURL = newURL
        if FileManager.default.fileExists(atPath: oldSidecar.path) {
            try? FileManager.default.moveItem(at: oldSidecar, to: sidecarURL)
        }
    }

    // MARK: Capture (PencilKit -> anchors)

    func capture(drawing: PKDrawing, blocks: [Block]) {
        guard !isReadOnly, !blocks.isEmpty else { return }
        for item in ink { rememberOriginal(item) }
        var grouped: [String: [PKStroke]] = [:]
        var retained: [UUID: Set<Int>] = [:]
        for stroke in drawing.strokes {
            let signature = InkStrokeIdentity.fingerprint(stroke)
            if let (id, index) = renderedSources[signature], originals[id] != nil {
                retained[id, default: []].insert(index)
                continue
            }
            guard let block = captureAnchor.flatMap({ anchor in blocks.first { $0.blockID == anchor.blockID } })
                ?? Self.anchorBlock(for: stroke.renderBounds, in: blocks) else { continue }
            grouped[block.blockID ?? Self.key(block), default: []].append(stroke)
        }

        var items: [AnchoredInk] = []
        for (id, indices) in retained {
            guard !orphans.contains(where: { $0.id == id }) else { continue }
            guard var item = originals[id],
                  let original = try? PKDrawing(data: item.strokeData) else { continue }
            if item.behavior != .rigid, indices.count < (renderedCounts[id] ?? indices.count) { continue }
            if item.behavior == .rigid && indices.count != original.strokes.count {
                let remaining = original.strokes.enumerated().compactMap { indices.contains($0.offset) ? $0.element : nil }
                let partial = PKDrawing(strokes: remaining)
                item.strokeData = partial.dataRepresentation()
                item.offset = Self.finite(partial.bounds.origin)
                item.size = Self.finite(partial.bounds.size)
            }
            items.append(item)
        }
        let byKey = Dictionary(blocks.map { ($0.blockID ?? Self.key($0), $0) }, uniquingKeysWith: { a, _ in a })
        for (key, strokes) in grouped {
            guard let block = byKey[key] else { continue }
            let origin = block.frame.origin
            let relative = PKDrawing(strokes: strokes)
                .transformed(using: CGAffineTransform(translationX: -origin.x, y: -origin.y))
            var item = AnchoredInk(
                blockHash: block.hash,
                blockSeq: block.seq,
                offset: Self.finite(relative.bounds.origin),
                size: Self.finite(relative.bounds.size),
                strokeData: relative.dataRepresentation()
            )
            item.blockID = block.blockID
            if let anchor = captureAnchor, anchor.blockID == block.blockID {
                item.anchor = anchor
                item.behavior = captureBehavior
            }
            items.append(item)
            originals[item.id] = item
            for (index, stroke) in strokes.enumerated() {
                renderedSources[InkStrokeIdentity.fingerprint(stroke)] = (item.id, index)
            }
            renderedCounts[item.id] = strokes.count
        }

        // Ink anchored to a block that's absent from the current layout never
        // made it into the live drawing (rebuildDrawing skips it), so the
        // re-derivation above can't see it. Carry it forward instead of
        // silently dropping it.
        let unresolved = ink.filter { Self.resolve($0, in: blocks) == nil }
        ink = items + unresolved.filter { missing in !items.contains(where: { $0.id == missing.id }) }
    }

    // MARK: Render (anchors -> PencilKit)

    /// Reconstruct the full drawing for the given (current) block layout.
    func rebuildDrawing(blocks: [Block]) -> PKDrawing {
        var strokes: [PKStroke] = []
        for item in ink {
            rememberOriginal(item)
            guard let block = Self.resolve(item, in: blocks),
                  let relative = try? PKDrawing(data: item.strokeData) else { continue }
            let placed: PKDrawing
            if item.behavior != .rigid, let rects = rangeRects[item.id], !rects.isEmpty,
               let sample = relative.strokes.first {
                let fragments = rects.map { rect -> PKStroke in
                    let y = item.behavior == .underline ? rect.maxY : rect.midY
                    let width = item.behavior == .underline ? max(1, sample.path.first?.size.height ?? 2) : rect.height
                    let points = [rect.minX, rect.maxX].enumerated().map { index, x in
                        PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: Double(index) * 0.01,
                                      size: CGSize(width: width, height: width),
                                      opacity: item.behavior == .highlight ? 0.25 : 1,
                                      force: 1, azimuth: 0, altitude: .pi / 2)
                    }
                    let path = PKStrokePath(controlPoints: points, creationDate: sample.path.creationDate)
                    return PKStroke(ink: sample.ink, path: path)
                }
                placed = PKDrawing(strokes: fragments)
            } else {
                placed = relative.transformed(
                    using: CGAffineTransform(translationX: block.frame.origin.x, y: block.frame.origin.y))
            }
            let archived = originals[item.id].flatMap { try? PKDrawing(data: $0.strokeData) }
            for (index, stroke) in placed.strokes.enumerated() {
                let fingerprint = InkStrokeIdentity.fingerprint(stroke)
                var originalIndex = index
                if item.behavior == .rigid, index < relative.strokes.count {
                    let relativeID = InkStrokeIdentity.fingerprint(relative.strokes[index])
                    originalIndex = archived?.strokes.firstIndex(where: {
                        InkStrokeIdentity.fingerprint($0) == relativeID
                    }) ?? index
                }
                renderedSources[fingerprint] = (item.id, originalIndex)
                strokes.append(stroke)
            }
            renderedCounts[item.id] = placed.strokes.count
        }
        return PKDrawing(strokes: strokes)
    }

    // MARK: External edit -> re-anchor

    /// Apply an external markdown edit: ink whose block survived is followed;
    /// ink whose block disappeared is moved to `orphans`. Never destructive.
    /// Orphans record their last absolute position (from the pre-edit layout) so
    /// they can be restored near where the user last saw them.
    @discardableResult
    func applyExternalEdit(oldBlocks: [Block], newBlocks: [Block]) -> Reanchor.Result {
        let result = Reanchor.reanchor(ink: ink, oldBlocks: oldBlocks, newBlocks: newBlocks)
        ink = result.followed
        let stamped = result.orphaned.map { orphan -> AnchoredInk in
            var copy = orphan
            if copy.lastKnownOrigin == nil {
                copy.lastKnownOrigin = orphan.resolvedOrigin(in: oldBlocks)
            }
            return copy
        }
        orphans.append(contentsOf: stamped)
        return Reanchor.Result(followed: result.followed, orphaned: stamped)
    }

    /// Permanently remove an orphan.
    func removeOrphan(_ id: UUID) {
        guard !isReadOnly else { return }
        orphans.removeAll { $0.id == id }
    }

    func detach(_ id: UUID, blocks: [Block]) {
        guard let index = ink.firstIndex(where: { $0.id == id }) else { return }
        var item = ink.remove(at: index)
        item.lastKnownOrigin = item.resolvedOrigin(in: blocks)
        orphans.append(item)
    }

    /// Re-attach an orphan to the current block nearest its last known position,
    /// keeping it visually where the user last saw it.
    @discardableResult
    func restoreOrphan(_ id: UUID, in blocks: [Block]) -> Bool {
        guard !isReadOnly, let index = orphans.firstIndex(where: { $0.id == id }), !blocks.isEmpty else { return false }
        var item = orphans.remove(at: index)

        // Fail safe: require a real last position AND a decodable payload before
        // any mutation. Otherwise re-insert and bail — a stale offset or corrupt
        // stroke must NOT teleport the ink to the top of the document or persist
        // a broken copy; the orphan stays in the tray, restorable or deletable.
        guard let last = item.lastKnownOrigin else { orphans.insert(item, at: index); return false }
        guard let drawing = try? PKDrawing(data: item.strokeData) else {
            orphans.insert(item, at: index); return false
        }
        let target = Self.nearestBlock(to: last, in: blocks) ?? blocks[0]

        // Translate the (old-block-relative) stroke data so it lands at `last`
        // when later rendered as `targetOrigin + strokeData`.
        let shift = CGPoint(x: last.x - item.offset.x - target.frame.origin.x,
                            y: last.y - item.offset.y - target.frame.origin.y)
        let shifted = drawing.transformed(using: CGAffineTransform(translationX: shift.x, y: shift.y))
        item.strokeData = shifted.dataRepresentation()
        item.offset = Self.finite(shifted.bounds.origin)
        item.size = Self.finite(shifted.bounds.size)
        item.blockHash = target.hash
        item.blockSeq = target.seq
        item.blockID = target.blockID
        item.anchor = nil
        item.behavior = .rigid
        item.lastKnownOrigin = nil
        originals[item.id] = item
        ink.append(item)
        return true
    }

    // MARK: Persistence

    @discardableResult
    func save(blocks: [Block], documentText: String) -> Bool {
        // Never overwrite a sidecar written by a newer build (see isReadOnly).
        guard !isReadOnly else { return true }
        let sidecar = Sidecar(
            documentHash: Hashing.documentHash(documentText),
            layoutWidth: layoutWidth.isFinite ? layoutWidth : 1390,
            blocks: blocks.map(BlockSnapshot.init),
            ink: ink,
            orphans: orphans,
            appVersion: Self.appVersion,
            studyInsertions: studyInsertions
        )
        let data: Data
        do { data = try sidecar.encoded() }
        catch { onSaveFailure?(error); return false }

        // One coordinated retry before giving up, so a transient coordination
        // failure during a background flush doesn't silently drop the ink.
        if coordinatedWrite(data) != nil, let retryError = coordinatedWrite(data) {
            onSaveFailure?(retryError)
            return false
        }
        return true
    }

    /// Coordinated atomic write of the sidecar. Returns the error on failure,
    /// nil on success.
    private func coordinatedWrite(_ data: Data) -> Error? {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: sidecarURL, options: .forReplacing, error: &coordError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        return coordError ?? writeError
    }

    /// Load existing ink. Returns the saved sidecar (with its block snapshot) so
    /// the caller can detect/repair drift against a fresh render.
    @discardableResult
    func load() -> Sidecar? {
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return nil }
        var loaded: Sidecar?
        var decodeError: Error?
        var hadData = false
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: sidecarURL, options: [], error: &coordError) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            hadData = true
            do { loaded = try Sidecar.decoded(from: data) }
            catch { decodeError = error }
        }
        if let loaded {
            renderedSources = [:]
            renderedCounts = [:]
            originals = [:]
            ink = loaded.ink
            orphans = loaded.orphans
            layoutWidth = loaded.layoutWidth
            studyInsertions = loaded.studyInsertions
        } else if let sidecarError = decodeError as? SidecarError {
            // Written by a newer build — the bytes are FINE, just unreadable by
            // this schema. Go read-only so we never overwrite it; no .corrupt
            // backup (nothing is corrupt).
            switch sidecarError {
            case .newerVersion, .unsupportedVersion: isReadOnly = true
            }
        } else if hadData {
            // Genuinely undecodable. Preserve the bytes under a UNIQUE name so a
            // later corruption can't overwrite this evidence.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = sidecarURL.appendingPathExtension("corrupt-\(stamp)")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.copyItem(at: sidecarURL, to: backup)
            }
        }
        return loaded
    }

    /// If this document has no sidecar, look for one stranded by an external
    /// rename (`Old.md.inknote` left behind after `Old.md` -> `New.md` in the
    /// Files app): a sibling whose own markdown file is gone and whose stored
    /// documentHash matches this document's exact text. Conservative on
    /// purpose — a rename + edit won't match, and if another document in the
    /// folder has identical content the ink could belong to it instead, so
    /// the stranded file stays put in both cases.
    func adoptStrandedSidecarIfNeeded(documentText: String) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: sidecarURL.path) else { return }
        let directory = documentURL.deletingLastPathComponent()
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let docHash = Hashing.documentHash(documentText)

        let ambiguous = entries.contains { sibling in
            sibling.standardizedFileURL != documentURL.standardizedFileURL
                && LibraryStore.documentExtensions.contains(sibling.pathExtension.lowercased())
                && (try? String(contentsOf: sibling, encoding: .utf8)).map(Hashing.documentHash) == docHash
        }
        if ambiguous { return }

        for url in entries where url.pathExtension == "inknote" {
            let owner = url.deletingPathExtension()
            guard !fm.fileExists(atPath: owner.path),
                  let data = try? Data(contentsOf: url),
                  let sidecar = try? Sidecar.decoded(from: data),
                  sidecar.documentHash == docHash else { continue }
            try? fm.moveItem(at: url, to: sidecarURL)
            return
        }
    }

    /// Re-key ink saved under an older block-hashing scheme. Hash inputs have
    /// evolved (image alt/src now feed the identity), but `Block.text` still
    /// carries the raw textContent — whose hash IS the legacy identity. Any
    /// ink that doesn't resolve against current identities but matches a
    /// block's legacy hash+seq is re-keyed in place, so it stays exactly
    /// where the user drew it.
    func migrateLegacyAnchors(to blocks: [Block]) {
        let currentKeys = Set(blocks.map(Self.key))
        var legacyIdentity: [String: Block] = [:]
        var counts: [String: Int] = [:]
        for block in blocks {
            let legacyHash = Hashing.blockHash(block.text ?? "")
            let seq = counts[legacyHash, default: 0]
            counts[legacyHash] = seq + 1
            legacyIdentity["\(legacyHash)#\(seq)"] = block
        }
        for index in ink.indices {
            let key = "\(ink[index].blockHash)#\(ink[index].blockSeq)"
            guard !currentKeys.contains(key), let target = legacyIdentity[key] else { continue }
            ink[index].blockHash = target.hash
            ink[index].blockSeq = target.seq
        }
    }

    // MARK: Helpers

    static func key(_ block: Block) -> String { "\(block.hash)#\(block.seq)" }

    private static func resolve(_ item: AnchoredInk, in blocks: [Block]) -> Block? {
        if let id = item.anchor?.blockID ?? item.blockID {
            return blocks.first { $0.blockID == id }
        }
        return blocks.block(hash: item.blockHash, seq: item.blockSeq)
    }

    private func rememberOriginal(_ item: AnchoredInk) {
        if var previous = originals[item.id] {
            previous.blockHash = item.blockHash
            previous.blockSeq = item.blockSeq
            previous.blockID = item.blockID
            previous.anchor = item.anchor
            previous.behavior = item.behavior
            originals[item.id] = previous
        } else {
            originals[item.id] = item
        }
    }

    func restoreStudyTargets(in blocks: [Block]) {
        let ids = Set(studyInsertions.flatMap { [$0.id] + $0.blockIDs })
        let restored = orphans.filter { item in
            guard let id = item.anchor?.blockID ?? item.blockID else { return false }
            return ids.contains(id) && blocks.contains { $0.blockID == id }
        }
        let restoredIDs = Set(restored.map(\.id))
        orphans.removeAll { restoredIDs.contains($0.id) }
        ink.append(contentsOf: restored.map { item in
            var copy = item
            copy.lastKnownOrigin = nil
            return copy
        })
    }

    struct Attachment {
        var blockID: String?
        var blockHash: String
        var blockSeq: Int
        var anchor: TextAnchor?
        var detached: Bool
    }

    func attachments() -> [UUID: Attachment] {
        var result: [UUID: Attachment] = [:]
        for item in ink + orphans {
            result[item.id] = Attachment(blockID: item.blockID, blockHash: item.blockHash,
                                         blockSeq: item.blockSeq, anchor: item.anchor,
                                         detached: orphans.contains { $0.id == item.id })
        }
        return result
    }

    func restoreAttachments(_ saved: [UUID: Attachment]) {
        var attached: [AnchoredInk] = []
        var detached: [AnchoredInk] = []
        for var item in ink + orphans {
            if let reference = saved[item.id] {
                item.blockID = reference.blockID
                item.blockHash = reference.blockHash
                item.blockSeq = reference.blockSeq
                item.anchor = reference.anchor
                if reference.detached { detached.append(item) }
                else { item.lastKnownOrigin = nil; attached.append(item) }
            } else if orphans.contains(where: { $0.id == item.id }) {
                detached.append(item)
            } else {
                attached.append(item)
            }
        }
        ink = attached
        orphans = detached
    }

    func applyTextReplacement(blockID: String, start: Int, end: Int, replacement: String,
                              oldText: String, blocks: [Block]) {
        var detached: [UUID] = []
        for index in ink.indices {
            guard let anchor = ink[index].anchor, anchor.blockID == blockID else { continue }
            if let changed = anchor.applyingReplacement(startUTF16: start, endUTF16: end,
                                                        replacement: replacement, oldText: oldText) {
                ink[index].anchor = changed
            } else {
                detached.append(ink[index].id)
            }
        }
        for id in detached { detach(id, blocks: blocks) }
    }

    func applyBlockMappings(_ mappings: [EditorBlockMapping], blocks: [Block]) {
        var detached: [UUID] = []
        for index in ink.indices {
            let id = ink[index].anchor?.blockID ?? ink[index].blockID
            let candidates = mappings.filter { $0.fromBlockID == id }
            guard !candidates.isEmpty else { continue }
            if let anchor = ink[index].anchor {
                let containing = candidates.filter {
                    anchor.startUTF16 >= $0.fromStartUTF16 && anchor.endUTF16 <= $0.fromEndUTF16
                }
                guard containing.count == 1, let map = containing.first,
                      let changed = anchor.remapped(blockID: map.toBlockID, text: map.targetText,
                                                   offsetDeltaUTF16: map.offsetDeltaUTF16) else {
                    detached.append(ink[index].id)
                    continue
                }
                ink[index].anchor = changed
                ink[index].blockID = map.toBlockID
            } else if let map = candidates.first(where: { $0.fromStartUTF16 == 0 }) {
                ink[index].blockID = map.toBlockID
            }
        }
        for id in detached { detach(id, blocks: blocks) }
    }

    /// The block whose vertical span contains the point, else the vertically
    /// nearest block (so margin scribbles still anchor somewhere sensible).
    static func nearestBlock(to point: CGPoint, in blocks: [Block]) -> Block? {
        if let containing = blocks.first(where: { $0.frame.minY <= point.y && point.y <= $0.frame.maxY }) {
            return containing
        }
        return blocks.min(by: { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) })
    }

    /// The block a stroke should anchor to: the one whose vertical span overlaps
    /// the stroke's bounds the most, so a tall mark (a brace, a long underline, a
    /// circle drawn around several blocks) belongs to the block it covers most —
    /// not just whichever block its top edge happened to land in. Falls back to
    /// the vertically nearest block when there is no overlap (e.g. a scribble in
    /// the writing margin below the last block).
    static func anchorBlock(for rect: CGRect, in blocks: [Block]) -> Block? {
        var best: (Block, CGFloat)?
        for block in blocks {
            let overlap = min(rect.maxY, block.frame.maxY) - max(rect.minY, block.frame.minY)
            if overlap > 0, best == nil || overlap > best!.1 {
                best = (block, overlap)
            }
        }
        if let best { return best.0 }
        return nearestBlock(to: CGPoint(x: rect.midX, y: rect.midY), in: blocks)
    }

    /// Clamp non-finite scalars to 0 so a degenerate stroke bounds can never make
    /// the sidecar JSON unencodable (which would otherwise silently drop a save).
    static func finite(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x.isFinite ? p.x : 0, y: p.y.isFinite ? p.y : 0)
    }
    static func finite(_ s: CGSize) -> CGSize {
        CGSize(width: s.width.isFinite ? s.width : 0, height: s.height.isFinite ? s.height : 0)
    }

    static let appVersion: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1"
}
