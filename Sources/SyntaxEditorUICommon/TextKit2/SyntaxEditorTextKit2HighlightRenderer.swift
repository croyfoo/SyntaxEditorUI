#if canImport(UIKit) || canImport(AppKit)
import Foundation
import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

package struct SyntaxEditorTextKit2ColorRun {
    package var range: NSRange
    package let color: SyntaxEditorColor

    package init(range: NSRange, color: SyntaxEditorColor) {
        self.range = range
        self.color = color
    }
}

package struct SyntaxEditorTextKit2FontRun {
    package var range: NSRange
    package let font: SyntaxEditorFont

    package init(range: NSRange, font: SyntaxEditorFont) {
        self.range = range
        self.font = font
    }
}

package struct SyntaxEditorTextKit2RunSet {
    package let colorRuns: [SyntaxEditorTextKit2ColorRun]
    package let fontRuns: [SyntaxEditorTextKit2FontRun]

    package init(colorRuns: [SyntaxEditorTextKit2ColorRun], fontRuns: [SyntaxEditorTextKit2FontRun]) {
        self.colorRuns = colorRuns
        self.fontRuns = fontRuns
    }
}

package struct SyntaxEditorTextKit2ColorOperation {
    package let range: NSRange
    package let color: SyntaxEditorColor

    package init(range: NSRange, color: SyntaxEditorColor) {
        self.range = range
        self.color = color
    }
}

package struct SyntaxEditorTextKit2FontOperation {
    package let range: NSRange
    package let font: SyntaxEditorFont

    package init(range: NSRange, font: SyntaxEditorFont) {
        self.range = range
        self.font = font
    }
}

package struct SyntaxEditorTextKit2StyleOperations {
    package let colorOperations: [SyntaxEditorTextKit2ColorOperation]
    package let fontOperations: [SyntaxEditorTextKit2FontOperation]

    package init(
        colorOperations: [SyntaxEditorTextKit2ColorOperation],
        fontOperations: [SyntaxEditorTextKit2FontOperation]
    ) {
        self.colorOperations = colorOperations
        self.fontOperations = fontOperations
    }

    package static var empty: SyntaxEditorTextKit2StyleOperations {
        SyntaxEditorTextKit2StyleOperations(colorOperations: [], fontOperations: [])
    }

    package var isEmpty: Bool {
        colorOperations.isEmpty && fontOperations.isEmpty
    }
}

