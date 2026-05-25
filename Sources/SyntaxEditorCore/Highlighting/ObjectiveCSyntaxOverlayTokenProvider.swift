import Foundation

enum ObjectiveCSyntaxOverlayTokenProvider {
    static func mergingOverlayTokens(
        tokens: [SyntaxHighlightToken],
        source: String
    ) -> [SyntaxHighlightToken] {
        let nsSource = source as NSString
        guard nsSource.length > 0 else {
            return objectiveCBaseTokens(from: tokens, source: nsSource)
        }

        let baseTokens = objectiveCBaseTokens(from: tokens, source: nsSource)
        let index = ObjectiveCFileSymbolIndex(source: nsSource, tokens: baseTokens)
        let overlayTokens = semanticTokens(from: baseTokens, source: nsSource, index: index)
        guard overlayTokens.isEmpty == false else {
            return baseTokens
        }

        return deduplicated(mergedTokens(baseTokens: baseTokens, overlayTokens: overlayTokens))
    }

    private static func semanticTokens(
        from tokens: [SyntaxHighlightToken],
        source: NSString,
        index: ObjectiveCFileSymbolIndex
    ) -> [SyntaxHighlightToken] {
        var overlayTokens: [SyntaxHighlightToken] = []
        overlayTokens.reserveCapacity(tokens.count / 4)

        for token in tokens {
            guard token.language == .objectiveC || token.language == nil,
                  token.range.location >= 0,
                  token.range.length > 0,
                  token.range.upperBound <= source.length
            else {
                continue
            }

            let text = source.substring(with: token.range)
            guard isObjectiveCIdentifier(text) else {
                continue
            }

            if index.containsPropertyDeclarationNameRange(token.range) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .declarationOther))
                continue
            }

            switch token.syntaxID {
            case .identifier:
                if isSelfMemberName(token.range, in: source),
                   index.localProperties.contains(text) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariable))
                } else if isMemberNameInKnownSelfChain(token.range, in: source, localProperties: index.localProperties) {
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

    private static func expressionPrefixEndsWithSelf(_ prefix: String) -> Bool {
        var trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if expressionPrefixDirectlyEndsWithSelf(trimmed) {
            return true
        }
        if parenthesizedSelfSuffixEndsWithSelf(trimmed) {
            return true
        }

        while let unwrapped = unwrappedOuterParentheses(trimmed) {
            trimmed = unwrapped
            if expressionPrefixDirectlyEndsWithSelf(trimmed) {
                return true
            }
        }

        return false
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
                        && expressionPrefixEndsWithSelf(inner)
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

    private static func unwrappedOuterParentheses(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "(", trimmed.last == ")" else {
            return nil
        }

        var depth = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0, trimmed.index(after: index) != trimmed.endIndex {
                    return nil
                }
                if depth < 0 {
                    return nil
                }
            }
            index = trimmed.index(after: index)
        }

        guard depth == 0 else {
            return nil
        }
        return String(trimmed.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keepsSelfChainConnected(_ suffix: String) -> Bool {
        var parenDepth = 0
        var bracketDepth = 0
        var index = suffix.startIndex

        while index < suffix.endIndex {
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

    private static func hasUnmatchedClosingDelimiter(_ suffix: String) -> Bool {
        var parenDepth = 0
        var bracketDepth = 0

        for character in suffix {
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
                continue
            }
        }

        return false
    }

    private static func hasUnmatchedClosingSquareBracket(_ suffix: String) -> Bool {
        var bracketDepth = 0

        for character in suffix {
            switch character {
            case "[":
                bracketDepth += 1
            case "]":
                if bracketDepth == 0 {
                    return true
                }
                bracketDepth -= 1
            default:
                continue
            }
        }

        return false
    }

    private static func containsOnlyClosingParenthesesAndWhitespace(_ suffix: String) -> Bool {
        suffix.allSatisfy { character in
            character == ")" || character.isWhitespace
        }
    }

    private static func hasUnmatchedOpeningDelimiter(_ suffix: String) -> Bool {
        var parenDepth = 0
        var bracketDepth = 0

        for character in suffix {
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
                continue
            }
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
        return !isObjectiveCIdentifierCharacter(previous)
            && previous != ")"
            && previous != "]"
            && previous != "["
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
        source: NSString
    ) -> [SyntaxHighlightToken] {
        var syntaxIDsByRange: [String: Set<EditorSourceSyntaxID>] = [:]
        for token in tokens where token.language == .objectiveC || token.language == nil {
            syntaxIDsByRange[rangeKey(token.range), default: []].insert(token.syntaxID)
        }

        return tokens.filter { token in
            !isObjectiveCSemanticOverlayToken(
                token,
                syntaxIDsAtSameRange: syntaxIDsByRange[rangeKey(token.range)] ?? [],
                source: source
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
        syntaxIDsAtSameRange: Set<EditorSourceSyntaxID>,
        source: NSString
    ) -> Bool {
        guard token.language == .objectiveC || token.language == nil else {
            return false
        }
        switch token.syntaxID {
        case .declarationType,
             .identifierConstantSystem:
            return true
        case .declarationOther:
            return syntaxIDsAtSameRange.contains(.identifierFunction)
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

    private static func isObjectiveCIdentifier(_ text: String) -> Bool {
        objectiveCIdentifierRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        ) != nil
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

    private static func rangeKey(_ range: NSRange) -> String {
        "\(range.location):\(range.length)"
    }

    private static let objectiveCIdentifierRegex = try! NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_]*$"#
    )

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
}

private struct ObjectiveCFileSymbolIndex {
    let localTypes: Set<String>
    let localFunctions: Set<String>
    let localProperties: Set<String>
    private let propertyDeclarationNameRanges: [NSRange]

    init(source: NSString, tokens: [SyntaxHighlightToken]) {
        var localTypes = Self.scanLocalTypes(source: source)
        var localFunctions = Set<String>()
        let propertyDeclarations = Self.scanLocalPropertyDeclarations(source: source, tokens: tokens)
        let zeroArgumentMethodNameRanges = Self.zeroArgumentMethodNameRanges(in: source)
        var localProperties = Set(propertyDeclarations.map { $0.name })

        for token in tokens {
            guard token.language == .objectiveC || token.language == nil,
                  token.range.location >= 0,
                  token.range.length > 0,
                  token.range.upperBound <= source.length
            else {
                continue
            }

            let text = source.substring(with: token.range)
            guard Self.isIdentifier(text) else {
                continue
            }

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

        self.localTypes = localTypes
        self.localFunctions = localFunctions
        self.localProperties = localProperties
        self.propertyDeclarationNameRanges = propertyDeclarations.map { $0.range }
    }

    func containsPropertyDeclarationNameRange(_ range: NSRange) -> Bool {
        propertyDeclarationNameRanges.contains { NSEqualRanges($0, range) }
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
            guard let relativeNameRange = propertyDeclaredNameRange(in: declaration) else {
                continue
            }
            let range = NSRange(
                location: match.range.location + relativeNameRange.location,
                length: relativeNameRange.length
            )
            let name = source.substring(with: range)
            if isIdentifier(name), isCodeIdentifierRange(range, tokens: tokens, source: source) {
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
        guard !typedefIgnoredIdentifiers.contains(previousName),
              let firstCharacter = previousName.first else {
            return false
        }
        return firstCharacter == "_" || firstCharacter.isLowercase
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
        identifierRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        ) != nil
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
        pattern: #"\(\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\([^;]*\)"#
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
