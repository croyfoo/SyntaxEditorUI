import Foundation
import SwiftTreeSitter

// Provides Swift substring tokens that cannot be expressed by Tree-sitter
// captures alone, such as MARK comments and URLs inside comments.
struct SwiftSemanticOverlayState: SyntaxOverlayState {
    fileprivate var index: SwiftFileSymbolIndex?
    fileprivate var indexedSourceUTF16Length: Int
    fileprivate var indexedDeclarationFingerprint: Int
}

typealias SwiftSemanticOverlayResult = SyntaxOverlayResult

private struct SwiftOverlayPreparation {
    let baseTokensForIndex: [SyntaxHighlightToken]
    let outputBaseTokens: [SyntaxHighlightToken]
    let tokenIndex: SwiftTokenIndex
    let excludedPreprocessorRanges: [NSRange]
}

private struct SwiftIndexedToken {
    let range: NSRange
    let text: String
}

private struct SwiftTokenIndex {
    private let semanticCandidateTokens: [SwiftIndexedToken]

    init(tokens: [SyntaxHighlightToken], source: NSString, targetRange: NSRange?) {
        var semanticCandidateTokens: [SwiftIndexedToken] = []
        semanticCandidateTokens.reserveCapacity(tokens.count / 3)

        for token in tokens {
            guard token.language == .swift || token.language == nil,
                  token.syntaxID == .plain,
                  token.range.location >= 0,
                  token.range.length > 0,
                  token.range.upperBound <= source.length,
                  targetRange.map({ Self.rangesIntersect(token.range, $0) }) ?? true
            else {
                continue
            }

            let text = source.substring(with: token.range)
            guard SwiftSyntaxOverlayTokenProvider.isSwiftIdentifier(text) else {
                continue
            }
            semanticCandidateTokens.append(SwiftIndexedToken(range: token.range, text: text))
        }

        self.semanticCandidateTokens = semanticCandidateTokens.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length < $1.range.length
        }
    }

    func semanticTokens(intersecting targetRange: NSRange?) -> ArraySlice<SwiftIndexedToken> {
        guard let targetRange else {
            return semanticCandidateTokens[...]
        }

        let lowerBound = lowerBoundForLocation(targetRange.location)
        var upperBound = lowerBound
        while upperBound < semanticCandidateTokens.count,
              semanticCandidateTokens[upperBound].range.location < targetRange.upperBound {
            upperBound += 1
        }
        return semanticCandidateTokens[lowerBound..<upperBound]
    }

    private func lowerBoundForLocation(_ location: Int) -> Int {
        var lower = 0
        var upper = semanticCandidateTokens.count
        while lower < upper {
            let midpoint = (lower + upper) / 2
            if semanticCandidateTokens[midpoint].range.upperBound <= location {
                lower = midpoint + 1
            } else {
                upper = midpoint
            }
        }
        return lower
    }

    private static func rangesIntersect(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        max(lhs.location, rhs.location) < min(lhs.upperBound, rhs.upperBound)
    }
}

enum SwiftSyntaxOverlayTokenProvider: SyntaxOverlayProvider {
    static func mergingOverlayTokens(
        tokens: [SyntaxHighlightToken],
        source: String,
        rootNode: Node? = nil,
        refreshRange: NSRange? = nil
    ) -> [SyntaxHighlightToken] {
        var state: SwiftSemanticOverlayState?
        return mergingOverlayResult(
            tokens: tokens,
            source: source,
            rootNode: rootNode,
            refreshRange: refreshRange,
            state: &state
        ).tokens
    }

