import Foundation

struct PlainTextLanguage: SyntaxLanguageSupport {
    init() {}

    var language: SyntaxLanguage { .plainText }
    var displayName: String { "Plain Text" }
    var aliases: Set<String> { ["plain-text", "plain", "plaintext", "text", "txt", "text/plain"] }
    var treeSitterSupport: SyntaxTreeSitterSupport? { nil }
    var supportsCodeEditingCommands: Bool { false }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        nil
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        false
    }
}
