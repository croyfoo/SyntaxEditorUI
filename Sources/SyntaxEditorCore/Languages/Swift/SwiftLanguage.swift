import Foundation
import SwiftTreeSitter
import TreeSitterSwift

struct SwiftLanguage: SyntaxLanguageSupport {
    init() {}

    var language: SyntaxLanguage { .swift }
    var displayName: String { "Swift" }
    var treeSitterSupport: SyntaxTreeSitterSupport? {
        SyntaxTreeSitterSupport(
            name: "Swift",
            bundleName: "TreeSitterSwift_TreeSitterSwift",
            queryDirectories: Self.queryDirectories,
            makeLanguage: { unsafe Language(tree_sitter_swift()) }
        )
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        SyntaxLanguageTextUtilities.toggleLineComment(
            source: source,
            selection: selection,
            commentPrefix: "//"
        )
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        let nsSource = source as NSString
        let clampedLocation = max(0, min(location, nsSource.length))
        let prefix = nsSource.substring(to: clampedLocation)
        return PrefixAnalyzer(text: prefix).analysis.isInsideLiteralOrComment
    }
}

private extension SwiftLanguage {
    static var queryDirectories: [URL] {
        BundledLanguageQueryResources.directories(named: "SwiftQueries")
    }
}

private extension SwiftLanguage {
    struct PrefixAnalysis {
        var inLineComment = false
        var blockCommentDepth = 0
        var inStringLiteralText = false

        var isInsideLiteralOrComment: Bool {
            inLineComment || blockCommentDepth > 0 || inStringLiteralText
        }
    }

    struct StringStart {
        let hashCount: Int
        let isMultiline: Bool
        let openerLength: Int
    }

    struct StringContext {
        let hashCount: Int
        let isMultiline: Bool
        var isEscaped = false
    }

    enum LexicalContext {
        case string(StringContext)
        case interpolation(parenDepth: Int)
    }

    struct PrefixAnalyzer {
        let analysis: PrefixAnalysis

        init(text: String) {
            let nsText = text as NSString
            var contexts: [LexicalContext] = []
            var inLineComment = false
            var blockCommentDepth = 0
            var cursor = 0

            let slash: unichar = 47
            let asterisk: unichar = 42
            let backslash: unichar = 92
            let lineFeed: unichar = 10
            let carriageReturn: unichar = 13
            let openParen: unichar = 40
            let closeParen: unichar = 41

            while cursor < nsText.length {
                let codeUnit = nsText.character(at: cursor)
                let nextCodeUnit: unichar? = cursor + 1 < nsText.length ? nsText.character(at: cursor + 1) : nil

                if inLineComment {
                    if codeUnit == lineFeed || codeUnit == carriageReturn {
                        inLineComment = false
                    }
                    cursor += 1
                    continue
                }

                if blockCommentDepth > 0 {
                    if codeUnit == slash, nextCodeUnit == asterisk {
                        blockCommentDepth += 1
                        cursor += 2
                        continue
                    }

                    if codeUnit == asterisk, nextCodeUnit == slash {
                        blockCommentDepth -= 1
                        cursor += 2
                        continue
                    }

                    cursor += 1
                    continue
                }

                if case .string(var stringContext) = contexts.last {
                    if stringContext.hashCount == 0, stringContext.isEscaped {
                        stringContext.isEscaped = false
                        contexts[contexts.count - 1] = .string(stringContext)
                        cursor += 1
                        continue
                    }

                    if let interpolationLength = Self.interpolationOpenerLength(
                        in: nsText,
                        at: cursor,
                        hashCount: stringContext.hashCount
                    ) {
                        contexts.append(.interpolation(parenDepth: 1))
                        cursor += interpolationLength
                        continue
                    }

                    if stringContext.hashCount == 0, codeUnit == backslash {
                        stringContext.isEscaped = true
                        contexts[contexts.count - 1] = .string(stringContext)
                        cursor += 1
                        continue
                    }

                    if let closeLength = Self.stringCloseLength(
                        in: nsText,
                        at: cursor,
                        context: stringContext
                    ) {
                        _ = contexts.popLast()
                        cursor += closeLength
                        continue
                    }

                    cursor += 1
                    continue
                }

                if case .interpolation(let parenDepth) = contexts.last {
                    if codeUnit == openParen {
                        contexts[contexts.count - 1] = .interpolation(parenDepth: parenDepth + 1)
                        cursor += 1
                        continue
                    }

                    if codeUnit == closeParen {
                        if parenDepth == 1 {
                            _ = contexts.popLast()
                        } else {
                            contexts[contexts.count - 1] = .interpolation(parenDepth: parenDepth - 1)
                        }
                        cursor += 1
                        continue
                    }
                }

                if codeUnit == slash, nextCodeUnit == slash {
                    inLineComment = true
                    cursor += 2
                    continue
                }

                if codeUnit == slash, nextCodeUnit == asterisk {
                    blockCommentDepth = 1
                    cursor += 2
                    continue
                }

                if let start = Self.stringStart(in: nsText, at: cursor) {
                    contexts.append(
                        .string(
                            StringContext(
                                hashCount: start.hashCount,
                                isMultiline: start.isMultiline
                            )
                        )
                    )
                    cursor += start.openerLength
                    continue
                }

                cursor += 1
            }

            var analysis = PrefixAnalysis()
            analysis.inLineComment = inLineComment
            analysis.blockCommentDepth = blockCommentDepth
            if case .string = contexts.last {
                analysis.inStringLiteralText = true
            }
            self.analysis = analysis
        }

