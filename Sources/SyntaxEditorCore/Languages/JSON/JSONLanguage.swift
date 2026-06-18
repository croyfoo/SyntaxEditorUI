import Foundation
import SwiftTreeSitter
import TreeSitterJSON

struct JSONLanguage: SyntaxLanguageSupport {
    init() {}

    var language: SyntaxLanguage { .json }
    var displayName: String { "JSON" }
    var treeSitterSupport: SyntaxLanguage.TreeSitterSupport? {
        SyntaxLanguage.TreeSitterSupport(
            name: "JSON",
            bundleName: "TreeSitterJSON_TreeSitterJSON",
            queryDirectories: Self.queryDirectories,
            makeLanguage: { unsafe Language(tree_sitter_json()) }
        )
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguage.EditResult? {
        nil
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        let nsSource = source as NSString
        let clampedLocation = max(0, min(location, nsSource.length))
        let lineRange = nsSource.lineRange(for: NSRange(location: clampedLocation, length: 0))
        let linePrefixLength = max(0, clampedLocation - lineRange.location)
        let linePrefix = nsSource.substring(with: NSRange(location: lineRange.location, length: linePrefixLength))
        return SyntaxLanguageTextUtilities.hasOddUnescapedQuote(in: linePrefix, quote: "\"")
    }
}

private extension JSONLanguage {
    static var queryDirectories: [URL] {
        BundledLanguageQueryResources.directories(named: "JSONQueries")
    }
}
