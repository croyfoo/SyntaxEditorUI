#if canImport(AppKit)
import AppKit
import Foundation
import SyntaxEditorCore

struct MacSyntaxHighlightColorRun {
    var range: NSRange
    let color: NSColor
}

final class SyntaxEditorMacLayoutManager: NSLayoutManager {
    private var syntaxForegroundRuns: [MacSyntaxHighlightColorRun] = []
    private var syntaxSourceLength = 0
    private var materializedSyntaxForegroundRanges: [NSRange] = []

    private(set) var syntaxForegroundMaterializationCountForTesting = 0

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        materializeSyntaxForeground(forGlyphRange: glyphsToShow)
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    }

    func installSyntaxForegroundRuns(_ runs: [MacSyntaxHighlightColorRun], sourceLength: Int) {
        clearMaterializedSyntaxForeground()
        syntaxForegroundRuns = runs.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                lhs.range.length < rhs.range.length
            } else {
                lhs.range.location < rhs.range.location
            }
        }
        syntaxSourceLength = sourceLength
    }

    func clearSyntaxForegroundRendering() {
        clearMaterializedSyntaxForeground()
        syntaxForegroundRuns = []
        syntaxSourceLength = 0
    }

    func suspendSyntaxForegroundMaterialization() {
        syntaxForegroundRuns = []
        syntaxSourceLength = -1
    }

    func prepareSyntaxForegroundForPendingTextMutation(
        _ mutation: SyntaxHighlightMutation,
        sourceLength: Int,
        invalidatedRange: NSRange
    ) {
        let clampedInvalidatedRange = SyntaxEditorRangeUtilities.clampedRange(
            invalidatedRange,
            utf16Length: sourceLength
        )
        if clampedInvalidatedRange.length > 0 {
            removeTemporaryAttribute(.foregroundColor, forCharacterRange: clampedInvalidatedRange)
        }

        syntaxForegroundRuns = shiftedColorRuns(
            syntaxForegroundRuns,
            by: mutation,
            sourceLength: sourceLength,
            removing: clampedInvalidatedRange
        )
        materializedSyntaxForegroundRanges = shiftedRanges(
            materializedSyntaxForegroundRanges,
            by: mutation,
            sourceLength: sourceLength,
            removing: clampedInvalidatedRange
        )
        syntaxSourceLength = sourceLength
    }

    func clearMaterializedSyntaxForegroundRendering() {
        clearMaterializedSyntaxForeground()
    }

    func materializeSyntaxForegroundForTesting(in range: NSRange) {
        materializeSyntaxForeground(in: range)
    }

    private func materializeSyntaxForeground(forGlyphRange glyphRange: NSRange) {
        guard glyphRange.length > 0 else { return }
        let characterRange = unsafe self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        materializeSyntaxForeground(in: characterRange)
    }

    private func materializeSyntaxForeground(in range: NSRange) {
        guard let textStorage = unsafe self.textStorage,
              textStorage.length == syntaxSourceLength
        else { return }
        let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textStorage.length)
        guard clamped.length > 0 else { return }

        removeTemporaryAttribute(.foregroundColor, forCharacterRange: clamped)
        var runIndex = firstSyntaxForegroundRunIndex(intersecting: clamped)
        while runIndex < syntaxForegroundRuns.count {
            let run = syntaxForegroundRuns[runIndex]
            guard run.range.location < clamped.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: clamped)
            if intersection.length > 0 {
                addTemporaryAttribute(.foregroundColor, value: run.color, forCharacterRange: intersection)
            }
            runIndex += 1
        }

        appendMaterializedSyntaxForegroundRange(clamped)
        syntaxForegroundMaterializationCountForTesting += 1
    }

    private func firstSyntaxForegroundRunIndex(intersecting range: NSRange) -> Int {
        var lowerBound = 0
        var upperBound = syntaxForegroundRuns.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if syntaxForegroundRuns[midIndex].range.upperBound <= range.location {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return lowerBound
    }

    private func shiftedColorRuns(
        _ runs: [MacSyntaxHighlightColorRun],
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int,
        removing invalidatedRange: NSRange
    ) -> [MacSyntaxHighlightColorRun] {
        var shiftedRuns: [MacSyntaxHighlightColorRun] = []
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
                shiftedRuns.append(MacSyntaxHighlightColorRun(range: remainingRange, color: run.color))
            }
        }

        return shiftedRuns
    }

    private func shiftedRanges(
        _ ranges: [NSRange],
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int,
        removing invalidatedRange: NSRange
    ) -> [NSRange] {
        var shiftedRanges: [NSRange] = []
        shiftedRanges.reserveCapacity(ranges.count)

        for range in ranges {
            for shiftedRange in splitRangeAfterMutation(range, by: mutation, sourceLength: sourceLength) {
                shiftedRanges.append(contentsOf: rangesBySubtracting(invalidatedRange, from: shiftedRange))
            }
        }

        return mergedRanges(shiftedRanges)
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

    private func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        let sortedRanges = ranges.sorted { lhs, rhs in
            if lhs.location == rhs.location {
                lhs.length < rhs.length
            } else {
                lhs.location < rhs.location
            }
        }
        var merged: [NSRange] = []
        for range in sortedRanges {
            guard var last = merged.last else {
                merged.append(range)
                continue
            }
            if last.upperBound < range.location {
                merged.append(range)
            } else {
                let upperBound = max(last.upperBound, range.upperBound)
                last.length = upperBound - last.location
                merged[merged.count - 1] = last
            }
        }
        return merged
    }

    private func clearMaterializedSyntaxForeground() {
        guard let textStorage = unsafe self.textStorage,
              textStorage.length > 0
        else {
            materializedSyntaxForegroundRanges.removeAll()
            return
        }

        for range in materializedSyntaxForegroundRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textStorage.length)
            guard clamped.length > 0 else { continue }
            removeTemporaryAttribute(.foregroundColor, forCharacterRange: clamped)
        }
        materializedSyntaxForegroundRanges.removeAll()
    }

    private func appendMaterializedSyntaxForegroundRange(_ range: NSRange) {
        var nextRanges: [NSRange] = []
        var mergedRange = range
        var didInsert = false

        for existing in materializedSyntaxForegroundRanges {
            if existing.upperBound < mergedRange.location {
                nextRanges.append(existing)
            } else if mergedRange.upperBound < existing.location {
                if !didInsert {
                    nextRanges.append(mergedRange)
                    didInsert = true
                }
                nextRanges.append(existing)
            } else {
                let lowerBound = min(existing.location, mergedRange.location)
                let upperBound = max(existing.upperBound, mergedRange.upperBound)
                mergedRange = NSRange(location: lowerBound, length: upperBound - lowerBound)
            }
        }

        if !didInsert {
            nextRanges.append(mergedRange)
        }
        materializedSyntaxForegroundRanges = nextRanges
    }
}

