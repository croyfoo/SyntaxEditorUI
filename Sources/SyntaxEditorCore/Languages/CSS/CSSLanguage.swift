import Foundation
import SwiftTreeSitter
import TreeSitterCSS

struct CSSLanguage: SyntaxLanguageSupport {
    init() {}

    var language: SyntaxLanguage { .css }
    var displayName: String { "CSS" }
    var treeSitterSupport: SyntaxTreeSitterSupport? {
        SyntaxTreeSitterSupport(
            name: "CSS",
            bundleName: "TreeSitterCSS_TreeSitterCSS",
            queryDirectories: Self.queryDirectories,
            makeLanguage: { unsafe Language(tree_sitter_css()) }
        )
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        SyntaxLanguageTextUtilities.toggleWrappedComment(
            source: source,
            selection: selection,
            openMarker: "/*",
            closeMarker: "*/"
        )
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        let nsSource = source as NSString
        let clampedLocation = max(0, min(location, nsSource.length))
        let prefix = nsSource.substring(to: clampedLocation)
        return PrefixAnalyzer(text: prefix).analysis.isInsideLiteralOrComment
    }
}

private extension CSSLanguage {
    static var queryDirectories: [URL] {
        BundledLanguageQueryResources.directories(named: "CSSQueries")
    }
}

extension CSSLanguage {
    struct PrefixAnalysis {
        var inSingleQuote = false
        var inDoubleQuote = false
        var inBlockComment = false
        var isEscaped = false

        var isInsideLiteralOrComment: Bool {
            inSingleQuote || inDoubleQuote || inBlockComment
        }
    }

    struct PrefixAnalyzer {
        let analysis: PrefixAnalysis

        init(text: String) {
            let nsText = text as NSString
            var analysis = PrefixAnalysis()
            var cursor = 0
            Self.advance(&analysis, in: nsText, cursor: &cursor, limit: nsText.length)
            self.analysis = analysis
        }

        static func advance(
            _ analysis: inout PrefixAnalysis,
            in source: NSString,
            cursor: inout Int,
            limit: Int
        ) {
            let upperBound = max(0, min(limit, source.length))
            let singleQuote: unichar = 39
            let doubleQuote: unichar = 34
            let backslash: unichar = 92
            let slash: unichar = 47
            let asterisk: unichar = 42

            while cursor < upperBound {
                let codeUnit = source.character(at: cursor)
                let nextCodeUnit: unichar? = cursor + 1 < source.length ? source.character(at: cursor + 1) : nil

                if analysis.inBlockComment {
                    if codeUnit == asterisk, nextCodeUnit == slash {
                        analysis.inBlockComment = false
                        cursor += 2
                    } else {
                        cursor += 1
                    }
                    continue
                }

                if analysis.isEscaped {
                    analysis.isEscaped = false
                    cursor += 1
                    continue
                }

                if analysis.inSingleQuote {
                    if codeUnit == backslash {
                        analysis.isEscaped = true
                    } else if codeUnit == singleQuote {
                        analysis.inSingleQuote = false
                    }
                    cursor += 1
                    continue
                }

                if analysis.inDoubleQuote {
                    if codeUnit == backslash {
                        analysis.isEscaped = true
                    } else if codeUnit == doubleQuote {
                        analysis.inDoubleQuote = false
                    }
                    cursor += 1
                    continue
                }

                if codeUnit == slash, nextCodeUnit == asterisk {
                    analysis.inBlockComment = true
                    cursor += 2
                    continue
                }

                if codeUnit == singleQuote {
                    analysis.inSingleQuote = true
                    cursor += 1
                    continue
                }

                if codeUnit == doubleQuote {
                    analysis.inDoubleQuote = true
                    cursor += 1
                    continue
                }

                cursor += 1
            }
        }
    }
}
