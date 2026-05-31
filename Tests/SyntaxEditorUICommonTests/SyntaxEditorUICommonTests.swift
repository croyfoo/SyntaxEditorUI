import Foundation
import Testing
import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@testable import SyntaxEditorUICommon

@MainActor
struct SyntaxEditorUICommonTests {
    @Test("SyntaxEditorUICommon exposes highlight style storage")
    func exposesHighlightStyleStorage() {
        let system = EditorTextSystem()
        #expect(system.styleStore.appliedColorRunsForTesting.isEmpty)
        #expect(system.styleStore.appliedFontRunsForTesting.isEmpty)
        #expect(system.layoutManager.textContainer === system.container)
        #expect(system.container.textLayoutManager === system.layoutManager)
        #expect(system.layoutManager.renderingAttributesValidator == nil)
    }

    @Test("Editor text system centralizes UTF-16 range conversion")
    func centralizesUTF16RangeConversion() throws {
        let system = EditorTextSystem()
        TextEditingTransaction.perform(on: system.textContentStorage) { storage in
            storage.setAttributedString(NSAttributedString(string: "abcdef"))
        }

        let range = NSRange(location: 1, length: 3)
        let textRange = try #require(system.textRange(forUTF16Range: range))

        #expect(system.utf16Range(for: textRange) == range)
        #expect(system.utf16Range(for: system.textContentStorage.documentRange) == NSRange(location: 0, length: 6))
    }

