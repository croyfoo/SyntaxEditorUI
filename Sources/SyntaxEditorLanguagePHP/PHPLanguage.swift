import Foundation
import SyntaxEditorCoreTypes
import SyntaxEditorLanguageSupport
import SwiftTreeSitter
import TreeSitterPHP

package struct PHPLanguage: SyntaxLanguageSupport {
    package init() {}

    package var language: SyntaxLanguage { .php }
    package var displayName: String { "PHP" }
    package var treeSitterSupport: SyntaxLanguageTreeSitterSupport? {
        SyntaxLanguageTreeSitterSupport(
            name: "PHP",
            bundleName: "TreeSitterPHP_TreeSitterPHP",
            queryDirectories: Self.queryDirectories,
            // `tree_sitter_php` parses PHP embedded in text/HTML (the common
            // `.php` file); `tree_sitter_php_only` would be pure-PHP source.
            makeLanguage: { unsafe Language(tree_sitter_php()) }
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
        return SyntaxLanguageTextUtilities.hasOddUnescapedQuote(in: linePrefix, quote: "\"")
            || SyntaxLanguageTextUtilities.hasOddUnescapedQuote(in: linePrefix, quote: "'")
    }
}

private extension PHPLanguage {
    static var queryDirectories: [URL] {
        BundledLanguageQueryResources.directories(in: .module, named: "PHPQueries")
    }
}
