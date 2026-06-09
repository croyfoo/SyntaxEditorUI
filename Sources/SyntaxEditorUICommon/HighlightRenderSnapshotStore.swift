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

package struct HighlightRenderSnapshot {
    package let revision: Int?
    package let language: SyntaxLanguage?
    package let textLength: Int
    package let baseForeground: SyntaxEditorColor?
    package let baseFont: SyntaxEditorFont?
    package let colorRuns: [HighlightColorRun]
    package let fontRuns: [HighlightFontRun]
    package let suppressionRanges: [NSRange]

    package init(
        revision: Int?,
        language: SyntaxLanguage?,
        textLength: Int,
        baseForeground: SyntaxEditorColor?,
        baseFont: SyntaxEditorFont?,
        colorRuns: [HighlightColorRun],
        fontRuns: [HighlightFontRun],
        suppressionRanges: [NSRange]
    ) {
        let textLength = max(0, textLength)
        self.revision = revision
        self.language = language
        self.textLength = textLength
        self.baseForeground = baseForeground
        self.baseFont = baseFont
        self.colorRuns = HighlightRunUtilities.coalescedColorRuns(
            HighlightRunUtilities.normalizedColorRuns(colorRuns, textLength: textLength)
        )
        self.fontRuns = HighlightRunUtilities.coalescedFontRuns(
            HighlightRunUtilities.normalizedFontRuns(fontRuns, textLength: textLength)
        )
        self.suppressionRanges = HighlightRunUtilities.normalizedRanges(
            suppressionRanges,
            textLength: textLength
        )
    }

    package static var empty: HighlightRenderSnapshot {
        HighlightRenderSnapshot(
            revision: nil,
            language: nil,
            textLength: 0,
            baseForeground: nil,
            baseFont: nil,
            colorRuns: [],
            fontRuns: [],
            suppressionRanges: []
        )
    }
}

