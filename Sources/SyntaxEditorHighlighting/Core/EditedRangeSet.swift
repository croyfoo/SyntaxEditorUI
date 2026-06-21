import Foundation
import SyntaxEditorCoreTypes
import SyntaxEditorLanguageHTML
import SyntaxEditorLanguageSupport
import SyntaxEditorLanguages
import SyntaxEditorTheme

/// A coalescing set of invalidated UTF-16 ranges that survives cancellation.
///
/// Modeled on CotEditor's `EditedRangeSet`: work that gets cancelled leaves its
/// ranges here; every committed edit splices the stored ranges into the new
/// coordinate space; consumers drain chunks (viewport-first) until empty.
package struct EditedRangeSet: Sendable {
    package private(set) var ranges = IndexSet()

    package init() {}

    package var isEmpty: Bool { ranges.isEmpty }

    package mutating func insert(_ range: NSRange) {
        guard range.length > 0, range.location >= 0 else { return }
        ranges.insert(integersIn: range.location..<range.upperBound)
    }

    package mutating func formUnion(_ other: EditedRangeSet) {
        ranges.formUnion(other.ranges)
    }

    package mutating func clear() {
        ranges.removeAll()
    }

    package mutating func remove(_ range: NSRange) {
        guard range.length > 0 else { return }
        ranges.remove(integersIn: range.location..<range.upperBound)
    }

    /// Splices the stored ranges through a text mutation (pre-edit coordinates,
    /// `newLength` = replacement UTF-16 length): positions after the replaced
    /// region shift by the delta; positions inside it collapse onto the
    /// replacement range, which is marked invalid when any stored range touched it.
    package mutating func splice(location: Int, oldLength: Int, newLength: Int, documentLength: Int) {
        guard !ranges.isEmpty else { return }
        let delta = newLength - oldLength
        let oldEnd = location + oldLength
        var next = IndexSet()
        var touchedReplacement = false

        for range in ranges.rangeView {
            let lower = range.lowerBound
            let upper = range.upperBound
            if upper <= location {
                next.insert(integersIn: lower..<upper)
                continue
            }
            if lower >= oldEnd {
                let shiftedLower = lower + delta
                let shiftedUpper = upper + delta
                if shiftedUpper > shiftedLower, shiftedLower >= 0 {
                    next.insert(integersIn: shiftedLower..<min(shiftedUpper, documentLength))
                }
                continue
            }
            // Overlaps the replaced region: keep the outside parts, mark the
            // replacement itself invalid.
            touchedReplacement = true
            if lower < location {
                next.insert(integersIn: lower..<location)
            }
            if upper > oldEnd {
                let shiftedUpper = upper + delta
                let start = location + newLength
                if shiftedUpper > start {
                    next.insert(integersIn: start..<min(shiftedUpper, documentLength))
                }
            }
        }
        if touchedReplacement, newLength > 0 {
            next.insert(integersIn: location..<min(location + newLength, documentLength))
        }
        ranges = next
    }

    /// Removes and returns the next chunk to process: the contiguous stored range
    /// nearest to `near` (or the first one), clipped to `budget` UTF-16 units.
    package mutating func popChunk(near hint: Int?, budget: Int) -> NSRange? {
        guard !ranges.isEmpty else { return nil }
        var chosen: Range<Int>?
        if let hint {
            var bestDistance = Int.max
            for range in ranges.rangeView {
                let distance = range.contains(hint)
                    ? 0
                    : min(abs(range.lowerBound - hint), abs(range.upperBound - hint))
                if distance < bestDistance {
                    bestDistance = distance
                    chosen = range
                    if distance == 0 { break }
                }
            }
        } else {
            chosen = ranges.rangeView.first { _ in true }
        }
        guard let range = chosen else { return nil }
        let length = min(range.count, max(1, budget))
        let start: Int
        if let hint, range.contains(hint) {
            // Center the chunk on the hint inside this range.
            start = max(range.lowerBound, min(hint - length / 2, range.upperBound - length))
        } else {
            start = range.lowerBound
        }
        let chunk = NSRange(location: start, length: min(length, range.upperBound - start))
        ranges.remove(integersIn: chunk.location..<chunk.upperBound)
        return chunk
    }
}
