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
    @Test("SyntaxEditorUICommon exposes TextKit 2 style storage")
    func exposesTextKit2StyleStorage() {
        let system = SyntaxEditorTextKit2System()
        #expect(system.styleStore.appliedColorRunsForTesting.isEmpty)
        #expect(system.styleStore.appliedFontRunsForTesting.isEmpty)
        #expect(system.layoutManager.textContainer === system.container)
        #expect(system.container.textLayoutManager === system.layoutManager)
        #expect(system.layoutManager.renderingAttributesValidator == nil)
    }

    @Test("TextKit 2 style store emits content attribute operations")
    func emitsContentAttributeOperations() {
        let store = SyntaxEditorTextKit2StyleStore()
        let operations = store.apply(
            SyntaxEditorTextKit2RunSet(
                colorRuns: [SyntaxEditorTextKit2ColorRun(range: NSRange(location: 1, length: 3), color: .red)],
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

    @Test("TextKit 2 style store coalesces adjacent same-color foreground runs")
    func coalescesAdjacentSameColorForegroundRuns() {
        let store = SyntaxEditorTextKit2StyleStore()
        let operations = store.apply(
            SyntaxEditorTextKit2RunSet(
                colorRuns: [
                    SyntaxEditorTextKit2ColorRun(range: NSRange(location: 0, length: 2), color: redColor),
                    SyntaxEditorTextKit2ColorRun(range: NSRange(location: 2, length: 3), color: redColor),
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

    @Test("TextKit 2 style store diffs only refreshed foreground ranges")
    func diffsOnlyRefreshedForegroundRanges() {
        let store = SyntaxEditorTextKit2StyleStore()
        _ = store.apply(
            SyntaxEditorTextKit2RunSet(
                colorRuns: [
                    SyntaxEditorTextKit2ColorRun(range: NSRange(location: 0, length: 3), color: redColor),
                    SyntaxEditorTextKit2ColorRun(range: NSRange(location: 10, length: 3), color: redColor),
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
            SyntaxEditorTextKit2RunSet(
                colorRuns: [SyntaxEditorTextKit2ColorRun(range: NSRange(location: 0, length: 3), color: redColor)],
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
            SyntaxEditorTextKit2RunSet(
                colorRuns: [SyntaxEditorTextKit2ColorRun(range: NSRange(location: 0, length: 3), color: blueColor)],
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

    @Test("TextKit 2 style store records text mutation without repainting unaffected split runs")
    func recordsTextMutationWithoutRepaintingUnaffectedSplitRuns() {
        let store = SyntaxEditorTextKit2StyleStore()
        _ = store.apply(
            SyntaxEditorTextKit2RunSet(
                colorRuns: [SyntaxEditorTextKit2ColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            refreshedRange: NSRange(location: 0, length: 10),
            mutation: nil,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )

        let operations = store.apply(
            SyntaxEditorTextKit2RunSet(colorRuns: [], fontRuns: []),
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