    static func mergingOverlayResult(
        tokens: [SyntaxHighlightToken],
        source: String,
        rootNode: Node? = nil,
        refreshRange: NSRange? = nil,
        state: inout SwiftSemanticOverlayState?
    ) -> SwiftSemanticOverlayResult {
        let nsSource = source as NSString
        guard nsSource.length > 0 else {
            state = nil
            return SwiftSemanticOverlayResult(
                tokens: preparedOverlayInput(from: tokens, source: nsSource, targetRange: nil).baseTokensForIndex,
                refreshRangeOverride: nil,
                isCancelled: false
            )
        }

        let proposedTargetRange = refreshRange.map {
            SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: nsSource.length)
        }
        let previousState = state
        let declarationFingerprint = semanticIndexFingerprint(in: nsSource)
        let declarationFingerprintChanged = previousState.map {
            $0.indexedDeclarationFingerprint != declarationFingerprint
        } ?? true
        let targetRange = proposedTargetRange == nil
            || previousState?.index == nil
            || declarationFingerprintChanged
            ? nil
            : proposedTargetRange
        let preparation = preparedOverlayInput(from: tokens, source: nsSource, targetRange: targetRange)
        let shouldRebuildIndex = proposedTargetRange == nil
            || previousState?.index == nil
            || previousState?.indexedSourceUTF16Length != nsSource.length
            || declarationFingerprintChanged
        let index: SwiftFileSymbolIndex
        var rebuiltState: SwiftSemanticOverlayState?
        if shouldRebuildIndex {
            index = SwiftFileSymbolIndex(source: nsSource, tokens: preparation.baseTokensForIndex, rootNode: rootNode)
            guard !index.isCancelled else {
                return SwiftSemanticOverlayResult(
                    tokens: tokens,
                    refreshRangeOverride: nil,
                    isCancelled: true
                )
            }
            rebuiltState = SwiftSemanticOverlayState(
                index: index,
                indexedSourceUTF16Length: nsSource.length,
                indexedDeclarationFingerprint: declarationFingerprint
            )
        } else {
            index = previousState!.index!
        }

        guard !Task.isCancelled else {
            return SwiftSemanticOverlayResult(
                tokens: tokens,
                refreshRangeOverride: nil,
                isCancelled: true
            )
        }

        let overlayTokens =
            tokensInCommentLines(
                source: nsSource,
                existingTokens: preparation.baseTokensForIndex,
                targetRange: targetRange
            ) +
            tokensInPreprocessorLines(
                source: nsSource,
                excludedRanges: preparation.excludedPreprocessorRanges,
                targetRange: targetRange
            ) +
            tokensInSemanticSymbolRanges(
                source: nsSource,
                tokenIndex: preparation.tokenIndex,
                index: index,
                targetRange: targetRange
            )
        if let rebuiltState {
            state = rebuiltState
        }
        guard overlayTokens.isEmpty == false else {
            return SwiftSemanticOverlayResult(
                tokens: preparation.outputBaseTokens,
                refreshRangeOverride: targetRange,
                isCancelled: false
            )
        }

        return SwiftSemanticOverlayResult(
            tokens: deduplicated((preparation.outputBaseTokens + overlayTokens).sorted(by: SyntaxHighlightTokenOrdering.displayOrder)),
            refreshRangeOverride: targetRange,
            isCancelled: false
        )
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
        excludedRanges: [NSRange],
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
                guard !rangeIntersectsMergedRanges(range, excludedRanges) else {
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
        tokenIndex: SwiftTokenIndex,
        index: SwiftFileSymbolIndex,
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        guard source.length > 0 else {
            return []
        }

        var tokens: [SyntaxHighlightToken] = []

        for token in tokenIndex.semanticTokens(intersecting: targetRange) {
            guard !isPreprocessorLine(containing: token.range, in: source)
            else {
                continue
            }

            let overlays = semanticOverlays(
                    for: token.text,
                    range: token.range,
                    in: source,
                    index: index
            )
            guard !overlays.isEmpty else {
                continue
            }
            tokens.append(contentsOf: overlays.map {
                canonicalToken(range: $0.range, syntaxID: $0.syntaxID)
            })
        }

        return tokens
    }

    private struct SemanticOverlay {
        let range: NSRange
        let syntaxID: EditorSourceSyntaxID
    }

