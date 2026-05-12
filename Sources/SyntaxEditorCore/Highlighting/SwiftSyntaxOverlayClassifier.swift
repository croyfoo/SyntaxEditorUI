import Foundation

// Adds Swift-specific semantic overlays that Tree-sitter captures do not
// provide directly. This does not resolve project or same-file symbols.
enum SwiftSyntaxOverlayClassifier {
    static func classify(
        tokens: [SyntaxHighlightToken],
        source: String,
        refreshRange: NSRange? = nil
    ) -> [SyntaxHighlightToken] {
        let nsSource = source as NSString
        let classificationRange = refreshRange.map {
            lineEnvelopeRange(containing: $0, in: nsSource)
        }
        let declarationRanges = Set(
            tokens
                .filter { $0.rawCaptureName.lowercased().hasPrefix("declaration.swift.") }
                .map { rangeKey($0.range) }
        )

        let classified = tokens.map { token in
            if let classificationRange,
               SyntaxEditorRangeUtilities.intersection(of: token.range, and: classificationRange).length == 0 {
                return token
            }

            guard token.range.location >= 0,
                  token.range.length > 0,
                  token.range.upperBound <= nsSource.length,
                  declarationRanges.contains(rangeKey(token.range)) == false
            else {
                return token
            }

            let text = nsSource.substring(with: token.range)
            guard text.isEmpty == false else { return token }

            let captureName = token.rawCaptureName.lowercased()
            let nextCaptureName: String?
            if shouldTreatAsPlainAttributeArgument(text, token: token, captureName: captureName, in: nsSource) {
                nextCaptureName = "identifier.swift.argument.label"
            } else if (captureName == "type.swift.reference" || captureName == "variable"),
               isImportName(token, in: nsSource)
            {
                nextCaptureName = "identifier.swift.import.name"
            } else if captureName == "type.swift.reference" {
                nextCaptureName = "identifier.swift.other.type"
            } else if captureName == "variable.parameter", text.first?.isUppercase == true {
                nextCaptureName = "identifier.swift.other.type"
            } else if captureName == "function.swift.call" {
                if isArgumentLabel(token, in: nsSource) {
                    nextCaptureName = "identifier.swift.argument.label"
                } else if text.first?.isUppercase == true {
                    nextCaptureName = "identifier.swift.other.type"
                } else {
                    nextCaptureName = "identifier.swift.other.function"
                }
            } else if captureName == "function.swift.macro" {
                nextCaptureName = "identifier.swift.other.macro"
            } else if captureName == "attribute.swift.name" {
                nextCaptureName = "identifier.swift.other.type"
            } else if captureName == "variable.member" {
                if isArgumentLabel(token, in: nsSource) {
                    nextCaptureName = "identifier.swift.argument.label"
                } else {
                    nextCaptureName = "identifier.swift.other.property"
                }
            } else if captureName == "variable", isArgumentLabel(token, in: nsSource) {
                nextCaptureName = "identifier.swift.argument.label"
            } else {
                nextCaptureName = nil
            }

            guard let nextCaptureName else { return token }
            return SyntaxHighlightToken(range: token.range, rawCaptureName: nextCaptureName)
        }

        let augmented = classified + semanticOverlayTokens(
            in: source,
            existingTokens: classified,
            targetRange: classificationRange
        )
        return deduplicated(augmented.sorted(by: SyntaxHighlightTokenOrdering.displayOrder))
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

    private static func isArgumentLabel(_ token: SyntaxHighlightToken, in source: NSString) -> Bool {
        var location = token.range.upperBound
        while location < source.length {
            let character = source.character(at: location)
            if character == 58 {
                return true
            }
            guard character == 9 || character == 32 else {
                return false
            }
            location += 1
        }
        return false
    }

    private static func shouldTreatAsPlainAttributeArgument(
        _ text: String,
        token: SyntaxHighlightToken,
        captureName: String,
        in source: NSString
    ) -> Bool {
        guard captureName == "function.swift.call"
            || captureName == "type.swift.reference"
            || captureName == "variable"
            || captureName == "variable.member"
        else {
            return false
        }
        guard swiftKeywordNames.contains(text) == false else {
            return false
        }
        return isInsideAttributeArgumentList(token, in: source)
    }

    private static func isInsideAttributeArgumentList(_ token: SyntaxHighlightToken, in source: NSString) -> Bool {
        let lineRange = source.lineRange(for: NSRange(location: token.range.location, length: 0))
        let line = source.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@attached(") || trimmed.hasPrefix("@freestanding(") else {
            return false
        }

        let lineStart = lineRange.location
        let openRange = source.range(of: "(", options: [], range: lineRange)
        let closeRange = source.range(of: ")", options: .backwards, range: lineRange)
        guard openRange.location != NSNotFound,
              closeRange.location != NSNotFound
        else {
            return false
        }

        let tokenStart = token.range.location
        return tokenStart > openRange.location
            && tokenStart < closeRange.location
            && tokenStart >= lineStart
    }

    private static func isImportName(_ token: SyntaxHighlightToken, in source: NSString) -> Bool {
        let lineRange = source.lineRange(for: NSRange(location: token.range.location, length: 0))
        guard token.range.location >= lineRange.location else { return false }

        let prefixRange = NSRange(location: lineRange.location, length: token.range.location - lineRange.location)
        var prefix = source.substring(with: prefixRange)
            .trimmingCharacters(in: .whitespaces)

        if prefix.hasPrefix("@") {
            guard let importRange = prefix.range(of: " import ") else {
                return prefix.hasSuffix(" import")
            }
            prefix = String(prefix[importRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            return prefix.isEmpty || prefix.allSatisfy(\.isSwiftImportPathCharacter)
        }

        guard prefix == "import" || prefix.hasPrefix("import ") else {
            return false
        }

        let importKindNames: Set<String> = [
            "class",
            "enum",
            "func",
            "protocol",
            "struct",
            "typealias",
            "var",
        ]
        var remainder = prefix.dropFirst("import".count)
            .trimmingCharacters(in: .whitespaces)
        if let firstWord = remainder.split(whereSeparator: \.isWhitespace).first,
           importKindNames.contains(String(firstWord)) {
            remainder = remainder.dropFirst(firstWord.count)
                .trimmingCharacters(in: .whitespaces)
        }

        return remainder.isEmpty || remainder.allSatisfy(\.isSwiftImportPathCharacter)
    }

    private static func braceBodyRange(
        openingBraceLocation: Int,
        in source: NSString,
        existingTokens: [SyntaxHighlightToken]
    ) -> NSRange? {
        var depth = 0
        var location = openingBraceLocation
        while location < source.length {
            let characterRange = NSRange(location: location, length: 1)
            if isInsideLiteralOrComment(characterRange, existingTokens: existingTokens) {
                location += 1
                continue
            }

            let character = source.character(at: location)
            if character == 123 {
                depth += 1
            } else if character == 125 {
                depth -= 1
                if depth == 0 {
                    return NSRange(
                        location: openingBraceLocation + 1,
                        length: location - openingBraceLocation - 1
                    )
                }
            }
            location += 1
        }
        return nil
    }

    private static func semanticOverlayTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        let searchRange = targetRange.map {
            SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: nsSource.length)
        } ?? fullRange
        guard searchRange.length > 0 else {
            return []
        }

        var tokens: [SyntaxHighlightToken] = []

        var location = searchRange.location
        while location < searchRange.upperBound {
            let remainingRange = NSRange(location: location, length: searchRange.upperBound - location)
            let lineRange = nsSource.lineRange(for: NSRange(location: location, length: 0))
            let clampedLineRange = NSIntersectionRange(lineRange, remainingRange)
            guard clampedLineRange.length > 0 else { break }

            let line = nsSource.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("// MARK:"),
               let markRange = substringRange("MARK:", in: nsSource, lineRange: clampedLineRange) {
                tokens.append(SyntaxHighlightToken(range: markRange, rawCaptureName: "comment.mark"))
            }

            if trimmed.hasPrefix("///") || trimmed.hasPrefix("/**") || trimmed.hasPrefix("*") {
                for keyword in documentationMarkupKeywords {
                    guard let keywordRange = substringRange("\(keyword):", in: nsSource, lineRange: clampedLineRange) else {
                        continue
                    }
                    tokens.append(SyntaxHighlightToken(
                        range: NSRange(location: keywordRange.location, length: keyword.utf16.count),
                        rawCaptureName: "comment.documentation.keyword"
                    ))
                }
            }

            tokens.append(contentsOf: urlTokens(in: nsSource, lineRange: clampedLineRange))
            location = clampedLineRange.location + clampedLineRange.length
        }

        tokens.append(contentsOf: declarationTokens(
            in: source,
            existingTokens: existingTokens,
            targetRange: searchRange
        ))
        tokens.append(contentsOf: attributeTokens(
            in: source,
            existingTokens: existingTokens,
            targetRange: searchRange
        ))
        tokens.append(contentsOf: keywordTokens(
            in: source,
            existingTokens: existingTokens,
            targetRange: searchRange
        ))
        return tokens
    }

    private static var documentationMarkupKeywords: [String] {
        [
            "Attention",
            "Author",
            "Authors",
            "Bug",
            "Complexity",
            "Copyright",
            "Date",
            "Experiment",
            "Important",
            "Invariant",
            "Note",
            "Parameter",
            "Parameters",
            "Postcondition",
            "Precondition",
            "Remark",
            "Requires",
            "Returns",
            "See Also",
            "Since",
            "Throws",
            "Todo",
            "Version",
            "Warning",
        ]
    }

    private static func substringRange(
        _ substring: String,
        in source: NSString,
        lineRange: NSRange
    ) -> NSRange? {
        let range = source.range(of: substring, options: [], range: lineRange)
        return range.location == NSNotFound ? nil : range
    }

    private static func urlTokens(in source: NSString, lineRange: NSRange) -> [SyntaxHighlightToken] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s\])>"]+"#) else {
            return []
        }

        return regex.matches(in: source as String, range: lineRange).map {
            SyntaxHighlightToken(range: $0.range, rawCaptureName: "text.uri")
        }
    }

    private static func keywordTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [SyntaxHighlightToken] {
        precedenceGroupKeywordTokens(in: source, existingTokens: existingTokens, targetRange: targetRange)
            + contextualKeywordTokens(in: source, existingTokens: existingTokens, targetRange: targetRange)
            + compilerDirectiveKeywordTokens(in: source, existingTokens: existingTokens, targetRange: targetRange)
            + compilerDirectiveLineTokens(in: source, existingTokens: existingTokens, targetRange: targetRange)
            + availabilityKeywordTokens(in: source, existingTokens: existingTokens, targetRange: targetRange)
    }

    private static func declarationTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [SyntaxHighlightToken] {
        typeDeclarations(in: source, existingTokens: existingTokens, targetRange: targetRange).map {
            SyntaxHighlightToken(range: $0.range, rawCaptureName: "declaration.swift.type.name")
        }
        + functionDeclarations(in: source, existingTokens: existingTokens, targetRange: targetRange).map {
            SyntaxHighlightToken(range: $0.range, rawCaptureName: "declaration.swift.function.name")
        }
        + typeAliasLikeDeclarations(in: source, existingTokens: existingTokens, targetRange: targetRange).map {
            SyntaxHighlightToken(range: $0.range, rawCaptureName: "declaration.swift.other.name")
        }
        + macroDeclarations(in: source, existingTokens: existingTokens, targetRange: targetRange).map {
            SyntaxHighlightToken(range: $0.range, rawCaptureName: "declaration.swift.macro.name")
        }
        + precedenceGroupDeclarations(in: source, existingTokens: existingTokens, targetRange: targetRange).map {
            SyntaxHighlightToken(range: $0.range, rawCaptureName: "declaration.swift.type.name")
        }
    }

    private static func typeDeclarations(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [(name: String, range: NSRange)] {
        declarationNames(
            pattern: #"\b(?:actor|class|enum|protocol|struct)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            in: source,
            existingTokens: existingTokens,
            targetRange: targetRange
        )
        + declarationNames(
            pattern: #"\bextension\s+([A-Za-z_][A-Za-z0-9_\.]*)"#,
            in: source,
            existingTokens: existingTokens,
            targetRange: targetRange
        )
    }

    private static func functionDeclarations(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [(name: String, range: NSRange)] {
        declarationNames(
            pattern: #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            in: source,
            existingTokens: existingTokens,
            targetRange: targetRange
        )
    }

    private static func attributeTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [SyntaxHighlightToken] {
        let names = swiftPredefinedAttributeNames
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: #"@("# + names + #")\b"#) else {
            return []
        }

        return regex.matches(in: source, range: targetRange).flatMap { match -> [SyntaxHighlightToken] in
            let punctuationRange = NSRange(location: match.range.location, length: 1)
            let nameRange = match.range(at: 1)
            guard isInsideLiteralOrComment(match.range, existingTokens: existingTokens) == false else {
                return []
            }
            return [
                SyntaxHighlightToken(
                    range: punctuationRange,
                    rawCaptureName: "keyword.swift.attribute.builtin.punctuation"
                ),
                SyntaxHighlightToken(
                    range: nameRange,
                    rawCaptureName: "keyword.swift.attribute.builtin"
                ),
            ]
        }
    }

    private static var swiftPredefinedAttributeNames: [String] {
        [
            "available",
            "backDeployed",
            "discardableResult",
            "dynamicCallable",
            "dynamicMemberLookup",
            "frozen",
            "GKInspectable",
            "inlinable",
            "main",
            "nonobjc",
            "NSApplicationMain",
            "NSCopying",
            "NSManaged",
            "objc",
            "objcMembers",
            "preconcurrency",
            "propertyWrapper",
            "resultBuilder",
            "requires_stored_property_inits",
            "testable",
            "UIApplicationMain",
            "unchecked",
            "usableFromInline",
            "warn_unqualified_access",
            "IBAction",
            "IBSegueAction",
            "IBOutlet",
            "IBDesignable",
            "IBInspectable",
            "attached",
            "autoclosure",
            "convention",
            "escaping",
            "freestanding",
            "Sendable",
            "unknown",
        ]
    }

    private static func typeAliasLikeDeclarations(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [(name: String, range: NSRange)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(?:associatedtype|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        ) else {
            return []
        }

        let nsSource = source as NSString
        return regex.matches(in: source, range: targetRange).compactMap { match in
            let range = match.range(at: 1)
            guard range.location != NSNotFound,
                  isInsideLiteralOrComment(range, existingTokens: existingTokens) == false
            else {
                return nil
            }
            return (nsSource.substring(with: range), range)
        }
    }

    private static func macroDeclarations(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [(name: String, range: NSRange)] {
        declarationNames(
            pattern: #"\bmacro\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            in: source,
            existingTokens: existingTokens,
            targetRange: targetRange
        )
    }

    private static func precedenceGroupDeclarations(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [(name: String, range: NSRange)] {
        declarationNames(
            pattern: #"\bprecedencegroup\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            in: source,
            existingTokens: existingTokens,
            targetRange: targetRange
        )
    }

    private static func declarationNames(
        pattern: String,
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [(name: String, range: NSRange)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsSource = source as NSString
        return regex.matches(in: source, range: targetRange).compactMap { match in
            let range = match.range(at: 1)
            guard range.location != NSNotFound,
                  isInsideLiteralOrComment(range, existingTokens: existingTokens) == false
            else {
                return nil
            }
            return (nsSource.substring(with: range), range)
        }
    }

    private static func precedenceGroupKeywordTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [SyntaxHighlightToken] {
        let bodyRanges = precedenceGroupBodyRanges(
            in: source,
            existingTokens: existingTokens,
            targetRange: targetRange
        )

        let tokens = regexTokens(
            pattern: #"(?m)^[ \t]*(associativity|assignment|higherThan|lowerThan)(?=[ \t]*:)"#,
            captureGroup: 1,
            captureName: "keyword",
            in: source,
            ranges: bodyRanges,
            existingTokens: existingTokens
        )
        + regexTokens(
            pattern: #"(?m)^[ \t]*associativity[ \t]*:[ \t]*(left|right|none)\b"#,
            captureGroup: 1,
            captureName: "keyword",
            in: source,
            ranges: bodyRanges,
            existingTokens: existingTokens
        )
        + regexTokens(
            pattern: #"(?m)^[ \t]*(?:higherThan|lowerThan)[ \t]*:[ \t]*([A-Za-z_][A-Za-z0-9_]*)\b"#,
            captureGroup: 1,
            captureName: "identifier.swift.other.type",
            in: source,
            ranges: bodyRanges,
            existingTokens: existingTokens
        )
        guard bodyRanges.count == 1, bodyRanges[0] == targetRange else {
            return tokens
        }
        let nsSource = source as NSString
        return tokens.filter {
            isInsidePrecedenceGroupBody(
                location: $0.range.location,
                in: nsSource,
                existingTokens: existingTokens
            )
        }
    }

    private static func precedenceGroupBodyRanges(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        guard targetRange == fullRange else {
            return [targetRange]
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"\bprecedencegroup\s+[A-Za-z_][A-Za-z0-9_]*\s*\{"#
        ) else {
            return []
        }

        let nsSource = source as NSString
        return regex.matches(in: source, range: fullRange).compactMap { match in
            let openingBraceLocation = match.range.location + match.range.length - 1
            let openingBraceRange = NSRange(location: openingBraceLocation, length: 1)
            guard isInsideLiteralOrComment(openingBraceRange, existingTokens: existingTokens) == false else {
                return nil
            }

            return braceBodyRange(
                openingBraceLocation: openingBraceLocation,
                in: nsSource,
                existingTokens: existingTokens
            )
        }
    }

    private static func isInsidePrecedenceGroupBody(
        location originalLocation: Int,
        in source: NSString,
        existingTokens: [SyntaxHighlightToken]
    ) -> Bool {
        guard source.length > 0 else { return false }

        var depth = 0
        var location = min(max(0, originalLocation - 1), source.length - 1)
        while true {
            let characterRange = NSRange(location: location, length: 1)
            if isInsideLiteralOrComment(characterRange, existingTokens: existingTokens) == false {
                let character = source.character(at: location)
                if character == 125 {
                    depth += 1
                } else if character == 123 {
                    if depth == 0 {
                        return lineBeforeOpeningBraceDeclaresPrecedenceGroup(
                            openingBraceLocation: location,
                            in: source
                        )
                    }
                    depth -= 1
                }
            }

            guard location > 0 else { return false }
            location -= 1
        }
    }

    private static func lineBeforeOpeningBraceDeclaresPrecedenceGroup(
        openingBraceLocation: Int,
        in source: NSString
    ) -> Bool {
        let lineRange = source.lineRange(for: NSRange(location: openingBraceLocation, length: 0))
        let prefixRange = NSRange(
            location: lineRange.location,
            length: openingBraceLocation - lineRange.location
        )
        let prefix = source.substring(with: prefixRange)
        return prefix.range(
            of: #"\bprecedencegroup\s+[A-Za-z_][A-Za-z0-9_]*\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func regexTokens(
        pattern: String,
        captureGroup: Int,
        captureName: String,
        in source: String,
        ranges: [NSRange],
        existingTokens: [SyntaxHighlightToken]
    ) -> [SyntaxHighlightToken] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return ranges.flatMap { range in
            regex.matches(in: source, range: range).compactMap { match in
                let tokenRange = match.range(at: captureGroup)
                guard tokenRange.location != NSNotFound,
                      isInsideLiteralOrComment(tokenRange, existingTokens: existingTokens) == false
                else {
                    return nil
                }
                return SyntaxHighlightToken(range: tokenRange, rawCaptureName: captureName)
            }
        }
    }

    private static func contextualKeywordTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [SyntaxHighlightToken] {
        regexTokens(
            pattern: #"(?m)(?:^[ \t]*|[{\n;][ \t]*)(defer)(?=[ \t]*\{)"#,
            captureGroup: 1,
            captureName: "keyword.swift.statement.reserved",
            in: source,
            ranges: [targetRange],
            existingTokens: existingTokens
        )
        + regexTokens(
            pattern: #"\bisolated\b(?=[ \t]+deinit\b)"#,
            captureGroup: 0,
            captureName: "keyword.swift.modifier.contextual",
            in: source,
            ranges: [targetRange],
            existingTokens: existingTokens
        )
    }

    private static func compilerDirectiveKeywordTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [SyntaxHighlightToken] {
        regexTokens(
            pattern: #"(?m)^[ \t]*(#(?:if|elseif|else|endif))\b"#,
            captureGroup: 1,
            captureName: "keyword.directive",
            in: source,
            ranges: [targetRange],
            existingTokens: existingTokens
        )
    }

    private static func compilerDirectiveLineTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [SyntaxHighlightToken] {
        let directiveConditionRanges = directiveConditionRanges(in: source, targetRange: targetRange)
        return regexTokens(
            pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\b|\d+|>=|<=|==|!=|>|<|&&|\|\||!|[.:(),]"#,
            captureGroup: 0,
            captureName: "keyword.directive.condition.swift",
            in: source,
            ranges: directiveConditionRanges,
            existingTokens: existingTokens
        )
    }

    private static func directiveConditionRanges(in source: String, targetRange: NSRange) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^[ \t]*#(?:if|elseif)\b([^\n]*)"#) else {
            return []
        }
        return regex.matches(in: source, range: targetRange).compactMap { match in
            let range = match.range(at: 1)
            return range.location == NSNotFound ? nil : range
        }
    }

    private static func availabilityKeywordTokens(
        in source: String,
        existingTokens: [SyntaxHighlightToken],
        targetRange: NSRange
    ) -> [SyntaxHighlightToken] {
        regexTokens(
            pattern: #"#(?:available|unavailable)\b"#,
            captureGroup: 0,
            captureName: "keyword.swift.availability",
            in: source,
            ranges: [targetRange],
            existingTokens: existingTokens
        )
        + regexTokens(
            pattern: #"(#)(?:available|unavailable)\b"#,
            captureGroup: 1,
            captureName: "keyword.swift.availability.punctuation",
            in: source,
            ranges: [targetRange],
            existingTokens: existingTokens
        )
        + regexTokens(
            pattern: #"#(available|unavailable)\b"#,
            captureGroup: 1,
            captureName: "keyword.swift.availability",
            in: source,
            ranges: [targetRange],
            existingTokens: existingTokens
        )
    }

    private static var swiftKeywordNames: Set<String> {
        [
            "Any",
            "Protocol",
            "Self",
            "Type",
            "actor",
            "associatedtype",
            "class",
            "deinit",
            "enum",
            "extension",
            "func",
            "import",
            "init",
            "macro",
            "operator",
            "precedencegroup",
            "protocol",
            "struct",
            "subscript",
            "typealias",
            "associativity",
            "assignment",
            "higherThan",
            "lowerThan",
            "async",
            "convenience",
            "didSet",
            "dynamic",
            "final",
            "get",
            "indirect",
            "infix",
            "lazy",
            "left",
            "mutating",
            "none",
            "nonmutating",
            "optional",
            "override",
            "package",
            "postfix",
            "precedence",
            "prefix",
            "required",
            "right",
            "set",
            "some",
            "unowned",
            "weak",
            "willSet",
            "break",
            "case",
            "catch",
            "continue",
            "default",
            "defer",
            "do",
            "else",
            "fallthrough",
            "for",
            "guard",
            "if",
            "in",
            "repeat",
            "return",
            "switch",
            "throw",
            "where",
            "while",
            "as",
            "await",
            "false",
            "is",
            "nil",
            "self",
            "super",
            "throws",
            "true",
            "try",
            "_",
        ]
    }

    private static func isInsideLiteralOrComment(
        _ range: NSRange,
        existingTokens: [SyntaxHighlightToken]
    ) -> Bool {
        existingTokens.contains { token in
            let captureName = token.rawCaptureName.lowercased()
            guard captureName.hasPrefix("comment")
                || captureName.hasPrefix("string")
                || captureName.contains("regex")
            else {
                return false
            }

            return NSLocationInRange(range.location, token.range)
                && NSMaxRange(range) <= NSMaxRange(token.range)
        }
    }
}

private extension Character {
    var isSwiftImportPathCharacter: Bool {
        isLetter || isNumber || self == "_" || self == "."
    }
}

enum SyntaxHighlightTokenOrdering {
    static func displayOrder(_ lhs: SyntaxHighlightToken, _ rhs: SyntaxHighlightToken) -> Bool {
        if lhs.range.location != rhs.range.location {
            return lhs.range.location < rhs.range.location
        }

        let lhsSpecificity = lhs.rawCaptureName.split(separator: ".").count
        let rhsSpecificity = rhs.rawCaptureName.split(separator: ".").count
        if lhsSpecificity != rhsSpecificity {
            return lhsSpecificity < rhsSpecificity
        }

        if lhs.range.length != rhs.range.length {
            return lhs.range.length > rhs.range.length
        }

        let lhsPriority = renderPriority(lhs.rawCaptureName)
        let rhsPriority = renderPriority(rhs.rawCaptureName)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.rawCaptureName < rhs.rawCaptureName
    }

    private static func renderPriority(_ captureName: String) -> Int {
        let name = captureName.lowercased()
        if name == "variable" || name == "variable.parameter" {
            return 0
        }
        if name.hasPrefix("comment") || name.hasPrefix("string") {
            return 1
        }
        if name.hasPrefix("type.swift.reference")
            || name.hasPrefix("function.swift.call")
            || name.hasPrefix("attribute.swift")
        {
            return 2
        }
        if name.hasPrefix("keyword")
            || name.hasPrefix("identifier.swift")
            || name.hasPrefix("declaration.swift")
            || name.hasPrefix("text.uri")
        {
            return 3
        }
        return 2
    }
}
