import Foundation

package struct EditorUndoState: Equatable {
    package let edits: [SyntaxEditorTextEdit]
    package let selectedRange: NSRange
    package let refreshStartUTF16: Int

    package init(edits: [SyntaxEditorTextEdit], selectedRange: NSRange, refreshStartUTF16: Int) {
        self.edits = edits
        self.selectedRange = selectedRange
        self.refreshStartUTF16 = refreshStartUTF16
    }
}