    private static func semanticOverlays(
        for text: String,
        range: NSRange,
        in source: NSString,
        index: SwiftFileSymbolIndex
    ) -> [SemanticOverlay] {
        let context = SwiftSemanticTokenContext(source: source, range: range, text: text)

        if let sigilRange = context.attributeSigilRange {
            if index.entry(
                named: text,
                at: range,
                allowedKinds: [.macro, .type]
            ) != nil {
                return []
            }

            if knownExternalAttributeFunctionNames.contains(text) {
                return [
                    SemanticOverlay(range: sigilRange, syntaxID: .identifierFunctionSystem),
                    SemanticOverlay(range: range, syntaxID: .identifierFunctionSystem),
                ]
            }
            if knownExternalAttributeClassNames.contains(text) {
                return [
                    SemanticOverlay(range: sigilRange, syntaxID: .identifierClassSystem),
                    SemanticOverlay(range: range, syntaxID: .identifierClassSystem),
                ]
            }
            let syntaxID: EditorSourceSyntaxID = context.startsLikeTypeName ? .identifierClassSystem : .identifierFunctionSystem
            return [
                SemanticOverlay(range: sigilRange, syntaxID: syntaxID),
                SemanticOverlay(range: range, syntaxID: syntaxID),
            ]
        }

        if let sigilRange = context.macroInvocationSigilRange {
            if let localMacro = index.entry(
                named: text,
                at: range,
                allowedKinds: [.macro]
            ) {
                return syntaxIDForLocalEntry(localMacro).map {
                    [
                        SemanticOverlay(range: sigilRange, syntaxID: $0),
                        SemanticOverlay(range: range, syntaxID: $0),
                    ]
                } ?? []
            }
            return [
                SemanticOverlay(range: sigilRange, syntaxID: .identifierMacroSystem),
                SemanticOverlay(range: range, syntaxID: .identifierMacroSystem),
            ]
        }

        guard !context.isImportLine,
              !context.isLabel,
              !context.isDeclarationContext,
              !context.isGenericParameterDeclarationContext,
              !context.isPatternBindingDeclarationContext,
              !context.isAttributeArgumentContext
        else {
            return []
        }

        if context.isMemberAccess {
            if let receiverName = context.memberReceiverName,
               let receiverType = index.declaredTypeName(forValueNamed: receiverName, at: range),
               knownExternalMemberVariablesByReceiverType[receiverType]?.contains(text) == true {
                return [SemanticOverlay(range: range, syntaxID: .identifierVariableSystem)]
            }

            if let localMember = index.entry(
                named: text,
                at: range,
                allowedKinds: [.function, .type, .variable],
                allowedRoles: .member
            ) {
                if localMember.kind == .type {
                    return syntaxIDForLocalEntry(localMember).map {
                        [SemanticOverlay(range: range, syntaxID: $0)]
                    } ?? []
                }

                if localMember.kind == .variable, text == "range" {
                    return [SemanticOverlay(range: range, syntaxID: .identifierConstantSystem)]
                }

                let syntaxID: EditorSourceSyntaxID = localMember.kind == .function
                    ? .identifierFunctionSystem
                    : .identifierVariableSystem
                return [SemanticOverlay(range: range, syntaxID: syntaxID)]
            }

            if let enumCase = index.enumCaseEntry(
                named: text,
                at: range,
                receiverTypeName: context.memberReceiverTypeName
            ) {
                return syntaxIDForLocalEntry(enumCase).map {
                    [SemanticOverlay(range: range, syntaxID: $0)]
                } ?? []
            }

            if context.startsLikeTypeName {
                return [SemanticOverlay(range: range, syntaxID: .identifierTypeSystem)]
            }
            if context.isFunctionCall || context.isTrailingClosureCall {
                return [SemanticOverlay(range: range, syntaxID: .identifierFunctionSystem)]
            }
            return [SemanticOverlay(range: range, syntaxID: .identifierVariableSystem)]
        }

        let localValueEntry = index.entry(
            named: text,
            at: range,
            allowedKinds: [.variable],
            allowedRoles: .local
        )
        let isTypeContext = context.isTypeContext

        if localValueEntry != nil, !isTypeContext {
            return []
        }

        if context.isAssignmentExpressionContext,
           let projectVariable = index.entry(
            named: text,
            at: range,
            allowedKinds: [.variable],
            allowedRoles: [.file, .member]
           ) {
            return syntaxIDForLocalEntry(projectVariable).map {
                [SemanticOverlay(range: range, syntaxID: $0)]
            } ?? []
        }

        if context.isCallArgumentValueContext,
           let projectVariable = index.entry(
            named: text,
            at: range,
            allowedKinds: [.variable],
            allowedRoles: [.file, .member]
           ) {
            return syntaxIDForLocalEntry(projectVariable).map {
                [SemanticOverlay(range: range, syntaxID: $0)]
            } ?? []
        }

        if isTypeContext {
            if localValueEntry != nil,
               context.isAssignmentExpressionContext || context.isCallArgumentValueContext {
                return []
            }

            if index.isGenericParameter(named: text, at: range) {
                return []
            }

            if let localType = index.entry(
                named: text,
                at: range,
                allowedKinds: [.type]
            ) {
                return syntaxIDForLocalEntry(localType).map {
                    [SemanticOverlay(range: range, syntaxID: $0)]
                } ?? []
            }

            if context.isFunctionCall,
               let localFunction = index.entry(
                named: text,
                at: range,
                allowedKinds: [.function]
               ) {
                return syntaxIDForLocalEntry(localFunction).map {
                    [SemanticOverlay(range: range, syntaxID: $0)]
                } ?? []
            }

            if let syntaxID = syntaxIDForKnownExternalType(named: text) {
                return [SemanticOverlay(range: range, syntaxID: syntaxID)]
            }

            return context.startsLikeTypeName
                ? [SemanticOverlay(range: range, syntaxID: .identifierTypeSystem)]
                : []
        }

        if context.isInsideStringInterpolation {
            return []
        }

        if let local = index.entry(
            named: text,
            at: range,
            allowedKinds: [.variable],
            allowedRoles: [.file, .member]
        ) {
            return syntaxIDForLocalEntry(local).map {
                [SemanticOverlay(range: range, syntaxID: $0)]
            } ?? []
        }

        if context.isFunctionCall {
            if knownExternalFunctionNames.contains(text) {
                return [SemanticOverlay(range: range, syntaxID: .identifierFunctionSystem)]
            }

            guard let localFunction = index.entry(
                named: text,
                at: range,
                allowedKinds: [.function]
            ) else {
                return [SemanticOverlay(range: range, syntaxID: .identifierFunctionSystem)]
            }
            return syntaxIDForLocalEntry(localFunction).map {
                [SemanticOverlay(range: range, syntaxID: $0)]
            } ?? []
        }

        return []
    }

