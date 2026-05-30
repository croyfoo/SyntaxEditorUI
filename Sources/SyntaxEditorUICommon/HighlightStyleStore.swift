#if canImport(UIKit) || canImport(AppKit)
import Foundation
import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

package struct HighlightColorRun {
    package var range: NSRange
    package let color: SyntaxEditorColor

    package init(range: NSRange, color: SyntaxEditorColor) {
        self.range = range
        self.color = color
    }
}

package struct HighlightFontRun {
    package var range: NSRange
    package let font: SyntaxEditorFont

    package init(range: NSRange, font: SyntaxEditorFont) {
        self.range = range
        self.font = font
    }
}

package struct HighlightRunSet {
    package let colorRuns: [HighlightColorRun]
    package let fontRuns: [HighlightFontRun]

    package init(colorRuns: [HighlightColorRun], fontRuns: [HighlightFontRun]) {
        self.colorRuns = colorRuns
        self.fontRuns = fontRuns
    }
}

package struct HighlightColorOperation {
    package let range: NSRange
    package let color: SyntaxEditorColor

    package init(range: NSRange, color: SyntaxEditorColor) {
        self.range = range
        self.color = color
    }
}

package struct HighlightFontOperation {
    package let range: NSRange
    package let font: SyntaxEditorFont

    package init(range: NSRange, font: SyntaxEditorFont) {
        self.range = range
        self.font = font
    }
}

package struct HighlightStyleOperations {
    package let colorOperations: [HighlightColorOperation]
    package let fontOperations: [HighlightFontOperation]

    package init(
        colorOperations: [HighlightColorOperation],
        fontOperations: [HighlightFontOperation]
    ) {
        self.colorOperations = colorOperations
        self.fontOperations = fontOperations
    }

    package static var empty: HighlightStyleOperations {
        HighlightStyleOperations(colorOperations: [], fontOperations: [])
    }

    package var isEmpty: Bool {
        colorOperations.isEmpty && fontOperations.isEmpty
    }
}

