#if canImport(UIKit) || canImport(AppKit)
import Foundation
import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SyntaxEditorTextKit2ColorRun {
    var range: NSRange
    let color: SyntaxEditorColor
}

struct SyntaxEditorTextKit2FontRun {
    var range: NSRange
    let font: SyntaxEditorFont
}

struct SyntaxEditorTextKit2RunSet {
    let colorRuns: [SyntaxEditorTextKit2ColorRun]
    let fontRuns: [SyntaxEditorTextKit2FontRun]
}

@MainActor
final class SyntaxEditorTextKit2RenderStore {
    private(set) var epoch = 0
    private(set) var materializationCount = 0
    private var textLength = 0
    private var baseForeground: SyntaxEditorColor?
    private var colorRuns: [SyntaxEditorTextKit2ColorRun] = []
    private var foregroundExclusionRanges: [NSRange] = []

    var hasForegroundRuns: Bool {
        baseForeground != nil || !colorRuns.isEmpty
    }

    func installForeground(
        colorRuns nextColorRuns: [SyntaxEditorTextKit2ColorRun],
        baseForeground nextBaseForeground: SyntaxEditorColor?,
        textLength nextTextLength: Int
    ) {
        textLength = max(0, nextTextLength)
        baseForeground = nextBaseForeground
        colorRuns = nextColorRuns
            .map { run in
                SyntaxEditorTextKit2ColorRun(
                    range: SyntaxEditorRangeUtilities.clampedRange(run.range, utf16Length: textLength),
                    color: run.color
                )
            }
            .filter { $0.range.length > 0 }
            .sorted { lhs, rhs in
                if lhs.range.location == rhs.range.location {
                    lhs.range.length < rhs.range.length
                } else {
                    lhs.range.location < rhs.range.location
                }
            }
        epoch += 1
    }

    func clearForeground(textLength nextTextLength: Int) {
        textLength = max(0, nextTextLength)
        baseForeground = nil
        colorRuns = []
        foregroundExclusionRanges = []
        epoch += 1
    }