    private static func syntaxIDForKnownExternalType(named name: String) -> EditorSourceSyntaxID? {
        if knownExternalClassNames.contains(name) {
            return .identifierClassSystem
        }
        if knownExternalTypeNames.contains(name) {
            return .identifierTypeSystem
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

    private static func deduplicated(_ tokens: [SyntaxHighlightToken]) -> [SyntaxHighlightToken] {
        var seen = Set<SyntaxOverlayTokenKey>()
        var unique: [SyntaxHighlightToken] = []
        unique.reserveCapacity(tokens.count)

        for token in tokens {
            let key = SyntaxOverlayTokenKey(token)
            guard seen.insert(key).inserted else { continue }
            unique.append(token)
        }

        return unique
    }

    static func semanticTargetRange(_ refreshRange: NSRange, in source: NSString) -> NSRange? {
        let targetRange = RefreshRangePolicy.lineEnvelope(containing: refreshRange, in: source)
        guard targetRange.length > 0 else {
            return nil
        }

        let context = source.substring(with: targetRange)
        let editedRange = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: source.length)
        return swiftRefreshLooksStructural(context, editedRange: editedRange, lineRange: targetRange) ? nil : targetRange
    }

    private static func swiftRefreshLooksStructural(
        _ text: String,
        editedRange: NSRange,
        lineRange: NSRange
    ) -> Bool {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        if structuralSwiftEditRegex.firstMatch(in: text, range: fullRange) != nil {
            return true
        }
        return swiftEditTouchesValueDeclarationHead(text, editedRange: editedRange, lineRange: lineRange)
            || swiftEditTouchesPreInBindingHead(text, editedRange: editedRange, lineRange: lineRange)
    }

    private static func swiftEditTouchesValueDeclarationHead(
        _ line: String,
        editedRange: NSRange,
        lineRange: NSRange
    ) -> Bool {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard valueDeclarationHeadRegex.firstMatch(in: line, range: fullRange) != nil else {
            return false
        }

        let assignmentRange = nsLine.range(of: "=")
        let safeValueStart: Int
        if assignmentRange.location == NSNotFound {
            safeValueStart = lineRange.upperBound
        } else {
            safeValueStart = lineRange.location + assignmentRange.upperBound
        }
        return editedRange.location < safeValueStart
    }

    private static func swiftEditTouchesPreInBindingHead(
        _ line: String,
        editedRange: NSRange,
        lineRange: NSRange
    ) -> Bool {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let inMatch = swiftPreInBindingKeywordRegex.firstMatch(in: line, range: fullRange) else {
            return false
        }
        let headRange = NSRange(location: 0, length: inMatch.range.location)
        guard swiftPreInBindingHeadRegex.firstMatch(in: line, range: headRange) != nil else {
            return false
        }
        let editedStart = max(0, editedRange.location - lineRange.location)
        return editedStart < inMatch.range.location
    }

    private static func semanticIndexFingerprint(in source: NSString) -> Int {
        var hasher = Hasher()

        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange)
            if swiftLineCanAffectSemanticIndex(line) {
                hasher.combine(line)
            }
            let nextLocation = lineRange.upperBound
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return hasher.finalize()
    }

