#if canImport(UIKit) || canImport(AppKit)
import Foundation

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
#endif
