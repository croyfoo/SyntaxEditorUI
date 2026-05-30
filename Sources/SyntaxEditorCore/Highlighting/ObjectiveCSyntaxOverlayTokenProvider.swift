import Foundation
import SwiftTreeSitter

private struct ObjectiveCRangeKey: Hashable {
    let location: Int
    let length: Int

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }
}

private struct ObjectiveCTokenKey: Hashable {
    let range: ObjectiveCRangeKey
    let rawCaptureName: String

    init(_ token: SyntaxHighlightToken) {
        range = ObjectiveCRangeKey(token.range)
        rawCaptureName = token.rawCaptureName
    }
}

private struct ObjectiveCSyntaxIDMask: OptionSet {
    let rawValue: UInt16

    static let identifier = Self(rawValue: 1 << 0)
    static let identifierType = Self(rawValue: 1 << 1)
    static let identifierTypeSystem = Self(rawValue: 1 << 2)
    static let identifierFunction = Self(rawValue: 1 << 3)
    static let identifierFunctionSystem = Self(rawValue: 1 << 4)

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    init(syntaxID: EditorSourceSyntaxID) {
        switch syntaxID {
        case .identifier:
            self = .identifier
        case .identifierType:
            self = .identifierType
        case .identifierTypeSystem:
            self = .identifierTypeSystem
        case .identifierFunction:
            self = .identifierFunction
        case .identifierFunctionSystem:
            self = .identifierFunctionSystem
        default:
            self = []
        }
    }
}

enum ObjectiveCSyntaxOverlayTokenProvider {
    static func mergingOverlayTokens(
        tokens: [SyntaxHighlightToken],
        source: String,
        rootNode: Node? = nil,
        refreshRange: NSRange? = nil
    ) -> [SyntaxHighlightToken] {
        let nsSource = source as NSString
        guard nsSource.length > 0 else {
            return objectiveCBaseTokens(from: tokens, source: nsSource)
        }

        let targetRange = objectiveCSemanticTargetRange(refreshRange, in: nsSource)
        let baseTokensForIndex = objectiveCBaseTokens(from: tokens, source: nsSource)
        let outputBaseTokens = targetRange.map {
            objectiveCBaseTokens(from: tokens, source: nsSource, strippingSemanticOverlaysIn: $0)
        } ?? baseTokensForIndex
        let nonCodeRanges = nonCodeRanges(from: baseTokensForIndex, sourceLength: nsSource.length)
        let index = ObjectiveCFileSymbolIndex(source: nsSource, tokens: baseTokensForIndex, rootNode: rootNode)
        let overlayTokens = semanticTokens(
            from: baseTokensForIndex,
            source: nsSource,
            index: index,
            targetRange: targetRange
        )
            + appleMacroTokens(in: nsSource, nonCodeRanges: nonCodeRanges, targetRange: targetRange)
            + appleEnumTypedefTokens(in: nsSource, nonCodeRanges: nonCodeRanges, targetRange: targetRange)
        guard overlayTokens.isEmpty == false else {
            return outputBaseTokens
        }

        return deduplicated(mergedTokens(baseTokens: outputBaseTokens, overlayTokens: overlayTokens))
    }

