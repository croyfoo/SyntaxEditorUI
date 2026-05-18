import Foundation

// Provides Swift substring tokens that cannot be expressed by Tree-sitter
// captures alone, such as MARK comments and URLs inside comments.
enum SwiftSyntaxOverlayTokenProvider {
    static func mergingOverlayTokens(
        tokens: [SyntaxHighlightToken],
        source: String,
        refreshRange: NSRange? = nil
    ) -> [SyntaxHighlightToken] {
        let nsSource = source as NSString
        let baseTokens = tokens.filter { !isSwiftSemanticOverlayToken($0) }
        let targetRange = refreshRange.map {
            lineEnvelopeRange(containing: $0, in: nsSource)
        }
        let overlayTokens =
            tokensInCommentLines(
                source: nsSource,
                existingTokens: baseTokens,
                targetRange: targetRange
            ) +
            tokensInPreprocessorLines(
                source: nsSource,
                existingTokens: baseTokens,
                targetRange: targetRange
            ) +
            tokensInSemanticSymbolRanges(
                source: nsSource,
                existingTokens: baseTokens
            )
        guard overlayTokens.isEmpty == false else {
            return baseTokens
        }

        return deduplicated((baseTokens + overlayTokens).sorted(by: SyntaxHighlightTokenOrdering.displayOrder))
    }

    private static func tokensInCommentLines(
        source: NSString,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        let fullRange = NSRange(location: 0, length: source.length)
        let searchRange = targetRange.map {
            SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: source.length)
        } ?? fullRange
        guard searchRange.length > 0 else {
            return []
        }

        let commentRanges = commentTokenRanges(
            overlapping: searchRange,
            existingTokens: existingTokens
        )
        guard !commentRanges.isEmpty else {
            return []
        }

        let sourceString = source as String
        var tokens: [SyntaxHighlightToken] = []
        var commentRangeIndex = 0
        var location = searchRange.location
        while location < searchRange.upperBound {
            let remainingRange = NSRange(location: location, length: searchRange.upperBound - location)
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let clampedLineRange = NSIntersectionRange(lineRange, remainingRange)
            guard clampedLineRange.length > 0 else { break }

            while commentRangeIndex < commentRanges.count,
                  commentRanges[commentRangeIndex].upperBound <= clampedLineRange.location {
                commentRangeIndex += 1
            }

            guard commentRangeIndex < commentRanges.count,
                  rangesIntersect(commentRanges[commentRangeIndex], clampedLineRange)
            else {
                location = clampedLineRange.upperBound
                continue
            }

            let line = source.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("// MARK:"),
               let markRange = substringRange("MARK:", in: source, lineRange: clampedLineRange) {
                tokens.append(canonicalToken(range: markTokenRange(from: markRange, in: source), syntaxID: .mark))
            }

            tokens.append(contentsOf: urlTokens(in: sourceString, lineRange: clampedLineRange))
            location = clampedLineRange.upperBound
        }

