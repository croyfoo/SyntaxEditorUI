import Foundation
import SwiftTreeSitter
import TreeSitterCSS

public struct CSSLanguage: SyntaxLanguage {
    public init() {}

    public var identifier: String { "css" }
    public var displayName: String { "CSS" }
    public var treeSitterSupport: SyntaxTreeSitterSupport {
        SyntaxTreeSitterSupport(
            name: "CSS",
            bundleName: "TreeSitterCSS_TreeSitterCSS",
            makeLanguage: { unsafe Language(tree_sitter_css()) }
        )
    }

    public func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        SyntaxLanguageTextUtilities.toggleWrappedComment(
            source: source,
            selection: selection,
            openMarker: "/*",
            closeMarker: "*/"
        )
    }

    public func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        let nsSource = source as NSString
        let clampedLocation = max(0, min(location, nsSource.length))
        let prefix = nsSource.substring(to: clampedLocation)
        return PrefixAnalyzer(text: prefix).analysis.isInsideLiteralOrComment
    }
}

private extension CSSLanguage {
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
            let singleQuote: unichar = 39
            let doubleQuote: unichar = 34
            let backslash: unichar = 92
            let slash: unichar = 47
            let asterisk: unichar = 42

            while cursor < nsText.length {
                let codeUnit = nsText.character(at: cursor)
                let nextCodeUnit: unichar? = cursor + 1 < nsText.length ? nsText.character(at: cursor + 1) : nil

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

            self.analysis = analysis
        }
    }
}
