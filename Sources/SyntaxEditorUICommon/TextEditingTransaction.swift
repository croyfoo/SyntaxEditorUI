#if canImport(UIKit) || canImport(AppKit)
import Foundation
import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
package enum TextEditingTransaction {
    private struct AttributeRollbackRun {
        let range: NSRange
        let foregroundColor: Any?
        let font: Any?
    }

    private struct AttributeRollbackChecksum {
        let range: NSRange
        let value: UInt64
    }

    private struct AttributeRollbackSnapshot {
        let checksums: [AttributeRollbackChecksum]
        let runs: [AttributeRollbackRun]
    }

    package static func perform(
        on textContentStorage: NSTextContentStorage,
        _ body: (NSTextStorage) -> Void
    ) {
        textContentStorage.performEditingTransaction {
            guard let textStorage = textContentStorage.textStorage else { return }
            body(textStorage)
        }
    }

    package static func apply(
        _ operations: HighlightStyleOperations,
        to textContentStorage: NSTextContentStorage
    ) {
        guard !operations.isEmpty else { return }

        perform(on: textContentStorage) { textStorage in
            apply(operations, to: textStorage)
        }
    }

    private static func apply(
        _ operations: HighlightStyleOperations,
        to textStorage: NSTextStorage
    ) {
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

    private static func rollbackRanges(
        for operations: HighlightStyleOperations,
        textLength: Int
    ) -> [NSRange] {
        let ranges = (operations.colorOperations.map(\.range) + operations.fontOperations.map(\.range))
            .map { SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: textLength) }
            .filter { $0.length > 0 }
            .sorted {
                if $0.location == $1.location {
                    return $0.length < $1.length
                }
                return $0.location < $1.location
            }

        guard var current = ranges.first else { return [] }
        var merged: [NSRange] = []
        for range in ranges.dropFirst() {
            let currentEnd = current.location + current.length
            let rangeEnd = range.location + range.length
            if range.location <= currentEnd {
                current.length = max(currentEnd, rangeEnd) - current.location
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    private static func makeRollbackSnapshot(
        for operations: HighlightStyleOperations,
        in textStorage: NSTextStorage
    ) -> AttributeRollbackSnapshot {
        let rollbackRanges = rollbackRanges(for: operations, textLength: textStorage.length)
        let string = textStorage.string as NSString
        let checksums = rollbackRanges.map { range in
            AttributeRollbackChecksum(
                range: range,
                value: utf16Checksum(in: range, string: string)
            )
        }
        var runs: [AttributeRollbackRun] = []
        for range in rollbackRanges {
            var location = range.location
            while location < range.upperBound {
                var effectiveRange = NSRange(location: location, length: 1)
                let attributes = unsafe textStorage.attributes(at: location, effectiveRange: &effectiveRange)
                let rollbackRange = NSIntersectionRange(effectiveRange, range)
                guard rollbackRange.length > 0 else {
                    location += 1
                    continue
                }
                runs.append(AttributeRollbackRun(
                    range: rollbackRange,
                    foregroundColor: attributes[.foregroundColor],
                    font: attributes[.font]
                ))
                location = rollbackRange.upperBound
            }
        }
        return AttributeRollbackSnapshot(checksums: checksums, runs: runs)
    }

    private static func utf16Checksum(in range: NSRange, string: NSString) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let end = range.location + range.length
        var location = range.location
        while location < end {
            hash ^= UInt64(string.character(at: location))
            hash &*= 1_099_511_628_211
            location += 1
        }
        return hash
    }

    private static func apply(
        _ operations: HighlightStyleOperations,
        to textContentStorage: NSTextContentStorage,
        rollbackSnapshots: inout [AttributeRollbackSnapshot]
    ) {
        perform(on: textContentStorage) { textStorage in
            rollbackSnapshots.append(makeRollbackSnapshot(for: operations, in: textStorage))
            apply(operations, to: textStorage)
        }
    }

    private static func restore(
        _ snapshot: AttributeRollbackSnapshot,
        to textContentStorage: NSTextContentStorage
    ) {
        guard !snapshot.runs.isEmpty else { return }

        perform(on: textContentStorage) { textStorage in
            let textLength = textStorage.length
            let string = textStorage.string as NSString
            for checksum in snapshot.checksums {
                let range = SyntaxEditorRangeUtilities.clampedRange(checksum.range, utf16Length: textLength)
                guard range.length == checksum.range.length,
                      utf16Checksum(in: range, string: string) == checksum.value
                else {
                    return
                }
            }
            for run in snapshot.runs {
                let range = SyntaxEditorRangeUtilities.clampedRange(run.range, utf16Length: textLength)
                guard range.length == run.range.length else { continue }
                if let foregroundColor = run.foregroundColor {
                    textStorage.addAttribute(.foregroundColor, value: foregroundColor, range: range)
                } else {
                    textStorage.removeAttribute(.foregroundColor, range: range)
                }
                if let font = run.font {
                    textStorage.addAttribute(.font, value: font, range: range)
                } else {
                    textStorage.removeAttribute(.font, range: range)
                }
            }
        }
    }

    package static func applyIncrementally(
        _ operations: HighlightStyleOperations,
        to textContentStorage: NSTextContentStorage,
        maximumOperationsPerTransaction: Int = 2048,
        shouldContinue: @MainActor () -> Bool = { true }
    ) async -> Bool {
        guard !operations.isEmpty else { return true }

        let maximumOperationsPerTransaction = max(1, maximumOperationsPerTransaction)
        var colorIndex = operations.colorOperations.startIndex
        var fontIndex = operations.fontOperations.startIndex
        var rollbackSnapshots: [AttributeRollbackSnapshot] = []

        func cancelAfterPartialApply() -> Bool {
            for rollbackSnapshot in rollbackSnapshots.reversed() {
                restore(rollbackSnapshot, to: textContentStorage)
            }
            return false
        }

        while colorIndex < operations.colorOperations.endIndex {
            guard !Task.isCancelled, shouldContinue() else { return cancelAfterPartialApply() }

            let colorCount = min(
                maximumOperationsPerTransaction,
                operations.colorOperations.distance(from: colorIndex, to: operations.colorOperations.endIndex)
            )

            let colorEndIndex = operations.colorOperations.index(colorIndex, offsetBy: colorCount)
            let chunk = HighlightStyleOperations(
                colorOperations: Array(operations.colorOperations[colorIndex..<colorEndIndex]),
                fontOperations: []
            )

            autoreleasepool {
                apply(chunk, to: textContentStorage, rollbackSnapshots: &rollbackSnapshots)
            }

            colorIndex = colorEndIndex

            guard !Task.isCancelled, shouldContinue() else { return cancelAfterPartialApply() }

            if colorIndex < operations.colorOperations.endIndex || !operations.fontOperations.isEmpty {
                await Task.yield()
            }
        }

        while fontIndex < operations.fontOperations.endIndex {
            guard !Task.isCancelled, shouldContinue() else { return cancelAfterPartialApply() }

            let fontCount = min(
                maximumOperationsPerTransaction,
                operations.fontOperations.distance(from: fontIndex, to: operations.fontOperations.endIndex)
            )

            let fontEndIndex = operations.fontOperations.index(fontIndex, offsetBy: fontCount)
            let chunk = HighlightStyleOperations(
                colorOperations: [],
                fontOperations: Array(operations.fontOperations[fontIndex..<fontEndIndex])
            )

            autoreleasepool {
                apply(chunk, to: textContentStorage, rollbackSnapshots: &rollbackSnapshots)
            }

            fontIndex = fontEndIndex

            guard !Task.isCancelled, shouldContinue() else { return cancelAfterPartialApply() }

            if fontIndex < operations.fontOperations.endIndex {
                await Task.yield()
            }
        }

        guard !Task.isCancelled, shouldContinue() else { return cancelAfterPartialApply() }
        return true
    }
}
#endif
