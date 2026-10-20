import Foundation

public enum AnnotationBehavior: String, Codable, Sendable {
    case rigid, underline, highlight
}

/// Offsets crossing the JavaScript boundary are half-open UTF-16 offsets.
/// Conversion requires whole extended grapheme clusters, including Korean and emoji.
public struct TextAnchor: Codable, Equatable, Sendable {
    public var blockID: String
    public var startUTF16: Int
    public var endUTF16: Int
    public var quote: String
    public var prefix: String
    public var suffix: String

    public init(blockID: String, startUTF16: Int, endUTF16: Int,
                quote: String = "", prefix: String = "", suffix: String = "") {
        self.blockID = blockID
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
        self.quote = quote
        self.prefix = prefix
        self.suffix = suffix
    }

    public static func stringRange(in text: String, startUTF16: Int,
                                   endUTF16: Int) -> Range<String.Index>? {
        guard startUTF16 >= 0, endUTF16 >= startUTF16,
              endUTF16 <= text.utf16.count else { return nil }
        var boundaries: [Int: String.Index] = [:]
        for index in text.indices {
            boundaries[index.utf16Offset(in: text)] = index
        }
        boundaries[text.utf16.count] = text.endIndex
        guard let start = boundaries[startUTF16], let end = boundaries[endUTF16] else { return nil }
        return start..<end
    }

    public static func capture(blockID: String, text: String, startUTF16: Int,
                               endUTF16: Int) -> TextAnchor? {
        guard !blockID.isEmpty,
              let range = stringRange(in: text, startUTF16: startUTF16, endUTF16: endUTF16) else { return nil }
        return TextAnchor(blockID: blockID, startUTF16: startUTF16, endUTF16: endUTF16,
                          quote: String(text[range]),
                          prefix: String(text[..<range.lowerBound].suffix(24)),
                          suffix: String(text[range.upperBound...].prefix(24)))
    }

    /// Use for unknown/external edits. Repeated quotes require unique context;
    /// the previous ordinal/offset never resolves an ambiguous match.
    public func reconciled(in text: String) -> TextAnchor? {
        guard !quote.isEmpty else { return nil }
        var matches: [TextAnchor] = []
        for index in text.indices where text[index...].hasPrefix(quote) {
            let start = index.utf16Offset(in: text)
            guard let candidate = Self.capture(blockID: blockID, text: text,
                                               startUTF16: start, endUTF16: start + quote.utf16.count) else { continue }
            matches.append(candidate)
        }
        if matches.count == 1 { return matches[0] }
        let contextual = matches.filter {
            (prefix.isEmpty || $0.prefix.hasSuffix(prefix))
                && (suffix.isEmpty || $0.suffix.hasPrefix(suffix))
        }
        return contextual.count == 1 ? contextual[0] : nil
    }

    /// Apply an editor-provided replacement in the same block. Insertions at
    /// either edge stay outside the selected text; deletion of the whole target detaches.
    public func applyingReplacement(startUTF16 editStart: Int, endUTF16 editEnd: Int,
                                    replacement: String, oldText: String) -> TextAnchor? {
        guard let editRange = Self.stringRange(in: oldText, startUTF16: editStart, endUTF16: editEnd),
              let ownRange = Self.stringRange(in: oldText, startUTF16: startUTF16, endUTF16: endUTF16),
              String(oldText[ownRange]) == quote else { return nil }
        var newText = oldText
        newText.replaceSubrange(editRange, with: replacement)
        let delta = replacement.utf16.count - (editEnd - editStart)
        let start: Int
        let end: Int
        if editEnd <= startUTF16 {
            start = startUTF16 + delta
            end = endUTF16 + delta
        } else if editStart >= endUTF16 {
            start = startUTF16
            end = endUTF16
        } else {
            guard !(editStart <= startUTF16 && editEnd >= endUTF16) else { return nil }
            start = min(startUTF16, editStart)
            end = editEnd >= endUTF16 ? editStart + replacement.utf16.count : endUTF16 + delta
        }
        guard end > start else { return nil }
        return Self.capture(blockID: blockID, text: newText, startUTF16: start, endUTF16: end)
    }

    public func remapped(blockID: String, text: String, offsetDeltaUTF16: Int) -> TextAnchor? {
        let (start, startOverflow) = startUTF16.addingReportingOverflow(offsetDeltaUTF16)
        let (end, endOverflow) = endUTF16.addingReportingOverflow(offsetDeltaUTF16)
        guard !startOverflow, !endOverflow,
              let mapped = Self.capture(blockID: blockID, text: text, startUTF16: start, endUTF16: end),
              mapped.quote == quote else { return nil }
        return mapped
    }
}
