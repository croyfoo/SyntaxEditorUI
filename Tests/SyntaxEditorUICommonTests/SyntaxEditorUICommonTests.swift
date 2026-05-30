import Foundation
import Testing

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@testable import SyntaxEditorUICommon

@MainActor
struct SyntaxEditorUICommonTests {
    @Test("SyntaxEditorUICommon exposes TextKit 2 render storage")
    func exposesTextKit2RenderStorage() {
        let store = SyntaxEditorTextKit2RenderStore()
        #expect(store.hasForegroundRuns == false)
    }

    @Test("TextKit 2 render store skips absent base foreground materialization")
    func skipsAbsentBaseForegroundMaterialization() {
        let store = SyntaxEditorTextKit2RenderStore()
        store.installForeground(colorRuns: [], baseForeground: nil, textLength: 8)

        var applyCount = 0
        store.materializeForeground(in: NSRange(location: 0, length: 8)) { _, _ in
            applyCount += 1
        }

        #expect(applyCount == 0)
    }

    @Test("TextKit 2 render store coalesces adjacent same-color foreground runs")
    func coalescesAdjacentSameColorForegroundRuns() {
        let store = SyntaxEditorTextKit2RenderStore()
        store.installForeground(
            colorRuns: [
                SyntaxEditorTextKit2ColorRun(range: NSRange(location: 0, length: 2), color: .red),
                SyntaxEditorTextKit2ColorRun(range: NSRange(location: 2, length: 3), color: .red),
            ],
            baseForeground: nil,
            textLength: 5
        )

        var appliedRanges: [NSRange] = []
        store.materializeForeground(in: NSRange(location: 0, length: 5)) { range, color in
            guard color != nil else { return }
            appliedRanges.append(range)
        }

        #expect(appliedRanges.count == 1)
        #expect(appliedRanges.first?.location == 0)
        #expect(appliedRanges.first?.length == 5)
    }
}