    @Test("Text layout geometry centralizes range intersection")
    func centralizesRangeIntersection() {
        let ranges = [
            NSRange(location: 0, length: 3),
            NSRange(location: 5, length: 4),
            NSRange(location: 12, length: 2),
        ]

        #expect(TextLayoutGeometry.ranges(ranges, intersecting: NSRange(location: 2, length: 5)) == [
            NSRange(location: 2, length: 1),
            NSRange(location: 5, length: 2),
        ])
        #expect(TextLayoutGeometry.ranges(ranges, intersecting: NSRange(location: 20, length: 2)).isEmpty)
    }

    @Test("Document line metrics centralizes resize estimates without rebuilds")
    func documentLineMetricsCachesResizeEstimates() {
        let metrics = DocumentLineMetrics(
            source: "let extremelyLongIdentifierName = value\nlet short = true",
            tabWidth: 4
        )
        let rebuildCount = metrics.fullRebuildCount

        let wide = metrics.estimatedDocumentSize(
            minimumSize: CGSize(width: 360, height: 40),
            lineWrappingEnabled: true,
            lineHeight: 10,
            columnWidth: 10,
            lineFragmentPadding: 0
        )
        let narrow = metrics.estimatedDocumentSize(
            minimumSize: CGSize(width: 80, height: 40),
            lineWrappingEnabled: true,
            lineHeight: 10,
            columnWidth: 10,
            lineFragmentPadding: 0
        )

        #expect(metrics.fullRebuildCount == rebuildCount)
        #expect(narrow.height > wide.height)
    }

    @Test("Text editing transaction applies style operations incrementally")
    func appliesStyleOperationsIncrementally() async {
        let system = EditorTextSystem()
        TextEditingTransaction.perform(on: system.textContentStorage) { storage in
            storage.setAttributedString(NSAttributedString(string: "abcdef"))
        }

        let font = SyntaxEditorFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        let completed = await TextEditingTransaction.applyIncrementally(
            HighlightStyleOperations(
                colorOperations: [HighlightColorOperation(range: NSRange(location: 0, length: 6), color: redColor)],
                fontOperations: [HighlightFontOperation(range: NSRange(location: 1, length: 3), font: font)]
            ),
            to: system.textContentStorage,
            maximumOperationsPerTransaction: 1
        )

        #expect(completed)
        #expect((system.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? SyntaxEditorColor)?.isEqual(redColor) == true)
        #expect((system.textStorage.attribute(.font, at: 1, effectiveRange: nil) as? SyntaxEditorFont) == font)
    }

    @Test("Text editing transaction rolls back incremental font operations after cancellation validation fails")
    func rollsBackIncrementalFontOperationsAfterCancellationValidationFails() async {
        let system = EditorTextSystem()
        TextEditingTransaction.perform(on: system.textContentStorage) { storage in
            storage.setAttributedString(NSAttributedString(string: "abcdef"))
        }

        let firstFont = SyntaxEditorFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        let secondFont = SyntaxEditorFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        var validationCount = 0
        let completed = await TextEditingTransaction.applyIncrementally(
            HighlightStyleOperations(
                colorOperations: [],
                fontOperations: [
                    HighlightFontOperation(range: NSRange(location: 0, length: 1), font: firstFont),
                    HighlightFontOperation(range: NSRange(location: 1, length: 1), font: secondFont),
                ]
            ),
            to: system.textContentStorage,
            maximumOperationsPerTransaction: 1,
            shouldContinue: {
                validationCount += 1
                return validationCount < 2
            }
        )

        #expect(!completed)
        #expect(system.textStorage.attribute(.font, at: 0, effectiveRange: nil) == nil)
        #expect(system.textStorage.attribute(.font, at: 1, effectiveRange: nil) == nil)
    }

    @Test("Highlight style store leaves storage unchanged after incremental cancellation")
    func leavesStorageUnchangedAfterIncrementalCancellation() async {
        let system = EditorTextSystem()
        let store = HighlightStyleStore()
        TextEditingTransaction.perform(on: system.textContentStorage) { storage in
            let attributedString = NSMutableAttributedString(string: "ab")
            attributedString.addAttribute(.foregroundColor, value: baseForeground, range: NSRange(location: 0, length: 2))
            storage.setAttributedString(attributedString)
        }

        let transaction = store.prepareApply(
            HighlightRunSet(
                colorRuns: [
                    HighlightColorRun(range: NSRange(location: 0, length: 1), color: redColor),
                    HighlightColorRun(range: NSRange(location: 1, length: 1), color: blueColor),
                ],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 2),
            mutation: nil,
            textLength: 2,
            baseForeground: baseForeground,
            baseFont: nil
        )
        var validationCount = 0

        let completed = await TextEditingTransaction.applyIncrementally(
            transaction.operations,
            to: system.textContentStorage,
            maximumOperationsPerTransaction: 1,
            shouldContinue: {
                validationCount += 1
                return validationCount < 2
            }
        )

        #expect(!completed)
        #expect(store.appliedColorRunsForTesting.isEmpty)
        #expect(store.epoch == 0)
        #expect((system.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? SyntaxEditorColor)?.isEqual(baseForeground) == true)
    }

    @Test("Highlight style store emits content attribute operations")
    func emitsContentAttributeOperations() {
        let store = HighlightStyleStore()
        let operations = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 1, length: 3), color: .red)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 8),
            mutation: nil,
            textLength: 8,
            baseForeground: baseForeground,
            baseFont: nil
        )

        #expect(operations.colorOperations.count == 1)
        #expect(operations.colorOperations.first?.range == NSRange(location: 1, length: 3))
        #expect(operations.colorOperations.first?.color.isEqual(redColor) == true)
        #expect(store.epoch == 1)
    }

    @Test("Highlight style store coalesces adjacent same-color foreground runs")
    func coalescesAdjacentSameColorForegroundRuns() {
        let store = HighlightStyleStore()
        let operations = store.apply(
            HighlightRunSet(
                colorRuns: [
                    HighlightColorRun(range: NSRange(location: 0, length: 2), color: redColor),
                    HighlightColorRun(range: NSRange(location: 2, length: 3), color: redColor),
                ],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 5),
            mutation: nil,
            textLength: 5,
            baseForeground: baseForeground,
            baseFont: nil
        )

        #expect(operations.colorOperations.count == 1)
        #expect(operations.colorOperations.first?.range == NSRange(location: 0, length: 5))
        #expect(store.appliedColorRunsForTesting.count == 1)
    }

    @Test("Highlight style store diffs only refreshed foreground ranges")
    func diffsOnlyRefreshedForegroundRanges() {
        let store = HighlightStyleStore()
        _ = store.apply(
            HighlightRunSet(
                colorRuns: [
                    HighlightColorRun(range: NSRange(location: 0, length: 3), color: redColor),
                    HighlightColorRun(range: NSRange(location: 10, length: 3), color: redColor),
                ],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 20),
            mutation: nil,
            textLength: 20,
            baseForeground: baseForeground,
            baseFont: nil
        )

        let unchangedOperations = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 3), color: redColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 3),
            mutation: nil,
            textLength: 20,
            baseForeground: baseForeground,
            baseFont: nil
        )
        #expect(unchangedOperations.colorOperations.isEmpty)

        let changedOperations = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 3), color: blueColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 3),
            mutation: nil,
            textLength: 20,
            baseForeground: baseForeground,
            baseFont: nil
        )
        #expect(changedOperations.colorOperations.map(\.range) == [
            NSRange(location: 0, length: 3),
            NSRange(location: 0, length: 3),
        ])
        #expect(store.appliedColorRunsForTesting.map(\.range) == [
            NSRange(location: 0, length: 3),
            NSRange(location: 10, length: 3),
        ])
    }

    @Test("Highlight style store refreshes plain foreground when base foreground changes")
    func refreshesPlainForegroundWhenBaseForegroundChanges() {
        let store = HighlightStyleStore()
        _ = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 4, length: 2), color: redColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 12),
            mutation: nil,
            textLength: 12,
            baseForeground: baseForeground,
            baseFont: nil
        )

        let operations = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 4, length: 2), color: redColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 12),
            mutation: nil,
            textLength: 12,
            baseForeground: blueColor,
            baseFont: nil
        )

        #expect(operations.colorOperations.map(\.range) == [
            NSRange(location: 0, length: 12),
            NSRange(location: 4, length: 2),
        ])
        #expect(operations.colorOperations.first?.color.isEqual(blueColor) == true)
        #expect(operations.colorOperations.last?.color.isEqual(redColor) == true)
    }

    @Test("Highlight style store resets expanding foreground runs before applying replacement style")
    func resetsExpandingForegroundRunsBeforeApplyingReplacementStyle() {
        let store = HighlightStyleStore()
        _ = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 5, length: 5), color: blueColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 10),
            mutation: nil,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )

        let operations = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 10),
            mutation: nil,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )

        #expect(operations.colorOperations.map(\.range) == [
            NSRange(location: 5, length: 5),
            NSRange(location: 0, length: 10),
        ])
        #expect(operations.colorOperations.first?.color.isEqual(baseForeground) == true)
        #expect(operations.colorOperations.last?.color.isEqual(redColor) == true)
    }

    @Test("Highlight style store records text mutation without repainting unaffected split runs")
    func recordsTextMutationWithoutRepaintingUnaffectedSplitRuns() {
        let store = HighlightStyleStore()
        _ = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 10),
            mutation: nil,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )

        let operations = store.apply(
            HighlightRunSet(colorRuns: [], fontRuns: []),
            refreshedRange: NSRange(location: 5, length: 2),
            mutation: SyntaxHighlightMutation(location: 5, length: 0, replacement: "xx"),
            textLength: 12,
            baseForeground: baseForeground,
            baseFont: nil
        )
        #expect(store.appliedColorRunsForTesting.map(\.range) == [
            NSRange(location: 0, length: 5),
            NSRange(location: 7, length: 5),
        ])
        #expect(operations.colorOperations.isEmpty)
    }

    @Test("Highlight style store resets shrinking font runs before applying replacement style")
    func resetsShrinkingFontRunsBeforeApplyingReplacementStyle() {
        let store = HighlightStyleStore()
        let baseFont = SyntaxEditorFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = SyntaxEditorFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        _ = store.apply(
            HighlightRunSet(
                colorRuns: [],
                fontRuns: [HighlightFontRun(range: NSRange(location: 0, length: 10), font: boldFont)]
            ),
            refreshedRange: NSRange(location: 0, length: 10),
            mutation: nil,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: baseFont
        )

        let operations = store.apply(
            HighlightRunSet(
                colorRuns: [],
                fontRuns: [HighlightFontRun(range: NSRange(location: 0, length: 5), font: boldFont)]
            ),
            refreshedRange: NSRange(location: 0, length: 10),
            mutation: nil,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: baseFont
        )

        #expect(operations.fontOperations.map(\.range) == [
            NSRange(location: 0, length: 10),
            NSRange(location: 0, length: 5),
        ])
        #expect(operations.fontOperations.first?.font == baseFont)
        #expect(operations.fontOperations.last?.font == boldFont)
    }

    @Test("Highlight style store resets logical state without repaint operations")
    func resetsLogicalStateWithoutRepaintOperations() {
        let store = HighlightStyleStore()
        _ = store.apply(
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 10),
            mutation: nil,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )

        store.reset(textLength: 40)

        #expect(store.appliedColorRunsForTesting.isEmpty)
        #expect(store.appliedFontRunsForTesting.isEmpty)
        #expect(store.epoch == 2)

        let operations = store.apply(
            HighlightRunSet(colorRuns: [], fontRuns: []),
            refreshedRange: NSRange(location: 0, length: 40),
            mutation: nil,
            textLength: 40,
            baseForeground: baseForeground,
            baseFont: nil
        )
        #expect(operations.isEmpty)
    }
}

private var baseForeground: SyntaxEditorColor {
#if canImport(UIKit)
    .label
#elseif canImport(AppKit)
    .labelColor
#endif
}

private var redColor: SyntaxEditorColor {
#if canImport(UIKit)
    .red
#elseif canImport(AppKit)
    .red
#endif
}

private var blueColor: SyntaxEditorColor {
#if canImport(UIKit)
    .blue
#elseif canImport(AppKit)
    .blue
#endif
}
