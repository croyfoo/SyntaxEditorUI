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

    @Test("Text range intersection index clips sorted ranges without scanning by fragment")
    func textRangeIntersectionIndexClipsSortedRanges() {
        let index = TextRangeIntersectionIndex(
            ranges: [
                NSRange(location: 8, length: 4),
                NSRange(location: 0, length: 5),
                NSRange(location: 20, length: 10),
                NSRange(location: 4, length: 0),
                NSRange(location: 3, length: 6),
                NSRange(location: 12, length: 2),
            ],
            utf16Length: 24
        )

        #expect(index.ranges(intersecting: NSRange(location: 4, length: 16)) == [
            NSRange(location: 4, length: 1),
            NSRange(location: 4, length: 5),
            NSRange(location: 8, length: 4),
            NSRange(location: 12, length: 2),
        ])
        #expect(index.sourceRanges(intersecting: NSRange(location: 21, length: 10)) == [
            NSRange(location: 20, length: 4),
        ])
        #expect(index.ranges(intersecting: NSRange(location: 24, length: 4)).isEmpty)
    }

    @Test("Highlight token range index includes long tokens that start before the refresh range")
    func highlightTokenRangeIndexIncludesLongTokensBeforeRefreshRange() {
        let tokens = [
            SyntaxHighlightToken(
                range: NSRange(location: 0, length: 80),
                rawCaptureName: "editor.syntax.swift.comment"
            ),
            SyntaxHighlightToken(
                range: NSRange(location: 10, length: 2),
                rawCaptureName: "editor.syntax.swift.keyword"
            ),
            SyntaxHighlightToken(
                range: NSRange(location: 20, length: 2),
                rawCaptureName: "editor.syntax.swift.string"
            ),
            SyntaxHighlightToken(
                range: NSRange(location: 30, length: 2),
                rawCaptureName: "editor.syntax.swift.keyword"
            ),
        ]
        let index = HighlightTokenRangeIndex(tokens: tokens)

        #expect(index.firstTokenIndex(intersecting: NSRange(location: 60, length: 1)) == 0)
        #expect(index.firstTokenIndex(intersecting: NSRange(location: 81, length: 1)) == tokens.count)
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

    @Test("Highlight render snapshot leaves TextKit storage unchanged")
    func highlightRenderSnapshotLeavesTextKitStorageUnchanged() {
        let system = EditorTextSystem()
        TextEditingTransaction.perform(on: system.textContentStorage) { storage in
            let attributedString = NSMutableAttributedString(string: "ab")
            attributedString.addAttribute(.foregroundColor, value: baseForeground, range: NSRange(location: 0, length: 2))
            storage.setAttributedString(attributedString)
        }

        system.styleStore.commitSnapshot(
            runSet: HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 2), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 2),
            revision: 1,
            language: .swift,
            textLength: 2,
            baseForeground: baseForeground,
            baseFont: nil
        )

        #expect((system.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? SyntaxEditorColor)?.isEqual(baseForeground) == true)
        #expect(system.styleStore.foregroundColor(at: 0)?.isEqual(redColor) == true)
    }

    @Test("Highlight render snapshot coalesces adjacent same-color runs")
    func highlightRenderSnapshotCoalescesAdjacentSameColorRuns() {
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet:
            HighlightRunSet(
                colorRuns: [
                    HighlightColorRun(range: NSRange(location: 0, length: 2), color: redColor),
                    HighlightColorRun(range: NSRange(location: 2, length: 3), color: redColor),
                ],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 5),
            revision: 1,
            language: .swift,
            textLength: 5,
            baseForeground: baseForeground,
            baseFont: nil
        )

        #expect(store.appliedColorRunsForTesting.map(\.range) == [
            NSRange(location: 0, length: 5),
        ])
        #expect(store.epoch == 1)
    }

    @Test("Highlight render snapshot replaces only committed range")
    func highlightRenderSnapshotReplacesOnlyCommittedRange() {
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet:
            HighlightRunSet(
                colorRuns: [
                    HighlightColorRun(range: NSRange(location: 0, length: 3), color: redColor),
                    HighlightColorRun(range: NSRange(location: 10, length: 3), color: redColor),
                ],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 20),
            revision: 1,
            language: .swift,
            textLength: 20,
            baseForeground: baseForeground,
            baseFont: nil
        )
        store.commitSnapshot(
            runSet:
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 3), color: blueColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 3),
            revision: 2,
            language: .swift,
            textLength: 20,
            baseForeground: baseForeground,
            baseFont: nil
        )

        #expect(store.appliedColorRunsForTesting.map(\.range) == [
            NSRange(location: 0, length: 3),
            NSRange(location: 10, length: 3),
        ])
        #expect(store.appliedColorRunsForTesting.first?.color.isEqual(blueColor) == true)
        #expect(store.appliedColorRunsForTesting.last?.color.isEqual(redColor) == true)
    }

    @Test("Pending highlight edit keeps snapshot unshifted and resolves visible insertion lazily")
    func pendingHighlightEditKeepsSnapshotUnshiftedAndResolvesVisibleInsertionLazily() {
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet:
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 10),
            revision: 1,
            language: .swift,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )

        store.recordPendingEdit(
            SyntaxHighlightMutation(location: 5, length: 0, replacement: "xx"),
            currentTextLength: 12
        )

        #expect(store.appliedColorRunsForTesting.map(\.range) == [
            NSRange(location: 0, length: 10),
        ])
        #expect(store.colorRuns(in: NSRange(location: 0, length: 12)).map(\.range) == [
            NSRange(location: 0, length: 5),
            NSRange(location: 7, length: 5),
        ])
        #expect(store.pendingDirtyRangesForTesting == [NSRange(location: 5, length: 2)])
    }

    @Test("Pending highlight edit resolves deletion and replacement lazily")
    func pendingHighlightEditResolvesDeletionAndReplacementLazily() {
        let deletionStore = HighlightRenderSnapshotStore()
        deletionStore.commitSnapshot(
            runSet:
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 10),
            revision: 1,
            language: .swift,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )
        deletionStore.recordPendingEdit(
            SyntaxHighlightMutation(location: 3, length: 2, replacement: ""),
            currentTextLength: 8
        )
        #expect(deletionStore.colorRuns(in: NSRange(location: 0, length: 8)).map(\.range) == [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 4),
        ])

        let replacementStore = HighlightRenderSnapshotStore()
        replacementStore.commitSnapshot(
            runSet:
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 10),
            revision: 1,
            language: .swift,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )
        replacementStore.recordPendingEdit(
            SyntaxHighlightMutation(location: 2, length: 3, replacement: "XY"),
            currentTextLength: 9
        )
        #expect(replacementStore.colorRuns(in: NSRange(location: 0, length: 9)).map(\.range) == [
            NSRange(location: 0, length: 2),
            NSRange(location: 4, length: 5),
        ])
    }

    @Test("Pending highlight edit composes multiple edits")
    func pendingHighlightEditComposesMultipleEdits() {
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet:
            HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 10),
            revision: 1,
            language: .swift,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )
        store.recordPendingEdit(
            SyntaxHighlightMutation(location: 5, length: 0, replacement: "xx"),
            currentTextLength: 12
        )
        store.recordPendingEdit(
            SyntaxHighlightMutation(location: 0, length: 0, replacement: "y"),
            currentTextLength: 13
        )

        #expect(store.colorRuns(in: NSRange(location: 0, length: 13)).map(\.range) == [
            NSRange(location: 1, length: 5),
            NSRange(location: 8, length: 5),
        ])
        #expect(store.pendingDirtyRangesForTesting == [
            NSRange(location: 0, length: 1),
            NSRange(location: 6, length: 2),
        ])
    }

    @Test("Highlight visible resolver suppresses marked text ranges")
    func highlightVisibleResolverSuppressesMarkedTextRanges() {
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet: HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 10),
            revision: 1,
            language: .swift,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil,
            suppressionRanges: [NSRange(location: 3, length: 3)]
        )

        #expect(store.colorRuns(in: NSRange(location: 0, length: 10)).map(\.range) == [
            NSRange(location: 0, length: 3),
            NSRange(location: 6, length: 4),
        ])
    }

    @Test("Snapshot commit clears pending highlight edits")
    func snapshotCommitClearsPendingHighlightEdits() {
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet: HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 10),
            revision: 1,
            language: .swift,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )
        store.recordPendingEdit(
            SyntaxHighlightMutation(location: 5, length: 0, replacement: "xx"),
            currentTextLength: 12
        )
        #expect(store.hasPendingEditsForTesting)

        let invalidatedDirtyRanges = store.commitSnapshot(
            runSet: HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 12), color: blueColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 12),
            revision: 2,
            language: .swift,
            textLength: 12,
            baseForeground: baseForeground,
            baseFont: nil
        )

        #expect(invalidatedDirtyRanges == [NSRange(location: 5, length: 2)])
        #expect(!store.hasPendingEditsForTesting)
        #expect(store.foregroundColor(at: 5)?.isEqual(blueColor) == true)
    }

    @Test("Partial snapshot commit preserves pending edit mapping")
    func partialSnapshotCommitPreservesPendingEditMapping() {
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet: HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 10),
            revision: 1,
            language: .swift,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )
        store.recordPendingEdit(
            SyntaxHighlightMutation(location: 5, length: 0, replacement: "xx"),
            currentTextLength: 12
        )

        let partialInvalidatedRanges = store.commitSnapshot(
            runSet: HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 5, length: 2), color: blueColor)],
                fontRuns: []
            ),
            range: NSRange(location: 5, length: 2),
            revision: 2,
            language: .swift,
            textLength: 12,
            baseForeground: baseForeground,
            baseFont: nil
        )

        #expect(partialInvalidatedRanges.isEmpty)
        #expect(store.hasPendingEditsForTesting)
        let visibleRuns = store.colorRuns(in: NSRange(location: 0, length: 12))
        #expect(visibleRuns.map(\.range) == [
            NSRange(location: 0, length: 5),
            NSRange(location: 5, length: 2),
            NSRange(location: 7, length: 5),
        ])
        #expect(visibleRuns[0].color.isEqual(redColor))
        #expect(visibleRuns[1].color.isEqual(blueColor))
        #expect(visibleRuns[2].color.isEqual(redColor))
    }

    @Test("Highlight render snapshot clears stale font runs without dropping color runs")
    func highlightRenderSnapshotClearsStaleFontRunsWithoutDroppingColorRuns() {
        #if canImport(UIKit)
        let baseFont = UIFont.systemFont(ofSize: 13)
        let syntaxFont = UIFont.boldSystemFont(ofSize: 13)
        let nextBaseFont = UIFont.systemFont(ofSize: 17)
        #elseif canImport(AppKit)
        let baseFont = NSFont.systemFont(ofSize: 13)
        let syntaxFont = NSFont.boldSystemFont(ofSize: 13)
        let nextBaseFont = NSFont.systemFont(ofSize: 17)
        #endif
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet: HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 5), color: redColor)],
                fontRuns: [HighlightFontRun(range: NSRange(location: 0, length: 5), font: syntaxFont)]
            ),
            range: NSRange(location: 0, length: 5),
            revision: 1,
            language: .swift,
            textLength: 5,
            baseForeground: baseForeground,
            baseFont: baseFont
        )

        let invalidatedRanges = store.updateBaseFont(
            nextBaseFont,
            textLength: 5,
            clearsFontRuns: true
        )

        #expect(invalidatedRanges == [NSRange(location: 0, length: 5)])
        #expect(store.foregroundColor(at: 0)?.isEqual(redColor) == true)
        #expect(store.font(at: 0) == nil)
    }

    @Test("Highlight render snapshot resets logical state")
    func highlightRenderSnapshotResetsLogicalState() {
        let store = HighlightRenderSnapshotStore()
        store.commitSnapshot(
            runSet: HighlightRunSet(
                colorRuns: [HighlightColorRun(range: NSRange(location: 0, length: 10), color: redColor)],
                fontRuns: []
            ),
            range: NSRange(location: 0, length: 10),
            revision: 1,
            language: .swift,
            textLength: 10,
            baseForeground: baseForeground,
            baseFont: nil
        )

        store.reset(textLength: 40)

        #expect(store.appliedColorRunsForTesting.isEmpty)
        #expect(store.appliedFontRunsForTesting.isEmpty)
        #expect(store.epoch == 2)
    }
}

struct SyntaxEditorTaskWaiterTests {
    @Test("Task waiter keeps timeout authoritative when timeout cancels waited task")
    func keepsTimeoutAuthoritativeWhenTimeoutCancelsWaitedTask() async {
        let taskFinished = DispatchSemaphore(value: 0)
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            taskFinished.signal()
        }
        defer {
            task.cancel()
        }

        let didComplete = await syntaxEditorWaitForTaskCompletionForTesting(
            task,
            timeoutNanoseconds: 1
        ) {
            task.cancel()
            taskFinished.wait()
            Thread.sleep(forTimeInterval: 0.01)
        }

        #expect(!didComplete)
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