package struct PendingHighlightEditMap {
    private struct Edit {
        let location: Int
        let length: Int
        let replacementLength: Int
        let previousTextLength: Int
        let resultingTextLength: Int

        var delta: Int {
            replacementLength - length
        }
    }

    private var edits: [Edit] = []
    private var dirtyRanges: [NSRange] = []
    package private(set) var currentTextLength: Int?

    package init() {}

    package var isEmpty: Bool {
        edits.isEmpty
    }

    package var visibleDirtyRanges: [NSRange] {
        dirtyRanges
    }

    package mutating func recordPendingEdit(
        _ mutation: SyntaxHighlightMutation,
        currentTextLength: Int
    ) {
        let currentTextLength = max(0, currentTextLength)
        let replacementLength = mutation.replacement.utf16.count
        let previousTextLength = max(0, currentTextLength - (replacementLength - mutation.length))
        let edit = Edit(
            location: min(max(0, mutation.location), previousTextLength),
            length: min(max(0, mutation.length), previousTextLength - min(max(0, mutation.location), previousTextLength)),
            replacementLength: replacementLength,
            previousTextLength: previousTextLength,
            resultingTextLength: currentTextLength
        )

        dirtyRanges = HighlightRunUtilities.normalizedRanges(
            dirtyRanges.flatMap {
                Self.currentRanges(forSnapshotRange: $0, applying: edit)
            },
            textLength: currentTextLength
        )
        if let dirtyRange = Self.dirtyRange(for: edit) {
            dirtyRanges.append(dirtyRange)
            dirtyRanges = HighlightRunUtilities.normalizedRanges(dirtyRanges, textLength: currentTextLength)
        }

        edits.append(edit)
        self.currentTextLength = currentTextLength
    }

    package mutating func clear() {
        edits = []
        dirtyRanges = []
        currentTextLength = nil
    }

    package func currentRanges(forSnapshotRange range: NSRange) -> [NSRange] {
        edits.reduce([range]) { ranges, edit in
            ranges.flatMap {
                Self.currentRanges(forSnapshotRange: $0, applying: edit)
            }
        }
    }

    package func snapshotRanges(forCurrentRange range: NSRange) -> [NSRange] {
        edits.reversed().reduce([range]) { ranges, edit in
            ranges.flatMap {
                Self.snapshotRanges(forCurrentRange: $0, reverting: edit)
            }
        }
    }

    private static func dirtyRange(for edit: Edit) -> NSRange? {
        if edit.replacementLength > 0 {
            return NSRange(location: edit.location, length: edit.replacementLength)
        }
        guard edit.resultingTextLength > 0 else { return nil }
        return NSRange(location: min(edit.location, edit.resultingTextLength - 1), length: 1)
    }

    private static func currentRanges(forSnapshotRange range: NSRange, applying edit: Edit) -> [NSRange] {
        let editStart = edit.location
        let editEnd = edit.location + edit.length

        if range.upperBound <= editStart {
            return clampedNonEmpty(range, textLength: edit.resultingTextLength)
        }

        if range.location >= editEnd {
            let shifted = NSRange(location: range.location + edit.delta, length: range.length)
            return clampedNonEmpty(shifted, textLength: edit.resultingTextLength)
        }

        var ranges: [NSRange] = []
        if range.location < editStart {
            ranges.append(NSRange(location: range.location, length: editStart - range.location))
        }
        if range.upperBound > editEnd {
            ranges.append(
                NSRange(
                    location: editStart + edit.replacementLength,
                    length: range.upperBound - editEnd
                )
            )
        }
        return ranges.flatMap { clampedNonEmpty($0, textLength: edit.resultingTextLength) }
    }

    private static func snapshotRanges(forCurrentRange range: NSRange, reverting edit: Edit) -> [NSRange] {
        let editStart = edit.location
        let insertedEnd = edit.location + edit.replacementLength

        if range.upperBound <= editStart {
            return clampedNonEmpty(range, textLength: edit.previousTextLength)
        }

        if range.location >= insertedEnd {
            let shifted = NSRange(location: range.location - edit.delta, length: range.length)
            return clampedNonEmpty(shifted, textLength: edit.previousTextLength)
        }

        var ranges: [NSRange] = []
        if range.location < editStart {
            ranges.append(NSRange(location: range.location, length: editStart - range.location))
        }
        if range.upperBound > insertedEnd {
            ranges.append(
                NSRange(
                    location: insertedEnd - edit.delta,
                    length: range.upperBound - insertedEnd
                )
            )
        }
        return ranges.flatMap { clampedNonEmpty($0, textLength: edit.previousTextLength) }
    }

    private static func clampedNonEmpty(_ range: NSRange, textLength: Int) -> [NSRange] {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
        return clamped.length > 0 ? [clamped] : []
    }
}

