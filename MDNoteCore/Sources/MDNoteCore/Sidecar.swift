import Foundation
import CoreGraphics

/// On-disk companion file stored next to a markdown document
/// (`<name>.md.inknote`). Holds the ink and the block snapshot it was anchored
/// against, so we can detect/repair drift when the markdown changes externally.
public struct Sidecar: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    /// Hash of the full markdown text at save time (cheap external-edit check).
    public var documentHash: String
    /// Fixed layout width the ink was authored against (see "폭 고정" design).
    public var layoutWidth: CGFloat
    /// Snapshot of the blocks (identity + line range + text) at save time.
    public var blocks: [BlockSnapshot]
    public var ink: [AnchoredInk]
    public var orphans: [AnchoredInk]
    public var appVersion: String
    public var studyInsertions: [StudyInsertion]

    public init(
        version: Int = Sidecar.currentVersion,
        documentHash: String,
        layoutWidth: CGFloat,
        blocks: [BlockSnapshot],
        ink: [AnchoredInk],
        orphans: [AnchoredInk] = [],
        appVersion: String,
        studyInsertions: [StudyInsertion] = []
    ) {
        self.version = version
        self.documentHash = documentHash
        self.layoutWidth = layoutWidth
        self.blocks = blocks
        self.ink = ink
        self.orphans = orphans
        self.appVersion = appVersion
        self.studyInsertions = studyInsertions
    }

    private enum CodingKeys: String, CodingKey {
        case version, documentHash, layoutWidth, blocks, ink, orphans, appVersion, studyInsertions
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else { throw SidecarError.newerVersion(version) }
        guard version >= 1 else { throw SidecarError.unsupportedVersion(version) }
        documentHash = try values.decode(String.self, forKey: .documentHash)
        layoutWidth = try values.decode(CGFloat.self, forKey: .layoutWidth)
        blocks = try values.decode([BlockSnapshot].self, forKey: .blocks)
        ink = try values.decode([AnchoredInk].self, forKey: .ink)
        orphans = try values.decodeIfPresent([AnchoredInk].self, forKey: .orphans) ?? []
        appVersion = try values.decode(String.self, forKey: .appVersion)
        studyInsertions = try values.decodeIfPresent([StudyInsertion].self, forKey: .studyInsertions) ?? []
        if version == 1 { migrateVersionOne() }
    }

    private mutating func migrateVersionOne() {
        for index in blocks.indices where blocks[index].blockID == nil {
            blocks[index].blockID = UUID().uuidString
        }
        var migratedInk: [AnchoredInk] = []
        for item in ink {
            var migrated = item
            let candidates = blocks.filter { $0.hash == item.blockHash && $0.seq == item.blockSeq }
            if candidates.count == 1 {
                migrated.blockID = candidates[0].blockID
                migratedInk.append(migrated)
            } else {
                orphans.append(item)
            }
        }
        ink = migratedInk
        version = Self.currentVersion
    }

    public func encoded() throws -> Data {
        guard version <= Self.currentVersion else { throw SidecarError.newerVersion(version) }
        guard version >= 1 else { throw SidecarError.unsupportedVersion(version) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Decode a sidecar, gating on its version so a file written by a NEWER app
    /// build is recognised as *newer*, not corrupt. The caller can then refuse
    /// to overwrite it (instead of clobbering the user's ink with an older
    /// schema). A genuine decode failure still throws the underlying error.
    public static func decoded(from data: Data) throws -> Sidecar {
        if let env = try? JSONDecoder().decode(VersionEnvelope.self, from: data),
           env.version > currentVersion {
            throw SidecarError.newerVersion(env.version)
        }
        return try JSONDecoder().decode(Sidecar.self, from: data)
    }
}

/// Errors surfaced while loading a sidecar.
public enum SidecarError: Error, Equatable, Sendable {
    /// The file was written by a newer app version (version > currentVersion).
    /// Its bytes are intact — do not back up as `.corrupt`, and do not overwrite.
    case newerVersion(Int)
    case unsupportedVersion(Int)
}

/// Cheap probe that reads only the version field, so a forward-incompatible
/// sidecar can be detected before attempting a full decode against this build's
/// schema.
private struct VersionEnvelope: Decodable { let version: Int }

/// Lightweight, geometry-free record of a block as it was when ink was saved.
/// (Geometry is recomputed from a fresh render on load, so we don't persist it.)
public struct BlockSnapshot: Codable, Equatable, Sendable {
    public var blockID: String?
    public var hash: String
    public var seq: Int
    public var sourceLineStart: Int
    public var sourceLineEnd: Int
    public var text: String?

    public init(hash: String, seq: Int, sourceLineStart: Int, sourceLineEnd: Int, text: String? = nil,
                blockID: String? = nil) {
        self.hash = hash
        self.seq = seq
        self.sourceLineStart = sourceLineStart
        self.sourceLineEnd = sourceLineEnd
        self.text = text
        self.blockID = blockID
    }

    public init(_ block: Block) {
        self.init(
            hash: block.hash,
            seq: block.seq,
            sourceLineStart: block.sourceLineStart,
            sourceLineEnd: block.sourceLineEnd,
            text: block.text,
            blockID: block.blockID
        )
    }

    /// Reconstruct a geometry-less `Block` for matching purposes.
    public var block: Block {
        Block(hash: hash, seq: seq, sourceLineStart: sourceLineStart,
              sourceLineEnd: sourceLineEnd, frame: .zero, text: text, blockID: blockID)
    }
}