    private static func semanticTokens(
        from tokens: [SyntaxHighlightToken],
        source: NSString,
        index: ObjectiveCFileSymbolIndex,
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        var overlayTokens: [SyntaxHighlightToken] = []
        overlayTokens.reserveCapacity(tokens.count / 4)

        for token in tokens {
            guard token.language == .objectiveC || token.language == nil,
                  token.range.location >= 0,
                  token.range.length > 0,
                  token.range.upperBound <= source.length,
                  targetRange.map({ rangesIntersect(token.range, $0) }) ?? true,
                  isObjectiveCIdentifierRange(token.range, in: source)
            else {
                continue
            }

            let text = source.substring(with: token.range)

            if appleMacroNames.contains(text) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .preprocessor))
                continue
            }

            if index.containsPropertyDeclarationNameRange(token.range) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .declarationOther))
                continue
            }

            switch token.syntaxID {
            case .identifier:
                if (index.containsSelfMemberNameRange(token.range) && index.localProperties.contains(text)) ||
                    (isSelfMemberName(token.range, in: source) && index.localProperties.contains(text)) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariable))
                } else if index.containsSelfChainMemberNameRange(token.range) ||
                    isMemberNameInKnownSelfChain(token.range, in: source, localProperties: index.localProperties) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariableSystem))
                }

            case .identifierType, .identifierTypeSystem:
                guard !keywordLikeTypeNames.contains(text) else {
                    continue
                }
                if isTypeDeclarationName(token.range, text: text, in: source) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .declarationType))
                } else if index.localTypes.contains(text) || shouldTreatUnknownTypeAsProject(text) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierType))
                }

            case .identifierFunction:
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .declarationOther))

            case .identifierFunctionSystem:
                if index.localFunctions.contains(text),
                   isCFunctionCallName(token.range, in: source) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierFunction))
                }

            default:
                continue
            }
        }

        return overlayTokens
    }

    private static func appleMacroTokens(
        in source: NSString,
        nonCodeRanges: [NSRange],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        let string = source as String
        let searchRange = targetRange ?? NSRange(location: 0, length: source.length)
        return appleMacroRegex.matches(in: string, range: searchRange).compactMap { match in
            let range = match.range
            guard range.location != NSNotFound,
                  range.length > 0,
                  !rangeIntersectsSortedRanges(range, nonCodeRanges)
            else {
                return nil
            }
            return canonicalToken(range: range, syntaxID: .preprocessor)
        }
    }

    private static func appleEnumTypedefTokens(
        in source: NSString,
        nonCodeRanges: [NSRange],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        let string = source as String
        let searchRange = targetRange ?? NSRange(location: 0, length: source.length)
        var tokens: [SyntaxHighlightToken] = []
        for match in appleEnumTypedefRegex.matches(in: string, range: searchRange) {
            guard match.numberOfRanges == 5,
                  !rangeIntersectsSortedRanges(match.range, nonCodeRanges)
            else { continue }

            let typedefRange = match.range(at: 1)
            let macroRange = match.range(at: 2)
            let declaredNameRange = match.range(at: 4)
            guard typedefRange.location != NSNotFound,
                  macroRange.location != NSNotFound,
                  declaredNameRange.location != NSNotFound
            else {
                continue
            }

            tokens.append(canonicalToken(range: typedefRange, syntaxID: .keyword))
            tokens.append(canonicalToken(range: macroRange, syntaxID: .preprocessor))
            tokens.append(canonicalToken(range: declaredNameRange, syntaxID: .declarationType))
        }
        return tokens
    }

    private static func nonCodeRanges(
        from tokens: [SyntaxHighlightToken],
        sourceLength: Int
    ) -> [NSRange] {
        tokens.compactMap { token -> NSRange? in
            guard token.language == .objectiveC || token.language == nil else {
                return nil
            }
            switch token.syntaxID {
            case .comment, .string, .character:
                return SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: sourceLength)
            default:
                return nil
            }
        }.sorted { lhs, rhs in
            if lhs.location != rhs.location {
                return lhs.location < rhs.location
            }
            return lhs.length < rhs.length
        }
    }

    private static func rangeIntersectsSortedRanges(_ range: NSRange, _ sortedRanges: [NSRange]) -> Bool {
        var lower = 0
        var upper = sortedRanges.count
        while lower < upper {
            let midpoint = (lower + upper) / 2
            if sortedRanges[midpoint].upperBound <= range.location {
                lower = midpoint + 1
            } else {
                upper = midpoint
            }
        }
        guard lower < sortedRanges.count else {
            return false
        }
        return SyntaxEditorRangeUtilities.intersection(of: range, and: sortedRanges[lower]).length > 0
    }

    private static func rangesIntersect(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        SyntaxEditorRangeUtilities.intersection(of: lhs, and: rhs).length > 0
    }

    private static func objectiveCSemanticTargetRange(_ refreshRange: NSRange?, in source: NSString) -> NSRange? {
        guard let refreshRange else {
            return nil
        }
        let clamped = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: source.length)
        guard clamped.length > 0 else {
            return nil
        }

        let targetRange = source.lineRange(for: clamped)
        let contextRange = objectiveCUnsafeEditContextRange(around: targetRange, in: source)
        let context = source.substring(with: contextRange)
        return objectiveCRefreshLooksStructural(context) ? nil : targetRange
    }

    private static func objectiveCUnsafeEditContextRange(around range: NSRange, in source: NSString) -> NSRange {
        var lower = range.location
        var upper = range.upperBound

        if lower > 0 {
            let previousLocation = max(0, lower - 1)
            let previousLine = source.lineRange(for: NSRange(location: previousLocation, length: 0))
            lower = previousLine.location
        }
        if upper < source.length {
            let nextLine = source.lineRange(for: NSRange(location: upper, length: 0))
            upper = nextLine.upperBound
        }

        return NSRange(location: lower, length: max(0, min(upper, source.length) - lower))
    }

    private static func objectiveCRefreshLooksStructural(_ text: String) -> Bool {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return structuralObjectiveCEditRegex.firstMatch(in: text, range: fullRange) != nil
    }

    private static func shouldTreatUnknownTypeAsProject(_ name: String) -> Bool {
        guard name.first?.isUppercase == true else {
            return false
        }
        return !ObjectiveCSystemSymbols.isSystemType(name)
    }

    private static func isTypeDeclarationName(_ range: NSRange, text: String, in source: NSString) -> Bool {
        let prefix = linePrefix(before: range, in: source)
            .trimmingCharacters(in: .whitespaces)
        if prefix.range(
            of: #"@(?:interface|implementation|protocol)\s*$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if prefix.range(
            of: #"@class(?:\s+[A-Za-z_][A-Za-z0-9_]*\s*,\s*)*$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if prefix.contains("typedef") {
            return typedefDeclarationName(around: range, in: source) == text
        }
        return false
    }

    private static func isCFunctionCallName(_ range: NSRange, in source: NSString) -> Bool {
        let after = source.substring(from: min(range.upperBound, source.length))
        guard let character = after.first(where: { !$0.isWhitespace }) else {
            return false
        }
        return character == "("
    }

    private static func looksLikeCFunctionDeclarationPrefix(before range: NSRange, in source: NSString) -> Bool {
        let prefix = linePrefix(before: range, in: source)
            .trimmingCharacters(in: .whitespaces)
        guard prefix.isEmpty == false else {
            return false
        }
        if prefix == "return" || prefix.hasSuffix("=") || prefix.hasSuffix("(") || prefix.hasSuffix(",") {
            return false
        }
        if prefix.hasSuffix(".") || prefix.hasSuffix("->") || prefix.hasSuffix("[") {
            return false
        }
        return true
    }

    private static func isMessageReceiverName(_ range: NSRange, in source: NSString) -> Bool {
        previousNonWhitespaceCharacter(before: range, in: source) == "["
    }

    private static func isSelfMemberName(_ range: NSRange, in source: NSString) -> Bool {
        guard let expressionPrefix = memberAccessExpressionPrefix(before: range, in: source) else {
            return false
        }
        return expressionPrefixEndsWithSelf(expressionPrefix)
    }

    private static func isMemberNameInKnownSelfChain(
        _ range: NSRange,
        in source: NSString,
        localProperties: Set<String>
    ) -> Bool {
        guard let expressionPrefix = memberAccessExpressionPrefix(before: range, in: source) else {
            return false
        }

        let expression = expressionPrefix as NSString
        let matches = selfRootMemberRegex.matches(
            in: expressionPrefix,
            range: NSRange(location: 0, length: expression.length)
        )
        for match in matches.reversed() {
            let selfRange = match.range(at: 2)
            let wrappedSelfClosingRange = match.range(at: 3)
            let firstMemberRange = match.range(at: 4)
            guard selfRange.location != NSNotFound,
                  firstMemberRange.location != NSNotFound else {
                continue
            }
            if isInsideCommentOrLiteral(selfRange, in: expression) {
                continue
            }
            let firstMember = expression.substring(with: firstMemberRange)
            guard localProperties.contains(firstMember) else {
                continue
            }
            let beforeSelf = expression.substring(to: selfRange.location)
            if wrappedSelfClosingRange.location != NSNotFound,
               wrappedSelfClosingRange.length > 0,
               !allowsWrappedSelfChainStart(beforeSelf) {
                continue
            }
            let suffix = expression.substring(from: match.range.upperBound)
            let hasUnmatchedClosing = hasUnmatchedClosingDelimiter(suffix)
            let allowsWrappedSelfChainClose = hasUnmatchedClosing
                && !hasUnmatchedClosingSquareBracket(suffix)
                && containsOnlyClosingParenthesesAndWhitespace(suffix)
                && allowsWrappedSelfChainStart(beforeSelf)
            if keepsSelfChainConnected(suffix)
                && !hasUnmatchedOpeningDelimiter(suffix)
                && (!hasUnmatchedClosing || allowsWrappedSelfChainClose) {
                return true
            }
        }
        return false
    }

    private static func memberAccessExpressionPrefix(before range: NSRange, in source: NSString) -> String? {
        guard range.location > 0 else {
            return nil
        }

        var cursor = range.location - 1
        while cursor >= 0 {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                break
            }
            if cursor == 0 {
                return nil
            }
            cursor -= 1
        }

        let operatorStart: Int
        let character = source.substring(with: NSRange(location: cursor, length: 1))
        if character == "." {
            operatorStart = cursor
        } else if character == ">", cursor > 0,
                  source.substring(with: NSRange(location: cursor - 1, length: 1)) == "-" {
            operatorStart = cursor - 1
        } else {
            return nil
        }

        let start = expressionBoundaryBefore(location: operatorStart, in: source)
        guard start < operatorStart else {
            return nil
        }
        return source.substring(with: NSRange(location: start, length: operatorStart - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func expressionBoundaryBefore(location: Int, in source: NSString) -> Int {
        guard location > 0 else {
            return 0
        }

        var cursor = location - 1
        while cursor >= 0 {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if let nextCursor = indexBeforeQuotedLiteralEnding(at: cursor, in: source) {
                cursor = nextCursor
                continue
            }
            if character == ";" || character == "{" || character == "}" {
                return cursor + 1
            }
            if cursor == 0 {
                break
            }
            cursor -= 1
        }
        return 0
    }

    private static func indexBeforeQuotedLiteralEnding(at location: Int, in source: NSString) -> Int? {
        let quote = source.substring(with: NSRange(location: location, length: 1))
        guard quote == "\"" || quote == "'",
              !isEscaped(location, in: source) else {
            return nil
        }

        var cursor = location - 1
        while cursor >= 0 {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character == quote, !isEscaped(cursor, in: source) {
                if quote == "\"",
                   cursor > 0,
                   source.substring(with: NSRange(location: cursor - 1, length: 1)) == "@" {
                    return cursor - 2
                }
                return cursor - 1
            }
            cursor -= 1
        }
        return nil
    }

    private static func isEscaped(_ location: Int, in source: NSString) -> Bool {
        var backslashCount = 0
        var cursor = location - 1
        while cursor >= 0,
              source.substring(with: NSRange(location: cursor, length: 1)) == "\\" {
            backslashCount += 1
            cursor -= 1
        }
        return backslashCount % 2 == 1
    }

    private static func expressionPrefixEndsWithSelf(_ prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if expressionPrefixDirectlyEndsWithSelf(trimmed) {
            return true
        }
        return parenthesizedSelfSuffixEndsWithSelf(trimmed)
    }

    private static func expressionPrefixDirectlyEndsWithSelf(_ prefix: String) -> Bool {
        guard prefix.hasSuffix("self") else {
            return false
        }
        let beforeSelf = prefix.dropLast("self".count)
        guard let previous = beforeSelf.last else {
            return true
        }
        return !isObjectiveCIdentifierCharacter(previous)
    }

    private static func parenthesizedSelfSuffixEndsWithSelf(_ prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.last == ")" else {
            return false
        }

        var depth = 0
        var index = trimmed.index(before: trimmed.endIndex)
        while true {
            let character = trimmed[index]
            if character == ")" {
                depth += 1
            } else if character == "(" {
                depth -= 1
                if depth == 0 {
                    let innerStart = trimmed.index(after: index)
                    let innerEnd = trimmed.index(before: trimmed.endIndex)
                    let inner = String(trimmed[innerStart..<innerEnd])
                    let before = String(trimmed[..<index])
                    return allowsWrappedSelfChainStart(before)
                        && expressionPrefixIsBareOrCastWrappedSelf(inner)
                }
                if depth < 0 {
                    return false
                }
            }

            if index == trimmed.startIndex {
                break
            }
            index = trimmed.index(before: index)
        }
        return false
    }

    private static func expressionPrefixIsBareOrCastWrappedSelf(_ prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "self" {
            return true
        }
        if parenthesizedSelfSuffixEndsWithSelf(trimmed) {
            return true
        }
        guard trimmed.hasSuffix("self") else {
            return false
        }
        let beforeSelf = String(trimmed.dropLast("self".count))
        return allowsCastOnlyPrefixBeforeSelf(beforeSelf)
    }

    private static func allowsCastOnlyPrefixBeforeSelf(_ beforeSelf: String) -> Bool {
        var prefix = beforeSelf.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            while let match = trailingCastRegex.firstMatch(
                in: prefix,
                range: NSRange(location: 0, length: (prefix as NSString).length)
            ) {
                prefix = (prefix as NSString).substring(to: match.range.location)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }

            while prefix.hasSuffix("(") {
                prefix = String(prefix.dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }
        }
        return prefix.isEmpty
    }

    private static func isInsideCommentOrLiteral(_ range: NSRange, in text: NSString) -> Bool {
        var cursor = 0
        var quote: String?
        var isLineComment = false
        var isBlockComment = false
        var isEscaped = false

        while cursor < min(range.location, text.length) {
            let character = text.substring(with: NSRange(location: cursor, length: 1))
            let next = cursor + 1 < text.length
                ? text.substring(with: NSRange(location: cursor + 1, length: 1))
                : ""

            if isLineComment {
                if character == "\n" || character == "\r" {
                    isLineComment = false
                }
            } else if isBlockComment {
                if character == "*", next == "/" {
                    isBlockComment = false
                    cursor += 1
                }
            } else if let activeQuote = quote {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "/", next == "/" {
                isLineComment = true
                cursor += 1
            } else if character == "/", next == "*" {
                isBlockComment = true
                cursor += 1
            } else if character == "\"" || character == "'" {
                quote = character
            }

            cursor += 1
        }

        return quote != nil || isLineComment || isBlockComment
    }

    private static func keepsSelfChainConnected(_ suffix: String) -> Bool {
        var parenDepth = 0
        var bracketDepth = 0
        var index = suffix.startIndex

        while index < suffix.endIndex {
            if let nextIndex = indexAfterSkippableTriviaOrLiteral(startingAt: index, in: suffix) {
                index = nextIndex
                continue
            }
            let character = suffix[index]
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                if parenDepth > 0 {
                    parenDepth -= 1
                }
            case "[":
                bracketDepth += 1
            case "]":
                if bracketDepth > 0 {
                    bracketDepth -= 1
                }
            case ";", "{", "}":
                return false
            case "=", "?", ":":
                if parenDepth == 0 && bracketDepth == 0 {
                    return false
                }
            case ",":
                if parenDepth == 0 && bracketDepth == 0 {
                    return false
                }
            case "-":
                let nextIndex = suffix.index(after: index)
                if nextIndex < suffix.endIndex, suffix[nextIndex] == ">" {
                    index = suffix.index(after: nextIndex)
                    continue
                }
                if parenDepth == 0 && bracketDepth == 0 {
                    return false
                }
            case "+", "*", "/", "%", "&", "|", "^", "!", "~", "<", ">":
                if parenDepth == 0 && bracketDepth == 0 {
                    return false
                }
            default:
                break
            }
            index = suffix.index(after: index)
        }

        return true
    }

    private static func indexAfterSkippableTriviaOrLiteral(
        startingAt index: String.Index,
        in text: String
    ) -> String.Index? {
        if let nextIndex = indexAfterComment(startingAt: index, in: text) {
            return nextIndex
        }
        if let nextIndex = indexAfterLiteral(startingAt: index, in: text) {
            return nextIndex
        }
        return nil
    }

    private static func indexAfterComment(startingAt index: String.Index, in text: String) -> String.Index? {
        guard text[index] == "/" else {
            return nil
        }
        let markerIndex = text.index(after: index)
        guard markerIndex < text.endIndex else {
            return nil
        }

        if text[markerIndex] == "/" {
            var cursor = text.index(after: markerIndex)
            while cursor < text.endIndex {
                let character = text[cursor]
                if character == "\n" || character == "\r" {
                    return text.index(after: cursor)
                }
                cursor = text.index(after: cursor)
            }
            return text.endIndex
        }

        if text[markerIndex] == "*" {
            var cursor = text.index(after: markerIndex)
            while cursor < text.endIndex {
                let next = text.index(after: cursor)
                if text[cursor] == "*", next < text.endIndex, text[next] == "/" {
                    return text.index(after: next)
                }
                cursor = next
            }
        }
        return nil
    }

    private static func indexAfterLiteral(startingAt index: String.Index, in text: String) -> String.Index? {
        let character = text[index]
        if character == "@" {
            let nextIndex = text.index(after: index)
            guard nextIndex < text.endIndex, text[nextIndex] == "\"" else {
                return nil
            }
            return indexAfterQuotedLiteral(startingAt: nextIndex, in: text)
        }
        if character == "\"" || character == "'" {
            return indexAfterQuotedLiteral(startingAt: index, in: text)
        }
        return nil
    }

    private static func indexAfterQuotedLiteral(startingAt quoteIndex: String.Index, in text: String) -> String.Index {
        let quote = text[quoteIndex]
        var isEscaped = false
        var cursor = text.index(after: quoteIndex)
        while cursor < text.endIndex {
            let character = text[cursor]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == quote {
                return text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }
        return text.endIndex
    }

    private static func hasUnmatchedClosingDelimiter(_ suffix: String) -> Bool {
        var parenDepth = 0
        var bracketDepth = 0
        var index = suffix.startIndex

        while index < suffix.endIndex {
            if let nextIndex = indexAfterSkippableTriviaOrLiteral(startingAt: index, in: suffix) {
                index = nextIndex
                continue
            }
            let character = suffix[index]
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                if parenDepth == 0 {
                    return true
                }
                parenDepth -= 1
            case "[":
                bracketDepth += 1
            case "]":
                if bracketDepth == 0 {
                    return true
                }
                bracketDepth -= 1
            default:
                break
            }
            index = suffix.index(after: index)
        }

        return false
    }

    private static func hasUnmatchedClosingSquareBracket(_ suffix: String) -> Bool {
        var bracketDepth = 0
        var index = suffix.startIndex

        while index < suffix.endIndex {
            if let nextIndex = indexAfterSkippableTriviaOrLiteral(startingAt: index, in: suffix) {
                index = nextIndex
                continue
            }
            let character = suffix[index]
            switch character {
            case "[":
                bracketDepth += 1
            case "]":
                if bracketDepth == 0 {
                    return true
                }
                bracketDepth -= 1
            default:
                break
            }
            index = suffix.index(after: index)
        }

        return false
    }

    private static func containsOnlyClosingParenthesesAndWhitespace(_ suffix: String) -> Bool {
        var index = suffix.startIndex
        while index < suffix.endIndex {
            if let nextIndex = indexAfterSkippableTriviaOrLiteral(startingAt: index, in: suffix) {
                index = nextIndex
                continue
            }
            let character = suffix[index]
            guard character == ")" || character.isWhitespace else {
                return false
            }
            index = suffix.index(after: index)
        }
        return true
    }

    private static func hasUnmatchedOpeningDelimiter(_ suffix: String) -> Bool {
        var parenDepth = 0
        var bracketDepth = 0
        var index = suffix.startIndex

        while index < suffix.endIndex {
            if let nextIndex = indexAfterSkippableTriviaOrLiteral(startingAt: index, in: suffix) {
                index = nextIndex
                continue
            }
            let character = suffix[index]
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                if parenDepth > 0 {
                    parenDepth -= 1
                }
            case "[":
                bracketDepth += 1
            case "]":
                if bracketDepth > 0 {
                    bracketDepth -= 1
                }
            default:
                break
            }
            index = suffix.index(after: index)
        }

        return parenDepth > 0 || bracketDepth > 0
    }

    private static func allowsWrappedSelfChainStart(_ beforeSelf: String) -> Bool {
        var prefix = beforeSelf.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            while let match = trailingCastRegex.firstMatch(
                in: prefix,
                range: NSRange(location: 0, length: (prefix as NSString).length)
            ) {
                prefix = (prefix as NSString).substring(to: match.range.location)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }

            while prefix.hasSuffix("(") {
                prefix = String(prefix.dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }
        }
        guard prefix.isEmpty == false else {
            return true
        }
        if parenthesizedSelfPrefixKeywords.contains(prefix) {
            return true
        }
        guard let previous = prefix.last else {
            return true
        }
        return previous == "=" || parenthesizedSelfPrefixOperators.contains(previous)
    }

    private static func previousNonWhitespaceCharacter(before range: NSRange, in source: NSString) -> Character? {
        guard range.location > 0 else {
            return nil
        }
        var cursor = range.location - 1
        while cursor >= 0 {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return character.first
            }
            if cursor == 0 {
                break
            }
            cursor -= 1
        }
        return nil
    }

    private static func linePrefix(before range: NSRange, in source: NSString) -> String {
        let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
        let prefixLength = max(0, range.location - lineRange.location)
        return source.substring(with: NSRange(location: lineRange.location, length: prefixLength))
    }

    private static func typedefDeclarationName(around range: NSRange, in source: NSString) -> String? {
        let before = source.substring(to: min(range.location, source.length))
        guard let typedefRange = before.range(of: "typedef", options: .backwards) else {
            return nil
        }

        let start = before.distance(from: before.startIndex, to: typedefRange.lowerBound)
        let remaining = source.substring(from: start)
        guard let semicolon = remaining.firstIndex(of: ";") else {
            return nil
        }

        let length = remaining.distance(from: remaining.startIndex, to: semicolon) + 1
        let declaration = source.substring(with: NSRange(location: start, length: length)) as NSString
        return ObjectiveCFileSymbolIndex.typedefDeclaredName(in: declaration)
    }

    private static func canonicalToken(
        range: NSRange,
        syntaxID: EditorSourceSyntaxID
    ) -> SyntaxHighlightToken {
        SyntaxHighlightToken(
            range: range,
            syntaxID: syntaxID,
            language: .objectiveC,
            rawCaptureName: EditorSyntaxCapture.rawCaptureName(syntaxID: syntaxID, language: .objectiveC)
        )
    }

    private static func objectiveCBaseTokens(
        from tokens: [SyntaxHighlightToken],
        source: NSString,
        strippingSemanticOverlaysIn stripRange: NSRange? = nil
    ) -> [SyntaxHighlightToken] {
        var syntaxIDsByRange: [ObjectiveCRangeKey: ObjectiveCSyntaxIDMask] = [:]
        for token in tokens where token.language == .objectiveC || token.language == nil {
            syntaxIDsByRange[ObjectiveCRangeKey(token.range), default: []]
                .formUnion(ObjectiveCSyntaxIDMask(syntaxID: token.syntaxID))
        }

        return tokens.filter { token in
            !isObjectiveCSemanticOverlayToken(
                token,
                syntaxIDsAtSameRange: syntaxIDsByRange[ObjectiveCRangeKey(token.range)] ?? [],
                source: source,
                strippingSemanticOverlaysIn: stripRange
            )
        }
    }

    private static func mergedTokens(
        baseTokens: [SyntaxHighlightToken],
        overlayTokens: [SyntaxHighlightToken]
    ) -> [SyntaxHighlightToken] {
        let annotatedTokens = baseTokens.map { (token: $0, isOverlay: false) }
            + overlayTokens.map { (token: $0, isOverlay: true) }

        return annotatedTokens.sorted { lhs, rhs in
            if lhs.token.range.location != rhs.token.range.location {
                return lhs.token.range.location < rhs.token.range.location
            }
            if lhs.token.range.length != rhs.token.range.length {
                return lhs.token.range.length > rhs.token.range.length
            }
            if lhs.isOverlay != rhs.isOverlay {
                return !lhs.isOverlay && rhs.isOverlay
            }
            return SyntaxHighlightTokenOrdering.displayOrder(lhs.token, rhs.token)
        }.map(\.token)
    }

    private static func isObjectiveCSemanticOverlayToken(
        _ token: SyntaxHighlightToken,
        syntaxIDsAtSameRange: ObjectiveCSyntaxIDMask,
        source: NSString,
        strippingSemanticOverlaysIn stripRange: NSRange?
    ) -> Bool {
        guard token.language == .objectiveC || token.language == nil else {
            return false
        }
        if let stripRange,
           !rangesIntersect(token.range, stripRange) {
            return false
        }
        switch token.syntaxID {
        case .declarationType,
             .identifierConstantSystem:
            return true
        case .declarationOther:
            return syntaxIDsAtSameRange.contains(.identifierFunction)
                || syntaxIDsAtSameRange.contains(.identifier)
        case .identifierType:
            if syntaxIDsAtSameRange.contains(.identifierTypeSystem) {
                return true
            }
            guard token.range.upperBound <= source.length else {
                return false
            }
            let text = source.substring(with: token.range)
            return syntaxIDsAtSameRange.contains(.identifier)
                && isMessageReceiverName(token.range, in: source)
                && !isTypeDeclarationName(token.range, text: text, in: source)
        case .identifierFunction:
            if syntaxIDsAtSameRange.contains(.identifierFunctionSystem) {
                return true
            }
            return token.range.upperBound <= source.length
                && isCFunctionCallName(token.range, in: source)
                && !looksLikeCFunctionDeclarationPrefix(before: token.range, in: source)
        case .identifierVariable,
             .identifierVariableSystem:
            return true
        default:
            return false
        }
    }

    private static func isObjectiveCIdentifierRange(_ range: NSRange, in source: NSString) -> Bool {
        guard range.location >= 0,
              range.length > 0,
              range.upperBound <= source.length,
              isObjectiveCIdentifierStart(source.character(at: range.location))
        else {
            return false
        }

        var cursor = range.location + 1
        while cursor < range.upperBound {
            guard isObjectiveCIdentifierContinue(source.character(at: cursor)) else {
                return false
            }
            cursor += 1
        }
        return true
    }

    private static func isObjectiveCIdentifierStart(_ unit: unichar) -> Bool {
        unit == underscoreCodeUnit
            || (uppercaseACodeUnit...uppercaseZCodeUnit).contains(unit)
            || (lowercaseACodeUnit...lowercaseZCodeUnit).contains(unit)
    }

    private static func isObjectiveCIdentifierContinue(_ unit: unichar) -> Bool {
        isObjectiveCIdentifierStart(unit) || (zeroCodeUnit...nineCodeUnit).contains(unit)
    }

    private static func deduplicated(_ tokens: [SyntaxHighlightToken]) -> [SyntaxHighlightToken] {
        var seen = Set<ObjectiveCTokenKey>()
        var unique: [SyntaxHighlightToken] = []
        unique.reserveCapacity(tokens.count)

        for token in tokens {
            let key = ObjectiveCTokenKey(token)
            guard seen.insert(key).inserted else { continue }
            unique.append(token)
        }
        return unique
    }

    private static let structuralObjectiveCEditRegex = try! NSRegularExpression(
        pattern: #"(?m)^\s*(?:@(?:class|end|implementation|interface|property|protocol)|typedef\b|[-+]\s*\(|[A-Za-z_][A-Za-z0-9_ <>,_*]*\([^;{}]*\)\s*[;{]|[A-Za-z_][A-Za-z0-9_ <>,_*]*\*+\s*[A-Za-z_][A-Za-z0-9_]*\s*;)|\bNS_(?:ENUM|OPTIONS)\b|^\s*#"#)

    private static let appleMacroRegex = try! NSRegularExpression(
        pattern: #"\b(?:NS_ASSUME_NONNULL_BEGIN|NS_ASSUME_NONNULL_END|NS_SWIFT_NAME|NS_ENUM|NS_OPTIONS)\b"#
    )

    private static let appleEnumTypedefRegex = try! NSRegularExpression(
        pattern: #"\b(typedef)\s+(NS_ENUM|NS_OPTIONS)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
    )

    private static let appleMacroNames: Set<String> = [
        "NS_ASSUME_NONNULL_BEGIN",
        "NS_ASSUME_NONNULL_END",
        "NS_SWIFT_NAME",
        "NS_ENUM",
        "NS_OPTIONS",
    ]

    private static func isObjectiveCIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static let selfRootMemberRegex = try! NSRegularExpression(
        pattern: #"(^|[^A-Za-z0-9_])(self)((?:\s*\))*)\s*(?:\.|->)([A-Za-z_][A-Za-z0-9_]*)"#
    )

    private static let trailingCastRegex = try! NSRegularExpression(
        pattern: #"\(\s*[A-Za-z_][A-Za-z0-9_ <>,*]*\s*\)\s*$"#
    )

    private static let keywordLikeTypeNames: Set<String> = [
        "BOOL", "IMP", "SEL", "id", "instancetype"
    ]

    private static let parenthesizedSelfPrefixKeywords: Set<String> = [
        "else if", "for", "if", "return", "switch", "while"
    ]

    private static let parenthesizedSelfPrefixOperators: Set<Character> = [
        "+", "-", "*", "/", "%", "&", "|", "^"
    ]

    private static let underscoreCodeUnit = unichar(95)
    private static let uppercaseACodeUnit = unichar(65)
    private static let uppercaseZCodeUnit = unichar(90)
    private static let lowercaseACodeUnit = unichar(97)
    private static let lowercaseZCodeUnit = unichar(122)
    private static let zeroCodeUnit = unichar(48)
    private static let nineCodeUnit = unichar(57)
}

