import Foundation
import SyntaxEditorCoreTypes
import SyntaxEditorLanguageSupport
import SwiftTreeSitter
import TreeSitterBash

package struct ShellLanguage: SyntaxLanguageSupport {
    package init() {}

    package var language: SyntaxLanguage { .shell }
    package var displayName: String { "Shell" }
    package var treeSitterSupport: SyntaxLanguageTreeSitterSupport? {
        SyntaxLanguageTreeSitterSupport(
            name: "Shell",
            bundleName: "TreeSitterBash_TreeSitterBash",
            queryDirectories: Self.queryDirectories,
            makeLanguage: { unsafe Language(tree_sitter_bash()) }
        )
    }

    package func toggleComment(source: String, selection: NSRange) -> SyntaxLanguage.EditResult? {
        nil
    }

    package func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        let nsSource = source as NSString
        let clampedLocation = max(0, min(location, nsSource.length))
        let lineRange = nsSource.lineRange(for: NSRange(location: clampedLocation, length: 0))
        let linePrefixLength = max(0, clampedLocation - lineRange.location)
        let linePrefix = nsSource.substring(with: NSRange(location: lineRange.location, length: linePrefixLength))
        if linePrefix.contains("#") { return true }
        return SyntaxLanguageTextUtilities.hasOddUnescapedQuote(in: linePrefix, quote: "\"")
            || SyntaxLanguageTextUtilities.hasOddUnescapedQuote(in: linePrefix, quote: "'")
    }
}

private extension ShellLanguage {
    static var queryDirectories: [URL] {
        BundledLanguageQueryResources.directories(in: .module, named: "ShellQueries")
    }
}