    func setForegroundExclusionRanges(_ ranges: [NSRange], textLength nextTextLength: Int) {
        textLength = max(0, nextTextLength)
        foregroundExclusionRanges = ranges
            .map { SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: textLength) }
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
        epoch += 1
    }

    func prepareForegroundForPendingTextMutation(
        _ mutation: SyntaxHighlightMutation,
        sourceLength nextTextLength: Int,
        invalidatedRange: NSRange
    ) {
        textLength = max(0, nextTextLength)
        let clampedInvalidatedRange = SyntaxEditorRangeUtilities.clampedRange(
            invalidatedRange,
            utf16Length: textLength
        )
        colorRuns = shiftedColorRuns(
            colorRuns,
            by: mutation,
            sourceLength: textLength,
            removing: clampedInvalidatedRange
        )
        foregroundExclusionRanges = foregroundExclusionRanges.flatMap { range in
            splitRangeAfterMutation(range, by: mutation, sourceLength: textLength)
                .flatMap { rangesBySubtracting(clampedInvalidatedRange, from: $0) }
        }
        epoch += 1
    }

    func materializeForeground(
        in requestedRange: NSRange,
        using applier: (NSRange, SyntaxEditorColor?) -> Void
    ) {
        let clampedRequestedRange = SyntaxEditorRangeUtilities.clampedRange(
            requestedRange,
            utf16Length: textLength
        )
        guard clampedRequestedRange.length > 0 else { return }

        materializationCount += 1
        applier(clampedRequestedRange, baseForeground)

        var runIndex = lowerBoundColorRunIndex(for: clampedRequestedRange.location)
        while runIndex < colorRuns.count {
            let run = colorRuns[runIndex]
            guard run.range.location < clampedRequestedRange.upperBound else { break }

            let intersection = NSIntersectionRange(run.range, clampedRequestedRange)
            if intersection.length > 0 {
                applyForeground(
                    run.color,
                    in: intersection,
                    excluding: foregroundExclusionRanges,
                    applier: applier
                )
            }
            runIndex += 1
        }

        for excludedRange in foregroundExclusionRanges {
            let intersection = NSIntersectionRange(excludedRange, clampedRequestedRange)
            if intersection.length > 0 {
                applier(intersection, nil)
            }
        }
    }

    func foregroundColor(at location: Int) -> SyntaxEditorColor? {
        var foregroundColor: SyntaxEditorColor?
        materializeForeground(in: NSRange(location: location, length: 1)) { _, color in
            foregroundColor = color
        }
        return foregroundColor
    }

    private func applyForeground(
        _ color: SyntaxEditorColor,
        in range: NSRange,
        excluding excludedRanges: [NSRange],
        applier: (NSRange, SyntaxEditorColor?) -> Void
    ) {
        var remainingRanges = [range]
        for excludedRange in excludedRanges {
            remainingRanges = remainingRanges.flatMap { remainingRange in
                subtract(excludedRange, from: remainingRange)
            }
            guard !remainingRanges.isEmpty else { return }
        }

        for remainingRange in remainingRanges {
            applier(remainingRange, color)
        }
    }

    private func subtract(_ removedRange: NSRange, from range: NSRange) -> [NSRange] {
        let intersection = NSIntersectionRange(removedRange, range)
        guard intersection.length > 0 else { return [range] }

        var ranges: [NSRange] = []
        if intersection.location > range.location {
            ranges.append(NSRange(location: range.location, length: intersection.location - range.location))
        }
        if intersection.upperBound < range.upperBound {
            ranges.append(NSRange(location: intersection.upperBound, length: range.upperBound - intersection.upperBound))
        }
        return ranges
    }

    private func lowerBoundColorRunIndex(for location: Int) -> Int {
        var lowerBound = 0
        var upperBound = colorRuns.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if colorRuns[midIndex].range.upperBound <= location {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return lowerBound
    }

    private func shiftedColorRuns(
        _ runs: [SyntaxEditorTextKit2ColorRun],
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int,
        removing invalidatedRange: NSRange
    ) -> [SyntaxEditorTextKit2ColorRun] {
        var shiftedRuns: [SyntaxEditorTextKit2ColorRun] = []
        shiftedRuns.reserveCapacity(runs.count)

        for run in runs {
            guard let shiftedRange = shiftedRangeAfterMutation(
                run.range,
                by: mutation,
                sourceLength: sourceLength
            ) else {
                continue
            }
            for remainingRange in rangesBySubtracting(invalidatedRange, from: shiftedRange) {
                shiftedRuns.append(SyntaxEditorTextKit2ColorRun(range: remainingRange, color: run.color))
            }
        }

        return shiftedRuns
    }

    private func shiftedRangeAfterMutation(
        _ range: NSRange,
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int
    ) -> NSRange? {
        let editEnd = mutation.location + mutation.length
        let delta = mutation.replacement.utf16.count - mutation.length
        let shifted: NSRange
        if range.upperBound <= mutation.location {
            shifted = range
        } else if range.location >= editEnd {
            shifted = NSRange(location: range.location + delta, length: range.length)
        } else {
            return nil
        }

        let clamped = SyntaxEditorRangeUtilities.clampedRange(shifted, utf16Length: sourceLength)
        return clamped.length > 0 ? clamped : nil
    }

    private func splitRangeAfterMutation(
        _ range: NSRange,
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int
    ) -> [NSRange] {
        let editEnd = mutation.location + mutation.length
        let delta = mutation.replacement.utf16.count - mutation.length
        var ranges: [NSRange] = []

        if range.location < mutation.location {
            ranges.append(NSRange(location: range.location, length: min(range.upperBound, mutation.location) - range.location))
        }
        if range.upperBound > editEnd {
            let shiftedLocation = max(range.location, editEnd) + delta
            ranges.append(NSRange(location: shiftedLocation, length: range.upperBound - max(range.location, editEnd)))
        }

        return ranges.compactMap { range in
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: sourceLength)
            return clamped.length > 0 ? clamped : nil
        }
    }

    private func rangesBySubtracting(_ removal: NSRange, from range: NSRange) -> [NSRange] {
        let intersection = SyntaxEditorRangeUtilities.intersection(of: range, and: removal)
        guard intersection.length > 0 else { return [range] }

        var ranges: [NSRange] = []
        if intersection.location > range.location {
            ranges.append(NSRange(location: range.location, length: intersection.location - range.location))
        }
        if intersection.upperBound < range.upperBound {
            ranges.append(NSRange(location: intersection.upperBound, length: range.upperBound - intersection.upperBound))
        }
        return ranges
    }
}

@MainActor
final class SyntaxEditorTextKit2System {
    let textContentStorage: NSTextContentStorage
    let layoutManager: NSTextLayoutManager
    let container: NSTextContainer
    let renderStore: SyntaxEditorTextKit2RenderStore