    private static func swiftLineCanAffectSemanticIndex(_ line: String) -> Bool {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        if structuralSwiftEditRegex.firstMatch(in: line, range: fullRange) != nil {
            return true
        }
        if valueDeclarationHeadRegex.firstMatch(in: line, range: fullRange) != nil {
            return true
        }
        guard let inMatch = swiftPreInBindingKeywordRegex.firstMatch(in: line, range: fullRange) else {
            return false
        }
        let headRange = NSRange(location: 0, length: inMatch.range.location)
        return swiftPreInBindingHeadRegex.firstMatch(in: line, range: headRange) != nil
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

    private static let structuralSwiftEditRegex = try! NSRegularExpression(
        pattern: #"(^|\s)(@\w+|#if|#elseif|#else|#endif|#sourceLocation|class|struct|enum|actor|protocol|extension|func|init|deinit|subscript|typealias|associatedtype|case|macro|operator|precedencegroup|import)\b"#,
        options: [.anchorsMatchLines]
    )

    private static let valueDeclarationHeadRegex = try! NSRegularExpression(
        pattern: #"^\s*(let|var)\s+[A-Za-z_][A-Za-z0-9_]*"#
    )

    private static let swiftPreInBindingKeywordRegex = try! NSRegularExpression(
        pattern: #"\bin\b"#
    )

    private static let swiftPreInBindingHeadRegex = try! NSRegularExpression(
        pattern: #"(?:(?:^|[{\[(,;=]\s*)|(?:^\s*for\s+))(?:case\s+)?(?:let\s+|var\s+)?[A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*(?:let\s+|var\s+)?[A-Za-z_][A-Za-z0-9_]*)*\s*$"#
    )

    private static func urlTokens(in source: String, lineRange: NSRange) -> [SyntaxHighlightToken] {
        urlRegex.matches(in: source, range: lineRange).map {
            canonicalToken(range: $0.range, syntaxID: .url)
        }
    }

    private static func mergedExcludedPreprocessorRanges(existingTokens: [SyntaxHighlightToken]) -> [NSRange] {
        let ranges: [NSRange] = existingTokens.compactMap { token -> NSRange? in
            guard token.language == .swift || token.language == nil else {
                return nil
            }
            let value = token.syntaxID.rawValue
            guard value == "string" || value == "character" || value.hasPrefix("comment") else {
                return nil
            }
            return token.range
        }
        .sorted {
            if $0.location != $1.location {
                return $0.location < $1.location
            }
            return $0.length < $1.length
        }
        return mergedRanges(ranges)
    }

    private static func rangeIntersectsMergedRanges(_ range: NSRange, _ mergedRanges: [NSRange]) -> Bool {
        guard !mergedRanges.isEmpty else {
            return false
        }

        var lower = 0
        var upper = mergedRanges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if mergedRanges[middle].upperBound <= range.location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        guard lower < mergedRanges.count else {
            return false
        }
        return mergedRanges[lower].location < range.upperBound
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

    fileprivate static func isSwiftIdentifier(_ text: String) -> Bool {
        var iterator = text.utf8.makeIterator()
        guard let first = iterator.next(),
              isSwiftIdentifierStartByte(first)
        else {
            return false
        }

        while let byte = iterator.next() {
            guard isSwiftIdentifierContinueByte(byte) else {
                return false
            }
        }
        return true
    }

    private static func preparedOverlayInput(
        from tokens: [SyntaxHighlightToken],
        source: NSString,
        targetRange: NSRange?
    ) -> SwiftOverlayPreparation {
        let generatedMacroOverlayRangeKeys = generatedSystemMacroOverlayRangeKeys(from: tokens, source: source)
        var baseTokensForIndex: [SyntaxHighlightToken] = []
        var outputBaseTokens: [SyntaxHighlightToken] = []
        baseTokensForIndex.reserveCapacity(tokens.count)
        outputBaseTokens.reserveCapacity(tokens.count)

        for token in tokens {
            let stripsFromIndex = isSwiftSemanticOverlayToken(
                token,
                generatedSystemMacroOverlayRangeKeys: generatedMacroOverlayRangeKeys
            )
            if !stripsFromIndex {
                baseTokensForIndex.append(token)
            }

            let stripsFromOutput = targetRange.map { stripRange in
                rangesIntersect(token.range, stripRange) && stripsFromIndex
            } ?? stripsFromIndex
            if !stripsFromOutput {
                outputBaseTokens.append(token)
            }
        }

        return SwiftOverlayPreparation(
            baseTokensForIndex: baseTokensForIndex,
            outputBaseTokens: outputBaseTokens,
            tokenIndex: SwiftTokenIndex(tokens: baseTokensForIndex, source: source, targetRange: targetRange),
            excludedPreprocessorRanges: mergedExcludedPreprocessorRanges(existingTokens: baseTokensForIndex)
        )
    }

    private static func isSwiftSemanticOverlayToken(
        _ token: SyntaxHighlightToken,
        generatedSystemMacroOverlayRangeKeys: Set<SyntaxOverlayRangeKey>
    ) -> Bool {
        guard token.language == .swift || token.language == nil else {
            return false
        }
        switch token.syntaxID {
        case .identifierType,
             .identifierTypeSystem,
             .identifierClass,
             .identifierClassSystem,
             .identifierFunction,
             .identifierFunctionSystem,
             .identifierMacro,
             .identifierConstant,
             .identifierConstantSystem,
             .identifierVariable,
             .identifierVariableSystem:
            return true
        case .identifierMacroSystem:
            return generatedSystemMacroOverlayRangeKeys.contains(SyntaxOverlayRangeKey(token.range))
        default:
            return false
        }
    }

    private static func generatedSystemMacroOverlayRangeKeys(
        from tokens: [SyntaxHighlightToken],
        source: NSString
    ) -> Set<SyntaxOverlayRangeKey> {
        var macroNameRangesByLocation: [Int: [NSRange]] = [:]
        var sigilRanges: [NSRange] = []

        for token in tokens where token.syntaxID == .identifierMacroSystem {
            guard token.language == .swift || token.language == nil,
                  token.range.location >= 0,
                  token.range.upperBound <= source.length
            else {
                continue
            }

            if token.range.length == 1,
               source.substring(with: token.range) == "#" {
                sigilRanges.append(token.range)
            } else {
                macroNameRangesByLocation[token.range.location, default: []].append(token.range)
            }
        }

        var rangeKeys = Set<SyntaxOverlayRangeKey>()
        for sigilRange in sigilRanges {
            guard let nameRanges = macroNameRangesByLocation[sigilRange.upperBound] else {
                continue
            }
            rangeKeys.insert(SyntaxOverlayRangeKey(sigilRange))
            for nameRange in nameRanges {
                rangeKeys.insert(SyntaxOverlayRangeKey(nameRange))
            }
        }
        return rangeKeys
    }

    private static func isSwiftIdentifierStartByte(_ byte: UInt8) -> Bool {
        byte == 95
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
    }

    private static func isSwiftIdentifierContinueByte(_ byte: UInt8) -> Bool {
        isSwiftIdentifierStartByte(byte) || (byte >= 48 && byte <= 57)
    }

    private static let knownExternalTypeNames: Set<String> = [
        "AdditionPrecedence", "Bool", "ClosedRange", "Double", "Float", "Int", "StaticString", "String", "UInt", "UUID"
    ]

    private static let knownExternalClassNames: Set<String> = [
        "CaseIterable", "Comparable", "Hashable", "Identifiable", "MainActor", "Sendable", "Sequence"
    ]

    private static let knownExternalFunctionNames: Set<String> = [
        "max", "min"
    ]

    private static let knownExternalAttributeFunctionNames: Set<String> = [
        "Observable"
    ]

    private static let knownExternalAttributeClassNames: Set<String> = [
        "MainActor"
    ]

    private static let knownExternalMemberVariablesByReceiverType: [String: Set<String>] = [
        "ClosedRange": ["lowerBound", "upperBound"]
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

    var isGenericParameterDeclarationContext: Bool {
        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        guard trimmedBefore.contains("<"),
              !trimmedBefore.hasSuffix(":"),
              !trimmedBefore.contains("=")
        else {
            return false
        }

        return Self.genericParameterDeclarationPrefixRegex.firstMatch(
            in: trimmedBefore,
            range: NSRange(location: 0, length: (trimmedBefore as NSString).length)
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

    var attributeSigilRange: NSRange? {
        sigilRangeImmediatelyBeforeToken("@")
    }

    var macroInvocationSigilRange: NSRange? {
        sigilRangeImmediatelyBeforeToken("#")
    }

    var isMemberAccess: Bool {
        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        return trimmedBefore.hasSuffix(".") && !trimmedBefore.hasSuffix("..")
    }

    var memberReceiverTypeName: String? {
        memberReceiverName
    }

    var memberReceiverName: String? {
        guard isMemberAccess else {
            return nil
        }

        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        guard trimmedBefore.hasSuffix(".") else {
            return nil
        }

        let receiverText = String(trimmedBefore.dropLast())
        guard let match = Self.memberReceiverRegex.matches(
            in: receiverText,
            range: NSRange(location: 0, length: (receiverText as NSString).length)
        ).last else {
            return nil
        }

        return (receiverText as NSString).substring(with: match.range)
    }

    var isSelfMemberAccess: Bool {
        before.trimmingCharacters(in: .whitespaces).hasSuffix("self.")
    }

    var isFunctionCall: Bool {
        after.trimmingCharacters(in: .whitespaces).hasPrefix("(")
    }

    var isAttributeArgumentContext: Bool {
        guard let atIndex = before.lastIndex(of: "@") else {
            return false
        }
        let suffix = before[atIndex...]
        return suffix.contains("(") && !suffix.contains(")")
    }

    var isTrailingClosureCall: Bool {
        after.trimmingCharacters(in: .whitespaces).hasPrefix("{")
    }

    var isTypeInheritanceClause: Bool {
        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        return Self.typeInheritancePrefixRegex.firstMatch(
            in: trimmedBefore,
            range: NSRange(location: 0, length: (trimmedBefore as NSString).length)
        ) != nil
    }

    var isOperatorPrecedenceReference: Bool {
        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        return Self.operatorPrecedencePrefixRegex.firstMatch(
            in: trimmedBefore,
            range: NSRange(location: 0, length: (trimmedBefore as NSString).length)
        ) != nil
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

        if startsLikeTypeName && (isTypeInheritanceClause || isOperatorPrecedenceReference) {
            return true
        }

        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        if startsLikeTypeName,
           Self.opaqueExistentialTypePrefixRegex.firstMatch(
            in: trimmedBefore,
            range: NSRange(location: 0, length: (trimmedBefore as NSString).length)
           ) != nil {
            return true
        }

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

    private func sigilRangeImmediatelyBeforeToken(_ sigil: String) -> NSRange? {
        let sigilLength = (sigil as NSString).length
        guard sigilLength > 0,
              range.location >= sigilLength
        else {
            return nil
        }

        let sigilRange = NSRange(location: range.location - sigilLength, length: sigilLength)
        guard source.substring(with: sigilRange) == sigil else {
            return nil
        }

        if sigilRange.location > 0 {
            let previousRange = NSRange(location: sigilRange.location - 1, length: 1)
            let previous = source.substring(with: previousRange)
            guard previous.range(of: #"^[A-Za-z0-9_#@]$"#, options: .regularExpression) == nil else {
                return nil
            }
        }

        return sigilRange
    }

    private static let declarationPrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:let|var|func|macro|class|struct|enum|actor|protocol|typealias|associatedtype)\s+$"#
    )

    private static let genericParameterDeclarationPrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:class|struct|enum|actor|protocol|func)\s+[A-Za-z_][A-Za-z0-9_]*[^\n<]*<[^=\n{}()]*$"#
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

    private static let opaqueExistentialTypePrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:some|any)$"#
    )

    private static let typeInheritancePrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:class|struct|enum|actor|protocol)\s+[A-Za-z_][A-Za-z0-9_]*(?:<[^=\n{}()]*>)?\s*:\s*[^=\n{}()]*$"#
    )

    private static let operatorPrecedencePrefixRegex = try! NSRegularExpression(
        pattern: #"\b(?:prefix|infix|postfix)\s+operator\b[^:\n]*:\s*$"#
    )

    private static let memberReceiverRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z_][A-Za-z0-9_]*$"#
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
