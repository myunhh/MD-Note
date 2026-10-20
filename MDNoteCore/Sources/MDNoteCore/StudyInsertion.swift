import Foundation

public enum StudyInsertionKind: String, Codable, Sendable { case blank, markdown }
public enum StudyPlacement: String, Codable, Sendable { case flow, floating }

/// The insertion's `id` is also its ink target block ID. A missing parent is
/// retained for reattachment, never silently rebound to another paragraph.
public struct StudyInsertion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var afterBlockID: String?
    public var kind: StudyInsertionKind
    public var markdown: String
    public var height: Double
    public var placement: StudyPlacement
    public var order: Int
    public var blockIDs: [String]

    public init(id: String = UUID().uuidString, afterBlockID: String? = nil,
                kind: StudyInsertionKind = .blank, markdown: String = "",
                height: Double = 160, placement: StudyPlacement = .flow, order: Int = 0,
                blockIDs: [String] = []) {
        self.id = id
        self.afterBlockID = afterBlockID
        self.kind = kind
        self.markdown = markdown
        self.height = height
        self.placement = placement
        self.order = order
        self.blockIDs = blockIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, afterBlockID, kind, markdown, height, placement, order, blockIDs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        afterBlockID = try values.decodeIfPresent(String.self, forKey: .afterBlockID)
        kind = try values.decode(StudyInsertionKind.self, forKey: .kind)
        markdown = try values.decode(String.self, forKey: .markdown)
        height = try values.decode(Double.self, forKey: .height)
        placement = try values.decode(StudyPlacement.self, forKey: .placement)
        order = try values.decode(Int.self, forKey: .order)
        blockIDs = try values.decodeIfPresent([String].self, forKey: .blockIDs) ?? []
    }

    public var isValid: Bool {
        !id.isEmpty && height.isFinite && height >= 0 && afterBlockID != id
    }
}

/// Pure value operations: retain the previous array for undo/redo. Removing a
/// space does not remove associated ink; reconciliation detaches that ink.
public enum StudyInsertions {
    public static func upserting(_ insertion: StudyInsertion, in items: [StudyInsertion]) -> [StudyInsertion]? {
        guard insertion.isValid else { return nil }
        var result = items
        if let index = result.firstIndex(where: { $0.id == insertion.id }) {
            result[index] = insertion
        } else {
            result.append(insertion)
        }
        return result
    }

    public static func removing(id: String, from items: [StudyInsertion]) -> [StudyInsertion] {
        items.filter { $0.id != id }
    }
}