package struct HighlightVisibleRunResolver {
    private let snapshot: HighlightRenderSnapshot
    private let pendingEditMap: PendingHighlightEditMap
    private let currentTextLength: Int
    private let currentSuppressionRanges: [NSRange]

    package init(
        snapshot: HighlightRenderSnapshot,
        pendingEditMap: PendingHighlightEditMap,
        currentTextLength: Int,
        currentSuppressionRanges: [NSRange]
    ) {
        self.snapshot = snapshot
        self.pendingEditMap = pendingEditMap
        self.currentTextLength = max(0, currentTextLength)
        self.currentSuppressionRanges = HighlightRunUtilities.normalizedRanges(
            currentSuppressionRanges,
            textLength: max(0, currentTextLength)
        )
    }

    package func forEachColorRun(
        in currentRange: NSRange,
        _ body: (HighlightColorRun) -> Void
    ) {
        forEachCurrentVisibleRange(in: currentRange) { visibleRange in
            for snapshotRange in snapshotRanges(forCurrentVisibleRange: visibleRange) {
                HighlightRunUtilities.forEachColorRun(snapshot.colorRuns, in: snapshotRange) { run in
                    for currentRunRange in pendingEditMap.currentRanges(forSnapshotRange: run.range) {
                        let intersection = SyntaxEditorRangeUtilities.intersection(of: currentRunRange, and: visibleRange)
                        guard intersection.length > 0 else { continue }
                        body(HighlightColorRun(range: intersection, color: run.color))
                    }
                }
            }
        }
    }

    package func forEachFontRun(
        in currentRange: NSRange,
        _ body: (HighlightFontRun) -> Void
    ) {
        forEachCurrentVisibleRange(in: currentRange) { visibleRange in
            for snapshotRange in snapshotRanges(forCurrentVisibleRange: visibleRange) {
                HighlightRunUtilities.forEachFontRun(snapshot.fontRuns, in: snapshotRange) { run in
                    for currentRunRange in pendingEditMap.currentRanges(forSnapshotRange: run.range) {
                        let intersection = SyntaxEditorRangeUtilities.intersection(of: currentRunRange, and: visibleRange)
                        guard intersection.length > 0 else { continue }
                        body(HighlightFontRun(range: intersection, font: run.font))
                    }
                }
            }
        }
    }

    private func forEachCurrentVisibleRange(
        in currentRange: NSRange,
        _ body: (NSRange) -> Void
    ) {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(currentRange, utf16Length: currentTextLength)
        guard clamped.length > 0 else { return }

        let suppressedRanges = HighlightRunUtilities.normalizedRanges(
            pendingEditMap.visibleDirtyRanges + currentSuppressionRanges,
            textLength: currentTextLength
        )
        for visibleRange in HighlightRunUtilities.rangesBySubtracting(suppressedRanges, from: clamped) {
            body(visibleRange)
        }
    }

    private func snapshotRanges(forCurrentVisibleRange range: NSRange) -> [NSRange] {
        if pendingEditMap.isEmpty {
            return [SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: snapshot.textLength)]
                .filter { $0.length > 0 }
        }
        return pendingEditMap.snapshotRanges(forCurrentRange: range)
    }
}

