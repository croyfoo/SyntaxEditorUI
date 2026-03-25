import Foundation
import SwiftTreeSitter
import TreeSitterJSON

public struct JSONLanguage: SyntaxLanguage {
    public init() {}

    public var identifier: String { "json" }
    public var displayName: String { "JSON" }
    public var treeSitterSupport: SyntaxTreeSitterSupport {
        SyntaxTreeSitterSupport(
            name: "JSON",
            bundleName: "TreeSitterJSON_TreeSitterJSON",
            makeLanguage: { unsafe Language(tree_sitter_json()) }
        )
    }

    public func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        nil
    }

    public func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        let nsSource = source as NSString
        let clampedLocation = max(0, min(location, nsSource.length))
        let lineRange = nsSource.lineRange(for: NSRange(location: clampedLocation, length: 0))
        let linePrefixLength = max(0, clampedLocation - lineRange.location)
        let linePrefix = nsSource.substring(with: NSRange(location: lineRange.location, length: linePrefixLength))
        return SyntaxLanguageTextUtilities.hasOddUnescapedQuote(in: linePrefix, quote: "\"")
    }
}