private struct ObjectiveCTreeSymbolFacts {
    var localTypes = Set<String>()
    var localFunctions = Set<String>()
    var localProperties = Set<String>()
    var propertyDeclarations: [(name: String, range: NSRange)] = []
    var selfMemberNameRangeKeys = Set<ObjectiveCRangeKey>()
    var selfChainMemberNameRangeKeys = Set<ObjectiveCRangeKey>()
    var selfChainCandidates: [(firstMember: String, fieldRange: NSRange)] = []
}

private struct ObjectiveCFileSymbolIndex {
    let localTypes: Set<String>
    let localFunctions: Set<String>
    let localProperties: Set<String>
    private let propertyDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>
    private let selfMemberNameRangeKeys: Set<ObjectiveCRangeKey>
    private let selfChainMemberNameRangeKeys: Set<ObjectiveCRangeKey>

    init(source: NSString, tokens: [SyntaxHighlightToken], rootNode: Node? = nil) {
        let treeFacts = rootNode.map {
            Self.collectTreeSymbolFacts(from: $0, source: source, tokens: tokens)
        } ?? ObjectiveCTreeSymbolFacts()

        var localTypes = treeFacts.localTypes
        var localFunctions = treeFacts.localFunctions
        var propertyDeclarations = treeFacts.propertyDeclarations
        let zeroArgumentMethodNameRanges = rootNode == nil ? Self.zeroArgumentMethodNameRanges(in: source) : []
        var localProperties = treeFacts.localProperties
        localProperties.formUnion(propertyDeclarations.map(\.name))

        if rootNode == nil {
            localTypes.formUnion(Self.scanLocalTypes(source: source))
            propertyDeclarations.append(contentsOf: Self.scanLocalPropertyDeclarations(source: source, tokens: tokens))
            localProperties.formUnion(propertyDeclarations.map(\.name))
        }

        for token in tokens {
            guard token.language == .objectiveC || token.language == nil,
                  token.range.location >= 0,
                  token.range.length > 0,
                  token.range.upperBound <= source.length,
                  Self.isIdentifierRange(token.range, in: source)
            else {
                continue
            }

            let text = source.substring(with: token.range)

            switch token.syntaxID {
            case .identifierType:
                localTypes.insert(text)
            case .identifierFunction:
                localFunctions.insert(text)
                if Self.isZeroArgumentMethodName(
                    token.range,
                    in: zeroArgumentMethodNameRanges
                ) {
                    localProperties.insert(text)
                }
            default:
                continue
            }
        }

        var selfChainMemberNameRangeKeys = treeFacts.selfChainMemberNameRangeKeys
        for candidate in treeFacts.selfChainCandidates where localProperties.contains(candidate.firstMember) {
            selfChainMemberNameRangeKeys.insert(ObjectiveCRangeKey(candidate.fieldRange))
        }

        self.localTypes = localTypes
        self.localFunctions = localFunctions
        self.localProperties = localProperties
        self.propertyDeclarationNameRangeKeys = Set(propertyDeclarations.map { ObjectiveCRangeKey($0.range) })
        self.selfMemberNameRangeKeys = treeFacts.selfMemberNameRangeKeys
        self.selfChainMemberNameRangeKeys = selfChainMemberNameRangeKeys
    }