@MainActor
package final class HighlightRenderSnapshotStore {
    package private(set) var generation = 0
    package var epoch: Int { generation }
    package private(set) var snapshot: HighlightRenderSnapshot = .empty

    private var pendingEditMap = PendingHighlightEditMap()
    private var currentTextLength = 0
    private var currentSuppressionRanges: [NSRange] = []

    package var baseForeground: SyntaxEditorColor? {
        snapshot.baseForeground
    }

    package var appliedColorRunsForTesting: [HighlightColorRun] {
        snapshot.colorRuns
    }

    package var appliedFontRunsForTesting: [HighlightFontRun] {
        snapshot.fontRuns
    }

    package var pendingDirtyRangesForTesting: [NSRange] {
        pendingEditMap.visibleDirtyRanges
    }

    package var hasPendingEditsForTesting: Bool {
        !pendingEditMap.isEmpty
    }

    package var hasMaterializedRuns: Bool {
        !snapshot.colorRuns.isEmpty || !snapshot.fontRuns.isEmpty
    }

    package func colorRuns(in range: NSRange) -> [HighlightColorRun] {
        var runs: [HighlightColorRun] = []
        forEachColorRun(in: range) { runs.append($0) }
        return HighlightRunUtilities.coalescedColorRuns(runs)
    }

    package func foregroundColor(at location: Int) -> SyntaxEditorColor? {
        guard location >= 0, location < currentTextLength else { return nil }
        var color: SyntaxEditorColor?
        forEachColorRun(in: NSRange(location: location, length: 1)) { run in
            color = run.color
        }
        return color
    }

    package func font(at location: Int) -> SyntaxEditorFont? {
        guard location >= 0, location < currentTextLength else { return nil }
        var font: SyntaxEditorFont?
        forEachFontRun(in: NSRange(location: location, length: 1)) { run in
            font = run.font
        }
        return font
    }

    package func effectiveForegroundColor(at location: Int) -> SyntaxEditorColor? {
        foregroundColor(at: location) ?? baseForeground
    }

    package func updateBaseForeground(_ color: SyntaxEditorColor?, textLength nextTextLength: Int? = nil) {
        let nextTextLength = nextTextLength.map { max(0, $0) } ?? currentTextLength
        let baseChanged: Bool
        switch (snapshot.baseForeground, color) {
        case (.none, .none):
            baseChanged = false
        case let (.some(lhs), .some(rhs)):
            baseChanged = !lhs.isEqual(rhs)
        default:
            baseChanged = true
        }

        let textLengthChanged = currentTextLength != nextTextLength
        currentTextLength = nextTextLength
        if baseChanged || textLengthChanged {
            snapshot = HighlightRenderSnapshot(
                revision: snapshot.revision,
                language: snapshot.language,
                textLength: snapshot.textLength,
                baseForeground: color,
                baseFont: snapshot.baseFont,
                colorRuns: snapshot.colorRuns,
                fontRuns: snapshot.fontRuns,
                suppressionRanges: snapshot.suppressionRanges
            )
            generation += 1
        }
    }

    package func forEachColorRun(
        in range: NSRange,
        _ body: (HighlightColorRun) -> Void
    ) {
        resolver().forEachColorRun(in: range, body)
    }

    package func forEachFontRun(
        in range: NSRange,
        _ body: (HighlightFontRun) -> Void
    ) {
        resolver().forEachFontRun(in: range, body)
    }

    package func commitSnapshot(
        runSet: HighlightRunSet,
        range refreshedRange: NSRange,
        revision: Int?,
        language: SyntaxLanguage?,
        textLength nextTextLength: Int,
        baseForeground: SyntaxEditorColor,
        baseFont: SyntaxEditorFont?,
        suppressionRanges nextSuppressionRanges: [NSRange] = []
    ) {
        let nextTextLength = max(0, nextTextLength)
        let clampedRefreshRange = SyntaxEditorRangeUtilities.clampedRange(
            refreshedRange,
            utf16Length: nextTextLength
        )
        let normalizedSuppressionRanges = HighlightRunUtilities.normalizedRanges(
            nextSuppressionRanges,
            textLength: nextTextLength
        )

        var nextColorRuns = snapshot.colorRuns
        var nextFontRuns = snapshot.fontRuns
        let normalizedColorRuns = HighlightRunUtilities.clippedColorRuns(
            HighlightRunUtilities.coalescedColorRuns(
                HighlightRunUtilities.normalizedColorRuns(runSet.colorRuns, textLength: nextTextLength)
                    .flatMap { run in
                        HighlightRunUtilities.rangesBySubtracting(normalizedSuppressionRanges, from: run.range)
                            .map { HighlightColorRun(range: $0, color: run.color) }
                    }
            ),
            to: clampedRefreshRange
        )
        let normalizedFontRuns = HighlightRunUtilities.clippedFontRuns(
            HighlightRunUtilities.coalescedFontRuns(
                HighlightRunUtilities.normalizedFontRuns(runSet.fontRuns, textLength: nextTextLength)
            ),
            to: clampedRefreshRange
        )

        HighlightRunUtilities.replaceColorRuns(&nextColorRuns, in: clampedRefreshRange, with: normalizedColorRuns)
        HighlightRunUtilities.replaceFontRuns(&nextFontRuns, in: clampedRefreshRange, with: normalizedFontRuns)

        snapshot = HighlightRenderSnapshot(
            revision: revision,
            language: language,
            textLength: nextTextLength,
            baseForeground: baseForeground,
            baseFont: baseFont,
            colorRuns: nextColorRuns,
            fontRuns: nextFontRuns,
            suppressionRanges: normalizedSuppressionRanges
        )
        currentTextLength = nextTextLength
        currentSuppressionRanges = normalizedSuppressionRanges
        pendingEditMap.clear()
        generation += 1
    }

    package func recordPendingEdit(
        _ mutation: SyntaxHighlightMutation,
        currentTextLength nextTextLength: Int
    ) {
        currentTextLength = max(0, nextTextLength)
        pendingEditMap.recordPendingEdit(mutation, currentTextLength: currentTextLength)
        generation += 1
    }

    package func updateSuppressionRanges(_ suppressionRanges: [NSRange], textLength nextTextLength: Int? = nil) {
        if let nextTextLength {
            currentTextLength = max(0, nextTextLength)
        }
        let normalized = HighlightRunUtilities.normalizedRanges(
            suppressionRanges,
            textLength: currentTextLength
        )
        guard normalized != currentSuppressionRanges else { return }
        currentSuppressionRanges = normalized
        generation += 1
    }

    package func clear(
        textLength nextTextLength: Int,
        baseForeground: SyntaxEditorColor,
        baseFont: SyntaxEditorFont?
    ) {
        let nextTextLength = max(0, nextTextLength)
        snapshot = HighlightRenderSnapshot(
            revision: nil,
            language: nil,
            textLength: nextTextLength,
            baseForeground: baseForeground,
            baseFont: baseFont,
            colorRuns: [],
            fontRuns: [],
            suppressionRanges: []
        )
        currentTextLength = nextTextLength
        currentSuppressionRanges = []
        pendingEditMap.clear()
        generation += 1
    }

    package func reset(textLength nextTextLength: Int) {
        let nextTextLength = max(0, nextTextLength)
        snapshot = HighlightRenderSnapshot(
            revision: nil,
            language: nil,
            textLength: nextTextLength,
            baseForeground: snapshot.baseForeground,
            baseFont: snapshot.baseFont,
            colorRuns: [],
            fontRuns: [],
            suppressionRanges: []
        )
        currentTextLength = nextTextLength
        currentSuppressionRanges = []
        pendingEditMap.clear()
        generation += 1
    }

    private func resolver() -> HighlightVisibleRunResolver {
        HighlightVisibleRunResolver(
            snapshot: snapshot,
            pendingEditMap: pendingEditMap,
            currentTextLength: currentTextLength,
            currentSuppressionRanges: currentSuppressionRanges
        )
    }
}