@MainActor
struct MacHighlightRenderer {
    let layoutManager: NSLayoutManager
    let textStorage: NSTextStorage

    func installSyntaxForegroundRuns(_ runs: [MacSyntaxHighlightColorRun], sourceLength: Int) {
        (layoutManager as? SyntaxEditorMacLayoutManager)?.installSyntaxForegroundRuns(
            runs,
            sourceLength: sourceLength
        )
    }

    func clearSyntaxForegroundRendering() {
        (layoutManager as? SyntaxEditorMacLayoutManager)?.clearSyntaxForegroundRendering()
    }

    func suspendSyntaxForegroundMaterialization() {
        (layoutManager as? SyntaxEditorMacLayoutManager)?.suspendSyntaxForegroundMaterialization()
    }

    func prepareSyntaxForegroundForPendingTextMutation(
        _ mutation: SyntaxHighlightMutation,
        sourceLength: Int,
        invalidatedRange: NSRange
    ) {
        (layoutManager as? SyntaxEditorMacLayoutManager)?.prepareSyntaxForegroundForPendingTextMutation(
            mutation,
            sourceLength: sourceLength,
            invalidatedRange: invalidatedRange
        )
    }

    func clearMaterializedSyntaxForegroundRendering() {
        (layoutManager as? SyntaxEditorMacLayoutManager)?.clearMaterializedSyntaxForegroundRendering()
    }

    func invalidateDisplay(forCharacterRanges ranges: [NSRange]) {
        let textLength = textStorage.length
        guard textLength > 0 else { return }

        for range in ranges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            layoutManager.invalidateDisplay(forCharacterRange: clamped)
        }
    }
}

@MainActor
struct MacBracketHighlightRenderer {
    let layoutManager: NSLayoutManager
    let textStorage: NSTextStorage

    func apply(oldRanges: [NSRange], newRanges: [NSRange], color: NSColor) {
        let textLength = textStorage.length
        guard textLength > 0 else { return }

        for range in oldRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: clamped)
        }

        for range in newRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: color,
                forCharacterRange: clamped
            )
        }
    }

    func clear(ranges: [NSRange]) {
        let textLength = textStorage.length
        guard textLength > 0 else { return }

        for range in ranges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: clamped)
        }
    }

    func invalidateDisplay(for ranges: [NSRange]) {
        MacHighlightRenderer(
            layoutManager: layoutManager,
            textStorage: textStorage
        )
        .invalidateDisplay(forCharacterRanges: ranges)
    }
}
#endif
