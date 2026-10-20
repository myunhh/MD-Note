import Foundation

public enum StableBlockIdentity {
    public static func reconcile(old: [Block], new: [Block], documentUnchanged: Bool = false) -> [Block] {
        var used = Set<String>()
        return new.map { block in
            var result = block
            if let id = block.blockID, !id.isEmpty,
               new.filter({ $0.blockID == id }).count == 1 {
                used.insert(id)
                return result
            }
            let candidates = old.filter {
                $0.hash == block.hash && $0.text == block.text
                    && (!documentUnchanged || $0.seq == block.seq)
            }
            let newCount = new.filter {
                $0.hash == block.hash && $0.text == block.text
                    && (!documentUnchanged || $0.seq == block.seq)
            }.count
            let assignedID: String
            if candidates.count == 1, newCount == 1,
               let id = candidates[0].blockID, !id.isEmpty, !used.contains(id),
               old.filter({ $0.blockID == id }).count == 1,
               !new.contains(where: { $0.blockID == id }) {
                assignedID = id
            } else {
                assignedID = UUID().uuidString
            }
            result.blockID = assignedID
            used.insert(assignedID)
            return result
        }
    }
}
