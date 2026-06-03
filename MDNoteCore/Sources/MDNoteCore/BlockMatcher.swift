import Foundation

/// Aligns two block sequences across an external markdown edit.
///
/// We match by the *sequence* of block content hashes using a Longest Common
/// Subsequence. This correctly handles insertions, deletions, and duplicate
/// blocks (it aligns by position within the LCS rather than by naive key
/// lookup, so repeated identical blocks keep their relative order).
public enum BlockMatcher {

    public struct Pair: Equatable, Sendable {
        public let oldIndex: Int
        public let newIndex: Int
        public init(oldIndex: Int, newIndex: Int) {
            self.oldIndex = oldIndex
            self.newIndex = newIndex
        }
    }

    /// Longest Common Subsequence alignment of two hash sequences.
    /// Returns matched `(oldIndex, newIndex)` pairs in ascending order.
    public static func lcs(_ a: [String], _ b: [String]) -> [Pair] {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return [] }

        // dp[i][j] = LCS length of a[i...] and b[j...]
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        var i = n - 1
        while i >= 0 {
            var j = m - 1
            while j >= 0 {
                if a[i] == b[j] {
                    dp[i][j] = dp[i + 1][j + 1] + 1
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
                j -= 1
            }
            i -= 1
        }

        var pairs: [Pair] = []
        var x = 0, y = 0
        while x < n && y < m {
            if a[x] == b[y] {
                pairs.append(Pair(oldIndex: x, newIndex: y))
                x += 1; y += 1
            } else if dp[x + 1][y] >= dp[x][y + 1] {
                x += 1
            } else {
                y += 1
            }
        }
        return pairs
    }

    /// Convenience: align two `Block` arrays by their content hashes.
    public static func match(old: [Block], new: [Block]) -> [Pair] {
        lcs(old.map(\.hash), new.map(\.hash))
    }
}
