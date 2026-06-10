import Foundation

/// Deterministic, process-stable hashing and text utilities used to identify
/// markdown blocks across edits.
///
/// NOTE: Swift's built-in `Hashable`/`hashValue` is randomly salted per process,
/// so it is unusable for persisting block identity. We use FNV-1a instead.
public enum Hashing {

    /// 64-bit FNV-1a hash of a string's UTF-8 bytes, rendered as hex.
    public static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(hash, radix: 16)
    }

    /// Collapse all ASCII-whitespace runs to a single space. This makes the
    /// hash insensitive to source re-wrapping while staying sensitive to the
    /// actual visible content of a block.
    ///
    /// Must stay byte-for-byte identical to `normalize` in bridge.js, which
    /// splits on ASCII whitespace only — so Unicode spaces (NBSP etc.) count as
    /// content, not separators, on both sides. Splitting works on Unicode
    /// scalars, not Characters: as a Character, "\r\n" is ONE grapheme that a
    /// Character-level split would fail to treat as whitespace.
    public static func normalize(_ text: String) -> String {
        var parts: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case " ", "\t", "\n", "\r":
                if !current.isEmpty { parts.append(current); current = "" }
            default:
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.joined(separator: " ")
    }

    /// Stable content hash for a markdown block.
    public static func blockHash(_ text: String) -> String {
        fnv1a(normalize(text))
    }

    /// Hash of an entire markdown document (used to detect external edits).
    public static func documentHash(_ markdown: String) -> String {
        fnv1a(markdown)
    }

    /// Word-set Jaccard similarity in [0, 1]. Used to suggest where orphaned ink
    /// might re-attach after a block was edited (not deleted).
    public static func similarity(_ a: String, _ b: String) -> Double {
        let wa = Set(normalize(a).lowercased().split(separator: " "))
        let wb = Set(normalize(b).lowercased().split(separator: " "))
        if wa.isEmpty && wb.isEmpty { return 1 }
        let intersection = wa.intersection(wb).count
        let union = wa.union(wb).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }
}
