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
        guard !operations.fontOperations.isEmpty else { return }

        perform(on: textContentStorage) { textStorage in
            let textLength = textStorage.length
            for operation in operations.fontOperations {
                let range = SyntaxEditorRangeUtilities.clampedRange(operation.range, utf16Length: textLength)
                guard range.length > 0 else { continue }
                textStorage.addAttribute(.font, value: operation.font, range: range)
            }
        }
    }

    package static func applyIncrementally(
        _ operations: HighlightStyleOperations,
        to textContentStorage: NSTextContentStorage,
        maximumOperationsPerTransaction: Int = 64,
        shouldContinue: @MainActor () -> Bool = { true }
    ) async -> Bool {
        guard !operations.isEmpty else { return true }

        let maximumOperationsPerTransaction = max(1, maximumOperationsPerTransaction)
        var fontIndex = operations.fontOperations.startIndex

        while fontIndex < operations.fontOperations.endIndex {
            guard !Task.isCancelled, shouldContinue() else { return false }

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
                apply(chunk, to: textContentStorage)
            }

            fontIndex = fontEndIndex

            guard !Task.isCancelled, shouldContinue() else { return false }

            if fontIndex < operations.fontOperations.endIndex {
                await Task.yield()
            }
        }

        return !Task.isCancelled && shouldContinue()
    }
}
#endif