    init(
        textContentStorage: NSTextContentStorage = NSTextContentStorage(),
        layoutManager: NSTextLayoutManager = NSTextLayoutManager(),
        container: NSTextContainer = NSTextContainer(),
        renderStore: SyntaxEditorTextKit2RenderStore = SyntaxEditorTextKit2RenderStore()
    ) {
        self.textContentStorage = textContentStorage
        self.layoutManager = layoutManager
        self.container = container
        self.renderStore = renderStore

        layoutManager.textContainer = container
        textContentStorage.addTextLayoutManager(layoutManager)
        textContentStorage.primaryTextLayoutManager = layoutManager

        layoutManager.renderingAttributesValidator = { [weak textContentStorage, weak renderStore] layoutManager, fragment in
            guard let textContentStorage,
                  let renderStore
            else { return }
            SyntaxEditorTextKit2HighlightRenderer.validateRenderingAttributes(
                layoutManager: layoutManager,
                textContentStorage: textContentStorage,
                renderStore: renderStore,
                fragment: fragment
            )
        }
    }

    var textStorage: NSTextStorage {
        guard let textStorage = textContentStorage.textStorage else {
            fatalError("SyntaxEditorTextKit2System requires NSTextContentStorage-backed NSTextStorage")
        }
        return textStorage
    }

    func textLocation(forUTF16Offset offset: Int) -> NSTextLocation? {
        let clampedOffset = min(max(0, offset), textStorage.length)
        return textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: clampedOffset
        )
    }

    func utf16Offset(for textLocation: NSTextLocation) -> Int {
        textContentStorage.offset(
            from: textContentStorage.documentRange.location,
            to: textLocation
        )
    }

    func textRange(forUTF16Range range: NSRange) -> NSTextRange? {
        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textStorage.length)
        guard let startLocation = textLocation(forUTF16Offset: clampedRange.location),
              let endLocation = textLocation(forUTF16Offset: clampedRange.location + clampedRange.length)
        else {
            return nil
        }
        return NSTextRange(location: startLocation, end: endLocation)
    }

    func utf16Range(for textRange: NSTextRange) -> NSRange {
        NSRange(
            location: textContentStorage.offset(
                from: textContentStorage.documentRange.location,
                to: textRange.location
            ),
            length: textContentStorage.offset(
                from: textRange.location,
                to: textRange.endLocation
            )
        )
    }

    func invalidateRenderingAttributes(for range: NSRange) {
        guard let textRange = textRange(forUTF16Range: range) else { return }
        layoutManager.invalidateRenderingAttributes(for: textRange)
    }
}

enum SyntaxEditorTextKit2HighlightRenderer {
    @MainActor
    static func validateRenderingAttributes(
        layoutManager: NSTextLayoutManager,
        textContentStorage: NSTextContentStorage,
        renderStore: SyntaxEditorTextKit2RenderStore,
        fragment: NSTextLayoutFragment
    ) {
        let fragmentRange = NSRange(
            location: textContentStorage.offset(
                from: textContentStorage.documentRange.location,
                to: fragment.rangeInElement.location
            ),
            length: textContentStorage.offset(
                from: fragment.rangeInElement.location,
                to: fragment.rangeInElement.endLocation
            )
        )
        guard fragmentRange.length > 0 else { return }

        guard let fragmentTextRange = textRange(
            forUTF16Range: fragmentRange,
            textContentStorage: textContentStorage
        ) else {
            return
        }
        layoutManager.removeRenderingAttribute(.foregroundColor, for: fragmentTextRange)

        renderStore.materializeForeground(in: fragmentRange) { range, color in
            guard let textRange = textRange(
                forUTF16Range: range,
                textContentStorage: textContentStorage
            ) else {
                return
            }
            if let color {
                layoutManager.addRenderingAttribute(.foregroundColor, value: color, for: textRange)
            } else {
                layoutManager.removeRenderingAttribute(.foregroundColor, for: textRange)
            }
        }
    }

    private static func textRange(
        forUTF16Range range: NSRange,
        textContentStorage: NSTextContentStorage
    ) -> NSTextRange? {
        let textLength = textContentStorage.attributedString?.length ?? 0
        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
        guard let startLocation = textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: clampedRange.location
        ),
        let endLocation = textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: clampedRange.location + clampedRange.length
        ) else {
            return nil
        }
        return NSTextRange(location: startLocation, end: endLocation)
    }
}
#endif
