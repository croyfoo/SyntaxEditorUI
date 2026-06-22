import Foundation
import SyntaxEditorCoreTypes
import SyntaxEditorLanguageSupport
import SyntaxEditorLanguages

extension EditorCommandEngine {
package struct UndoState: Equatable {
    package let edits: [SyntaxEditorTextChange.Replacement]
    package let selectedRange: NSRange
    package let refreshStartUTF16: Int

    package init(edits: [SyntaxEditorTextChange.Replacement], selectedRange: NSRange, refreshStartUTF16: Int) {
        self.edits = edits
        self.selectedRange = selectedRange
        self.refreshStartUTF16 = refreshStartUTF16
    }
}
}