        return tokens
    }

    private static func tokensInPreprocessorLines(
        source: NSString,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        let fullRange = NSRange(location: 0, length: source.length)
        let searchRange = targetRange.map {
            SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: source.length)
        } ?? fullRange
        guard searchRange.length > 0 else {
            return []
        }

        let sourceString = source as String
        var tokens: [SyntaxHighlightToken] = []
        var location = searchRange.location
        while location < searchRange.upperBound {
            let remainingRange = NSRange(location: location, length: searchRange.upperBound - location)
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let clampedLineRange = NSIntersectionRange(lineRange, remainingRange)
            guard clampedLineRange.length > 0 else { break }

            let line = source.substring(with: clampedLineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("#if")
                || trimmed.hasPrefix("#elseif")
                || trimmed.hasPrefix("#else")
                || trimmed.hasPrefix("#endif")
                || trimmed.hasPrefix("#sourceLocation")
            else {
                location = clampedLineRange.upperBound
                continue
            }

            for match in preprocessorRegex.matches(in: sourceString, range: clampedLineRange) {
                let range = match.range
                guard !isExcludedPreprocessorRange(range, existingTokens: existingTokens) else {
                    continue
                }
                appendPreprocessorTokens(for: range, in: source, to: &tokens)
            }
            location = clampedLineRange.upperBound
        }

        return tokens
    }

    private static func tokensInSemanticSymbolRanges(
        source: NSString,
        existingTokens: [SyntaxHighlightToken]
    ) -> [SyntaxHighlightToken] {
        guard source.length > 0 else {
            return []
        }

        let index = SwiftFileSymbolIndex(source: source, tokens: existingTokens)
        var tokens: [SyntaxHighlightToken] = []

        for token in existingTokens {
            guard token.language == .swift || token.language == nil,
                  token.syntaxID == .plain,
                  token.range.upperBound <= source.length,
                  !isPreprocessorLine(containing: token.range, in: source)
            else {
                continue
            }

            let text = source.substring(with: token.range)
            guard isSwiftIdentifier(text),
                  let syntaxID = semanticSyntaxID(
                    for: text,
                    range: token.range,
                    in: source,
                    index: index
                  )
            else {
                continue
            }
            tokens.append(canonicalToken(range: token.range, syntaxID: syntaxID))
        }

        return tokens
    }

    private static func semanticSyntaxID(
        for text: String,
        range: NSRange,
        in source: NSString,
        index: SwiftFileSymbolIndex
    ) -> EditorSourceSyntaxID? {
        let context = SwiftSemanticTokenContext(source: source, range: range, text: text)
        guard !context.isImportLine,
              !context.isAttributeContext,
              !context.isLabel,
              !context.isDeclarationContext,
              !context.isPatternBindingDeclarationContext
        else {
            return nil
        }

        if context.isMacroInvocation {
            return nil
        }

        if context.isSelfMemberAccess {
            return nil
        }

        if context.isMemberAccess {
            return nil
        }

        let localValueEntry = index.entry(
            named: text,
            at: range,
            allowedKinds: [.variable],
            rolePredicate: { $0 == .local }
        )
        let isTypeContext = context.isTypeContext

        if localValueEntry != nil, !isTypeContext {
            return nil
        }

        if context.isAssignmentExpressionContext,
           let projectVariable = index.entry(
            named: text,
            at: range,
            allowedKinds: [.variable],
            rolePredicate: { $0 == .file || $0 == .member }
           ) {
            return syntaxIDForLocalEntry(projectVariable)
        }

        if context.isCallArgumentValueContext,
           let projectVariable = index.entry(
            named: text,
            at: range,
            allowedKinds: [.variable],
            rolePredicate: { $0 == .file || $0 == .member }
           ) {
            return syntaxIDForLocalEntry(projectVariable)
        }

        if isTypeContext {
            if localValueEntry != nil,
               context.isAssignmentExpressionContext || context.isCallArgumentValueContext {
                return nil
            }

            if context.isFunctionCall,
               index.entry(
                named: text,
                at: range,
                allowedKinds: [.function],
                rolePredicate: { _ in true }
               ) != nil {
                return nil
            }
            return knownExternalTypeNames.contains(text) && !index.hasLocalType(named: text, at: range)
                ? .identifierTypeSystem
                : nil
        }

        if context.isInsideStringInterpolation {
            return nil
        }

        if let local = index.entry(
            named: text,
            at: range,
            allowedKinds: [.variable],
            rolePredicate: { $0 == .file || $0 == .member }
        ) {
            return syntaxIDForLocalEntry(local)
        }

        if context.isFunctionCall {
            return nil
        }

        return nil
    }

    private static func syntaxIDForLocalEntry(_ entry: SwiftFileSymbolIndex.Entry?) -> EditorSourceSyntaxID? {
        guard let entry else {
            return nil
        }
        switch entry.kind {
        case .type:
            return .identifierType
        case .function:
            return .identifierFunction
        case .variable:
            return .identifierVariable
        case .constant:
            return .identifierConstant
        case .macro:
            return .identifierMacro
        }
    }

    private static func canonicalToken(
        range: NSRange,
        syntaxID: EditorSourceSyntaxID
    ) -> SyntaxHighlightToken {
        SyntaxHighlightToken(
            range: range,
            syntaxID: syntaxID,
            language: .swift,
            rawCaptureName: EditorSyntaxCapture.rawCaptureName(syntaxID: syntaxID, language: .swift)
        )
    }

    private static func commentTokenRanges(
        overlapping targetRange: NSRange,
        existingTokens: [SyntaxHighlightToken]
    ) -> [NSRange] {
        let ranges = existingTokens.compactMap { token -> NSRange? in
            guard token.language == .swift || token.language == nil,
                  token.syntaxID.rawValue == "comment" || token.syntaxID.rawValue.hasPrefix("comment.")
            else {
                return nil
            }

            let range = SyntaxEditorRangeUtilities.intersection(of: token.range, and: targetRange)
            return range.length > 0 ? range : nil
        }
        .sorted { lhs, rhs in
            if lhs.location != rhs.location {
                return lhs.location < rhs.location
            }
            return lhs.length < rhs.length
        }

        return mergedRanges(ranges)
    }

    private static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        guard var current = ranges.first else {
            return []
        }

        var merged: [NSRange] = []
        merged.reserveCapacity(ranges.count)
        for range in ranges.dropFirst() {
            guard range.location <= current.upperBound else {
                merged.append(current)
                current = range
                continue
            }

            let upperBound = max(current.upperBound, range.upperBound)
            current = NSRange(location: current.location, length: upperBound - current.location)
        }
        merged.append(current)
        return merged
    }

    private static func rangesIntersect(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        max(lhs.location, rhs.location) < min(lhs.upperBound, rhs.upperBound)
    }

    private static func rangeKey(_ range: NSRange) -> String {
        "\(range.location):\(range.length)"
    }

    private static func deduplicated(_ tokens: [SyntaxHighlightToken]) -> [SyntaxHighlightToken] {
        var seen = Set<String>()
        var unique: [SyntaxHighlightToken] = []
        unique.reserveCapacity(tokens.count)

        for token in tokens {
            let key = "\(rangeKey(token.range)):\(token.rawCaptureName)"
            guard seen.insert(key).inserted else { continue }
            unique.append(token)
        }

        return unique
    }

    private static func lineEnvelopeRange(containing range: NSRange, in source: NSString) -> NSRange {
        guard source.length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: source.length)
        if clampedRange.length > 0 {
            return source.lineRange(for: clampedRange)
        }

        let location = min(clampedRange.location, source.length - 1)
        return source.lineRange(for: NSRange(location: location, length: 0))
    }

    private static func markTokenRange(from markerRange: NSRange, in source: NSString) -> NSRange {
        let lineRange = source.lineRange(for: markerRange)
        let rawRange = NSRange(
            location: markerRange.location,
            length: max(0, lineRange.upperBound - markerRange.location)
        )
        let rawText = source.substring(with: rawRange) as NSString
        let trimmedLength = rawText.trimmingCharacters(in: .newlines).utf16.count
        return NSRange(location: markerRange.location, length: trimmedLength)
    }

    private static func substringRange(
        _ substring: String,
        in source: NSString,
        lineRange: NSRange
    ) -> NSRange? {
        let range = source.range(of: substring, options: [], range: lineRange)
        return range.location == NSNotFound ? nil : range
    }

    private static let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s\])>"]+"#)

    private static let preprocessorRegex = try! NSRegularExpression(
        pattern: #"#[A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*|&&|\|\||==|!=|>=|<=|[!<>()(),:]"#
    )

    private static func urlTokens(in source: String, lineRange: NSRange) -> [SyntaxHighlightToken] {
        urlRegex.matches(in: source, range: lineRange).map {
            canonicalToken(range: $0.range, syntaxID: .url)
        }
    }

    private static func isExcludedPreprocessorRange(
        _ range: NSRange,
        existingTokens: [SyntaxHighlightToken]
    ) -> Bool {
        existingTokens.contains {
            guard $0.language == .swift || $0.language == nil else {
                return false
            }
            let value = $0.syntaxID.rawValue
            guard value == "string" || value == "character" || value.hasPrefix("comment") else {
                return false
            }
            return SyntaxEditorRangeUtilities.intersection(of: $0.range, and: range).length > 0
        }
    }

    private static func appendPreprocessorTokens(
        for range: NSRange,
        in source: NSString,
        to tokens: inout [SyntaxHighlightToken]
    ) {
        let text = source.substring(with: range)
        if text == "#sourceLocation" {
            tokens.append(canonicalToken(range: NSRange(location: range.location, length: 1), syntaxID: .preprocessor))
            tokens.append(canonicalToken(range: NSRange(location: range.location + 1, length: range.length - 1), syntaxID: .preprocessor))
        } else if text.hasPrefix("_"), text.count > 1 {
            tokens.append(canonicalToken(range: NSRange(location: range.location, length: 1), syntaxID: .preprocessor))
            tokens.append(canonicalToken(range: NSRange(location: range.location + 1, length: range.length - 1), syntaxID: .preprocessor))
        } else {
            tokens.append(canonicalToken(range: range, syntaxID: .preprocessor))
        }
    }

    private static func isPreprocessorLine(containing range: NSRange, in source: NSString) -> Bool {
        guard range.location >= 0, range.location <= source.length else {
            return false
        }
        let lineRange = source.lineRange(for: NSRange(location: min(range.location, max(0, source.length - 1)), length: 0))
        return source.substring(with: lineRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("#")
    }

    private static func isSwiftIdentifier(_ text: String) -> Bool {
        swiftIdentifierRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        )?.range == NSRange(location: 0, length: (text as NSString).length)
    }

    private static func isSwiftSemanticOverlayToken(_ token: SyntaxHighlightToken) -> Bool {
        guard token.language == .swift || token.language == nil else {
            return false
        }
        switch token.syntaxID {
        case .identifierType,
             .identifierTypeSystem,
             .identifierFunction,
             .identifierMacro,
             .identifierConstant,
             .identifierVariable:
            return true
        default:
            return false
        }
    }

    private static let swiftIdentifierRegex = try! NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_]*$"#
    )

    private static let knownExternalTypeNames: Set<String> = [
        "Bool", "ClosedRange", "Double", "Float", "Int", "StaticString", "String", "UInt"
    ]
}