@MainActor
package final class SyntaxEditorTextKit2StyleStore {
    package private(set) var epoch = 0
    private var textLength = 0
    private var colorRuns: [SyntaxEditorTextKit2ColorRun] = []
    private var fontRuns: [SyntaxEditorTextKit2FontRun] = []
    private var foregroundSuppressionRanges: [NSRange] = []

    package var appliedColorRunsForTesting: [SyntaxEditorTextKit2ColorRun] {
        colorRuns
    }

    package var appliedFontRunsForTesting: [SyntaxEditorTextKit2FontRun] {
        fontRuns
    }

    package func replaceAll(
        with runSet: SyntaxEditorTextKit2RunSet,
        textLength nextTextLength: Int,
        baseForeground: SyntaxEditorColor,
        baseFont: SyntaxEditorFont?,
        foregroundSuppressionRanges nextForegroundSuppressionRanges: [NSRange] = []
    ) -> SyntaxEditorTextKit2StyleOperations {
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
        _ runSet: SyntaxEditorTextKit2RunSet,
        refreshedRange: NSRange,
        mutation: SyntaxHighlightMutation?,
        textLength nextTextLength: Int,
        baseForeground: SyntaxEditorColor,
        baseFont: SyntaxEditorFont?,
        foregroundSuppressionRanges nextForegroundSuppressionRanges: [NSRange]? = nil
    ) -> SyntaxEditorTextKit2StyleOperations {
        let nextTextLength = max(0, nextTextLength)
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
                            .map { SyntaxEditorTextKit2ColorRun(range: $0, color: run.color) }
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

        return SyntaxEditorTextKit2StyleOperations(
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
    ) -> SyntaxEditorTextKit2StyleOperations {
        let colorOperations = colorRuns.map { run in
            SyntaxEditorTextKit2ColorOperation(range: run.range, color: baseForeground)
        }
        let fontOperations = baseFont.map { baseFont in
            fontRuns.map { run in
                SyntaxEditorTextKit2FontOperation(range: run.range, font: baseFont)
            }
        } ?? []

        textLength = max(0, nextTextLength)
        colorRuns = []
        fontRuns = []
        foregroundSuppressionRanges = []
        epoch += 1

        return SyntaxEditorTextKit2StyleOperations(
            colorOperations: colorOperations,
            fontOperations: fontOperations
        )
    }

    package func baseOperations(
        in range: NSRange,
        textLength nextTextLength: Int,
        baseForeground: SyntaxEditorColor,
        baseFont: SyntaxEditorFont?
    ) -> SyntaxEditorTextKit2StyleOperations {
        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: max(0, nextTextLength))
        guard clampedRange.length > 0 else { return .empty }

        let colorOperations = [SyntaxEditorTextKit2ColorOperation(range: clampedRange, color: baseForeground)]
        let fontOperations = baseFont.map { [SyntaxEditorTextKit2FontOperation(range: clampedRange, font: $0)] } ?? []
        return SyntaxEditorTextKit2StyleOperations(
            colorOperations: colorOperations,
            fontOperations: fontOperations
        )
    }

    private static func normalizedColorRuns(
        _ runs: [SyntaxEditorTextKit2ColorRun],
        textLength: Int
    ) -> [SyntaxEditorTextKit2ColorRun] {
        runs
            .map { run in
                SyntaxEditorTextKit2ColorRun(
                    range: SyntaxEditorRangeUtilities.clampedRange(run.range, utf16Length: textLength),
                    color: run.color
                )
            }
            .filter { $0.range.length > 0 }
            .sorted(by: sortColorRun)
    }

    private static func normalizedFontRuns(
        _ runs: [SyntaxEditorTextKit2FontRun],
        textLength: Int
    ) -> [SyntaxEditorTextKit2FontRun] {
        runs
            .map { run in
                SyntaxEditorTextKit2FontRun(
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
        _ runs: [SyntaxEditorTextKit2ColorRun],
        to range: NSRange
    ) -> [SyntaxEditorTextKit2ColorRun] {
        guard range.length > 0 else { return [] }
        let startIndex = firstColorRunIndex(intersecting: range, in: runs)
        var clippedRuns: [SyntaxEditorTextKit2ColorRun] = []
        clippedRuns.reserveCapacity(min(runs.count - startIndex, 128))

        for run in runs[startIndex...] {
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else { continue }
            clippedRuns.append(SyntaxEditorTextKit2ColorRun(range: intersection, color: run.color))
        }

        return coalescedColorRuns(clippedRuns)
    }

    private static func clippedFontRuns(
        _ runs: [SyntaxEditorTextKit2FontRun],
        to range: NSRange
    ) -> [SyntaxEditorTextKit2FontRun] {
        guard range.length > 0 else { return [] }
        let startIndex = firstFontRunIndex(intersecting: range, in: runs)
        var clippedRuns: [SyntaxEditorTextKit2FontRun] = []
        clippedRuns.reserveCapacity(min(runs.count - startIndex, 128))

        for run in runs[startIndex...] {
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else { continue }
            clippedRuns.append(SyntaxEditorTextKit2FontRun(range: intersection, font: run.font))
        }

        return coalescedFontRuns(clippedRuns)
    }

    private static func replaceColorRuns(
        _ runs: inout [SyntaxEditorTextKit2ColorRun],
        in range: NSRange,
        with replacementRuns: [SyntaxEditorTextKit2ColorRun]
    ) {
        guard range.length > 0 else { return }
        let startIndex = firstColorRunIndex(intersecting: range, in: runs)
        var endIndex = startIndex
        while endIndex < runs.count, runs[endIndex].range.location < range.upperBound {
            endIndex += 1
        }

        var insertedRuns: [SyntaxEditorTextKit2ColorRun] = []
        insertedRuns.reserveCapacity(replacementRuns.count + 2)
        if startIndex < endIndex {
            let firstRun = runs[startIndex]
            if firstRun.range.location < range.location {
                insertedRuns.append(
                    SyntaxEditorTextKit2ColorRun(
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
                    SyntaxEditorTextKit2ColorRun(
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
        _ runs: inout [SyntaxEditorTextKit2FontRun],
        in range: NSRange,
        with replacementRuns: [SyntaxEditorTextKit2FontRun]
    ) {
        guard range.length > 0 else { return }
        let startIndex = firstFontRunIndex(intersecting: range, in: runs)
        var endIndex = startIndex
        while endIndex < runs.count, runs[endIndex].range.location < range.upperBound {
            endIndex += 1
        }

        var insertedRuns: [SyntaxEditorTextKit2FontRun] = []
        insertedRuns.reserveCapacity(replacementRuns.count + 2)
        if startIndex < endIndex {
            let firstRun = runs[startIndex]
            if firstRun.range.location < range.location {
                insertedRuns.append(
                    SyntaxEditorTextKit2FontRun(
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
                    SyntaxEditorTextKit2FontRun(
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
        _ runs: inout [SyntaxEditorTextKit2ColorRun],
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
        _ runs: inout [SyntaxEditorTextKit2FontRun],
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
        in runs: [SyntaxEditorTextKit2ColorRun]
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
        in runs: [SyntaxEditorTextKit2FontRun]
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
        from previousRuns: [SyntaxEditorTextKit2ColorRun],
        to nextRuns: [SyntaxEditorTextKit2ColorRun],
        baseForeground: SyntaxEditorColor
    ) -> [SyntaxEditorTextKit2ColorOperation] {
        let nextKeys = Set(nextRuns.map(ColorRunKey.init))
        let previousKeys = Set(previousRuns.map(ColorRunKey.init))
        var operations: [SyntaxEditorTextKit2ColorOperation] = []
        operations.reserveCapacity(previousRuns.count + nextRuns.count)

        for run in previousRuns where !nextKeys.contains(ColorRunKey(run)) {
            operations.append(SyntaxEditorTextKit2ColorOperation(range: run.range, color: baseForeground))
        }
        for run in nextRuns where !previousKeys.contains(ColorRunKey(run)) {
            operations.append(SyntaxEditorTextKit2ColorOperation(range: run.range, color: run.color))
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
        from previousRuns: [SyntaxEditorTextKit2FontRun],
        to nextRuns: [SyntaxEditorTextKit2FontRun],
        baseFont: SyntaxEditorFont?
    ) -> [SyntaxEditorTextKit2FontOperation] {
        let nextKeys = Set(nextRuns.map(FontRunKey.init))
        let previousKeys = Set(previousRuns.map(FontRunKey.init))
        var operations: [SyntaxEditorTextKit2FontOperation] = []
        operations.reserveCapacity(previousRuns.count + nextRuns.count)

        if let baseFont {
            for run in previousRuns where !nextKeys.contains(FontRunKey(run)) {
                operations.append(SyntaxEditorTextKit2FontOperation(range: run.range, font: baseFont))
            }
        }
        for run in nextRuns where !previousKeys.contains(FontRunKey(run)) {
            operations.append(SyntaxEditorTextKit2FontOperation(range: run.range, font: run.font))
        }

        return operations.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                lhs.range.length < rhs.range.length
            } else {
                lhs.range.location < rhs.range.location
            }
        }
    }

    private static func coalescedColorRuns(
        _ runs: [SyntaxEditorTextKit2ColorRun]
    ) -> [SyntaxEditorTextKit2ColorRun] {
        var coalescedRuns: [SyntaxEditorTextKit2ColorRun] = []
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
        _ runs: [SyntaxEditorTextKit2FontRun]
    ) -> [SyntaxEditorTextKit2FontRun] {
        var coalescedRuns: [SyntaxEditorTextKit2FontRun] = []
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
        lhs: SyntaxEditorTextKit2ColorRun,
        rhs: SyntaxEditorTextKit2ColorRun
    ) -> Bool {
        if lhs.range.location == rhs.range.location {
            lhs.range.length < rhs.range.length
        } else {
            lhs.range.location < rhs.range.location
        }
    }

    private static func sortFontRun(
        lhs: SyntaxEditorTextKit2FontRun,
        rhs: SyntaxEditorTextKit2FontRun
    ) -> Bool {
        if lhs.range.location == rhs.range.location {
            lhs.range.length < rhs.range.length
        } else {
            lhs.range.location < rhs.range.location
        }
    }

    private static func shiftedColorRuns(
        _ runs: [SyntaxEditorTextKit2ColorRun],
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int
    ) -> [SyntaxEditorTextKit2ColorRun] {
        coalescedColorRuns(runs.flatMap { run in
            shiftedRangesAfterMutation(run.range, by: mutation, sourceLength: sourceLength)
                .map { SyntaxEditorTextKit2ColorRun(range: $0, color: run.color) }
        })
    }

    private static func shiftedFontRuns(
        _ runs: [SyntaxEditorTextKit2FontRun],
        by mutation: SyntaxHighlightMutation,
        sourceLength: Int
    ) -> [SyntaxEditorTextKit2FontRun] {
        coalescedFontRuns(runs.flatMap { run in
            shiftedRangesAfterMutation(run.range, by: mutation, sourceLength: sourceLength)
                .map { SyntaxEditorTextKit2FontRun(range: $0, font: run.font) }
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

        init(_ run: SyntaxEditorTextKit2ColorRun) {
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

        init(_ run: SyntaxEditorTextKit2FontRun) {
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

package enum SyntaxEditorTextKit2StyleApplier {
    @MainActor
    package static func performContentEditing(
        on textContentStorage: NSTextContentStorage,
        _ body: (NSTextStorage) -> Void
    ) {
        textContentStorage.performEditingTransaction {
            guard let textStorage = textContentStorage.textStorage else { return }
            body(textStorage)
        }
    }

    @MainActor
    package static func apply(
        _ operations: SyntaxEditorTextKit2StyleOperations,
        to textContentStorage: NSTextContentStorage
    ) {
        guard !operations.isEmpty else { return }

        performContentEditing(on: textContentStorage) { textStorage in
            let textLength = textStorage.length
            for operation in operations.colorOperations {
                let range = SyntaxEditorRangeUtilities.clampedRange(operation.range, utf16Length: textLength)
                guard range.length > 0 else { continue }
                textStorage.addAttribute(.foregroundColor, value: operation.color, range: range)
            }
            for operation in operations.fontOperations {
                let range = SyntaxEditorRangeUtilities.clampedRange(operation.range, utf16Length: textLength)
                guard range.length > 0 else { continue }
                textStorage.addAttribute(.font, value: operation.font, range: range)
            }
        }
    }
}

@MainActor
package final class SyntaxEditorTextKit2System {
    package let textContentStorage: NSTextContentStorage
    package let layoutManager: NSTextLayoutManager
    package let container: NSTextContainer
    package let styleStore: SyntaxEditorTextKit2StyleStore

    package init(
        textContentStorage: NSTextContentStorage = NSTextContentStorage(),
        layoutManager: NSTextLayoutManager = NSTextLayoutManager(),
        container: NSTextContainer = NSTextContainer(),
        styleStore: SyntaxEditorTextKit2StyleStore = SyntaxEditorTextKit2StyleStore()
    ) {
        self.textContentStorage = textContentStorage
        self.layoutManager = layoutManager
        self.container = container
        self.styleStore = styleStore

        layoutManager.textContainer = container
        textContentStorage.addTextLayoutManager(layoutManager)
        textContentStorage.primaryTextLayoutManager = layoutManager
    }

    package var textStorage: NSTextStorage {
        guard let textStorage = textContentStorage.textStorage else {
            fatalError("SyntaxEditorTextKit2System requires NSTextContentStorage-backed NSTextStorage")
        }
        return textStorage
    }

    package func textLocation(forUTF16Offset offset: Int) -> NSTextLocation? {
        let clampedOffset = min(max(0, offset), textStorage.length)
        return textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: clampedOffset
        )
    }

    package func utf16Offset(for textLocation: NSTextLocation) -> Int {
        textContentStorage.offset(
            from: textContentStorage.documentRange.location,
            to: textLocation
        )
    }

    package func textRange(forUTF16Range range: NSRange) -> NSTextRange? {
        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textStorage.length)
        guard let startLocation = textLocation(forUTF16Offset: clampedRange.location),
              let endLocation = textLocation(forUTF16Offset: clampedRange.location + clampedRange.length)
        else {
            return nil
        }
        return NSTextRange(location: startLocation, end: endLocation)
    }

    package func utf16Range(for textRange: NSTextRange) -> NSRange {
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

    package func invalidateRenderingAttributes(for range: NSRange) {
        guard let textRange = textRange(forUTF16Range: range) else { return }
        layoutManager.invalidateRenderingAttributes(for: textRange)
    }
}
#endif
