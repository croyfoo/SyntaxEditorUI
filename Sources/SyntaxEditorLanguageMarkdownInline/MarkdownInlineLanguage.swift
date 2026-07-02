import Foundation
import SyntaxEditorCoreTypes
import SyntaxEditorLanguageSupport
import SwiftTreeSitter
import TreeSitterMarkdownInline

/// The inline half of the split markdown grammar. Not opened directly for a file
/// extension; it's injected into the block grammar's inline content (see the
/// Markdown target's `injections.scm`) so emphasis, links, and code spans are
/// highlighted.
package struct MarkdownInlineLanguage: SyntaxLanguageSupport {
    package init() {}

    package var language: SyntaxLanguage { .markdownInline }
    package var displayName: String { "Markdown (inline)" }
    package var treeSitterSupport: SyntaxLanguageTreeSitterSupport? {
        SyntaxLanguageTreeSitterSupport(
            name: "MarkdownInline",
            bundleName: "TreeSitterMarkdown_TreeSitterMarkdownInline",
            queryDirectories: Self.queryDirectories,
            makeLanguage: { unsafe Language(tree_sitter_markdown_inline()) }
        )
    }

    package func toggleComment(source: String, selection: NSRange) -> SyntaxLanguage.EditResult? {
        nil
    }

    package func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        false
    }
}

private extension MarkdownInlineLanguage {
    static var queryDirectories: [URL] {
        BundledLanguageQueryResources.directories(in: .module, named: "MarkdownInlineQueries")
    }
}