private struct SwiftSemanticTokenContext {
    let source: NSString
    let range: NSRange
    let text: String
    let line: NSString
    let before: String
    let after: String

    init(source: NSString, range: NSRange, text: String) {
        self.source = source
        self.range = range
        self.text = text

        let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
        let line = source.substring(with: lineRange) as NSString
        let relativeLocation = max(0, range.location - lineRange.location)
        let afterLocation = min(line.length, relativeLocation + range.length)

        self.line = line
        self.before = line.substring(to: min(relativeLocation, line.length))
        self.after = line.substring(from: afterLocation)
    }

    var startsLikeTypeName: Bool {
        text.first?.isUppercase == true
    }

    var isImportLine: Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("import ")
    }

    var isAttributeContext: Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.hasPrefix("@") else {
            return false
        }
        guard before.contains("@") else {
            return false
        }
        return Self.declarationKeywordAfterAttributeRegex.firstMatch(
            in: before,
            range: NSRange(location: 0, length: (before as NSString).length)
        ) == nil
    }

    var isDeclarationContext: Bool {
        Self.declarationPrefixRegex.firstMatch(
            in: before,
            range: NSRange(location: 0, length: (before as NSString).length)
        ) != nil
    }

    var isPatternBindingDeclarationContext: Bool {
        Self.patternBindingDeclarationPrefixRegex.firstMatch(
            in: before,
            range: NSRange(location: 0, length: (before as NSString).length)
        ) != nil
            || Self.valuePatternDeclarationPrefixRegex.firstMatch(
                in: before,
                range: NSRange(location: 0, length: (before as NSString).length)
            ) != nil
    }

    var isLabel: Bool {
        after.trimmingCharacters(in: .whitespaces).hasPrefix(":")
            && previousNonWhitespace != "["
            && !isTernaryTrueOperand
    }

    var isCallArgumentValueContext: Bool {
        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        guard trimmedBefore.hasSuffix(":"),
              !isTernaryTrueOperand
        else {
            return false
        }

        return nearestUnclosedDelimiter(in: String(trimmedBefore.dropLast())) == "("
    }

    var isTernaryTrueOperand: Bool {
        containsTernaryQuestionAtCurrentNesting
    }

    var isMacroInvocation: Bool {
        previousNonWhitespace == "#"
    }

    var isMemberAccess: Bool {
        previousNonWhitespace == "."
    }

    var isSelfMemberAccess: Bool {
        before.trimmingCharacters(in: .whitespaces).hasSuffix("self.")
    }

    var isFunctionCall: Bool {
        after.trimmingCharacters(in: .whitespaces).hasPrefix("(")
    }

    var isAssignmentExpressionContext: Bool {
        before.trimmingCharacters(in: .whitespaces).hasSuffix("=")
            && Self.typeDeclarationAssignmentPrefixRegex.firstMatch(
                in: before,
                range: NSRange(location: 0, length: (before as NSString).length)
            ) == nil
    }

    private var containsTernaryQuestionAtCurrentNesting: Bool {
        let targetDepth = nestingDepth(in: Array(before))
        var depth = NestingDepth()
        let characters = Array(before)

        for index in characters.indices {
            let character = characters[index]
            if character == "?",
               depth == targetDepth,
               !isOptionalQuestion(at: index, in: characters)
            {
                return true
            }
            depth.apply(character)
        }

        return false
    }

    private func nestingDepth(in characters: [Character]) -> NestingDepth {
        var depth = NestingDepth()
        for character in characters {
            depth.apply(character)
        }
        return depth
    }

    private func isOptionalQuestion(at index: Int, in characters: [Character]) -> Bool {
        if characters.index(after: index) < characters.endIndex,
           characters[characters.index(after: index)] == "?"
        {
            return true
        }

        if nextNonWhitespaceCharacter(after: index, in: characters) == "." {
            return true
        }

        return previousIdentifier(before: index, in: characters) == "try"
    }

    private func nextNonWhitespaceCharacter(after index: Int, in characters: [Character]) -> Character? {
        var scan = characters.index(after: index)
        while scan < characters.endIndex {
            let character = characters[scan]
            if character != " " && character != "\t" {
                return character
            }
            scan = characters.index(after: scan)
        }
        return nil
    }

    private func nearestUnclosedDelimiter(in text: String) -> Character? {
        var stack: [Character] = []
        for character in text {
            switch character {
            case "(", "[", "{":
                stack.append(character)
            case ")":
                if stack.last == "(" { stack.removeLast() }
            case "]":
                if stack.last == "[" { stack.removeLast() }
            case "}":
                if stack.last == "{" { stack.removeLast() }
            default:
                break
            }
        }
        return stack.last
    }

    private func previousIdentifier(before index: Int, in characters: [Character]) -> String? {
        var scan = index
        var identifier = ""
        while scan > characters.startIndex {
            scan = characters.index(before: scan)
            let character = characters[scan]
            if character == " " || character == "\t" {
                if identifier.isEmpty {
                    continue
                }
                break
            }
            guard character.isLetter || character.isNumber || character == "_" else {
                break
            }
            identifier.insert(character, at: identifier.startIndex)
        }
        return identifier.isEmpty ? nil : identifier
    }

    var isTypeContext: Bool {
        if startsLikeTypeName && isFunctionCall {
            return true
        }

        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        if trimmedBefore.hasSuffix(":")
            || trimmedBefore.hasSuffix("=")
            || trimmedBefore.hasSuffix("->")
            || trimmedBefore.hasSuffix("<")
            || trimmedBefore.hasSuffix("[")
            || trimmedBefore.hasSuffix("(")
            || trimmedBefore.hasSuffix(",")
            || trimmedBefore.hasSuffix("&") {
            return startsLikeTypeName
        }

        if startsLikeTypeName,
           Self.castTypePrefixRegex.firstMatch(
            in: trimmedBefore,
            range: NSRange(location: 0, length: (trimmedBefore as NSString).length)
           ) != nil {
            return true
        }

        if startsLikeTypeName,
           isMemberAccess == false,
           after.trimmingCharacters(in: .whitespaces).hasPrefix(".") {
            return true
        }

        return false
    }

    var isInsideStringInterpolation: Bool {
        guard let opener = before.range(of: "\\(", options: .backwards) else {
            return false
        }
        let suffix = before[opener.upperBound...]
        return suffix.contains(")") == false
    }

    private var previousNonWhitespace: Character? {
        before.reversed().first { !$0.isWhitespace }
    }

    private static let declarationPrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:let|var|func|macro|class|struct|enum|actor|protocol|typealias|associatedtype)\s+$"#
    )

    private static let declarationKeywordAfterAttributeRegex = try! NSRegularExpression(
        pattern: #"\b(?:let|var|func|macro|class|struct|enum|actor|protocol|typealias|associatedtype)\b"#
    )

    private static let typeDeclarationAssignmentPrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:typealias|associatedtype)\b"#
    )

    private static let patternBindingDeclarationPrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:for\s+(?:case\s+)?(?:let\s+|var\s+)?|case\s+(?:let\s+|var\s+)|case\s+(?:let|var)\b[^\n]*\(|case\b[^\n]*\(\s*(?:let|var)\s+|catch\s+(?:let\s+|var\s+)?)$"#
    )
    private static let valuePatternDeclarationPrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:let|var)\b[^=:\n]*$"#
    )

    private static let castTypePrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:as\?|as!|as|is)$"#
    )
}