        private static func stringStart(in source: NSString, at offset: Int) -> StringStart? {
            guard offset >= 0, offset < source.length else { return nil }

            let hash: unichar = 35
            let quote: unichar = 34

            var cursor = offset
            var hashCount = 0
            while cursor < source.length, source.character(at: cursor) == hash {
                hashCount += 1
                cursor += 1
            }

            guard cursor < source.length, source.character(at: cursor) == quote else {
                return nil
            }

            let isMultiline = cursor + 2 < source.length &&
                source.character(at: cursor + 1) == quote &&
                source.character(at: cursor + 2) == quote

            let openerLength = hashCount + (isMultiline ? 3 : 1)
            return StringStart(hashCount: hashCount, isMultiline: isMultiline, openerLength: openerLength)
        }

        private static func interpolationOpenerLength(
            in source: NSString,
            at offset: Int,
            hashCount: Int
        ) -> Int? {
            guard offset >= 0, offset < source.length else { return nil }

            let backslash: unichar = 92
            let hash: unichar = 35
            let openParen: unichar = 40

            guard source.character(at: offset) == backslash else { return nil }
            var cursor = offset + 1

            for _ in 0..<hashCount {
                guard cursor < source.length, source.character(at: cursor) == hash else {
                    return nil
                }
                cursor += 1
            }

            guard cursor < source.length, source.character(at: cursor) == openParen else {
                return nil
            }

            return cursor - offset + 1
        }

        private static func stringCloseLength(
            in source: NSString,
            at offset: Int,
            context: StringContext
        ) -> Int? {
            guard offset >= 0, offset < source.length else { return nil }

            let quote: unichar = 34
            let hash: unichar = 35

            if context.isMultiline {
                guard offset + 2 < source.length,
                      source.character(at: offset) == quote,
                      source.character(at: offset + 1) == quote,
                      source.character(at: offset + 2) == quote
                else {
                    return nil
                }

                var cursor = offset + 3
                for _ in 0..<context.hashCount {
                    guard cursor < source.length, source.character(at: cursor) == hash else {
                        return nil
                    }
                    cursor += 1
                }
                return cursor - offset
            }

            guard source.character(at: offset) == quote else {
                return nil
            }

            var cursor = offset + 1
            for _ in 0..<context.hashCount {
                guard cursor < source.length, source.character(at: cursor) == hash else {
                    return nil
                }
                cursor += 1
            }
            return cursor - offset
        }
    }
}
