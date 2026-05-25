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
        let prefix = linePrefix(before: range, in: source)
            .trimmingCharacters(in: .whitespaces)
        return prefix.hasSuffix("self.") || prefix.hasSuffix("self->")
    }

    private static func isMemberNameInKnownSelfChain(
        _ range: NSRange,
        in source: NSString,
        localProperties: Set<String>
    ) -> Bool {
        let prefix = linePrefix(before: range, in: source)
            .trimmingCharacters(in: .whitespaces)
        guard let match = selfMemberChainRegex.firstMatch(
            in: prefix,
            range: NSRange(location: 0, length: (prefix as NSString).length)
        ) else {
            return false
        }
        let firstMemberRange = match.range(at: 1)
        guard firstMemberRange.location != NSNotFound else {
            return false
        }
        let firstMember = (prefix as NSString).substring(with: firstMemberRange)
        return localProperties.contains(firstMember)
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

    private static let selfMemberChainRegex = try! NSRegularExpression(
        pattern: #"(?:^|[^A-Za-z0-9_])self(?:\.|->)([A-Za-z_][A-Za-z0-9_]*)(?:\.|->)(?:[A-Za-z_][A-Za-z0-9_]*(?:\.|->))*$"#
    )

    private static let keywordLikeTypeNames: Set<String> = [
        "BOOL", "IMP", "SEL", "id", "instancetype"
    ]
}

private struct ObjectiveCFileSymbolIndex {
    let localTypes: Set<String>
    let localFunctions: Set<String>
    let localProperties: Set<String>

    init(source: NSString, tokens: [SyntaxHighlightToken]) {
        var localTypes = Self.scanLocalTypes(source: source)
        var localFunctions = Set<String>()
        var localProperties = Self.scanLocalProperties(source: source)

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
                if Self.isZeroArgumentMethodName(token.range, in: source) {
                    localProperties.insert(text)
                }
            default:
                continue
            }
        }

        self.localTypes = localTypes
        self.localFunctions = localFunctions
        self.localProperties = localProperties
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

    private static func scanLocalProperties(source: NSString) -> Set<String> {
        let string = source as String
        let fullRange = NSRange(location: 0, length: source.length)
        var names = Set<String>()

        for match in propertyRegex.matches(in: string, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { continue }
            let name = source.substring(with: range)
            if isIdentifier(name) {
                names.insert(name)
            }
        }

        for match in blockPropertyRegex.matches(in: string, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { continue }
            let name = source.substring(with: range)
            if isIdentifier(name) {
                names.insert(name)
            }
        }

        for match in zeroArgumentMethodRegex.matches(in: string, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { continue }
            let name = source.substring(with: range)
            if isIdentifier(name) {
                names.insert(name)
            }
        }

        return names
    }

    private static func isZeroArgumentMethodName(_ range: NSRange, in source: NSString) -> Bool {
        let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
        let line = source.substring(with: lineRange)
        let lineNS = line as NSString
        let relativeRange = NSRange(location: range.location - lineRange.location, length: range.length)
        guard let match = zeroArgumentMethodRegex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: lineNS.length)
        ) else {
            return false
        }
        return NSIntersectionRange(match.range(at: 1), relativeRange).length > 0
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

    private static let propertyRegex = try! NSRegularExpression(
        pattern: #"@property\b[^;\n]*\b([A-Za-z_][A-Za-z0-9_]*)\s*;"#
    )

    private static let blockPropertyRegex = try! NSRegularExpression(
        pattern: #"@property\b[^;\n]*\(\s*\^\s*(?:[A-Za-z_][A-Za-z0-9_]*\s+)*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
    )

    private static let zeroArgumentMethodRegex = try! NSRegularExpression(
        pattern: #"(?m)^[ \t]*[-+]\s*\([^)]*\)\s*([A-Za-z_][A-Za-z0-9_]*)\s*[;{]"#
    )

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
