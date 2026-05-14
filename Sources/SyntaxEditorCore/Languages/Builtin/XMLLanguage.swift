import Foundation
import SwiftTreeSitter
import TreeSitterXML

struct XMLLanguage {
    init() {}

    var identifier: String { "xml" }
    var displayName: String { "XML" }
    var treeSitterSupport: SyntaxTreeSitterSupport {
        SyntaxTreeSitterSupport(
            name: "XML",
            bundleName: "TreeSitterXML_TreeSitterXML",
            queryDirectories: Self.queryDirectories,
            makeLanguage: { unsafe Language(tree_sitter_xml()) }
        )
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        let nsSource = source as NSString
        let safeSelection = SyntaxEditorRangeUtilities.clampedRange(selection, utf16Length: nsSource.length)
        let targetLinesRange = SyntaxLanguageTextUtilities.selectedLineEnvelope(
            in: nsSource,
            selection: safeSelection
        )
        let targetStart = targetLinesRange.location
        let targetEnd = targetLinesRange.location + targetLinesRange.length
        guard Self.commentContextState(in: nsSource, location: targetStart) == .outside,
              Self.commentContextState(in: nsSource, location: targetEnd) == .outside
        else {
            return nil
        }
        let segment = nsSource.substring(with: targetLinesRange)
        let isWrappedComment = SyntaxLanguageTextUtilities.wrappedCommentBounds(
            in: segment,
            openMarker: "<!--",
            closeMarker: "-->"
        ) != nil
        if isWrappedComment == false, Self.shouldRejectDTDDelimiterComment(in: nsSource, range: targetLinesRange) {
            return nil
        }
        if SyntaxLanguageTextUtilities.shouldRejectMarkupCommentWrapping(segment) {
            return nil
        }

        return SyntaxLanguageTextUtilities.toggleWrappedComment(
            source: source,
            selection: safeSelection,
            openMarker: "<!--",
            closeMarker: "-->"
        )
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        let nsSource = source as NSString
        let clampedLocation = max(0, min(location, nsSource.length))
        let prefix = nsSource.substring(to: clampedLocation)
        return PrefixAnalyzer(text: prefix).analysis.shouldSuppressQuoteAutoPair
    }
}

private extension XMLLanguage {
    static var queryDirectories: [URL] {
        guard let resourceURL = Bundle.module.resourceURL else { return [] }
        return [resourceURL.appendingPathComponent("XMLQueries", isDirectory: true)]
    }
}

extension XMLLanguage {
    enum DTDDelimiter {
        case internalSubsetOpen
        case internalSubsetClose
    }

    enum CommentContextState {
        case outside
        case insideComment
        case insideTag
        case insideDeclaration
        case insideCDATA
    }

    struct PrefixAnalysis {
        var inTag = false
        var inComment = false
        var inCDATA = false
        var inDeclaration = false
        var inDeclarationSingleQuote = false
        var inDeclarationDoubleQuote = false
        var declarationBracketDepth = 0
        var inDTDMarkupDeclaration = false
        var pendingDeclarationLiterals = 0
        var previousDeclarationToken: String?
        var prePreviousDeclarationToken: String?
        var inSingleQuotedAttributeValue = false
        var inDoubleQuotedAttributeValue = false
        var inUnquotedAttributeValue = false
        var canStartAttributeValue = false
        var currentTagIsClosing = false

