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
        let targetRange = refreshRange.map {
            lineEnvelopeRange(containing: $0, in: nsSource)
        }
        let overlayTokens =
            tokensInCommentLines(
                source: nsSource,
                existingTokens: tokens,
                targetRange: targetRange
            ) +
            tokensInPreprocessorLines(
                source: nsSource,
                existingTokens: tokens,
                targetRange: targetRange
            ) +
            tokensInSemanticSymbolRanges(
                source: nsSource,
                existingTokens: tokens,
                targetRange: targetRange
            )
        guard overlayTokens.isEmpty == false else {
            return tokens
        }

        return deduplicated((tokens + overlayTokens).sorted(by: SyntaxHighlightTokenOrdering.displayOrder))
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

        let propertyNames = currentFilePropertyNames(in: source)
        var tokens: [SyntaxHighlightToken] = []

        for token in existingTokens {
            guard token.language == .swift || token.language == nil,
                  token.syntaxID == .plain,
                  SyntaxEditorRangeUtilities.intersection(of: token.range, and: searchRange).length > 0,
                  token.range.upperBound <= source.length,
                  !isPreprocessorLine(containing: token.range, in: source)
            else {
                continue
            }

            let text = source.substring(with: token.range)
            if externalTypeNames.contains(text) {
                tokens.append(canonicalToken(range: token.range, syntaxID: .identifierTypeSystem))
            } else if propertyNames.contains(text),
                      isProjectVariableReference(text, range: token.range, in: source) {
                tokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariable))
            }
        }

        return tokens
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

    private static let propertyDeclarationRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:public|private|fileprivate|internal|open|package|static|class|final|weak|unowned|lazy|nonisolated|private\s*\(\s*set\s*\))\s+)*(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#
    )

    private static let functionStartRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:public|private|fileprivate|internal|open|package|static|class|final|mutating|nonmutating|override|isolated|nonisolated)\s+)*(?:func|init|subscript|deinit)\b"#
    )

    private static let externalTypeNames: Set<String> = [
        "ClosedRange", "Int", "StaticString", "String"
    ]

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

    private static func isInsideStringInterpolation(before: String) -> Bool {
        guard let opener = before.range(of: "\\(", options: .backwards) else {
            return false
        }
        let suffix = before[opener.upperBound...]
        return suffix.contains(")") == false
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

    private static func isProjectVariableReference(_ text: String, range: NSRange, in source: NSString) -> Bool {
        let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
        let line = source.substring(with: lineRange)
        let relativeLocation = range.location - lineRange.location
        let before = (line as NSString).substring(to: max(0, relativeLocation))
        let afterLocation = min((line as NSString).length, relativeLocation + range.length)
        let after = (line as NSString).substring(from: afterLocation)
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedLine.hasPrefix("@") {
            return false
        }
        if line.contains("self.") {
            return false
        }
        if isInsideStringInterpolation(before: before) {
            return false
        }
        if before.trimmingCharacters(in: .whitespaces).hasSuffix(".") {
            return false
        }
        if after.trimmingCharacters(in: .whitespaces).hasPrefix(":") {
            return false
        }
        if declarationPrefixRegex.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil {
            return false
        }

        return text.count > 2
    }

    private static func currentFilePropertyNames(in source: NSString) -> Set<String> {
        var names = Set<String>()
        var functionDepth = 0
        var location = 0

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange)
            let code = lineBeforeLineComment(in: line)
            let codeNSString = code as NSString
            let fullRange = NSRange(location: 0, length: codeNSString.length)

            if functionDepth == 0,
               let match = propertyDeclarationRegex.firstMatch(in: code, range: fullRange),
               match.numberOfRanges > 1 {
                let nameRange = match.range(at: 1)
                if nameRange.location != NSNotFound {
                    names.insert(codeNSString.substring(with: nameRange))
                }
            }

            let startsFunction = functionStartRegex.firstMatch(in: code, range: fullRange) != nil
            let delta = braceDelta(in: code)
            if functionDepth == 0, startsFunction {
                functionDepth = max(1, delta)
            } else if functionDepth > 0 {
                functionDepth = max(0, functionDepth + delta)
            }

            location = lineRange.upperBound
        }

        return names
    }

    private static func lineBeforeLineComment(in line: String) -> String {
        guard let range = line.range(of: "//") else {
            return line
        }
        return String(line[..<range.lowerBound])
    }

    private static let declarationPrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:let|var)\s+$"#
    )

    private static func braceDelta(in line: String) -> Int {
        var delta = 0
        var isEscaped = false
        var isInString = false

        for character in line {
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }

            if character == "\"" {
                isInString = true
            } else if character == "{" {
                delta += 1
            } else if character == "}" {
                delta -= 1
            }
        }

        return delta
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
