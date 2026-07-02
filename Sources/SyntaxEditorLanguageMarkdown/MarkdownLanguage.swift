import Foundation
import SyntaxEditorCoreTypes
import SyntaxEditorLanguageSupport
import SwiftTreeSitter
import TreeSitterMarkdown

package struct MarkdownLanguage: SyntaxLanguageSupport {
    package init() {}

    package var language: SyntaxLanguage { .markdown }
    package var displayName: String { "Markdown" }
    package var treeSitterSupport: SyntaxLanguageTreeSitterSupport? {
        SyntaxLanguageTreeSitterSupport(
            name: "Markdown",
            bundleName: "TreeSitterMarkdown_TreeSitterMarkdown",
            queryDirectories: Self.queryDirectories,
            makeLanguage: { unsafe Language(tree_sitter_markdown()) }
        )
    }

    package func toggleComment(source: String, selection: NSRange) -> SyntaxLanguage.EditResult? {
        nil
    }

    package func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        false
    }
}

private extension MarkdownLanguage {
    static var queryDirectories: [URL] {
        BundledLanguageQueryResources.directories(in: .module, named: "MarkdownQueries")
    }
}
