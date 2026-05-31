#if canImport(UIKit) || canImport(AppKit)
import Foundation
import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
package enum TextLayoutGeometry {
    package static func ranges(_ ranges: [NSRange], intersecting targetRange: NSRange) -> [NSRange] {
        guard !ranges.isEmpty, targetRange.length > 0 else { return [] }
        return ranges.compactMap { range in
            let intersection = NSIntersectionRange(range, targetRange)
            return intersection.length > 0 ? intersection : nil
        }
    }

    package static func standardRects(
        layoutManager: NSTextLayoutManager,
        rangeConverter: TextRangeConverter,
        ranges: [NSRange],
        offsetBy origin: CGPoint = .zero
    ) -> [CGRect] {
        textSegmentRects(
            layoutManager: layoutManager,
            rangeConverter: rangeConverter,
            ranges: ranges,
            offsetBy: origin,
            segmentKind: .standard
        )
    }

    package static func selectionRects(
        layoutManager: NSTextLayoutManager,
        rangeConverter: TextRangeConverter,
        ranges: [NSRange],
        offsetBy origin: CGPoint = .zero
    ) -> [CGRect] {
        textSegmentRects(
            layoutManager: layoutManager,
            rangeConverter: rangeConverter,
            ranges: ranges,
            offsetBy: origin,
            segmentKind: .selection
        )
    }

    private static func textSegmentRects(
        layoutManager: NSTextLayoutManager,
        rangeConverter: TextRangeConverter,
        ranges: [NSRange],
        offsetBy origin: CGPoint,
        segmentKind: TextSegmentKind
    ) -> [CGRect] {
        guard !ranges.isEmpty else { return [] }

        var rects: [CGRect] = []
        for range in ranges {
            guard let textRange = rangeConverter.textRange(forUTF16Range: range) else { continue }
            layoutManager.ensureLayout(for: textRange)
            switch segmentKind {
            case .standard:
                layoutManager.enumerateTextSegments(
                    in: textRange,
                    type: .standard,
                    options: [.rangeNotRequired]
                ) { _, rect, _, _ in
                    rects.append(rect.offsetBy(dx: -origin.x, dy: -origin.y))
                    return true
                }
            case .selection:
                layoutManager.enumerateTextSegments(
                    in: textRange,
                    type: .selection,
                    options: [.upstreamAffinity]
                ) { _, rect, _, _ in
                    rects.append(rect.offsetBy(dx: -origin.x, dy: -origin.y))
                    return true
                }
            }
        }
        return rects
    }

    private enum TextSegmentKind {
        case standard
        case selection
    }
}

package struct TextRangeIntersectionIndex {
    private let ranges: [NSRange]
    private let prefixMaxUpperBounds: [Int]

    package init(ranges: [NSRange] = [], utf16Length: Int) {
        var normalized: [NSRange] = []
        normalized.reserveCapacity(ranges.count)
        for range in ranges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: utf16Length)
            guard clamped.length > 0 else { continue }
            normalized.append(clamped)
        }
        normalized.sort {
            if $0.location == $1.location {
                return $0.upperBound < $1.upperBound
            }
            return $0.location < $1.location
        }

        self.ranges = normalized

        var maxUpperBound = 0
        var prefixMaxUpperBounds: [Int] = []
        prefixMaxUpperBounds.reserveCapacity(normalized.count)
        for range in normalized {
            maxUpperBound = max(maxUpperBound, range.upperBound)
            prefixMaxUpperBounds.append(maxUpperBound)
        }
        self.prefixMaxUpperBounds = prefixMaxUpperBounds
    }

    package var isEmpty: Bool {
        ranges.isEmpty
    }

    package func ranges(intersecting targetRange: NSRange) -> [NSRange] {
        sourceRanges(intersecting: targetRange).compactMap { range in
            let intersection = NSIntersectionRange(range, targetRange)
            return intersection.length > 0 ? intersection : nil
        }
    }

    package func sourceRanges(intersecting targetRange: NSRange) -> [NSRange] {
        guard !ranges.isEmpty, targetRange.length > 0 else { return [] }

        let endIndex = firstRangeIndex(withLocationAtLeast: targetRange.upperBound)
        let startIndex = firstPrefixMaxUpperBoundIndex(greaterThan: targetRange.location)
        guard startIndex < endIndex else { return [] }

        var sourceRanges: [NSRange] = []
        for range in ranges[startIndex..<endIndex] {
            if NSIntersectionRange(range, targetRange).length > 0 {
                sourceRanges.append(range)
            }
        }
        return sourceRanges
    }

    private func firstRangeIndex(withLocationAtLeast location: Int) -> Int {
        var lower = ranges.startIndex
        var upper = ranges.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if ranges[middle].location < location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func firstPrefixMaxUpperBoundIndex(greaterThan location: Int) -> Int {
        var lower = prefixMaxUpperBounds.startIndex
        var upper = prefixMaxUpperBounds.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if prefixMaxUpperBounds[middle] <= location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}
#endif
