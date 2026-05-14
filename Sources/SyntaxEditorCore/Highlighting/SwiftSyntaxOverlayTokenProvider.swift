import Foundation

// Provides Swift substring tokens that cannot be expressed by Tree-sitter
// captures alone, such as documentation field names, URLs inside comments, and
// malformed directive arguments that the grammar does not keep inside the
// directive node.
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
            tokensInDirectiveLines(
                source: nsSource,
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
                tokens.append(canonicalToken(range: markRange, syntaxID: .mark))
            }

            if trimmed.hasPrefix("///") || trimmed.hasPrefix("/**") || trimmed.hasPrefix("*") {
                for keyword in documentationMarkupKeywords {
                    guard let keywordRange = substringRange("\(keyword):", in: source, lineRange: clampedLineRange) else {
                        continue
                    }
                    tokens.append(canonicalToken(
                        range: NSRange(location: keywordRange.location, length: keyword.utf16.count),
                        syntaxID: .documentationCommentKeyword
                    ))
                }
            }

            tokens.append(contentsOf: urlTokens(in: sourceString, lineRange: clampedLineRange))
            location = clampedLineRange.upperBound
        }

        return tokens
    }

    private static func tokensInDirectiveLines(
        source: NSString,
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
            guard trimmed.hasPrefix("#if") || trimmed.hasPrefix("#elseif") else {
                location = clampedLineRange.upperBound
                continue
            }

            let matches = directiveVersionRegex.matches(in: sourceString, range: clampedLineRange)
            for match in matches where match.numberOfRanges > 1 {
                tokens.append(canonicalToken(range: match.range(at: 1), syntaxID: .preprocessor))
            }
            location = clampedLineRange.upperBound
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

    private static let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s\])>"]+"#)

    private static let directiveVersionRegex = try! NSRegularExpression(
        pattern: #"_version\s*:\s*([0-9]+(?:\.[0-9]+)+)"#
    )

    private static func urlTokens(in source: String, lineRange: NSRange) -> [SyntaxHighlightToken] {
        urlRegex.matches(in: source, range: lineRange).map {
            canonicalToken(range: $0.range, syntaxID: .url)
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