        var shouldSuppressQuoteAutoPair: Bool {
            if inComment ||
                inCDATA ||
                inSingleQuotedAttributeValue ||
                inDoubleQuotedAttributeValue ||
                inDeclarationSingleQuote ||
                inDeclarationDoubleQuote
            {
                return true
            }

            if inTag || inDeclaration {
                return !canStartAttributeValue
            }

            return true
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

        @discardableResult
        static func advance(
            _ analysis: inout PrefixAnalysis,
            in source: NSString,
            cursor: inout Int,
            limit: Int,
            onDTDDelimiter: ((DTDDelimiter) -> Bool)? = nil
        ) -> Bool {
            let upperBound = max(0, min(limit, source.length))

            while cursor < upperBound {
                if analysis.inComment {
                    if hasPrefix("-->", in: source, at: cursor) {
                        analysis.inComment = false
                        cursor = min(cursor + 3, upperBound)
                    } else {
                        cursor += 1
                    }
                    continue
                }

                if analysis.inCDATA {
                    if hasPrefix("]]>", in: source, at: cursor) {
                        analysis.inCDATA = false
                        cursor = min(cursor + 3, upperBound)
                    } else {
                        cursor += 1
                    }
                    continue
                }

                if analysis.inDeclaration {
                    let codeUnit = source.character(at: cursor)

                    if analysis.inDeclarationSingleQuote {
                        if codeUnit == 39 {
                            analysis.inDeclarationSingleQuote = false
                            analysis.canStartAttributeValue = analysis.pendingDeclarationLiterals > 0
                        }
                        cursor += 1
                        continue
                    }

                    if analysis.inDeclarationDoubleQuote {
                        if codeUnit == 34 {
                            analysis.inDeclarationDoubleQuote = false
                            analysis.canStartAttributeValue = analysis.pendingDeclarationLiterals > 0
                        }
                        cursor += 1
                        continue
                    }

                    if hasPrefix("<!--", in: source, at: cursor) {
                        analysis.canStartAttributeValue = false
                        analysis.inComment = true
                        cursor += 4
                        continue
                    }

                    if analysis.declarationBracketDepth > 0 {
                        if hasPrefix("<!", in: source, at: cursor) || hasPrefix("<?", in: source, at: cursor) {
                            analysis.canStartAttributeValue = false
                            analysis.inDTDMarkupDeclaration = true
                            analysis.previousDeclarationToken = nil
                            analysis.prePreviousDeclarationToken = nil
                            cursor += 2
                            continue
                        }
                    }

                    if isWhitespace(codeUnit) {
                        cursor += 1
                        continue
                    }

                    if codeUnit == 61 {
                        analysis.canStartAttributeValue = true
                        cursor += 1
                        continue
                    }

                    if codeUnit == 39 {
                        if analysis.canStartAttributeValue {
                            if analysis.pendingDeclarationLiterals > 0 {
                                analysis.pendingDeclarationLiterals -= 1
                            }
                            analysis.inDeclarationSingleQuote = true
                            analysis.canStartAttributeValue = false
                        }
                        cursor += 1
                        continue
                    }

                    if codeUnit == 34 {
                        if analysis.canStartAttributeValue {
                            if analysis.pendingDeclarationLiterals > 0 {
                                analysis.pendingDeclarationLiterals -= 1
                            }
                            analysis.inDeclarationDoubleQuote = true
                            analysis.canStartAttributeValue = false
                        }
                        cursor += 1
                        continue
                    }

                    if codeUnit == 91 {
                        let opensInternalSubset =
                            analysis.declarationBracketDepth == 0 &&
                            analysis.inDTDMarkupDeclaration == false
                        let opensConditionalSection =
                            analysis.inDTDMarkupDeclaration &&
                            conditionalSectionKeywords.contains(analysis.previousDeclarationToken ?? "")
                        if (opensInternalSubset || opensConditionalSection),
                           onDTDDelimiter?(.internalSubsetOpen) == true
                        {
                            return true
                        }
                        analysis.canStartAttributeValue = false
                        if opensConditionalSection {
                            analysis.inDTDMarkupDeclaration = false
                            analysis.previousDeclarationToken = nil
                            analysis.prePreviousDeclarationToken = nil
                        }
                        analysis.declarationBracketDepth += 1
                        cursor += 1
                        continue
                    }

                    if codeUnit == 93, analysis.declarationBracketDepth > 0 {
                        let closesInternalSubset =
                            analysis.declarationBracketDepth == 1 &&
                            analysis.inDTDMarkupDeclaration == false &&
                            cursor + 1 < upperBound &&
                            source.character(at: cursor + 1) == 62
                        if closesInternalSubset, onDTDDelimiter?(.internalSubsetClose) == true {
                            return true
                        }
                        analysis.canStartAttributeValue = false
                        analysis.declarationBracketDepth -= 1
                        cursor += 1
                        continue
                    }

                    if codeUnit == 62, analysis.declarationBracketDepth == 0 {
                        analysis.inDeclaration = false
                        analysis.canStartAttributeValue = false
                        analysis.inDTDMarkupDeclaration = false
                        analysis.pendingDeclarationLiterals = 0
                        analysis.previousDeclarationToken = nil
                        analysis.prePreviousDeclarationToken = nil
                        cursor += 1
                        continue
                    }

                    if codeUnit == 62, analysis.inDTDMarkupDeclaration {
                        analysis.canStartAttributeValue = false
                        analysis.inDTDMarkupDeclaration = false
                        analysis.previousDeclarationToken = nil
                        analysis.prePreviousDeclarationToken = nil
                        cursor += 1
                        continue
                    }

                    if let token = declarationToken(in: source, cursor: &cursor) {
                        let uppercased = token.uppercased()
                        let followsEntityKeyword =
                            analysis.previousDeclarationToken == "ENTITY" ||
                            (analysis.previousDeclarationToken == "%" && analysis.prePreviousDeclarationToken == "ENTITY")

                        if followsEntityKeyword &&
                            uppercased != "%" &&
                            uppercased != "SYSTEM" &&
                            uppercased != "PUBLIC"
                        {
                            analysis.pendingDeclarationLiterals = 1
                            analysis.canStartAttributeValue = true
                        } else if declarationLiteralIntroducers.contains(uppercased) {
                            analysis.pendingDeclarationLiterals = uppercased == "PUBLIC" ? 2 : 1
                            analysis.canStartAttributeValue = true
                        } else if analysis.canStartAttributeValue {
                            analysis.canStartAttributeValue = false
                        }
                        analysis.prePreviousDeclarationToken = analysis.previousDeclarationToken
                        analysis.previousDeclarationToken = uppercased
                        continue
                    }

                    if analysis.canStartAttributeValue {
                        analysis.canStartAttributeValue = false
                    }
                    cursor += 1
                    continue
                }

                if analysis.inSingleQuotedAttributeValue {
                    if source.character(at: cursor) == 39 {
                        analysis.inSingleQuotedAttributeValue = false
                        analysis.inTag = true
                    }
                    cursor += 1
                    continue
                }

                if analysis.inDoubleQuotedAttributeValue {
                    if source.character(at: cursor) == 34 {
                        analysis.inDoubleQuotedAttributeValue = false
                        analysis.inTag = true
                    }
                    cursor += 1
                    continue
                }

                if analysis.inTag {
                    let codeUnit = source.character(at: cursor)

                    if codeUnit == 62 {
                        analysis.inTag = false
                        analysis.canStartAttributeValue = false
                        analysis.inUnquotedAttributeValue = false
                        analysis.currentTagIsClosing = false
                        cursor += 1
                        continue
                    }

                    if analysis.currentTagIsClosing {
                        cursor += 1
                        continue
                    }

                    if analysis.inUnquotedAttributeValue {
                        if isWhitespace(codeUnit) {
                            analysis.inUnquotedAttributeValue = false
                        }
                        cursor += 1
                        continue
                    }

                    if isWhitespace(codeUnit) {
                        cursor += 1
                        continue
                    }

                    if codeUnit == 61 {
                        analysis.canStartAttributeValue = true
                        cursor += 1
                        continue
                    }

                    if codeUnit == 39 {
                        if analysis.canStartAttributeValue {
                            analysis.inSingleQuotedAttributeValue = true
                            analysis.canStartAttributeValue = false
                        }
                        cursor += 1
                        continue
                    }

                    if codeUnit == 34 {
                        if analysis.canStartAttributeValue {
                            analysis.inDoubleQuotedAttributeValue = true
                            analysis.canStartAttributeValue = false
                        }
                        cursor += 1
                        continue
                    }

                    if analysis.canStartAttributeValue {
                        analysis.inUnquotedAttributeValue = true
                        analysis.canStartAttributeValue = false
                        cursor += 1
                        continue
                    }

                    analysis.canStartAttributeValue = false
                    cursor += 1
                    continue
                }

                if hasPrefix("<!--", in: source, at: cursor) {
                    analysis.inComment = true
                    cursor += 4
                    continue
                }

                if hasPrefix("<![CDATA[", in: source, at: cursor) {
                    analysis.inCDATA = true
                    cursor += 9
                    continue
                }

                if hasPrefix("<!", in: source, at: cursor) {
                    analysis.inDeclaration = true
                    analysis.inDeclarationSingleQuote = false
                    analysis.inDeclarationDoubleQuote = false
                    analysis.declarationBracketDepth = 0
                    analysis.inDTDMarkupDeclaration = false
                    analysis.pendingDeclarationLiterals = 0
                    analysis.previousDeclarationToken = nil
                    analysis.prePreviousDeclarationToken = nil
                    cursor += 2
                    continue
                }

                if startsTag(in: source, at: cursor) {
                    let tag = tagDescriptor(in: source, at: cursor)
                    analysis.inTag = true
                    analysis.canStartAttributeValue = false
                    analysis.inUnquotedAttributeValue = false
                    analysis.currentTagIsClosing = tag.isClosing
                    cursor = tag.nextCursor
                    continue
                }

                cursor += 1
            }

            return false
        }

        private static func startsTag(in source: NSString, at offset: Int) -> Bool {
            guard offset >= 0, offset < source.length, source.character(at: offset) == 60 else {
                return false
            }

            let nextOffset = offset + 1
            guard nextOffset < source.length,
                  let next = composedCharacter(in: source, at: nextOffset)
            else {
                return false
            }

            return next.value == "/" || next.value == "?" || isNameStartCharacter(next.value)
        }

        private static func tagDescriptor(
            in source: NSString,
            at offset: Int
        ) -> (isClosing: Bool, nextCursor: Int) {
            var cursor = offset + 1
            var isClosing = false

            if cursor < source.length, source.character(at: cursor) == 47 {
                isClosing = true
                cursor += 1
            } else if cursor < source.length, source.character(at: cursor) == 63 {
                cursor += 1
            }

            while cursor < source.length, isWhitespace(source.character(at: cursor)) {
                cursor += 1
            }

            while cursor < source.length,
                  let next = composedCharacter(in: source, at: cursor),
                  isTagNameCharacter(next.value)
            {
                cursor += next.length
            }

            return (isClosing: isClosing, nextCursor: cursor)
        }

        private static func hasPrefix(_ literal: String, in source: NSString, at offset: Int) -> Bool {
            let length = literal.utf16.count
            guard offset >= 0, offset + length <= source.length else {
                return false
            }

            return source.substring(with: NSRange(location: offset, length: length)) == literal
        }

        private static let declarationLiteralIntroducers: Set<String> = [
            "#FIXED",
            "PUBLIC",
            "SYSTEM",
        ]

        private static let conditionalSectionKeywords: Set<String> = [
            "IGNORE",
            "INCLUDE",
        ]

        private static func declarationToken(in source: NSString, cursor: inout Int) -> String? {
            guard cursor < source.length,
                  let first = composedCharacter(in: source, at: cursor),
                  isDeclarationTokenStart(first.value)
            else {
                return nil
            }

            let start = cursor
            cursor += first.length
            while cursor < source.length,
                  let next = composedCharacter(in: source, at: cursor),
                  isDeclarationTokenCharacter(next.value)
            {
                cursor += next.length
            }

            return source.substring(with: NSRange(location: start, length: cursor - start))
        }

        private static func composedCharacter(
            in source: NSString,
            at offset: Int
        ) -> (value: String, length: Int)? {
            guard offset >= 0, offset < source.length else {
                return nil
            }

            let range = source.rangeOfComposedCharacterSequence(at: offset)
            guard range.location != NSNotFound, range.length > 0 else {
                return nil
            }

            return (value: source.substring(with: range), length: range.length)
        }

        private static func isASCIIAlpha(_ codeUnit: unichar) -> Bool {
            (65...90).contains(Int(codeUnit)) || (97...122).contains(Int(codeUnit))
        }

        private static func isNameStartCharacter(_ codeUnit: unichar) -> Bool {
            isASCIIAlpha(codeUnit) ||
                codeUnit == 58 ||
                codeUnit == 95 ||
                {
                    guard let scalar = UnicodeScalar(Int(codeUnit)) else {
                        return false
                    }
                    return CharacterSet.letters.contains(scalar)
                }()
        }

        private static func isNameStartCharacter(_ value: String) -> Bool {
            if value == ":" || value == "_" {
                return true
            }

            return value.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }

        private static func isTagNameCharacter(_ codeUnit: unichar) -> Bool {
            isNameStartCharacter(codeUnit) ||
                (48...57).contains(Int(codeUnit)) ||
                codeUnit == 45 ||
                codeUnit == 46 ||
                isNameExtenderCharacter(codeUnit)
        }

        private static func isTagNameCharacter(_ value: String) -> Bool {
            if value == ":" || value == "_" || value == "-" || value == "." || isNameExtenderCharacter(value) {
                return true
            }

            return value.unicodeScalars.allSatisfy {
                CharacterSet.letters.contains($0) ||
                    CharacterSet.decimalDigits.contains($0) ||
                    CharacterSet.nonBaseCharacters.contains($0)
            }
        }

        private static func isNameExtenderCharacter(_ codeUnit: unichar) -> Bool {
            codeUnit == 0x00B7 || codeUnit == 0x203F || codeUnit == 0x2040
        }

        private static func isNameExtenderCharacter(_ value: String) -> Bool {
            value == "\u{00B7}" || value == "\u{203F}" || value == "\u{2040}"
        }

        private static func isDeclarationTokenStart(_ codeUnit: unichar) -> Bool {
            isNameStartCharacter(codeUnit) || codeUnit == 35 || codeUnit == 37
        }

        private static func isDeclarationTokenCharacter(_ codeUnit: unichar) -> Bool {
            isTagNameCharacter(codeUnit) || codeUnit == 35 || codeUnit == 37
        }

        private static func isDeclarationTokenStart(_ value: String) -> Bool {
            isNameStartCharacter(value) || value == "#" || value == "%"
        }

        private static func isDeclarationTokenCharacter(_ value: String) -> Bool {
            isTagNameCharacter(value) || value == "#" || value == "%"
        }

        private static func isWhitespace(_ codeUnit: unichar) -> Bool {
            codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13
        }
    }

    static func commentContextState(in source: NSString, location: Int) -> CommentContextState {
        let clampedLocation = max(0, min(location, source.length))
        let prefix = source.substring(to: clampedLocation)
        let analysis = PrefixAnalyzer(text: prefix).analysis

        if analysis.inComment {
            return .insideComment
        }
        if analysis.inCDATA {
            return .insideCDATA
        }
        if analysis.inDeclaration {
            if analysis.declarationBracketDepth > 0 && analysis.inDTDMarkupDeclaration == false {
                return .outside
            }
            return .insideDeclaration
        }
        if analysis.inTag {
            return .insideTag
        }
        return .outside
    }

    static func shouldRejectDTDDelimiterComment(in source: NSString, range: NSRange) -> Bool {
        let safeRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: source.length)
        guard safeRange.length > 0 else {
            return false
        }

        var analysis = PrefixAnalyzer(text: source.substring(to: safeRange.location)).analysis
        var cursor = safeRange.location
        return PrefixAnalyzer.advance(
            &analysis,
            in: source,
            cursor: &cursor,
            limit: NSMaxRange(safeRange),
            onDTDDelimiter: { _ in true }
        )
    }
}