@MainActor
package final class HighlightStyleStore {
    package private(set) var epoch = 0
    package private(set) var baseForeground: SyntaxEditorColor?
    private var textLength = 0
    private var colorRuns: [HighlightColorRun] = []
    private var fontRuns: [HighlightFontRun] = []
    private var foregroundSuppressionRanges: [NSRange] = []

    package var appliedColorRunsForTesting: [HighlightColorRun] {
        colorRuns
    }

    package var appliedFontRunsForTesting: [HighlightFontRun] {
        fontRuns
    }

    package func colorRuns(in range: NSRange) -> [HighlightColorRun] {
        Self.clippedColorRuns(colorRuns, to: range)
    }

    package func foregroundColor(at location: Int) -> SyntaxEditorColor? {
        guard location >= 0, location < textLength else { return nil }
        let range = NSRange(location: location, length: 1)
        let index = Self.firstColorRunIndex(intersecting: range, in: colorRuns)
        guard index < colorRuns.count,
              NSIntersectionRange(colorRuns[index].range, range).length > 0
        else {
            return nil
        }
        return colorRuns[index].color
    }

    package func effectiveForegroundColor(at location: Int) -> SyntaxEditorColor? {
        foregroundColor(at: location) ?? baseForeground
    }

    package func updateBaseForeground(_ color: SyntaxEditorColor?, textLength nextTextLength: Int? = nil) {
        let nextTextLength = nextTextLength.map { max(0, $0) } ?? textLength
        let baseChanged: Bool
        switch (baseForeground, color) {
        case (.none, .none):
            baseChanged = false
        case let (.some(lhs), .some(rhs)):
            baseChanged = !lhs.isEqual(rhs)
        default:
            baseChanged = true
        }

        let textLengthChanged = textLength != nextTextLength
        textLength = nextTextLength
        baseForeground = color
        if baseChanged || textLengthChanged {
            epoch += 1
        }
    }

    package func forEachColorRun(
        in range: NSRange,
        _ body: (HighlightColorRun) -> Void
    ) {
        guard range.length > 0 else { return }
        let startIndex = Self.firstColorRunIndex(intersecting: range, in: colorRuns)
        for run in colorRuns[startIndex...] {
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else { continue }
            body(HighlightColorRun(range: intersection, color: run.color))
        }
    }

    package func replaceAll(
        with runSet: HighlightRunSet,
        textLength nextTextLength: Int,
        baseForeground: SyntaxEditorColor,
        baseFont: SyntaxEditorFont?,
        foregroundSuppressionRanges nextForegroundSuppressionRanges: [NSRange] = []
    ) -> HighlightStyleOperations {
        apply(
            runSet,
            refreshedRange: NSRange(location: 0, length: max(0, nextTextLength)),
            mutation: nil,
            textLength: nextTextLength,
            baseForeground: baseForeground,
            baseFont: baseFont,
            foregroundSuppressionRanges: nextForegroundSuppressionRanges
        )
    }

    package func apply(
        _ runSet: HighlightRunSet,
        refreshedRange: NSRange,
        mutation: SyntaxHighlightMutation?,
        textLength nextTextLength: Int,
        baseForeground: SyntaxEditorColor,
        baseFont: SyntaxEditorFont?,
        foregroundSuppressionRanges nextForegroundSuppressionRanges: [NSRange]? = nil
    ) -> HighlightStyleOperations {
        let nextTextLength = max(0, nextTextLength)
        self.baseForeground = baseForeground
        if let mutation {
            recordTextMutation(mutation, textLength: nextTextLength)
        }

        let clampedRefreshRange = SyntaxEditorRangeUtilities.clampedRange(
            refreshedRange,
            utf16Length: nextTextLength
        )
        let effectiveSuppressionRanges = nextForegroundSuppressionRanges ?? foregroundSuppressionRanges
        let normalizedSuppressionRanges = Self.normalizedRanges(
            effectiveSuppressionRanges,
            textLength: nextTextLength
        )
        let normalizedNextColorRuns = Self.clippedColorRuns(
            Self.coalescedColorRuns(
                Self.normalizedColorRuns(runSet.colorRuns, textLength: nextTextLength)
                    .flatMap { run in
                        Self.rangesBySubtracting(normalizedSuppressionRanges, from: run.range)
                            .map { HighlightColorRun(range: $0, color: run.color) }
                    }
            ),
            to: clampedRefreshRange
        )
        let normalizedNextFontRuns = Self.clippedFontRuns(
            Self.coalescedFontRuns(
                Self.normalizedFontRuns(runSet.fontRuns, textLength: nextTextLength)
            ),
            to: clampedRefreshRange
        )
        let previousColorRuns = Self.clippedColorRuns(colorRuns, to: clampedRefreshRange)
        let previousFontRuns = Self.clippedFontRuns(fontRuns, to: clampedRefreshRange)
        let colorOperations = Self.colorOperations(
            from: previousColorRuns,
            to: normalizedNextColorRuns,
            baseForeground: baseForeground
        )
        let fontOperations = Self.fontOperations(
            from: previousFontRuns,
            to: normalizedNextFontRuns,
            baseFont: baseFont
        )

        Self.replaceColorRuns(&colorRuns, in: clampedRefreshRange, with: normalizedNextColorRuns)
        Self.replaceFontRuns(&fontRuns, in: clampedRefreshRange, with: normalizedNextFontRuns)
        textLength = nextTextLength
        foregroundSuppressionRanges = normalizedSuppressionRanges
        epoch += 1

        return HighlightStyleOperations(
            colorOperations: colorOperations,
            fontOperations: fontOperations
        )
    }

    private func recordTextMutation(_ mutation: SyntaxHighlightMutation, textLength nextTextLength: Int) {
        let nextTextLength = max(0, nextTextLength)
        colorRuns = Self.shiftedColorRuns(colorRuns, by: mutation, sourceLength: nextTextLength)
        fontRuns = Self.shiftedFontRuns(fontRuns, by: mutation, sourceLength: nextTextLength)
        foregroundSuppressionRanges = Self.normalizedRanges(
            foregroundSuppressionRanges.flatMap { range in
                Self.shiftedRangesAfterMutation(range, by: mutation, sourceLength: nextTextLength)
            },
            textLength: nextTextLength
        )
        textLength = nextTextLength
    }

    package func clear(
        textLength nextTextLength: Int,
        baseForeground: SyntaxEditorColor,
        baseFont: SyntaxEditorFont?
    ) -> HighlightStyleOperations {
        let colorOperations = colorRuns.map { run in
            HighlightColorOperation(range: run.range, color: baseForeground)
        }
        let fontOperations = baseFont.map { baseFont in
            fontRuns.map { run in
                HighlightFontOperation(range: run.range, font: baseFont)
            }
        } ?? []

        textLength = max(0, nextTextLength)
        self.baseForeground = baseForeground
        colorRuns = []
        fontRuns = []
        foregroundSuppressionRanges = []
        epoch += 1

        return HighlightStyleOperations(
            colorOperations: colorOperations,
            fontOperations: fontOperations
        )
    }

    package func reset(textLength nextTextLength: Int) {
        textLength = max(0, nextTextLength)
        colorRuns = []
        fontRuns = []
        foregroundSuppressionRanges = []
        epoch += 1
    }

    private static func normalizedColorRuns(
        _ runs: [HighlightColorRun],
        textLength: Int
    ) -> [HighlightColorRun] {
        runs
            .map { run in
                HighlightColorRun(
                    range: SyntaxEditorRangeUtilities.clampedRange(run.range, utf16Length: textLength),
                    color: run.color
                )
            }
            .filter { $0.range.length > 0 }
            .sorted(by: sortColorRun)
    }

    private static func normalizedFontRuns(
        _ runs: [HighlightFontRun],
        textLength: Int
    ) -> [HighlightFontRun] {
        runs
            .map { run in
                HighlightFontRun(
                    range: SyntaxEditorRangeUtilities.clampedRange(run.range, utf16Length: textLength),
                    font: run.font
                )
            }
            .filter { $0.range.length > 0 }
            .sorted(by: sortFontRun)
    }

    private static func normalizedRanges(_ ranges: [NSRange], textLength: Int) -> [NSRange] {
        coalescedRanges(
            ranges
                .map { SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: textLength) }
                .filter { $0.length > 0 }
                .sorted { lhs, rhs in
                    if lhs.location == rhs.location {
                        lhs.length < rhs.length
                    } else {
                        lhs.location < rhs.location
                    }
                }
        )
    }

    private static func coalescedRanges(_ ranges: [NSRange]) -> [NSRange] {
        var coalescedRanges: [NSRange] = []
        coalescedRanges.reserveCapacity(ranges.count)

        for range in ranges {
            if let last = coalescedRanges.last,
               last.upperBound >= range.location {
                let lowerBound = min(last.location, range.location)
                let upperBound = max(last.upperBound, range.upperBound)
                coalescedRanges[coalescedRanges.count - 1] = NSRange(
                    location: lowerBound,
                    length: upperBound - lowerBound
                )
            } else {
                coalescedRanges.append(range)
            }
        }

        return coalescedRanges
    }

    private static func clippedColorRuns(
        _ runs: [HighlightColorRun],
        to range: NSRange
    ) -> [HighlightColorRun] {
        guard range.length > 0 else { return [] }
        let startIndex = firstColorRunIndex(intersecting: range, in: runs)
        var clippedRuns: [HighlightColorRun] = []
        clippedRuns.reserveCapacity(min(runs.count - startIndex, 128))

        for run in runs[startIndex...] {
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else { continue }
            clippedRuns.append(HighlightColorRun(range: intersection, color: run.color))
        }

        return coalescedColorRuns(clippedRuns)
    }

    private static func clippedFontRuns(
        _ runs: [HighlightFontRun],
        to range: NSRange
    ) -> [HighlightFontRun] {
        guard range.length > 0 else { return [] }
        let startIndex = firstFontRunIndex(intersecting: range, in: runs)
        var clippedRuns: [HighlightFontRun] = []
        clippedRuns.reserveCapacity(min(runs.count - startIndex, 128))

        for run in runs[startIndex...] {
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else { continue }
            clippedRuns.append(HighlightFontRun(range: intersection, font: run.font))
        }

        return coalescedFontRuns(clippedRuns)
    }

    private static func replaceColorRuns(
        _ runs: inout [HighlightColorRun],
        in range: NSRange,
        with replacementRuns: [HighlightColorRun]
    ) {
        guard range.length > 0 else { return }
        let startIndex = firstColorRunIndex(intersecting: range, in: runs)
        var endIndex = startIndex
        while endIndex < runs.count, runs[endIndex].range.location < range.upperBound {
            endIndex += 1
        }

        var insertedRuns: [HighlightColorRun] = []
        insertedRuns.reserveCapacity(replacementRuns.count + 2)
        if startIndex < endIndex {
            let firstRun = runs[startIndex]
            if firstRun.range.location < range.location {
                insertedRuns.append(
                    HighlightColorRun(
                        range: NSRange(
                            location: firstRun.range.location,
                            length: range.location - firstRun.range.location
                        ),
                        color: firstRun.color
                    )
                )
            }
            let lastRun = runs[endIndex - 1]
            if lastRun.range.upperBound > range.upperBound {
                insertedRuns.append(
                    HighlightColorRun(
                        range: NSRange(
                            location: range.upperBound,
                            length: lastRun.range.upperBound - range.upperBound
                        ),
                        color: lastRun.color
                    )
                )
            }
        }

        insertedRuns.append(contentsOf: replacementRuns)
        let replacementCount = insertedRuns.count
        runs.replaceSubrange(startIndex..<endIndex, with: insertedRuns.sorted(by: sortColorRun))
        coalesceColorRunsAround(&runs, startIndex: startIndex, replacementCount: replacementCount)
    }

    private static func replaceFontRuns(
        _ runs: inout [HighlightFontRun],
        in range: NSRange,
        with replacementRuns: [HighlightFontRun]
    ) {
        guard range.length > 0 else { return }
        let startIndex = firstFontRunIndex(intersecting: range, in: runs)
        var endIndex = startIndex
        while endIndex < runs.count, runs[endIndex].range.location < range.upperBound {
            endIndex += 1
        }

        var insertedRuns: [HighlightFontRun] = []
        insertedRuns.reserveCapacity(replacementRuns.count + 2)
        if startIndex < endIndex {
            let firstRun = runs[startIndex]
            if firstRun.range.location < range.location {
                insertedRuns.append(
                    HighlightFontRun(
                        range: NSRange(
                            location: firstRun.range.location,
                            length: range.location - firstRun.range.location
                        ),
                        font: firstRun.font
                    )
                )
            }
            let lastRun = runs[endIndex - 1]
            if lastRun.range.upperBound > range.upperBound {
                insertedRuns.append(
                    HighlightFontRun(
                        range: NSRange(
                            location: range.upperBound,
                            length: lastRun.range.upperBound - range.upperBound
                        ),
                        font: lastRun.font
                    )
                )
            }
        }

        insertedRuns.append(contentsOf: replacementRuns)
        let replacementCount = insertedRuns.count
        runs.replaceSubrange(startIndex..<endIndex, with: insertedRuns.sorted(by: sortFontRun))
        coalesceFontRunsAround(&runs, startIndex: startIndex, replacementCount: replacementCount)
    }

    private static func coalesceColorRunsAround(
        _ runs: inout [HighlightColorRun],
        startIndex: Int,
        replacementCount: Int
    ) {
        guard !runs.isEmpty else { return }
        var currentIndex = max(0, min(startIndex, runs.count - 1) - 1)
        var upperIndex = min(runs.count - 1, startIndex + replacementCount + 1)

        while currentIndex < upperIndex, currentIndex + 1 < runs.count {
            let current = runs[currentIndex]
            let next = runs[currentIndex + 1]
            if current.color.isEqual(next.color),
               current.range.upperBound >= next.range.location {
                let upperBound = max(current.range.upperBound, next.range.upperBound)
                runs[currentIndex].range = NSRange(
                    location: current.range.location,
                    length: upperBound - current.range.location
                )
                runs.remove(at: currentIndex + 1)
                upperIndex = max(currentIndex, upperIndex - 1)
            } else {
                currentIndex += 1
            }
        }
    }

    private static func coalesceFontRunsAround(
        _ runs: inout [HighlightFontRun],
        startIndex: Int,
        replacementCount: Int
    ) {
        guard !runs.isEmpty else { return }
        var currentIndex = max(0, min(startIndex, runs.count - 1) - 1)
        var upperIndex = min(runs.count - 1, startIndex + replacementCount + 1)

        while currentIndex < upperIndex, currentIndex + 1 < runs.count {
            let current = runs[currentIndex]
            let next = runs[currentIndex + 1]
            if current.font == next.font,
               current.range.upperBound >= next.range.location {
                let upperBound = max(current.range.upperBound, next.range.upperBound)
                runs[currentIndex].range = NSRange(
                    location: current.range.location,
                    length: upperBound - current.range.location
                )
                runs.remove(at: currentIndex + 1)
                upperIndex = max(currentIndex, upperIndex - 1)
            } else {
                currentIndex += 1
            }
        }
    }

    private static func firstColorRunIndex(
        intersecting range: NSRange,
        in runs: [HighlightColorRun]
    ) -> Int {
        var lowerBound = 0
        var upperBound = runs.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if runs[midIndex].range.upperBound <= range.location {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return lowerBound
    }

    private static func firstFontRunIndex(
        intersecting range: NSRange,
        in runs: [HighlightFontRun]
    ) -> Int {
        var lowerBound = 0
        var upperBound = runs.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if runs[midIndex].range.upperBound <= range.location {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return lowerBound
    }

    private static func colorOperations(
        from previousRuns: [HighlightColorRun],
        to nextRuns: [HighlightColorRun],
        baseForeground: SyntaxEditorColor
    ) -> [HighlightColorOperation] {
        let nextKeys = Set(nextRuns.map(ColorRunKey.init))
        let previousKeys = Set(previousRuns.map(ColorRunKey.init))
        var operations: [HighlightColorOperation] = []
        operations.reserveCapacity(previousRuns.count + nextRuns.count)

        for run in previousRuns where !nextKeys.contains(ColorRunKey(run)) {
            operations.append(HighlightColorOperation(range: run.range, color: baseForeground))
        }
        for run in nextRuns where !previousKeys.contains(ColorRunKey(run)) {
            operations.append(HighlightColorOperation(range: run.range, color: run.color))
        }

        return operations.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                lhs.range.length < rhs.range.length
            } else {
                lhs.range.location < rhs.range.location
            }
        }
    }

    private static func fontOperations(
        from previousRuns: [HighlightFontRun],
        to nextRuns: [HighlightFontRun],
        baseFont: SyntaxEditorFont?
    ) -> [HighlightFontOperation] {
        let nextKeys = Set(nextRuns.map(FontRunKey.init))
        let previousKeys = Set(previousRuns.map(FontRunKey.init))
        var resetOperations: [HighlightFontOperation] = []
        var styledOperations: [HighlightFontOperation] = []
        resetOperations.reserveCapacity(previousRuns.count)
        styledOperations.reserveCapacity(nextRuns.count)

        if let baseFont {
            for run in previousRuns where !nextKeys.contains(FontRunKey(run)) {
                resetOperations.append(HighlightFontOperation(range: run.range, font: baseFont))
            }
        }
        for run in nextRuns where !previousKeys.contains(FontRunKey(run)) {
            styledOperations.append(HighlightFontOperation(range: run.range, font: run.font))
        }

        let resetCount = resetOperations.count
        var operations = sortedFontOperations(resetOperations)
        operations.reserveCapacity(resetCount + styledOperations.count)
        operations.append(contentsOf: sortedFontOperations(styledOperations))
        return operations
    }

    private static func sortedFontOperations(
        _ operations: [HighlightFontOperation]
    ) -> [HighlightFontOperation] {
        return operations.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                lhs.range.length < rhs.range.length
            } else {
                lhs.range.location < rhs.range.location
            }
        }
    }

    private static func coalescedColorRuns(
        _ runs: [HighlightColorRun]
    ) -> [HighlightColorRun] {
        var coalescedRuns: [HighlightColorRun] = []
        coalescedRuns.reserveCapacity(runs.count)

        for run in runs.sorted(by: sortColorRun) {
            if var last = coalescedRuns.last,
               last.color.isEqual(run.color),
               last.range.upperBound >= run.range.location,
               run.range.upperBound >= last.range.location {
                let lowerBound = min(last.range.location, run.range.location)
                let upperBound = max(last.range.upperBound, run.range.upperBound)
                last.range = NSRange(location: lowerBound, length: upperBound - lowerBound)
                coalescedRuns[coalescedRuns.count - 1] = last
            } else {
                coalescedRuns.append(run)
            }
        }

        return coalescedRuns
    }

    private static func coalescedFontRuns(
        _ runs: [HighlightFontRun]
    ) -> [HighlightFontRun] {
        var coalescedRuns: [HighlightFontRun] = []
        coalescedRuns.reserveCapacity(runs.count)

        for run in runs.sorted(by: sortFontRun) {
            if var last = coalescedRuns.last,
               last.font == run.font,
               last.range.upperBound >= run.range.location,
               run.range.upperBound >= last.range.location {
                let lowerBound = min(last.range.location, run.range.location)
                let upperBound = max(last.range.upperBound, run.range.upperBound)
                last.range = NSRange(location: lowerBound, length: upperBound - lowerBound)
                coalescedRuns[coalescedRuns.count - 1] = last
            } else {
                coalescedRuns.append(run)
            }
        }

        return coalescedRuns
    }

    private static func sortColorRun(
        lhs: HighlightColorRun,
        rhs: HighlightColorRun
    ) -> Bool {
        if lhs.range.location == rhs.range.location {
            lhs.range.length < rhs.range.length
        } else {
            lhs.range.location < rhs.range.location
        }
    }

    private static func sortFontRun(
        lhs: HighlightFontRun,
        rhs: HighlightFontRun
    ) -> Bool {
        if lhs.range.location == rhs.range.location {
            lhs.range.length < rhs.range.length
        } else {
            lhs.range.location < rhs.range.location
        }
    }

    private static func shiftedColorRuns(
        _ runs: [HighlightColorRun],
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int
    ) -> [HighlightColorRun] {
        coalescedColorRuns(runs.flatMap { run in
            shiftedRangesAfterMutation(run.range, by: mutation, sourceLength: sourceLength)
                .map { HighlightColorRun(range: $0, color: run.color) }
        })
    }

    private static func shiftedFontRuns(
        _ runs: [HighlightFontRun],
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int
    ) -> [HighlightFontRun] {
        coalescedFontRuns(runs.flatMap { run in
            shiftedRangesAfterMutation(run.range, by: mutation, sourceLength: sourceLength)
                .map { HighlightFontRun(range: $0, font: run.font) }
        })
    }

    private static func shiftedRangesAfterMutation(
        _ range: NSRange,
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int
    ) -> [NSRange] {
        let editStart = mutation.location
        let editEnd = mutation.location + mutation.length
        let replacementLength = mutation.replacement.utf16.count
        let delta = replacementLength - mutation.length

        if range.upperBound <= editStart {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: sourceLength)
            return clamped.length > 0 ? [clamped] : []
        }

        if range.location >= editEnd {
            let shifted = NSRange(location: range.location + delta, length: range.length)
            let clamped = SyntaxEditorRangeUtilities.clampedRange(shifted, utf16Length: sourceLength)
            return clamped.length > 0 ? [clamped] : []
        }

        var ranges: [NSRange] = []
        if range.location < editStart {
            let leadingRange = NSRange(location: range.location, length: editStart - range.location)
            let clamped = SyntaxEditorRangeUtilities.clampedRange(leadingRange, utf16Length: sourceLength)
            if clamped.length > 0 {
                ranges.append(clamped)
            }
        }
        if range.upperBound > editEnd {
            let trailingRange = NSRange(
                location: editStart + replacementLength,
                length: range.upperBound - editEnd
            )
            let clamped = SyntaxEditorRangeUtilities.clampedRange(trailingRange, utf16Length: sourceLength)
            if clamped.length > 0 {
                ranges.append(clamped)
            }
        }
        return ranges
    }

    private static func rangesBySubtracting(_ removals: [NSRange], from range: NSRange) -> [NSRange] {
        removals.reduce([range]) { remainingRanges, removal in
            remainingRanges.flatMap { rangesBySubtracting(removal, from: $0) }
        }
    }

    private static func rangesBySubtracting(_ removal: NSRange, from range: NSRange) -> [NSRange] {
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

    private struct ColorRunKey: Hashable {
        let location: Int
        let length: Int
        let colorComponents: ColorComponents

        init(_ run: HighlightColorRun) {
            location = run.range.location
            length = run.range.length
            colorComponents = ColorComponents(run.color)
        }
    }

    private struct FontRunKey: Hashable {
        let location: Int
        let length: Int
        let fontName: String
        let pointSize: CGFloat

        init(_ run: HighlightFontRun) {
            location = run.range.location
            length = run.range.length
            fontName = run.font.fontName
            pointSize = run.font.pointSize
        }
    }

    private struct ColorComponents: Hashable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        let fallbackHash: Int

        init(_ color: SyntaxEditorColor) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            let resolvedFallbackHash: Int
#if canImport(UIKit)
            if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                resolvedFallbackHash = 0
            } else {
                resolvedFallbackHash = color.hash
            }
#elseif canImport(AppKit)
            if let rgbColor = color.usingColorSpace(.genericRGB) {
                unsafe rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                resolvedFallbackHash = 0
            } else {
                resolvedFallbackHash = color.hash
            }
#endif
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
            self.fallbackHash = resolvedFallbackHash
        }
    }
}

#endif