    func containsPropertyDeclarationNameRange(_ range: NSRange) -> Bool {
        propertyDeclarationNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsSelfMemberNameRange(_ range: NSRange) -> Bool {
        selfMemberNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsSelfChainMemberNameRange(_ range: NSRange) -> Bool {
        selfChainMemberNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    private static func collectTreeSymbolFacts(
        from rootNode: Node,
        source: NSString,
        tokens: [SyntaxHighlightToken]
    ) -> ObjectiveCTreeSymbolFacts {
        var facts = ObjectiveCTreeSymbolFacts()
        collectTreeSymbolFacts(from: rootNode, source: source, tokens: tokens, into: &facts)
        return facts
    }

    private static func collectTreeSymbolFacts(
        from node: Node,
        source: NSString,
        tokens: [SyntaxHighlightToken],
        into facts: inout ObjectiveCTreeSymbolFacts
    ) {
        switch node.nodeType {
        case "class_interface", "class_implementation", "protocol_declaration":
            if let nameNode = primaryTypeIdentifier(in: node, source: source) {
                facts.localTypes.insert(source.substring(with: nameNode.range))
            }
        case "class_declaration", "protocol_forward_declaration":
            for nameNode in directIdentifierChildren(in: node) {
                facts.localTypes.insert(source.substring(with: nameNode.range))
            }
        case "type_definition":
            collectTypeDefinitionFacts(from: node, source: source, into: &facts)
        case "enum_specifier", "struct_specifier", "union_specifier":
            if let nameNode = node.child(byFieldName: "name") ?? directChild(in: node, nodeType: "type_identifier") {
                facts.localTypes.insert(source.substring(with: nameNode.range))
            }
        case "property_declaration":
            collectPropertyFacts(from: node, source: source, tokens: tokens, into: &facts)
        case "method_declaration", "method_definition":
            collectMethodFacts(from: node, source: source, into: &facts)
        case "function_declarator":
            collectFunctionDeclaratorFacts(from: node, source: source, into: &facts)
        case "field_expression":
            collectFieldExpressionFacts(from: node, source: source, into: &facts)
        default:
            break
        }

        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            collectTreeSymbolFacts(from: child, source: source, tokens: tokens, into: &facts)
        }
    }

    private static func collectTypeDefinitionFacts(
        from node: Node,
        source: NSString,
        into facts: inout ObjectiveCTreeSymbolFacts
    ) {
        for declarator in children(in: node, fieldName: "declarator") {
            if let identifier = declaratorIdentifier(in: declarator, preferredTypes: ["type_identifier", "identifier"]) {
                facts.localTypes.insert(source.substring(with: identifier.range))
            }
        }
    }

    private static func collectPropertyFacts(
        from node: Node,
        source: NSString,
        tokens: [SyntaxHighlightToken],
        into facts: inout ObjectiveCTreeSymbolFacts
    ) {
        guard let declarationRange = propertyStatementRange(startingAt: node.range.location, in: source) else {
            return
        }
        let declaration = source.substring(with: declarationRange) as NSString
        guard propertyDeclarationIsComplete(declaration),
              !propertyDeclarationAppearsToSwallowFollowingDeclaration(in: declaration) else {
            return
        }

        var didCollectFromToken = false
        for token in tokens where token.language == .objectiveC || token.language == nil {
            guard token.syntaxID == .declarationOther,
                  range(declarationRange, contains: token.range),
                  token.range.upperBound <= source.length,
                  isIdentifierRange(token.range, in: source)
            else {
                continue
            }
            let name = source.substring(with: token.range)
            facts.localProperties.insert(name)
            facts.propertyDeclarations.append((name: name, range: token.range))
            didCollectFromToken = true
        }

        guard !didCollectFromToken else {
            return
        }
        guard let relativeNameRange = propertyDeclaredNameRange(in: declaration) else {
            return
        }
        let range = NSRange(
            location: declarationRange.location + relativeNameRange.location,
            length: relativeNameRange.length
        )
        guard range.upperBound <= source.length,
              isIdentifierRange(range, in: source) else {
            return
        }
        let name = source.substring(with: range)
        facts.localProperties.insert(name)
        facts.propertyDeclarations.append((name: name, range: range))
    }

    private static func propertyStatementRange(startingAt start: Int, in source: NSString) -> NSRange? {
        guard start >= 0, start < source.length else {
            return nil
        }
        var cursor = start
        while cursor < source.length {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character == ";" {
                return NSRange(location: start, length: cursor - start + 1)
            }
            if character == "\n" || character == "\r" {
                let nextLineStart = cursor + 1
                if nextLineStart < source.length {
                    var lookahead = nextLineStart
                    while lookahead < source.length,
                          isWhitespace(source.substring(with: NSRange(location: lookahead, length: 1))) {
                        lookahead += 1
                    }
                    if lookahead < source.length {
                        let next = source.substring(with: NSRange(location: lookahead, length: 1))
                        if next == "@" || next == "-" || next == "+" {
                            return nil
                        }
                    }
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func propertyDeclarationIsComplete(_ declaration: NSString) -> Bool {
        var cursor = declaration.length - 1
        while cursor >= 0 {
            let character = declaration.substring(with: NSRange(location: cursor, length: 1))
            if isWhitespace(character) {
                if cursor == 0 {
                    return false
                }
                cursor -= 1
                continue
            }
            return character == ";"
        }
        return false
    }

    private static func collectMethodFacts(
        from node: Node,
        source: NSString,
        into facts: inout ObjectiveCTreeSymbolFacts
    ) {
        let directIdentifiers = directIdentifierChildren(in: node)
        guard directIdentifiers.count == 1,
              !hasDirectChild(in: node, nodeType: "method_parameter"),
              !hasDirectChild(in: node, nodeType: "keyword_declarator"),
              let nameNode = directIdentifiers.first
        else {
            return
        }
        facts.localProperties.insert(source.substring(with: nameNode.range))
    }

    private static func collectFunctionDeclaratorFacts(
        from node: Node,
        source: NSString,
        into facts: inout ObjectiveCTreeSymbolFacts
    ) {
        guard !hasAncestor(node, nodeTypes: [
            "property_declaration",
            "method_declaration",
            "method_definition",
            "method_parameter",
            "parameter_declaration"
        ]),
              let declarator = node.child(byFieldName: "declarator"),
              let identifier = declaratorIdentifier(in: declarator, preferredTypes: ["identifier"]) else {
            return
        }
        facts.localFunctions.insert(source.substring(with: identifier.range))
    }

    private static func collectFieldExpressionFacts(
        from node: Node,
        source: NSString,
        into facts: inout ObjectiveCTreeSymbolFacts
    ) {
        guard let fieldNode = node.child(byFieldName: "field"),
              let argumentNode = node.child(byFieldName: "argument") else {
            return
        }

        if expressionIsBareSelf(argumentNode, source: source) {
            facts.selfMemberNameRangeKeys.insert(ObjectiveCRangeKey(fieldNode.range))
        } else if let firstMember = firstSelfRootMemberName(in: argumentNode, source: source) {
            facts.selfChainCandidates.append((firstMember: firstMember, fieldRange: fieldNode.range))
        }
    }

    private static func primaryTypeIdentifier(in node: Node, source: NSString) -> Node? {
        for index in 0..<node.childCount {
            guard let child = node.child(at: index),
                  child.nodeType == "identifier",
                  node.fieldNameForChild(at: index) != "superclass",
                  node.fieldNameForChild(at: index) != "category",
                  child.range.upperBound <= source.length
            else {
                continue
            }
            return child
        }
        return nil
    }

    private static func directIdentifierChildren(in node: Node) -> [Node] {
        var identifiers: [Node] = []
        for index in 0..<node.childCount {
            guard let child = node.child(at: index),
                  child.nodeType == "identifier" || child.nodeType == "type_identifier"
            else {
                continue
            }
            identifiers.append(child)
        }
        return identifiers
    }

    private static func children(in node: Node, fieldName: String) -> [Node] {
        var children: [Node] = []
        for index in 0..<node.childCount {
            guard node.fieldNameForChild(at: index) == fieldName,
                  let child = node.child(at: index)
            else {
                continue
            }
            children.append(child)
        }
        return children
    }

    private static func directChild(in node: Node, nodeType: String) -> Node? {
        for index in 0..<node.childCount {
            guard let child = node.child(at: index),
                  child.nodeType == nodeType
            else {
                continue
            }
            return child
        }
        return nil
    }

    private static func hasDirectChild(in node: Node, nodeType: String) -> Bool {
        directChild(in: node, nodeType: nodeType) != nil
    }

    private static func declaratorIdentifier(in node: Node, preferredTypes: Set<String>) -> Node? {
        if let nodeType = node.nodeType,
           preferredTypes.contains(nodeType) {
            return node
        }
        if let declarator = node.child(byFieldName: "declarator"),
           let identifier = declaratorIdentifier(in: declarator, preferredTypes: preferredTypes) {
            return identifier
        }
        for index in 0..<node.childCount {
            guard let child = node.child(at: index),
                  let identifier = declaratorIdentifier(in: child, preferredTypes: preferredTypes)
            else {
                continue
            }
            return identifier
        }
        return nil
    }

    private static func expressionIsBareSelf(_ node: Node, source: NSString) -> Bool {
        guard node.range.upperBound <= source.length else {
            return false
        }
        return source.substring(with: node.range)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "self"
    }

    private static func firstSelfRootMemberName(in node: Node, source: NSString) -> String? {
        guard node.nodeType == "field_expression",
              let argument = node.child(byFieldName: "argument"),
              let field = node.child(byFieldName: "field"),
              field.range.upperBound <= source.length
        else {
            return nil
        }
        if expressionIsBareSelf(argument, source: source) {
            return source.substring(with: field.range)
        }
        return firstSelfRootMemberName(in: argument, source: source)
    }

    private static func hasAncestor(_ node: Node, nodeTypes: Set<String>) -> Bool {
        var current = node.parent
        while let node = current {
            if let nodeType = node.nodeType,
               nodeTypes.contains(nodeType) {
                return true
            }
            current = node.parent
        }
        return false
    }

    private static func range(_ outer: NSRange, contains inner: NSRange) -> Bool {
        inner.location >= outer.location && inner.upperBound <= outer.upperBound
    }

    private static func scanLocalTypes(source: NSString) -> Set<String> {
        let string = source as String
        let fullRange = NSRange(location: 0, length: source.length)
        var names = Set<String>()

        for regex in localTypeRegexes {
            for match in regex.matches(in: string, range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let range = match.range(at: 1)
                guard range.location != NSNotFound else { continue }
                let name = source.substring(with: range)
                if isIdentifier(name) {
                    names.insert(name)
                }
            }
        }

        for match in typedefRegex.matches(in: string, range: fullRange) {
            let range = match.range
            let declaration = source.substring(with: range) as NSString
            if let name = typedefDeclaredName(in: declaration) {
                names.insert(name)
            }
        }

        return names
    }

    static func typedefDeclaredName(in declaration: NSString) -> String? {
        if declaration.range(of: "NS_ENUM").location != NSNotFound
            || declaration.range(of: "NS_OPTIONS").location != NSNotFound {
            return nil
        }
        if let blockName = blockTypedefDeclaredName(in: declaration) {
            return blockName
        }

        let string = declaration as String
        let matches = identifierRegex.matches(
            in: string,
            range: NSRange(location: 0, length: declaration.length)
        )
        for match in matches.reversed() {
            let name = declaration.substring(with: match.range)
            if !typedefIgnoredIdentifiers.contains(name) {
                return name
            }
        }
        return nil
    }

    private static func blockTypedefDeclaredName(in declaration: NSString) -> String? {
        let string = declaration as String
        guard let match = blockTypedefNameRegex.firstMatch(
            in: string,
            range: NSRange(location: 0, length: declaration.length)
        ) else {
            return nil
        }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else {
            return nil
        }
        return declaration.substring(with: range)
    }

    private static func scanLocalPropertyDeclarations(
        source: NSString,
        tokens: [SyntaxHighlightToken]
    ) -> [(name: String, range: NSRange)] {
        let string = source as String
        let fullRange = NSRange(location: 0, length: source.length)
        var declarations: [(name: String, range: NSRange)] = []

        for match in propertyDeclarationRegex.matches(in: string, range: fullRange) {
            let propertyKeywordRange = NSRange(location: match.range.location, length: "@property".count)
            guard isCodeTokenRange(propertyKeywordRange, tokens: tokens, source: source) else {
                continue
            }

            let declaration = source.substring(with: match.range) as NSString
            if propertyDeclarationAppearsToSwallowFollowingDeclaration(in: declaration) {
                continue
            }
            guard let relativeNameRange = propertyDeclaredNameRange(in: declaration) else {
                continue
            }
            let range = NSRange(
                location: match.range.location + relativeNameRange.location,
                length: relativeNameRange.length
            )
            let name = source.substring(with: range)
            if isIdentifier(name),
               !typedefIgnoredIdentifiers.contains(name),
               isCodeIdentifierRange(range, tokens: tokens, source: source) {
                declarations.append((name: name, range: range))
            }
        }

        return declarations
    }

    private static func isCodeTokenRange(
        _ range: NSRange,
        tokens: [SyntaxHighlightToken],
        source: NSString
    ) -> Bool {
        tokens.contains { token in
            guard NSEqualRanges(token.range, range),
                  (token.language == .objectiveC || token.language == nil) else {
                return false
            }
            return source.substring(with: token.range) == "@property"
        }
    }

    private static func isCodeIdentifierRange(
        _ range: NSRange,
        tokens: [SyntaxHighlightToken],
        source: NSString
    ) -> Bool {
        tokens.contains { token in
            guard NSEqualRanges(token.range, range),
                  (token.language == .objectiveC || token.language == nil) else {
                return false
            }
            return isIdentifier(source.substring(with: token.range))
        }
    }

    private static func propertyDeclaredNameRange(in declaration: NSString) -> NSRange? {
        let string = declaration as String
        if let match = blockPropertyNameRegex.firstMatch(
            in: string,
            range: NSRange(location: 0, length: declaration.length)
        ) {
            let range = match.range(at: 1)
            if range.location != NSNotFound {
                return range
            }
        }
        if let match = functionPointerPropertyNameRegex.firstMatch(
            in: string,
            range: NSRange(location: 0, length: declaration.length)
        ) {
            let range = match.range(at: 1)
            if range.location != NSNotFound {
                return range
            }
        }
        let searchRange = propertyNameFallbackSearchRange(in: declaration)
        guard searchRange.length > 0 else {
            return nil
        }

        let searchableDeclaration = declaration.substring(with: searchRange) + ";"
        if let match = propertyNameBeforeTrailingAttributesRegex.firstMatch(
            in: searchableDeclaration,
            range: NSRange(location: 0, length: (searchableDeclaration as NSString).length)
        ) {
            let range = match.range(at: 1)
            if range.location != NSNotFound,
               range.upperBound <= searchRange.length {
                return range
            }
        }

        return identifierRegex.matches(
            in: string,
            range: searchRange
        ).last?.range
    }

    private static func propertyDeclarationAppearsToSwallowFollowingDeclaration(in declaration: NSString) -> Bool {
        let bodyStart = propertyBodyStart(in: declaration)
        guard bodyStart < declaration.length else {
            return false
        }

        let body = declaration.substring(from: bodyStart)
        let lines = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard lines.count > 1 else {
            return false
        }

        var previousLineContainsDeclaratorName = false
        for line in lines {
            if previousLineContainsDeclaratorName,
               propertyContinuationLineLooksLikeStandaloneDeclaration(line) {
                return true
            }
            previousLineContainsDeclaratorName = propertyBodyLineContainsDeclaratorName(line)
        }
        return false
    }

    private static func propertyBodyLineContainsDeclaratorName(_ line: String) -> Bool {
        let body = line as NSString
        let bodyWithoutGenerics = stringByRemovingAngleBracketContents(from: body)
        let end = trimmingTrailingPropertySyntax(in: bodyWithoutGenerics, end: bodyWithoutGenerics.length)
        guard let lastIdentifierRange = identifierRange(before: end, in: bodyWithoutGenerics) else {
            return false
        }
        return identifierRegex.firstMatch(
            in: bodyWithoutGenerics as String,
            range: NSRange(location: 0, length: lastIdentifierRange.location)
        ) != nil
    }

    private static func stringByRemovingAngleBracketContents(from text: NSString) -> NSString {
        var result = ""
        var depth = 0
        for character in text as String {
            if character == "<" {
                depth += 1
                continue
            }
            if character == ">", depth > 0 {
                depth -= 1
                continue
            }
            if depth == 0 {
                result.append(character)
            }
        }
        return result as NSString
    }

    private static func propertyContinuationLineLooksLikeStandaloneDeclaration(_ line: String) -> Bool {
        let trimmedLine = (line as NSString)
        let end = trimmingTrailingPropertySyntax(in: trimmedLine, end: trimmedLine.length)
        guard end > 0 else {
            return false
        }
        let declaration = trimmedLine.substring(to: end) as NSString
        let matches = identifierRegex.matches(
            in: declaration as String,
            range: NSRange(location: 0, length: declaration.length)
        )
        guard let firstMatch = matches.first else {
            return false
        }

        let firstIdentifier = declaration.substring(with: firstMatch.range)
        if isLikelyTrailingPropertyAttribute(firstIdentifier, in: declaration, matchCount: matches.count) {
            return false
        }
        if (declaration as String).contains("*") {
            return matches.count >= 1
        }
        return matches.count >= 2
    }

    private static func isLikelyTrailingPropertyAttribute(
        _ name: String,
        in declaration: NSString,
        matchCount: Int
    ) -> Bool {
        if name.hasPrefix("__") || bareTrailingPropertyAttributes.contains(name) {
            return true
        }
        if name.range(
            of: #"^(?:NS|CF|API|AVAILABLE|DEPRECATED|IB)_"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if isUppercaseIdentifier(name) {
            if matchCount == 1 {
                return true
            }
            let suffix = declaration.substring(from: name.utf16.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.first == "("
        }
        return false
    }

    private static func propertyNameFallbackSearchRange(in declaration: NSString) -> NSRange {
        var end = declaration.length
        end = trimmingTrailingPropertySyntax(in: declaration, end: end)

        var didStripSuffix = true
        while didStripSuffix {
            didStripSuffix = false
            end = trimmingTrailingPropertySyntax(in: declaration, end: end)

            if let range = trailingFunctionLikeMacroRange(in: declaration, end: end),
               hasIdentifierBefore(range.location, in: declaration) {
                end = range.location
                didStripSuffix = true
                continue
            }

            if let range = trailingIdentifierRange(in: declaration, end: end) {
                let name = declaration.substring(with: range)
                if shouldStripBareTrailingPropertyAttribute(
                    name,
                    before: range.location,
                    in: declaration
                ),
                   hasIdentifierBefore(range.location, in: declaration) {
                    end = range.location
                    didStripSuffix = true
                }
            }
        }

        end = trimmingTrailingPropertySyntax(in: declaration, end: end)
        return NSRange(location: 0, length: max(0, end))
    }

    private static func trimmingTrailingPropertySyntax(in declaration: NSString, end: Int) -> Int {
        var end = end
        while end > 0 {
            let character = declaration.substring(with: NSRange(location: end - 1, length: 1))
            if character == ";" || isWhitespace(character) {
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private static func trailingFunctionLikeMacroRange(in declaration: NSString, end: Int) -> NSRange? {
        guard end > 0,
              declaration.substring(with: NSRange(location: end - 1, length: 1)) == ")",
              let openParen = matchingOpeningParenthesis(in: declaration, before: end),
              let nameRange = identifierRange(before: openParen, in: declaration)
        else {
            return nil
        }

        let name = declaration.substring(with: nameRange)
        guard isIdentifier(name) else {
            return nil
        }
        return NSRange(location: nameRange.location, length: end - nameRange.location)
    }

    private static func matchingOpeningParenthesis(in declaration: NSString, before end: Int) -> Int? {
        var depth = 0
        var cursor = end - 1
        while cursor >= 0 {
            let character = declaration.substring(with: NSRange(location: cursor, length: 1))
            if character == ")" {
                depth += 1
            } else if character == "(" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
                if depth < 0 {
                    return nil
                }
            }

            if cursor == 0 {
                break
            }
            cursor -= 1
        }
        return nil
    }

    private static func trailingIdentifierRange(in declaration: NSString, end: Int) -> NSRange? {
        identifierRange(before: end, in: declaration)
    }

    private static func identifierRange(before location: Int, in declaration: NSString) -> NSRange? {
        var end = location
        while end > 0 {
            let character = declaration.substring(with: NSRange(location: end - 1, length: 1))
            if isWhitespace(character) {
                end -= 1
            } else {
                break
            }
        }

        var start = end
        while start > 0 {
            let character = Character(declaration.substring(with: NSRange(location: start - 1, length: 1)))
            if isIdentifierCharacter(character) {
                start -= 1
            } else {
                break
            }
        }
        guard start < end else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    private static func hasIdentifierBefore(_ location: Int, in declaration: NSString) -> Bool {
        identifierRegex.firstMatch(
            in: declaration as String,
            range: NSRange(location: 0, length: max(0, location))
        ) != nil
    }

    private static func shouldStripBareTrailingPropertyAttribute(
        _ name: String,
        before location: Int,
        in declaration: NSString
    ) -> Bool {
        if name.hasPrefix("__") || bareTrailingPropertyAttributes.contains(name) {
            return true
        }
        guard name.contains("_"),
              name == name.uppercased(),
              let previousRange = trailingIdentifierRange(in: declaration, end: location) else {
            return false
        }
        let previousName = declaration.substring(with: previousRange)
        if isUppercaseIdentifier(previousName) {
            return hasPropertyTypeIdentifierBefore(previousRange.location, in: declaration)
        }
        guard !typedefIgnoredIdentifiers.contains(previousName),
              !isLikelyLowercaseTypedefName(previousName),
              let firstCharacter = previousName.first else {
            return false
        }
        return firstCharacter == "_" || firstCharacter.isLowercase
    }

    private static func isUppercaseIdentifier(_ name: String) -> Bool {
        name == name.uppercased() && name.contains { $0.isLetter }
    }

    private static func hasPropertyTypeIdentifierBefore(_ location: Int, in declaration: NSString) -> Bool {
        let start = propertyBodyStart(in: declaration)
        guard start < location else {
            return false
        }
        return identifierRegex.firstMatch(
            in: declaration as String,
            range: NSRange(location: start, length: location - start)
        ) != nil
    }

    private static func propertyBodyStart(in declaration: NSString) -> Int {
        var cursor = "@property".utf16.count
        while cursor < declaration.length,
              isWhitespace(declaration.substring(with: NSRange(location: cursor, length: 1))) {
            cursor += 1
        }

        if cursor < declaration.length,
           declaration.substring(with: NSRange(location: cursor, length: 1)) == "(",
           let closeParen = matchingClosingParenthesis(in: declaration, after: cursor) {
            cursor = closeParen + 1
            while cursor < declaration.length,
                  isWhitespace(declaration.substring(with: NSRange(location: cursor, length: 1))) {
                cursor += 1
            }
        }
        return cursor
    }

    private static func matchingClosingParenthesis(in declaration: NSString, after openParen: Int) -> Int? {
        var depth = 0
        var cursor = openParen
        while cursor < declaration.length {
            let character = declaration.substring(with: NSRange(location: cursor, length: 1))
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
                if depth < 0 {
                    return nil
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func isLikelyLowercaseTypedefName(_ name: String) -> Bool {
        name.contains("_") && name.allSatisfy { character in
            character == "_" || character.isLowercase || character.isNumber
        }
    }

    private static func isWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static func zeroArgumentMethodNameRanges(in source: NSString) -> [NSRange] {
        let string = source as String
        let fullRange = NSRange(location: 0, length: source.length)
        return zeroArgumentMethodRegex.matches(in: string, range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1 else {
                return nil
            }
            let range = match.range(at: 1)
            return range.location == NSNotFound ? nil : range
        }
    }

    private static func isZeroArgumentMethodName(
        _ range: NSRange,
        in zeroArgumentMethodNameRanges: [NSRange]
    ) -> Bool {
        zeroArgumentMethodNameRanges.contains {
            NSIntersectionRange($0, range).length > 0
        }
    }

    private static func isIdentifier(_ text: String) -> Bool {
        let nsText = text as NSString
        return isIdentifierRange(NSRange(location: 0, length: nsText.length), in: nsText)
    }

    private static func isIdentifierRange(_ range: NSRange, in source: NSString) -> Bool {
        guard range.location >= 0,
              range.length > 0,
              range.upperBound <= source.length,
              isASCIIIdentifierStart(source.character(at: range.location))
        else {
            return false
        }
        var cursor = range.location + 1
        while cursor < range.upperBound {
            guard isASCIIIdentifierContinue(source.character(at: cursor)) else {
                return false
            }
            cursor += 1
        }
        return true
    }

    private static func isASCIIIdentifierStart(_ unit: unichar) -> Bool {
        unit == 95
            || (65...90).contains(unit)
            || (97...122).contains(unit)
    }

    private static func isASCIIIdentifierContinue(_ unit: unichar) -> Bool {
        isASCIIIdentifierStart(unit) || (48...57).contains(unit)
    }

    private static let localTypeRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"@(?:interface|implementation|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"#),
        try! NSRegularExpression(pattern: #"@class\s+([A-Za-z_][A-Za-z0-9_]*)"#),
        try! NSRegularExpression(pattern: #"\bNS_(?:ENUM|OPTIONS)\s*\([^,]+,\s*([A-Za-z_][A-Za-z0-9_]*)"#),
        try! NSRegularExpression(pattern: #"\b(?:struct|union|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"#),
    ]

    private static let propertyDeclarationRegex = try! NSRegularExpression(
        pattern: #"@property\b[^\n;]*(?:\n(?!\s*(?:[-+]|@))[^\n;]*)*;"#
    )

    private static let blockPropertyNameRegex = try! NSRegularExpression(
        pattern: #"@property\b[^;]*\(\s*\^\s*(?:[A-Za-z_][A-Za-z0-9_]*\s+)*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
    )

    private static let functionPointerPropertyNameRegex = try! NSRegularExpression(
        pattern: #"\(\s*\*+\s*(?:[A-Za-z_][A-Za-z0-9_]*\s+)*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\([^;]*\)"#
    )

    private static let propertyNameBeforeTrailingAttributesRegex = try! NSRegularExpression(
        pattern: #"\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\];]*\]\s*)?(?:(?:NS_[A-Z0-9_]+|CF_[A-Z0-9_]+|API_[A-Z0-9_]+|AVAILABLE_[A-Z0-9_]+|DEPRECATED_[A-Z0-9_]+|IB_[A-Z0-9_]+|__[A-Za-z0-9_]+__|__[A-Za-z0-9_]+)\s*(?:\([^;]*\))?\s*)*;"#
    )

    private static let zeroArgumentMethodRegex = try! NSRegularExpression(
        pattern: #"(?m)^[ \t]*[-+]\s*\([^)]*\)\s*([A-Za-z_][A-Za-z0-9_]*)\s*[;{]"#
    )

    private static let bareTrailingPropertyAttributes: Set<String> = [
        "IBInspectable", "IBOutlet", "NS_REFINED_FOR_SWIFT"
    ]

    private static let typedefRegex = try! NSRegularExpression(
        pattern: #"\btypedef\b[^;]*;"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let blockTypedefNameRegex = try! NSRegularExpression(
        pattern: #"\(\s*\^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
    )

    private static let identifierRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z_][A-Za-z0-9_]*"#
    )

    private static let typedefIgnoredIdentifiers: Set<String> = [
        "NS_ENUM", "NS_OPTIONS", "typedef", "struct", "union", "enum",
        "const", "unsigned", "signed", "short", "long", "int", "char",
        "void", "id", "BOOL", "NSInteger", "NSUInteger", "NSString",
        "NSError", "NSRange", "nullable", "nonnull", "_Nullable", "_Nonnull"
    ]
}

private enum ObjectiveCSystemSymbols {
    static func isSystemType(_ name: String) -> Bool {
        if knownTypeNames.contains(name) {
            return true
        }
        return knownTypePrefixes.contains { name.hasPrefix($0) }
    }

    private static let knownTypeNames: Set<String> = [
        "BOOL", "Class", "IMP", "NSInteger", "NSUInteger", "NSRange", "SEL",
        "char", "double", "float", "id", "instancetype", "int", "long",
        "short", "unichar", "unsigned", "void"
    ]

    private static let knownTypePrefixes: [String] = [
        "NS", "CF", "CG", "CA", "CI", "UI", "AV", "WK", "MTL", "OS", "dispatch_"
    ]

}
