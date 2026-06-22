import Foundation
import SyntaxEditorCoreTypes
import SyntaxEditorLanguageSupport

package struct PlainTextLanguage: SyntaxLanguageSupport {
    package init() {}

    package var language: SyntaxLanguage { .plainText }
    package var displayName: String { "Plain Text" }
    package var aliases: Set<String> { ["plain-text", "plain", "plaintext", "text", "txt", "text/plain"] }
    package var treeSitterSupport: SyntaxLanguageTreeSitterSupport? { nil }
    package var supportsCodeEditingCommands: Bool { false }

    package func toggleComment(source: String, selection: NSRange) -> SyntaxLanguage.EditResult? {
        nil
    }

    package func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        false
    }
}
