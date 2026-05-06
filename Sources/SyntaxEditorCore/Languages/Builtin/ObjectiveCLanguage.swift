import Foundation
import SwiftTreeSitter
import TreeSitterObjc

public struct ObjectiveCLanguage: SyntaxLanguage {
    public init() {}

    public var identifier: String { "objective-c" }
    public var displayName: String { "Objective-C" }
    public var treeSitterSupport: SyntaxTreeSitterSupport {
        SyntaxTreeSitterSupport(
            name: "Objective-C",
            bundleName: "TreeSitterObjc_TreeSitterObjc",
            queryDirectories: Self.queryDirectories,
            makeLanguage: { unsafe Language(tree_sitter_objc()) }
        )
    }

    public func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        SyntaxLanguageTextUtilities.toggleLineComment(
            source: source,
            selection: selection,
            commentPrefix: "//"
        )
    }

    public func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        let nsSource = source as NSString
        let clampedLocation = max(0, min(location, nsSource.length))
        let prefix = nsSource.substring(to: clampedLocation)
        return PrefixAnalyzer(text: prefix).analysis.isInsideLiteralOrComment
    }
}

private extension ObjectiveCLanguage {
    static var queryDirectories: [URL] {
        guard let queriesURL = Bundle.module.resourceURL?.appendingPathComponent(
            "ObjectiveCQueries",
            isDirectory: true
        ) else {
            return []
        }

        return [queriesURL]
    }

    struct PrefixAnalysis {
        var inLineComment = false
        var inBlockComment = false
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false

        var isInsideLiteralOrComment: Bool {
            inLineComment || inBlockComment || inSingleQuote || inDoubleQuote
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
            let atSign: unichar = 64
            let backslash: unichar = 92
            let slash: unichar = 47
            let asterisk: unichar = 42
            let newline: unichar = 10
            let carriageReturn: unichar = 13

            while cursor < upperBound {
                let codeUnit = source.character(at: cursor)
                let nextCodeUnit: unichar? = cursor + 1 < source.length ? source.character(at: cursor + 1) : nil

                if analysis.inLineComment {
                    if codeUnit == newline || codeUnit == carriageReturn {
                        analysis.inLineComment = false
                    }
                    cursor += 1
                    continue
                }

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

                if codeUnit == slash, nextCodeUnit == slash {
                    analysis.inLineComment = true
                    cursor += 2
                    continue
                }

                if codeUnit == slash, nextCodeUnit == asterisk {
                    analysis.inBlockComment = true
                    cursor += 2
                    continue
                }

                if codeUnit == atSign, nextCodeUnit == doubleQuote {
                    analysis.inDoubleQuote = true
                    cursor += 2
                    continue
                }

                if codeUnit == doubleQuote {
                    analysis.inDoubleQuote = true
                    cursor += 1
                    continue
                }

                if codeUnit == singleQuote {
                    analysis.inSingleQuote = true
                    cursor += 1
                    continue
                }

                cursor += 1
            }
        }
    }
}
