import Foundation

package struct EditorUndoState: Equatable {
    package let text: String
    package let selectedRange: NSRange
    package let refreshStartUTF16: Int

    package init(text: String, selectedRange: NSRange, refreshStartUTF16: Int) {
        self.text = text
        self.selectedRange = selectedRange
        self.refreshStartUTF16 = refreshStartUTF16
    }
}