fileprivate enum HighlightRunUtilities {
    static func normalizedColorRuns(
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

    static func normalizedFontRuns(
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

    static func normalizedRanges(_ ranges: [NSRange], textLength: Int) -> [NSRange] {
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

    static func coalescedRanges(_ ranges: [NSRange]) -> [NSRange] {
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

    static func clippedColorRuns(
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

    static func clippedFontRuns(
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

    static func replaceColorRuns(
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

    static func replaceFontRuns(
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

    static func forEachColorRun(
        _ runs: [HighlightColorRun],
        in range: NSRange,
        _ body: (HighlightColorRun) -> Void
    ) {
        guard range.length > 0 else { return }
        let startIndex = firstColorRunIndex(intersecting: range, in: runs)
        for run in runs[startIndex...] {
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else { continue }
            body(HighlightColorRun(range: intersection, color: run.color))
        }
    }

    static func forEachFontRun(
        _ runs: [HighlightFontRun],
        in range: NSRange,
        _ body: (HighlightFontRun) -> Void
    ) {
        guard range.length > 0 else { return }
        let startIndex = firstFontRunIndex(intersecting: range, in: runs)
        for run in runs[startIndex...] {
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else { continue }
            body(HighlightFontRun(range: intersection, font: run.font))
        }
    }

    static func coalescedColorRuns(
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

    static func coalescedFontRuns(
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

    static func rangesBySubtracting(_ removals: [NSRange], from range: NSRange) -> [NSRange] {
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
}

#endif
