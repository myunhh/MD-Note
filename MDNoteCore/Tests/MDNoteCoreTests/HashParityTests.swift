import XCTest
@testable import MDNoteCore

/// Locks invariant #3: `MDNoteCore.Hashing` must stay byte-for-byte identical to
/// `fnv1a`/`normalize` in `bridge.js`. These golden hex values are frozen here
/// AND duplicated verbatim in `MDNoteCore/Tests/parity/hash_parity.mjs`, which
/// runs the REAL bridge.js over the same inputs. That literal duplication IS the
/// cross-language assertion — if either side drifts (a "tidied" JS split, a
/// changed FNV constant), one of the two suites goes red before saved ink can
/// silently detach on the next external edit.
///
/// Scope: covers `normalize` + `fnv1a` + `blockHash` only. `blockIdentityText`
/// (bridge.js) is DOM-bound (image alt/src) and intentionally out of scope; if
/// identity-text construction ever changes, both sides must change together.
final class HashParityTests: XCTestCase {

    /// (label, input, expected blockHash hex). Hand-frozen — never auto-derive.
    static let golden: [(String, String, String)] = [
        ("empty", "", "cbf29ce484222325"),
        ("single", "a", "af63dc4c8601ec8c"),
        ("wrapped-whitespace", "The  quick\nbrown   fox", "2374316b9b449782"),
        ("nbsp-is-content", "\u{00A0}a b\u{00A0}", "7eceb45d77cb6896"),
        ("crlf-grapheme", "line\r\nline", "71a1002c25fbdf27"),
        ("tab", "a\tb c", "69cf480885ad45af"),
        ("emoji-accent", "café 🦊", "684bc87c3c68e35a"),
        ("hangul", "한글  글자\ttest", "d511b87bfe331621"),
    ]

    func testBlockHashMatchesGolden() {
        for (label, input, expected) in Self.golden {
            XCTAssertEqual(Hashing.blockHash(input), expected,
                           "blockHash drifted for case '\(label)' — invariant #3 (JS↔Swift parity) at risk")
        }
    }

    func testDocumentHashIsRawFNV() {
        // documentHash hashes the raw bytes (no normalize) — used for change
        // detection, must also stay stable.
        XCTAssertEqual(Hashing.documentHash("# Hi\n"), "cc38d4aa935e3a19")
    }
}