private struct NestingDepth: Equatable {
    var paren = 0
    var bracket = 0
    var brace = 0

    mutating func apply(_ character: Character) {
        switch character {
        case "(":
            paren += 1
        case ")":
            paren = max(0, paren - 1)
        case "[":
            bracket += 1
        case "]":
            bracket = max(0, bracket - 1)
        case "{":
            brace += 1
        case "}":
            brace = max(0, brace - 1)
        default:
            break
        }
    }
}

enum SyntaxHighlightTokenOrdering {
    static func displayOrder(_ lhs: SyntaxHighlightToken, _ rhs: SyntaxHighlightToken) -> Bool {
        if lhs.range.location != rhs.range.location {
            return lhs.range.location < rhs.range.location
        }

        if lhs.range.length != rhs.range.length {
            return lhs.range.length > rhs.range.length
        }

        let lhsPriority = renderPriority(lhs)
        let rhsPriority = renderPriority(rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        let lhsSpecificity = lhs.syntaxID.rawValue.split(separator: ".").count
        let rhsSpecificity = rhs.syntaxID.rawValue.split(separator: ".").count
        if lhsSpecificity != rhsSpecificity {
            return lhsSpecificity < rhsSpecificity
        }

        return lhs.rawCaptureName < rhs.rawCaptureName
    }

    private static func renderPriority(_ token: SyntaxHighlightToken) -> Int {
        let value = token.syntaxID.rawValue
        if value == "plain" {
            return 0
        }
        if value == "comment" || value == "string" {
            return 1
        }
        if value.hasPrefix("comment.doc") || value == "mark" || value == "url" {
            return 7
        }
        if value.hasPrefix("declaration.") || value == "identifier.macro" {
            return 6
        }
        if value == "keyword" || value == "preprocessor" {
            return 5
        }
        if value.contains(".type") || value.contains(".class") {
            return 4
        }
        if value.contains(".function") || value.contains(".macro") {
            return 3
        }
        if value == "attribute" || value.contains(".variable") || value.contains(".constant") {
            return 2
        }
        return 2
    }
}
