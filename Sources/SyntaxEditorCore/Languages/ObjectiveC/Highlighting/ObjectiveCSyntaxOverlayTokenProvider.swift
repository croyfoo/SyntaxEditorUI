import Foundation
import SwiftTreeSitter

private typealias ObjectiveCRangeKey = SyntaxOverlayRangeKey
private typealias ObjectiveCTokenKey = SyntaxOverlayTokenKey
private typealias ObjectiveCSyntaxIDMask = SyntaxOverlaySyntaxIDMask

struct ObjectiveCSemanticOverlayState: SyntaxOverlayState {
    fileprivate var index: ObjectiveCSemanticIndex?
}

typealias ObjectiveCSemanticOverlayResult = SyntaxOverlayResult

private struct ObjectiveCSemanticIndexSignature {
    let fingerprint: Int
    let structuralEditRanges: [NSRange]
}

fileprivate struct ObjectiveCSemanticLineSignature {
    let range: NSRange
    let contributesToSignature: Bool
    let fingerprint: Int
    let structuralEditRanges: [NSRange]
}

fileprivate struct ObjectiveCSemanticLineSignatureIndex {
    let lines: [ObjectiveCSemanticLineSignature]
    let fingerprint: Int
    let structuralEditRanges: [NSRange]

    init(source: NSString) {
        var lines: [ObjectiveCSemanticLineSignature] = []
        lines.reserveCapacity(max(1, source.length / 48))

        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            lines.append(Self.signature(for: lineRange, in: source))
            let nextLocation = lineRange.upperBound
            guard nextLocation > location else { break }
            location = nextLocation
        }

        self.init(lines: lines)
    }

    private init(lines: [ObjectiveCSemanticLineSignature]) {
        self.lines = lines
        self.fingerprint = Self.fingerprint(for: lines)
        self.structuralEditRanges = lines.flatMap(\.structuralEditRanges)
    }

    func applying(
        _ mutation: SyntaxHighlightMutation,
        to source: NSString
    ) -> ObjectiveCSemanticLineSignatureIndex? {
        guard !lines.isEmpty else {
            return nil
        }

        let replacementLength = mutation.replacement.utf16.count
        let previousSourceLength = source.length - (replacementLength - mutation.length)
        guard previousSourceLength >= 0,
              mutation.location >= 0,
              mutation.location <= previousSourceLength,
              mutation.location + mutation.length <= previousSourceLength else {
            return nil
        }

        let oldEnd = mutation.location + mutation.length
        let insertsAfterLastSignature = insertsAtEOFAfterTrailingLineBreak(
            mutation,
            source: source,
            previousSourceLength: previousSourceLength
        )
        let startIndex = insertsAfterLastSignature
            ? lines.count
            : lineIndex(containing: mutation.location, previousSourceLength: previousSourceLength)
        let endLookup = mutation.length == 0 ? mutation.location : max(mutation.location, oldEnd - 1)
        let endIndex = insertsAfterLastSignature
            ? lines.count - 1
            : lineIndex(containing: endLookup, previousSourceLength: previousSourceLength)
        let changedLineSignatures = Self.signaturesForChangedLines(mutation, in: source)
        guard !changedLineSignatures.isEmpty else { return nil }
        let delta = replacementLength - mutation.length

        var nextLines: [ObjectiveCSemanticLineSignature] = []
        nextLines.reserveCapacity(lines.count - (endIndex - startIndex + 1) + changedLineSignatures.count)
        var insertedChangedLines = false
        for index in lines.indices {
            if index < startIndex {
                nextLines.append(lines[index])
            } else if index == startIndex {
                nextLines.append(contentsOf: changedLineSignatures)
                insertedChangedLines = true
            } else if index <= endIndex {
                continue
            } else {
                let line = lines[index]
                nextLines.append(
                    ObjectiveCSemanticLineSignature(
                        range: NSRange(location: line.range.location + delta, length: line.range.length),
                        contributesToSignature: line.contributesToSignature,
                        fingerprint: line.fingerprint,
                        structuralEditRanges: line.structuralEditRanges.map {
                            NSRange(location: $0.location + delta, length: $0.length)
                        }
                    )
                )
            }
        }
        if !insertedChangedLines {
            nextLines.append(contentsOf: changedLineSignatures)
        }
        return ObjectiveCSemanticLineSignatureIndex(lines: nextLines)
    }

    private func insertsAtEOFAfterTrailingLineBreak(
        _ mutation: SyntaxHighlightMutation,
        source: NSString,
        previousSourceLength: Int
    ) -> Bool {
        guard mutation.length == 0,
              mutation.location == previousSourceLength,
              previousSourceLength > 0 else {
            return false
        }
        return LineOffsetTable.containsLineBreak(
            source.substring(with: NSRange(location: previousSourceLength - 1, length: 1))
        )
    }

    private func lineIndex(containing location: Int, previousSourceLength: Int) -> Int {
        let clampedLocation = min(max(0, location), max(0, previousSourceLength - 1))
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let midpoint = (lower + upper) / 2
            if lines[midpoint].range.upperBound <= clampedLocation {
                lower = midpoint + 1
            } else {
                upper = midpoint
            }
        }
        return min(lower, max(0, lines.count - 1))
    }

    static func signaturesForChangedLines(
        _ mutation: SyntaxHighlightMutation,
        in source: NSString
    ) -> [ObjectiveCSemanticLineSignature] {
        guard source.length > 0 else { return [] }
        let changedLineRange = SyntaxHighlightMutationLineRange.changedLineRange(for: mutation, in: source)
        var signatures: [ObjectiveCSemanticLineSignature] = []
        var cursor = changedLineRange.location
        while cursor < changedLineRange.upperBound {
            let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
            signatures.append(signature(for: lineRange, in: source))
            let next = lineRange.upperBound
            guard next > cursor else { break }
            cursor = next
        }
        return signatures
    }

    fileprivate static func signature(
        for lineRange: NSRange,
        in source: NSString
    ) -> ObjectiveCSemanticLineSignature {
        let line = source.substring(with: lineRange) as NSString
        var hasher = Hasher()
        let contributes = ObjectiveCSyntaxOverlayTokenProvider.appendObjectiveCSemanticIndexSignature(
            from: line,
            lineOffset: lineRange.location,
            into: &hasher
        )
        let structuralEditRanges = contributes
            ? ObjectiveCSyntaxOverlayTokenProvider.objectiveCSemanticStructuralEditRanges(
                in: line,
                lineOffset: lineRange.location
            )
            : []
        return ObjectiveCSemanticLineSignature(
            range: lineRange,
            contributesToSignature: contributes,
            fingerprint: hasher.finalize(),
            structuralEditRanges: structuralEditRanges
        )
    }

    private static func fingerprint(for lines: [ObjectiveCSemanticLineSignature]) -> Int {
        var hasher = Hasher()
        for line in lines where line.contributesToSignature {
            hasher.combine(line.fingerprint)
        }
        return hasher.finalize()
    }
}

private struct ObjectiveCOverlayPreparation {
    let baseTokensForIndex: [SyntaxHighlightToken]
    let outputBaseTokens: [SyntaxHighlightToken]
    let preservedOverlayTokens: [SyntaxHighlightToken]
    let nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex
    let tokenIndex: ObjectiveCTokenIndex
    let partialMergeTargetRange: NSRange?
    let partialMergeTokenRange: Range<Int>?
}

private struct ObjectiveCSemanticIndex {
    let fileSymbols: ObjectiveCFileSymbolIndex
    let sourceUTF16Length: Int
    let structuralFingerprint: Int
    let structuralEditRanges: [NSRange]
    let lineSignatureIndex: ObjectiveCSemanticLineSignatureIndex

    func shifted(
        by mutation: SyntaxHighlightMutation,
        source nextSource: NSString
    ) -> ObjectiveCSemanticIndex? {
        guard let shiftedSymbols = fileSymbols.shifted(
            by: mutation,
            sourceUTF16Length: nextSource.length
        ),
              Self.shiftedRanges(
                structuralEditRanges,
                by: mutation,
                sourceUTF16Length: nextSource.length
              ) != nil,
              let shiftedLineSignatureIndex = lineSignatureIndex.applying(
                mutation,
                to: nextSource
              ) else {
            return nil
        }
        return ObjectiveCSemanticIndex(
            fileSymbols: shiftedSymbols,
            sourceUTF16Length: nextSource.length,
            structuralFingerprint: shiftedLineSignatureIndex.fingerprint,
            structuralEditRanges: shiftedLineSignatureIndex.structuralEditRanges,
            lineSignatureIndex: shiftedLineSignatureIndex
        )
    }

    private static func shiftedRanges(
        _ ranges: [NSRange],
        by mutation: SyntaxHighlightMutation,
        sourceUTF16Length nextSourceUTF16Length: Int
    ) -> [NSRange]? {
        var shiftedRanges: [NSRange] = []
        shiftedRanges.reserveCapacity(ranges.count)
        for range in ranges {
            guard let shiftedRange = shiftedRange(
                range,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
            ) else {
                return nil
            }
            shiftedRanges.append(shiftedRange)
        }
        return shiftedRanges
    }

    private static func shiftedRange(
        _ range: NSRange,
        by mutation: SyntaxHighlightMutation,
        sourceUTF16Length nextSourceUTF16Length: Int
    ) -> NSRange? {
        let replacementLength = mutation.replacement.utf16.count
        let replacedRange = NSRange(location: mutation.location, length: mutation.length)
        let oldUpperBound = mutation.location + mutation.length
        let delta = replacementLength - mutation.length

        if range.upperBound <= mutation.location {
            return range
        }
        if mutation.length == 0,
           replacementLength > 0,
           range.location < mutation.location,
           mutation.location < range.upperBound {
            return nil
        }
        if range.location >= oldUpperBound {
            let shiftedLocation = range.location + delta
            guard shiftedLocation >= 0,
                  shiftedLocation + range.length <= nextSourceUTF16Length else {
                return nil
            }
            return NSRange(location: shiftedLocation, length: range.length)
        }
        if SyntaxEditorRangeUtilities.intersection(of: range, and: replacedRange).length > 0 {
            return nil
        }
        return range
    }
}

private struct ObjectiveCNonCodeRangeIndex {
    let ranges: [NSRange]

    init(ranges: [NSRange]) {
        self.ranges = Self.normalized(ranges)
    }

    init(tokens: [SyntaxHighlightToken], sourceLength: Int) {
        self.init(ranges: tokens.compactMap { token -> NSRange? in
            guard token.language == .objectiveC || token.language == nil else {
                return nil
            }
            switch token.syntaxID {
            case .comment, .string, .character:
                return SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: sourceLength)
            default:
                return nil
            }
        })
    }

    func intersects(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        let index = lowerBoundForRangeEnding(after: range.location)
        guard index < ranges.count else { return false }
        return SyntaxEditorRangeUtilities.intersection(of: range, and: ranges[index]).length > 0
    }

    func contains(_ location: Int) -> Bool {
        guard location >= 0 else { return false }
        let index = lowerBoundForRangeEnding(after: location)
        guard index < ranges.count else { return false }
        let range = ranges[index]
        return range.location <= location && location < range.upperBound
    }

    func upperBoundOfRange(containing location: Int) -> Int? {
        guard location >= 0 else { return nil }
        let index = lowerBoundForRangeEnding(after: location)
        guard index < ranges.count else { return nil }
        let range = ranges[index]
        guard range.location <= location && location < range.upperBound else { return nil }
        return range.upperBound
    }

    private func lowerBoundForRangeEnding(after location: Int) -> Int {
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let midpoint = (lower + upper) / 2
            if ranges[midpoint].upperBound <= location {
                lower = midpoint + 1
            } else {
                upper = midpoint
            }
        }
        return lower
    }

    private static func normalized(_ ranges: [NSRange]) -> [NSRange] {
        let sortedRanges = ranges
            .filter { $0.length > 0 }
            .sorted {
                if $0.location != $1.location {
                    return $0.location < $1.location
                }
                return $0.length < $1.length
            }
        guard var current = sortedRanges.first else { return [] }
        var result: [NSRange] = []
        for range in sortedRanges.dropFirst() {
            if range.location <= current.upperBound {
                let upperBound = max(current.upperBound, range.upperBound)
                current = NSRange(location: current.location, length: upperBound - current.location)
            } else {
                result.append(current)
                current = range
            }
        }
        result.append(current)
        return result
    }
}

private struct ObjectiveCIndexedToken {
    let range: NSRange
    let syntaxID: EditorSourceSyntaxID
}

private struct ObjectiveCTokenIndex {
    let identifierTokens: [ObjectiveCIndexedToken]
    private let declarationOtherIdentifierRanges: [NSRange]
    private let propertyKeywordRangeKeys: Set<ObjectiveCRangeKey>
    private let identifierRangeKeys: Set<ObjectiveCRangeKey>

    init(tokens: [SyntaxHighlightToken], source: NSString) {
        var identifierTokens: [ObjectiveCIndexedToken] = []
        var declarationOtherIdentifierRanges: [NSRange] = []
        var propertyKeywordRangeKeys = Set<ObjectiveCRangeKey>()
        var identifierRangeKeys = Set<ObjectiveCRangeKey>()
        identifierTokens.reserveCapacity(tokens.count)
        declarationOtherIdentifierRanges.reserveCapacity(tokens.count / 12)

        for token in tokens where token.language == .objectiveC || token.language == nil {
            guard token.range.location >= 0,
                  token.range.length > 0,
                  token.range.upperBound <= source.length else {
                continue
            }
            if token.range.length == "@property".utf16.count,
               source.substring(with: token.range) == "@property" {
                propertyKeywordRangeKeys.insert(ObjectiveCRangeKey(token.range))
            }
            guard ObjectiveCFileSymbolIndex.isIdentifierRange(token.range, in: source) else {
                continue
            }
            identifierRangeKeys.insert(ObjectiveCRangeKey(token.range))
            let indexedToken = ObjectiveCIndexedToken(range: token.range, syntaxID: token.syntaxID)
            identifierTokens.append(indexedToken)
            if token.syntaxID == .declarationOther {
                declarationOtherIdentifierRanges.append(token.range)
            }
        }

        self.identifierTokens = identifierTokens
        self.declarationOtherIdentifierRanges = declarationOtherIdentifierRanges.sorted {
            if $0.location != $1.location {
                return $0.location < $1.location
            }
            return $0.length < $1.length
        }
        self.propertyKeywordRangeKeys = propertyKeywordRangeKeys
        self.identifierRangeKeys = identifierRangeKeys
    }

    func declarationOtherIdentifierRanges(in range: NSRange) -> [NSRange] {
        var index = lowerBoundForDeclarationOtherIdentifier(location: range.location)
        var ranges: [NSRange] = []
        while index < declarationOtherIdentifierRanges.count {
            let candidate = declarationOtherIdentifierRanges[index]
            guard candidate.location < range.upperBound else {
                break
            }
            if candidate.location >= range.location,
               candidate.upperBound <= range.upperBound {
                ranges.append(candidate)
            }
            index += 1
        }
        return ranges
    }

    func containsPropertyKeywordRange(_ range: NSRange) -> Bool {
        propertyKeywordRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsIdentifierRange(_ range: NSRange) -> Bool {
        identifierRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    private func lowerBoundForDeclarationOtherIdentifier(location: Int) -> Int {
        var lower = 0
        var upper = declarationOtherIdentifierRanges.count
        while lower < upper {
            let midpoint = (lower + upper) / 2
            if declarationOtherIdentifierRanges[midpoint].location < location {
                lower = midpoint + 1
            } else {
                upper = midpoint
            }
        }
        return lower
    }
}

enum ObjectiveCSyntaxOverlayTokenProvider: SyntaxOverlayProvider {
    private static let objectiveCSemanticStructuralCharacters = CharacterSet(charactersIn: "#@{}();")

    static func mergingOverlayTokens(
        tokens: [SyntaxHighlightToken],
        source: String,
        rootNode: Node? = nil,
        refreshRange: NSRange? = nil
    ) -> [SyntaxHighlightToken] {
        var state: ObjectiveCSemanticOverlayState?
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
        state: inout ObjectiveCSemanticOverlayState?
    ) -> ObjectiveCSemanticOverlayResult {
        mergingOverlayResult(
            tokens: tokens,
            source: source,
            rootNode: rootNode,
            refreshRange: refreshRange,
            mutation: nil,
            state: &state
        )
    }

    static func mergingOverlayResult(
        tokens: [SyntaxHighlightToken],
        source: String,
        rootNode: Node? = nil,
        refreshRange: NSRange? = nil,
        mutation: SyntaxHighlightMutation?,
        tokenPrefixMaxUpperBounds: [Int]? = nil,
        state: inout ObjectiveCSemanticOverlayState?
    ) -> ObjectiveCSemanticOverlayResult {
        let nsSource = source as NSString
        guard nsSource.length > 0 else {
            state = nil
            return ObjectiveCSemanticOverlayResult(
                tokens: preparedOverlayInput(from: tokens, source: nsSource, targetRange: nil).baseTokensForIndex,
                refreshRangeOverride: nil,
                isCancelled: false
            )
        }

        let proposedTargetRange = refreshRange.map {
            SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: nsSource.length)
        }
        let previousIndex = state?.index
        let requiresSemanticIndexRebuild = mutation.map {
            objectiveCMutationRequiresSemanticIndexRebuild(
                $0,
                in: nsSource,
                previousIndex: previousIndex
            )
        } ?? false
        let shiftedLineSignatureIndex = mutation.flatMap { mutation in
            previousIndex?.lineSignatureIndex.applying(mutation, to: nsSource)
        }
        let shiftedPreviousIndex = mutation.flatMap { mutation in
            previousIndex?.shifted(by: mutation, source: nsSource)
        }
        let cannotShiftPreviousIndex = mutation != nil
            && previousIndex != nil
            && shiftedPreviousIndex == nil
        let shouldCheckStructuralFingerprint = mutation.map {
            requiresSemanticIndexRebuild
                || cannotShiftPreviousIndex
                || objectiveCMutationCanChangeSemanticSignature($0, in: nsSource, previousIndex: previousIndex)
        } ?? true
        let structuralSignature = if let previousIndex, !shouldCheckStructuralFingerprint {
            ObjectiveCSemanticIndexSignature(
                fingerprint: previousIndex.structuralFingerprint,
                structuralEditRanges: previousIndex.structuralEditRanges
            )
        } else if let shiftedLineSignatureIndex {
            ObjectiveCSemanticIndexSignature(
                fingerprint: shiftedLineSignatureIndex.fingerprint,
                structuralEditRanges: shiftedLineSignatureIndex.structuralEditRanges
            )
        } else {
            semanticIndexSignature(in: nsSource)
        }
        let structuralFingerprintChanged = shouldCheckStructuralFingerprint
            ? (previousIndex.map { $0.structuralFingerprint != structuralSignature.fingerprint } ?? true)
            : false
        let localStructuralTargetRange = if structuralFingerprintChanged,
                                            let mutation,
                                            previousIndex != nil {
            objectiveCLocalStructuralRefreshRange(for: mutation, in: nsSource, previousIndex: previousIndex)
        } else {
            nil as NSRange?
        }
        let structuralCheckRequiresFullTarget = structuralFingerprintChanged
            && localStructuralTargetRange == nil
        let targetRange = proposedTargetRange == nil
            || previousIndex == nil
            || structuralCheckRequiresFullTarget
            ? nil
            : (localStructuralTargetRange ?? proposedTargetRange)
        let shouldRebuildIndex = proposedTargetRange == nil
            || previousIndex == nil
            || requiresSemanticIndexRebuild
            || structuralFingerprintChanged
            || structuralCheckRequiresFullTarget
            || cannotShiftPreviousIndex
            || (previousIndex?.sourceUTF16Length != nsSource.length && mutation == nil)
        let preparation = preparedOverlayInput(
            from: tokens,
            source: nsSource,
            targetRange: targetRange,
            tokenPrefixMaxUpperBounds: tokenPrefixMaxUpperBounds,
            preparesFullIndex: shouldRebuildIndex
        )
        let semanticIndex: ObjectiveCSemanticIndex
        if shouldRebuildIndex {
            guard let rebuiltIndex = ObjectiveCFileSymbolIndex(
                source: nsSource,
                tokenIndex: preparation.tokenIndex,
                nonCodeRangeIndex: preparation.nonCodeRangeIndex,
                rootNode: rootNode,
                allowsCancellation: true
            ) else {
                return ObjectiveCSemanticOverlayResult(
                    tokens: tokens,
                    refreshRangeOverride: nil,
                    isCancelled: true
                )
            }
            semanticIndex = ObjectiveCSemanticIndex(
                fileSymbols: rebuiltIndex,
                sourceUTF16Length: nsSource.length,
                structuralFingerprint: structuralSignature.fingerprint,
                structuralEditRanges: structuralSignature.structuralEditRanges,
                lineSignatureIndex: ObjectiveCSemanticLineSignatureIndex(source: nsSource)
            )
        } else if let shiftedIndex = shiftedPreviousIndex {
            semanticIndex = shiftedIndex
        } else {
            semanticIndex = previousIndex!
        }

        guard !Task.isCancelled else {
            return ObjectiveCSemanticOverlayResult(
                tokens: tokens,
                refreshRangeOverride: nil,
                isCancelled: true
            )
        }

        let overlayTokens = semanticTokens(
            from: preparation.baseTokensForIndex,
            source: nsSource,
            index: semanticIndex.fileSymbols,
            targetRange: targetRange
        )
            + objectiveCMacroTokens(
                in: nsSource,
                nonCodeRanges: preparation.nonCodeRangeIndex.ranges,
                targetRange: targetRange
            )
            + preprocessorStringTokens(in: nsSource, tokens: preparation.baseTokensForIndex, targetRange: targetRange)
            + boxedExpressionDelimiterTokens(
                in: nsSource,
                nonCodeRanges: preparation.nonCodeRangeIndex.ranges,
                targetRange: targetRange
            )
            + boxedBooleanLiteralTokens(
                in: nsSource,
                nonCodeRanges: preparation.nonCodeRangeIndex.ranges,
                targetRange: targetRange
            )
        let mergedTokens = if let partialMergeTargetRange = preparation.partialMergeTargetRange,
                              let partialMergeTokenRange = preparation.partialMergeTokenRange {
            partialMergedTokens(
                existingTokens: tokens,
                replacementOverlayTokens: overlayTokens,
                targetRange: partialMergeTargetRange,
                tokenRange: partialMergeTokenRange
            )
        } else {
            deduplicated(
                mergedTokens(
                    baseTokens: preparation.outputBaseTokens,
                    overlayTokens: preparation.preservedOverlayTokens + overlayTokens
                )
            )
        }
        state = ObjectiveCSemanticOverlayState(index: semanticIndex)
        return ObjectiveCSemanticOverlayResult(
            tokens: mergedTokens,
            refreshRangeOverride: targetRange,
            isCancelled: false
        )
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

            if token.syntaxID == .keyword, text == "Class" {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .plain))
                continue
            }

            if preprocessorObjectiveCMacroIdentifiers.contains(text) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .preprocessor))
                continue
            }

            if index.containsPropertyDeclarationNameRange(token.range) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .declarationOther))
                continue
            }

            if index.containsTypeDeclarationNameRange(token.range) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .declarationType))
                continue
            }

            if index.containsSelfMemberNameRange(token.range) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariable))
                continue
            }

            if index.containsSelfChainMemberNameRange(token.range) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariableSystem))
                continue
            }

            if isSelfMemberName(token.range, in: source) {
                if index.shouldTrackSelfMemberName(text) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariable))
                }
                continue
            }

            if index.containsIvarName(text),
               !index.containsIvarDeclarationNameRange(token.range),
               !index.containsShadowedVariableRange(token.range) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariable))
                continue
            }

            if index.containsFileScopeVariableName(text),
               !index.containsFileScopeVariableDeclarationNameRange(token.range),
               !index.containsShadowedVariableRange(token.range) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierVariableSystem))
                continue
            }

            if knownObjectiveCFunctionPointerCastCallees.contains(text),
               isObjectiveCFunctionPointerCastCalleeName(token.range, in: source) {
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierFunctionSystem))
                continue
            }

            if token.syntaxID == .plain,
               isObjectiveCCallName(token.range, in: source) {
                if index.containsLocalMacroName(text) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .preprocessor))
                    continue
                }
                if index.localFunctions.contains(text) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierFunction))
                    continue
                }
                if knownObjectiveCSystemFunctionNames.contains(text) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .identifierFunctionSystem))
                    continue
                }
            }

            switch token.syntaxID {
            case .identifier:
                continue

            case .identifierType, .identifierTypeSystem:
                guard !keywordLikeTypeNames.contains(text) else {
                    continue
                }
                if isTypeDeclarationName(token.range, text: text, in: source) {
                    overlayTokens.append(canonicalToken(range: token.range, syntaxID: .declarationType))
                }

            case .identifierFunction:
                guard !appleMacroFunctionNames.contains(text) else {
                    continue
                }
                guard isObjectiveCFunctionOrMethodDeclarationName(token.range, in: source) else {
                    continue
                }
                overlayTokens.append(canonicalToken(range: token.range, syntaxID: .declarationOther))

            case .identifierFunctionSystem:
                continue

            default:
                continue
            }
        }

        return overlayTokens
    }

    private static func preprocessorStringTokens(
        in source: NSString,
        tokens: [SyntaxHighlightToken],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        let string = source as String
        var overlayTokens: [SyntaxHighlightToken] = []
        for token in tokens where (token.language == .objectiveC || token.language == nil)
            && token.syntaxID == .preprocessor
            && token.range.location >= 0
            && token.range.length > 0
            && token.range.upperBound <= source.length {
            let scanRange = SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: source.length)
            guard targetRange.map({ rangesIntersect(scanRange, $0) }) ?? true else {
                continue
            }

            for match in preprocessorQuotedStringRegex.matches(in: string, range: scanRange) {
                var range = match.range
                guard range.location != NSNotFound,
                      range.length > 0,
                      range.upperBound <= source.length else {
                    continue
                }
                if source.substring(with: NSRange(location: range.location, length: 1)) == "@" {
                    range = NSRange(location: range.location + 1, length: range.length - 1)
                }
                guard range.length > 0,
                      targetRange.map({ rangesIntersect(range, $0) }) ?? true else {
                    continue
                }
                overlayTokens.append(canonicalToken(range: range, syntaxID: .string))
            }
        }
        return overlayTokens
    }

    private static func objectiveCMacroTokens(
        in source: NSString,
        nonCodeRanges: [NSRange],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        let string = source as String
        let searchRange = targetRange ?? NSRange(location: 0, length: source.length)
        var tokens: [SyntaxHighlightToken] = []

        for match in preprocessorObjectiveCMacroRegex.matches(in: string, range: searchRange) {
            let range = match.range
            guard range.location != NSNotFound,
                  range.length > 0,
                  !rangeIntersectsSortedRanges(range, nonCodeRanges) else {
                continue
            }
            tokens.append(canonicalToken(range: range, syntaxID: .preprocessor))
        }

        for match in macroLikeObjectiveCIdentifierRegex.matches(in: string, range: searchRange) {
            let range = match.range
            guard range.location != NSNotFound,
                  range.length > 0,
                  !rangeIntersectsSortedRanges(range, nonCodeRanges) else {
                continue
            }
            let text = source.substring(with: range)
            guard !preprocessorObjectiveCMacroIdentifiers.contains(text) else {
                continue
            }
            guard objectiveCTypeIdentifierShouldStayPlain(range, text: text, in: source) else {
                continue
            }
            tokens.append(canonicalToken(range: range, syntaxID: .plain))
        }

        return tokens
    }

    private static func boxedExpressionDelimiterTokens(
        in source: NSString,
        nonCodeRanges: [NSRange],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        var tokens: [SyntaxHighlightToken] = []
        var searchLocation = 0
        while searchLocation < source.length {
            let searchRange = NSRange(location: searchLocation, length: source.length - searchLocation)
            let matchRange = source.range(of: "@(", options: [], range: searchRange)
            guard matchRange.location != NSNotFound else {
                break
            }
            let atRange = NSRange(location: matchRange.location, length: 1)
            let openParenRange = NSRange(location: matchRange.location + 1, length: 1)
            let closeParenRange = matchingCloseParenRange(
                openingAt: openParenRange.location,
                in: source
            )
            let fullRange = closeParenRange.map {
                NSRange(location: atRange.location, length: $0.upperBound - atRange.location)
            } ?? NSRange(location: atRange.location, length: 2)

            var delimiterRanges = [atRange, openParenRange]
            if let closeParenRange {
                delimiterRanges.append(closeParenRange)
            }

            if delimiterRanges.allSatisfy({ !rangeIntersectsSortedRanges($0, nonCodeRanges) }),
               targetRange.map({ rangesIntersect(fullRange, $0) }) ?? true {
                tokens.append(canonicalToken(range: atRange, syntaxID: .number))
                tokens.append(canonicalToken(range: openParenRange, syntaxID: .number))
                if let closeParenRange {
                    tokens.append(canonicalToken(range: closeParenRange, syntaxID: .number))
                }
            }

            searchLocation = max(matchRange.upperBound, searchLocation + 1)
        }
        return tokens
    }

    private static func boxedBooleanLiteralTokens(
        in source: NSString,
        nonCodeRanges: [NSRange],
        targetRange: NSRange?
    ) -> [SyntaxHighlightToken] {
        let string = source as String
        let searchRange = targetRange ?? NSRange(location: 0, length: source.length)
        return boxedBooleanLiteralRegex.matches(in: string, range: searchRange).flatMap { match -> [SyntaxHighlightToken] in
            let range = match.range
            guard range.location != NSNotFound,
                  range.length > 0,
                  !rangeIntersectsSortedRanges(range, nonCodeRanges)
            else {
                return []
            }
            let valueRange = NSRange(location: range.location + 1, length: range.length - 1)
            return [
                canonicalToken(range: range, syntaxID: .number),
                canonicalToken(range: valueRange, syntaxID: .number)
            ]
        }
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

    static func semanticTargetRange(
        _ refreshRange: NSRange,
        in source: NSString,
        mutation: SyntaxHighlightMutation? = nil
    ) -> NSRange? {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: source.length)
        guard clamped.length > 0 else {
            return nil
        }

        let targetRange = source.lineRange(for: clamped)
        let contextRange = objectiveCUnsafeEditContextRange(around: targetRange, in: source)
        let context = source.substring(with: contextRange)
        if let mutation,
           objectiveCLocalEditCanKeepSemanticTarget(mutation, in: source) {
            let mutationTargetRange = source.lineRange(
                for: objectiveCMutationChangedRange(mutation, in: source)
            )
            return boxedExpressionRefreshRange(around: mutationTargetRange, in: source) ?? mutationTargetRange
        }
        if let mutation,
           objectiveCInsertedTextCanKeepSemanticTarget(mutation) {
            let mutationTargetRange = source.lineRange(
                for: objectiveCMutationChangedRange(mutation, in: source)
            )
            return boxedExpressionRefreshRange(around: mutationTargetRange, in: source) ?? mutationTargetRange
        }
        guard !objectiveCRefreshLooksStructural(context) else {
            guard let mutation,
                  objectiveCLocalEditCanKeepSemanticTarget(mutation, in: source) else {
                return nil
            }
            let mutationTargetRange = source.lineRange(
                for: objectiveCMutationChangedRange(mutation, in: source)
            )
            if !objectiveCRefreshLooksStructural(source.substring(with: mutationTargetRange)) {
                return boxedExpressionRefreshRange(around: mutationTargetRange, in: source) ?? mutationTargetRange
            }
            guard let scopeRange = ObjectiveCFileSymbolIndex.containingFunctionLikeScopeRange(
                containing: min(max(0, mutation.location), max(0, source.length - 1)),
                in: source
            ) else {
                return nil
            }
            return boxedExpressionRefreshRange(around: scopeRange, in: source) ?? scopeRange
        }
        guard mutation.map({ objectiveCLocalEditCanKeepSemanticTarget($0, in: source) }) != false else {
            return nil
        }
        return boxedExpressionRefreshRange(around: targetRange, in: source) ?? targetRange
    }

    private static func objectiveCMutationChangedRange(
        _ mutation: SyntaxHighlightMutation,
        in source: NSString
    ) -> NSRange {
        let replacementLength = mutation.replacement.utf16.count
        let changedLocation = min(max(0, mutation.location), source.length)
        let changedStart = max(0, changedLocation - (mutation.length > 0 ? 1 : 0))
        let changedEnd = min(source.length, max(changedLocation + max(1, replacementLength), changedStart + 1))
        return NSRange(location: changedStart, length: changedEnd - changedStart)
    }

    private static func objectiveCLocalEditCanKeepSemanticTarget(
        _ mutation: SyntaxHighlightMutation,
        in source: NSString
    ) -> Bool {
        guard source.length > 0,
              mutation.location >= 0,
              mutation.location <= source.length else {
            return false
        }

        let changedRange = objectiveCMutationChangedRange(mutation, in: source)
        let lineRange = source.lineRange(for: changedRange)
        let line = source.substring(with: lineRange) as NSString
        let lineString = line as String
        let fullRange = NSRange(location: 0, length: line.length)
        let relativeChangedRange = NSRange(
            location: max(0, changedRange.location - lineRange.location),
            length: changedRange.length
        )

        if objectiveCVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            let statementEnd = line.range(of: ";").location
            guard statementEnd != NSNotFound else { return false }
            return objectiveCDeclarationSignatureRanges(in: line, statementEnd: statementEnd)
                .contains { rangesIntersect($0, relativeChangedRange) } == false
        }

        return ObjectiveCSemanticLineSignatureIndex.signaturesForChangedLines(mutation, in: source)
            .allSatisfy { !$0.contributesToSignature }
    }

    private static func objectiveCInsertedTextCanKeepSemanticTarget(
        _ mutation: SyntaxHighlightMutation
    ) -> Bool {
        guard mutation.length == 0,
              !mutation.replacement.isEmpty else {
            return false
        }

        return !objectiveCRefreshLooksStructural(mutation.replacement)
    }

    private static func boxedExpressionRefreshRange(around targetRange: NSRange, in source: NSString) -> NSRange? {
        var cursor = targetRange.location
        let upperBound = min(source.length, targetRange.upperBound)
        while cursor < upperBound {
            if let nextCursor = locationAfterSkippedCommentOrLiteral(startingAt: cursor, in: source) {
                cursor = min(nextCursor, upperBound)
                continue
            }
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            guard character == "(" else {
                cursor += 1
                continue
            }
            guard let closeParenRange = matchingCloseParenRange(openingAt: cursor, in: source) else {
                cursor += 1
                continue
            }
            let fullRange = NSRange(location: cursor, length: closeParenRange.upperBound - cursor)
            if !rangesIntersect(fullRange, targetRange) {
                cursor += 1
                continue
            }
            return unionRange(targetRange, fullRange)
        }
        return deletedBoxedExpressionRefreshRange(around: targetRange, in: source)
    }

    private static func deletedBoxedExpressionRefreshRange(around targetRange: NSRange, in source: NSString) -> NSRange? {
        var cursor = targetRange.location
        let upperBound = min(source.length, targetRange.upperBound)
        while cursor < upperBound {
            if let nextCursor = locationAfterSkippedCommentOrLiteral(startingAt: cursor, in: source) {
                cursor = min(nextCursor, upperBound)
                continue
            }
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character == "@",
               let closeParenRange = unmatchedClosingParenRange(after: cursor + 1, in: source) {
                return unionRange(targetRange, closeParenRange)
            }
            cursor += 1
        }
        return nil
    }

    private static func unmatchedClosingParenRange(after location: Int, in source: NSString) -> NSRange? {
        var cursor = min(max(0, location), source.length)
        var depth = 0
        while cursor < source.length {
            if let nextCursor = locationAfterSkippedCommentOrLiteral(startingAt: cursor, in: source) {
                cursor = nextCursor
                continue
            }

            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character == ";" || character == "{" || character == "}" {
                return nil
            }
            if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 {
                    return NSRange(location: cursor, length: 1)
                }
                depth -= 1
            }
            cursor += 1
        }
        return nil
    }

    private static func unionRange(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let lowerBound = min(lhs.location, rhs.location)
        let upperBound = max(lhs.upperBound, rhs.upperBound)
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
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
            || objectiveCTextContainsVariableDeclarationLine(nsText)
    }

    private static func objectiveCMutationReplacesPreviousStructuralSignatureText(
        _ mutation: SyntaxHighlightMutation,
        previousIndex: ObjectiveCSemanticIndex?
    ) -> Bool {
        guard mutation.length > 0,
              let previousIndex else {
            return false
        }

        return rangeIntersectsSortedRanges(
            NSRange(location: mutation.location, length: mutation.length),
            previousIndex.structuralEditRanges
        )
    }

    private static func semanticIndexSignature(in source: NSString) -> ObjectiveCSemanticIndexSignature {
        let lineSignatureIndex = ObjectiveCSemanticLineSignatureIndex(source: source)
        return ObjectiveCSemanticIndexSignature(
            fingerprint: lineSignatureIndex.fingerprint,
            structuralEditRanges: lineSignatureIndex.structuralEditRanges
        )
    }

    fileprivate static func objectiveCSemanticStructuralEditRanges(
        in line: NSString,
        lineOffset: Int
    ) -> [NSRange] {
        let lineString = line as String
        let fullRange = NSRange(location: 0, length: line.length)
        let structuralCharacterRanges = objectiveCSemanticStructuralCharacterRanges(
            in: line,
            lineOffset: lineOffset
        )

        guard let trimmedRange = objectiveCTrimmedRange(in: line) else {
            return structuralCharacterRanges
        }

        let trimmed = line.substring(with: trimmedRange)
        if trimmed.hasPrefix("#") {
            return [NSRange(location: lineOffset + trimmedRange.location, length: trimmedRange.length)]
        }

        if trimmed.hasPrefix("@property") {
            var ranges = structuralCharacterRanges
            if let keywordRange = objectiveCKeywordRange("@property", in: line) {
                ranges.append(NSRange(location: lineOffset + keywordRange.location, length: keywordRange.length))
            }
            if let nameRange = ObjectiveCFileSymbolIndex.propertyDeclaredNameRange(in: line) {
                ranges.append(NSRange(location: lineOffset + nameRange.location, length: nameRange.length))
            } else {
                return [NSRange(location: lineOffset + trimmedRange.location, length: trimmedRange.length)]
            }
            return sortedObjectiveCSemanticStructuralRanges(ranges)
        }

        if objectiveCForLoopVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            return sortedObjectiveCSemanticStructuralRanges(
                objectiveCDeclarationSignatureRanges(in: line, statementEnd: line.length)
                    .map { NSRange(location: lineOffset + $0.location, length: $0.length) }
            )
        }

        if objectiveCVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            let statementEnd = line.range(of: ";").location
            guard statementEnd != NSNotFound else {
                return [NSRange(location: lineOffset + trimmedRange.location, length: trimmedRange.length)]
            }
            return sortedObjectiveCSemanticStructuralRanges(
                objectiveCDeclarationSignatureRanges(in: line, statementEnd: statementEnd)
                    .map { NSRange(location: lineOffset + $0.location, length: $0.length) }
            )
        }

        guard structuralObjectiveCEditRegex.firstMatch(in: lineString, range: fullRange) != nil
            || objectiveCSemanticIndexFunctionSignatureLineRegex.firstMatch(in: lineString, range: fullRange) != nil
            || objectiveCSemanticIndexSplitFunctionNameLineRegex.firstMatch(in: lineString, range: fullRange) != nil else {
            return structuralCharacterRanges
        }

        var ranges = structuralCharacterRanges
        for match in ObjectiveCFileSymbolIndex.identifierRegex.matches(in: lineString, range: fullRange) {
            ranges.append(NSRange(location: lineOffset + match.range.location, length: match.range.length))
        }
        if ranges.isEmpty {
            ranges.append(NSRange(location: lineOffset + trimmedRange.location, length: trimmedRange.length))
        }
        return sortedObjectiveCSemanticStructuralRanges(ranges)
    }

    private static func objectiveCSemanticStructuralCharacterRanges(
        in line: NSString,
        lineOffset: Int
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < line.length {
            let searchRange = NSRange(location: cursor, length: line.length - cursor)
            let structuralRange = line.rangeOfCharacter(
                from: objectiveCSemanticStructuralCharacters,
                options: [],
                range: searchRange
            )
            guard structuralRange.location != NSNotFound else {
                break
            }
            ranges.append(NSRange(location: lineOffset + structuralRange.location, length: structuralRange.length))
            cursor = structuralRange.upperBound
        }
        return ranges
    }

    private static func sortedObjectiveCSemanticStructuralRanges(_ ranges: [NSRange]) -> [NSRange] {
        ranges
            .filter { $0.length > 0 }
            .sorted {
                if $0.location != $1.location {
                    return $0.location < $1.location
                }
                return $0.length < $1.length
            }
    }

    private static func objectiveCTrimmedRange(in line: NSString) -> NSRange? {
        var lower = 0
        var upper = line.length
        while lower < upper,
              objectiveCLineCharacterIsWhitespace(line.substring(with: NSRange(location: lower, length: 1))) {
            lower += 1
        }
        while upper > lower,
              objectiveCLineCharacterIsWhitespace(line.substring(with: NSRange(location: upper - 1, length: 1))) {
            upper -= 1
        }
        guard lower < upper else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    private static func objectiveCKeywordRange(_ keyword: String, in line: NSString) -> NSRange? {
        let range = line.range(of: keyword)
        guard range.location != NSNotFound else { return nil }
        return range
    }

    private static func objectiveCMutationMovesPreviousStructuralSignatureIntoNonCode(
        _ mutation: SyntaxHighlightMutation,
        in source: NSString,
        previousIndex: ObjectiveCSemanticIndex?
    ) -> Bool {
        guard let previousIndex,
              !previousIndex.structuralEditRanges.isEmpty,
              mutation.replacement.rangeOfCharacter(from: .newlines) == nil else {
            return false
        }

        let replacementLength = mutation.replacement.utf16.count
        let oldUpperBound = mutation.location + mutation.length
        let delta = replacementLength - mutation.length
        for range in previousIndex.structuralEditRanges {
            guard range.location >= oldUpperBound else { continue }

            let shiftedLocation = range.location + delta
            guard shiftedLocation >= 0,
                  shiftedLocation <= source.length else {
                continue
            }

            let lineRange = source.lineRange(for: NSRange(location: shiftedLocation, length: 0))
            guard lineRange.location <= mutation.location,
                  mutation.location <= shiftedLocation,
                  shiftedLocation <= lineRange.upperBound else {
                continue
            }

            let prefixRange = NSRange(
                location: lineRange.location,
                length: shiftedLocation - lineRange.location
            )
            if objectiveCTextCanStartCommentOrLiteral(source.substring(with: prefixRange)) {
                return true
            }
            if objectiveCMutationPrefixesLineSignatureWithNonWhitespace(
                mutation,
                lineRange: lineRange,
                shiftedSignatureLocation: shiftedLocation,
                in: source
            ) {
                return true
            }
        }
        return false
    }

    private static func objectiveCTextCanStartCommentOrLiteral(_ text: String) -> Bool {
        text.contains("//") || text.contains("/*") || text.contains("\"")
    }

    private static func objectiveCMutationPrefixesLineSignatureWithNonWhitespace(
        _ mutation: SyntaxHighlightMutation,
        lineRange: NSRange,
        shiftedSignatureLocation: Int,
        in source: NSString
    ) -> Bool {
        guard mutation.location < shiftedSignatureLocation,
              mutation.replacement.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else {
            return false
        }
        let prefixBeforeMutationRange = NSRange(
            location: lineRange.location,
            length: max(0, mutation.location - lineRange.location)
        )
        guard prefixBeforeMutationRange.upperBound <= source.length else {
            return false
        }
        return objectiveCLineCharacterIsWhitespace(source.substring(with: prefixBeforeMutationRange))
    }

    private static func objectiveCLineCharacterIsWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func objectiveCMutationRequiresSemanticIndexRebuild(
        _ mutation: SyntaxHighlightMutation,
        in source: NSString,
        previousIndex: ObjectiveCSemanticIndex?
    ) -> Bool {
        if previousIndex?.fileSymbols.mutationTouchesSelfMemberAccessOperator(mutation) == true {
            return true
        }

        let replacementLength = mutation.replacement.utf16.count
        let changedLocation = min(max(0, mutation.location), source.length)
        let changedStart = max(0, changedLocation - (mutation.length > 0 ? 1 : 0))
        let changedEnd = min(source.length, max(changedLocation + max(1, replacementLength), changedStart + 1))
        let changedRange = NSRange(location: changedStart, length: changedEnd - changedStart)
        let lineRange = source.lineRange(for: changedRange)
        let line = source.substring(with: lineRange) as NSString
        let relativeChangedRange = NSRange(
            location: max(0, changedRange.location - lineRange.location),
            length: changedRange.length
        )
        return objectiveCMutationCanChangeMemberAccessReceiver(
            line: line,
            relativeChangedRange: relativeChangedRange
        ) || objectiveCMutationCanChangeMemberAccessField(
            line: line,
            relativeChangedRange: relativeChangedRange
        )
    }

    private static func objectiveCMutationCanChangeSemanticSignature(
        _ mutation: SyntaxHighlightMutation,
        in source: NSString,
        previousIndex: ObjectiveCSemanticIndex?
    ) -> Bool {
        if objectiveCMutationReplacesPreviousStructuralSignatureText(mutation, previousIndex: previousIndex) {
            return true
        }
        if objectiveCMutationMovesPreviousStructuralSignatureIntoNonCode(
            mutation,
            in: source,
            previousIndex: previousIndex
        ) {
            return true
        }
        if let previousIndex,
           let shiftedLineSignatureIndex = previousIndex.lineSignatureIndex.applying(mutation, to: source) {
            return shiftedLineSignatureIndex.fingerprint != previousIndex.structuralFingerprint
        }
        if mutation.replacement.rangeOfCharacter(from: objectiveCSemanticStructuralCharacters) != nil {
            return true
        }

        let replacementLength = mutation.replacement.utf16.count
        let changedLocation = min(max(0, mutation.location), source.length)
        let changedStart = max(0, changedLocation - (mutation.length > 0 ? 1 : 0))
        let changedEnd = min(source.length, max(changedLocation + max(1, replacementLength), changedStart + 1))
        let changedRange = NSRange(location: changedStart, length: changedEnd - changedStart)
        let lineRange = source.lineRange(for: changedRange)
        let line = source.substring(with: lineRange) as NSString
        let lineString = line as String
        let fullRange = NSRange(location: 0, length: line.length)
        let relativeChangedRange = NSRange(
            location: max(0, changedRange.location - lineRange.location),
            length: changedRange.length
        )

        if objectiveCVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            let statementEnd = line.range(of: ";").location
            guard statementEnd != NSNotFound else { return true }
            return objectiveCDeclarationSignatureRanges(in: line, statementEnd: statementEnd)
                .contains { rangesIntersect($0, relativeChangedRange) }
        }

        if objectiveCForLoopVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            return objectiveCDeclarationSignatureRanges(in: line, statementEnd: line.length)
                .contains { rangesIntersect($0, relativeChangedRange) }
        }

        return structuralObjectiveCEditRegex.firstMatch(in: lineString, range: fullRange) != nil
            || objectiveCSemanticIndexFunctionSignatureLineRegex.firstMatch(in: lineString, range: fullRange) != nil
            || objectiveCSemanticIndexSplitFunctionNameLineRegex.firstMatch(in: lineString, range: fullRange) != nil
    }

    private static func objectiveCLocalStructuralRefreshRange(
        for mutation: SyntaxHighlightMutation,
        in source: NSString,
        previousIndex: ObjectiveCSemanticIndex?
    ) -> NSRange? {
        if objectiveCMutationReplacesPreviousStructuralSignatureText(mutation, previousIndex: previousIndex) {
            return nil
        }

        let replacementLength = mutation.replacement.utf16.count
        let changedLocation = min(max(0, mutation.location), source.length)
        let changedStart = max(0, changedLocation - (mutation.length > 0 ? 1 : 0))
        let changedEnd = min(source.length, max(changedLocation + max(1, replacementLength), changedStart + 1))
        let changedRange = NSRange(location: changedStart, length: changedEnd - changedStart)
        let lineRange = source.lineRange(for: changedRange)
        guard let scopeRange = ObjectiveCFileSymbolIndex.containingFunctionLikeScopeRange(
            containing: changedRange.location,
            in: source
        ) else {
            return nil
        }

        let line = source.substring(with: lineRange) as NSString
        let lineString = line as String
        let fullRange = NSRange(location: 0, length: line.length)
        let relativeChangedRange = NSRange(
            location: max(0, changedRange.location - lineRange.location),
            length: changedRange.length
        )

        if objectiveCVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            let statementEnd = line.range(of: ";").location
            guard statementEnd != NSNotFound else { return nil }
            let changesDeclarationName = objectiveCDeclarationSignatureRanges(in: line, statementEnd: statementEnd)
                .contains { rangesIntersect($0, relativeChangedRange) }
            return changesDeclarationName ? scopeRange : nil
        }

        if objectiveCForLoopVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            let changesDeclarationName = objectiveCDeclarationSignatureRanges(in: line, statementEnd: line.length)
                .contains { rangesIntersect($0, relativeChangedRange) }
            return changesDeclarationName ? scopeRange : nil
        }

        return nil
    }

    private static func objectiveCMutationCanChangeMemberAccessReceiver(
        line: NSString,
        relativeChangedRange: NSRange
    ) -> Bool {
        guard line.range(of: ".").location != NSNotFound
            || line.range(of: "->").location != NSNotFound
        else {
            return false
        }

        var cursor = 0
        while cursor < line.length {
            if let nextCursor = locationAfterSkippedCommentOrLiteral(startingAt: cursor, in: line) {
                cursor = nextCursor
                continue
            }

            let operatorRange: NSRange
            let character = line.substring(with: NSRange(location: cursor, length: 1))
            if character == "." {
                operatorRange = NSRange(location: cursor, length: 1)
            } else if character == "-",
                      cursor + 1 < line.length,
                      line.substring(with: NSRange(location: cursor + 1, length: 1)) == ">" {
                operatorRange = NSRange(location: cursor, length: 2)
            } else {
                cursor += 1
                continue
            }

            let expressionStart = expressionBoundaryBefore(location: operatorRange.location, in: line)
            guard expressionStart < operatorRange.location else {
                let operatorContextRange = NSRange(
                    location: max(0, operatorRange.location - 1),
                    length: min(line.length, operatorRange.upperBound + 1) - max(0, operatorRange.location - 1)
                )
                if rangesIntersect(operatorContextRange, relativeChangedRange),
                   memberFieldIdentifierRange(after: operatorRange.upperBound, in: line) != nil {
                    return true
                }
                cursor = operatorRange.upperBound
                continue
            }
            let expressionRange = NSRange(
                location: expressionStart,
                length: operatorRange.location - expressionStart
            )
            guard (rangesIntersect(expressionRange, relativeChangedRange)
                   || rangesIntersect(operatorRange, relativeChangedRange)),
                  memberFieldIdentifierRange(after: operatorRange.upperBound, in: line) != nil
            else {
                cursor = operatorRange.upperBound
                continue
            }
            return true
        }

        return false
    }

    private static func objectiveCMutationCanChangeMemberAccessField(
        line: NSString,
        relativeChangedRange: NSRange
    ) -> Bool {
        guard line.range(of: ".").location != NSNotFound
            || line.range(of: "->").location != NSNotFound
        else {
            return false
        }

        var cursor = 0
        while cursor < line.length {
            if let nextCursor = locationAfterSkippedCommentOrLiteral(startingAt: cursor, in: line) {
                cursor = nextCursor
                continue
            }

            let operatorRange: NSRange
            let character = line.substring(with: NSRange(location: cursor, length: 1))
            if character == "." {
                operatorRange = NSRange(location: cursor, length: 1)
            } else if character == "-",
                      cursor + 1 < line.length,
                      line.substring(with: NSRange(location: cursor + 1, length: 1)) == ">" {
                operatorRange = NSRange(location: cursor, length: 2)
            } else {
                cursor += 1
                continue
            }

            guard let fieldRange = memberFieldIdentifierRange(after: operatorRange.upperBound, in: line) else {
                cursor = operatorRange.upperBound
                continue
            }
            if rangesIntersect(fieldRange, relativeChangedRange) {
                return true
            }
            cursor = fieldRange.upperBound
        }

        return false
    }

    private static func memberFieldIdentifierRange(after location: Int, in line: NSString) -> NSRange? {
        var cursor = location
        while cursor < line.length {
            let character = line.substring(with: NSRange(location: cursor, length: 1)).first
            guard character?.isWhitespace == true else { break }
            cursor += 1
        }
        guard cursor < line.length,
              let firstCharacter = line.substring(with: NSRange(location: cursor, length: 1)).first,
              firstCharacter == "_" || firstCharacter.isLetter else {
            return nil
        }

        let start = cursor
        cursor += 1
        while cursor < line.length {
            guard let character = line.substring(with: NSRange(location: cursor, length: 1)).first,
                  isObjectiveCIdentifierCharacter(character) else {
                break
            }
            cursor += 1
        }
        return NSRange(location: start, length: cursor - start)
    }

    fileprivate static func appendObjectiveCSemanticIndexSignature(
        from line: NSString,
        lineOffset _: Int,
        into hasher: inout Hasher
    ) -> Bool {
        let lineString = line as String
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        let trimmed = lineString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("#") {
            hasher.combine("preprocessor")
            hasher.combine(trimmed)
            return true
        }

        if trimmed.hasPrefix("@property") {
            hasher.combine("property")
            if let nameRange = ObjectiveCFileSymbolIndex.propertyDeclaredNameRange(in: line) {
                hasher.combine(line.substring(with: nameRange))
                hasher.combine(nameRange.location)
            } else {
                hasher.combine(trimmed)
            }
            return true
        }

        if objectiveCForLoopVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            appendObjectiveCDeclarationNameSignature(
                kind: "for-variable",
                line: line,
                statementEnd: line.length,
                into: &hasher
            )
            return true
        }

        if objectiveCVariableDeclarationLineRegex.firstMatch(in: lineString, range: fullRange) != nil {
            let statementEnd = line.range(of: ";").location
            guard statementEnd != NSNotFound else { return false }
            appendObjectiveCDeclarationNameSignature(
                kind: "variable",
                line: line,
                statementEnd: statementEnd,
                into: &hasher
            )
            return true
        }

        guard structuralObjectiveCEditRegex.firstMatch(in: lineString, range: fullRange) != nil
            || objectiveCSemanticIndexFunctionSignatureLineRegex.firstMatch(in: lineString, range: fullRange) != nil
            || objectiveCSemanticIndexSplitFunctionNameLineRegex.firstMatch(in: lineString, range: fullRange) != nil else {
            return false
        }

        hasher.combine("structural")
        let identifiers = ObjectiveCFileSymbolIndex.identifierRegex.matches(in: lineString, range: fullRange)
        if identifiers.isEmpty {
            hasher.combine(trimmed)
            return true
        }
        for match in identifiers {
            let name = line.substring(with: match.range)
            guard !ObjectiveCFileSymbolIndex.typedefIgnoredIdentifiers.contains(name) else { continue }
            hasher.combine(name)
        }
        return true
    }

    private static func appendObjectiveCDeclarationNameSignature(
        kind: String,
        line: NSString,
        statementEnd: Int,
        into hasher: inout Hasher
    ) {
        let ranges = ObjectiveCFileSymbolIndex.declarationNameRanges(in: line, statementEnd: statementEnd)
        guard !ranges.isEmpty else { return }
        hasher.combine(kind)
        hasher.combine(objectiveCDeclarationShapeSignature(in: line, nameRanges: ranges, statementEnd: statementEnd))
        for range in ranges {
            let name = line.substring(with: range)
            guard !ObjectiveCFileSymbolIndex.typedefIgnoredIdentifiers.contains(name),
                  name != "const",
                  name != "static" else {
                continue
            }
            hasher.combine(name)
        }
    }

    private static func objectiveCDeclarationSignatureRanges(in line: NSString, statementEnd: Int) -> [NSRange] {
        let nameRanges = ObjectiveCFileSymbolIndex.declarationNameRanges(in: line, statementEnd: statementEnd)
        guard let firstNameRange = nameRanges.min(by: { $0.location < $1.location }) else { return [] }
        let shapeRange = NSRange(location: 0, length: max(0, min(firstNameRange.location, statementEnd)))
        if shapeRange.length > 0 {
            return [shapeRange] + nameRanges
        }
        return nameRanges
    }

    private static func objectiveCDeclarationShapeSignature(
        in line: NSString,
        nameRanges: [NSRange],
        statementEnd: Int
    ) -> String {
        guard let firstNameRange = nameRanges.min(by: { $0.location < $1.location }) else { return "" }
        let shapeLength = max(0, min(firstNameRange.location, statementEnd))
        guard shapeLength > 0 else { return "" }
        return line.substring(with: NSRange(location: 0, length: shapeLength))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func objectiveCTextContainsVariableDeclarationLine(_ text: NSString) -> Bool {
        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let line = text.substring(with: lineRange)
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            if objectiveCVariableDeclarationLineRegex.firstMatch(in: line, range: fullRange) != nil
                || objectiveCForLoopVariableDeclarationLineRegex.firstMatch(in: line, range: fullRange) != nil {
                return true
            }
            let nextLocation = lineRange.upperBound
            guard nextLocation > location else { break }
            location = nextLocation
        }
        return false
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

    private static func objectiveCTypeIdentifierShouldStayPlain(
        _ range: NSRange,
        text: String,
        in source: NSString
    ) -> Bool {
        let prefix = linePrefix(before: range, in: source)
        if prefix.contains("@property"), isUppercaseMacroLikeIdentifier(text) {
            return propertyMacroLikeIdentifierHasTrailingAttribute(range, in: source)
        }
        return prefix.range(
            of: #"\bNS_(?:ENUM|OPTIONS)\s*\(\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func propertyMacroLikeIdentifierHasTrailingAttribute(
        _ range: NSRange,
        in source: NSString
    ) -> Bool {
        let lineRange = source.lineRange(for: range)
        guard range.upperBound < lineRange.upperBound else {
            return false
        }
        let suffixRange = NSRange(
            location: range.upperBound,
            length: lineRange.upperBound - range.upperBound
        )
        let suffix = source.substring(with: suffixRange)
        guard let semicolon = suffix.firstIndex(of: ";") else {
            return false
        }
        let beforeSemicolon = suffix[..<semicolon]
        return beforeSemicolon.contains { !$0.isWhitespace }
    }

    private static func isUppercaseMacroLikeIdentifier(_ text: String) -> Bool {
        var hasUppercase = false
        var hasSeparator = false
        for scalar in text.unicodeScalars {
            if scalar == "_" {
                hasSeparator = true
                continue
            }
            if CharacterSet.decimalDigits.contains(scalar) {
                continue
            }
            guard CharacterSet.uppercaseLetters.contains(scalar) else {
                return false
            }
            hasUppercase = true
        }
        return hasUppercase && hasSeparator
    }

    private static func isCFunctionCallName(_ range: NSRange, in source: NSString) -> Bool {
        cCallOpeningParenLocation(after: range, in: source) != nil
    }

    private static func isObjectiveCCallName(_ range: NSRange, in source: NSString) -> Bool {
        isCFunctionCallName(range, in: source)
            && !lineStartsWithPreprocessorDirective(containing: range, in: source)
            && !isObjectiveCCFunctionDeclarationName(range, in: source)
    }

    private static func isObjectiveCFunctionPointerCastCalleeName(_ range: NSRange, in source: NSString) -> Bool {
        guard !lineStartsWithPreprocessorDirective(containing: range, in: source),
              !functionPointerNameLooksLikeDeclaration(range, in: source)
        else {
            return false
        }
        var cursor = range.upperBound
        while cursor < source.length {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cursor += 1
                continue
            }
            guard character == ")" else {
                return false
            }
            cursor += 1
            while cursor < source.length {
                let next = source.substring(with: NSRange(location: cursor, length: 1))
                if next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cursor += 1
                    continue
                }
                return next == "("
            }
            return false
        }
        return false
    }

    private static func cCallOpeningParenLocation(after range: NSRange, in source: NSString) -> Int? {
        var cursor = range.upperBound
        while cursor < source.length {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cursor += 1
                continue
            }
            return character == "(" ? cursor : nil
        }
        return nil
    }

    private static func functionPointerNameLooksLikeDeclaration(_ range: NSRange, in source: NSString) -> Bool {
        let prefix = linePrefix(before: range, in: source)
        if prefix.contains("@property") {
            return true
        }
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        if trimmedPrefix.hasPrefix("typedef") {
            return true
        }
        if trimmedPrefix.range(
            of: #"^(?:[A-Za-z_][A-Za-z0-9_]*\s+)+\*+$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return false
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

    private static func isObjectiveCFunctionOrMethodDeclarationName(_ range: NSRange, in source: NSString) -> Bool {
        let prefix = linePrefix(before: range, in: source)
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        if trimmedPrefix.hasPrefix("-") || trimmedPrefix.hasPrefix("+") {
            return true
        }
        if prefix.contains("[") {
            return false
        }
        return looksLikeCFunctionDeclarationPrefix(before: range, in: source)
    }

    fileprivate static func isObjectiveCCFunctionDeclarationName(_ range: NSRange, in source: NSString) -> Bool {
        let prefix = linePrefix(before: range, in: source)
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        guard !trimmedPrefix.hasPrefix("-"),
              !trimmedPrefix.hasPrefix("+"),
              !prefix.contains("[")
        else {
            return false
        }
        guard looksLikeCFunctionDeclarationPrefix(before: range, in: source),
              let openParen = cCallOpeningParenLocation(after: range, in: source),
              let closeParenRange = matchingCloseParenRange(openingAt: openParen, in: source)
        else {
            return false
        }
        var cursor = closeParenRange.upperBound
        while cursor < source.length {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cursor += 1
                continue
            }
            return character == "{" || character == ";"
        }
        return false
    }

    private static func isMessageReceiverName(_ range: NSRange, in source: NSString) -> Bool {
        previousNonWhitespaceCharacter(before: range, in: source) == "["
    }

    fileprivate static func isSelfMemberName(_ range: NSRange, in source: NSString) -> Bool {
        guard let expressionPrefix = memberAccessExpressionPrefix(before: range, in: source) else {
            return false
        }
        return expressionPrefixEndsWithSelf(expressionPrefix)
    }

    fileprivate static func isMemberNameInKnownSelfChain(
        _ range: NSRange,
        in source: NSString,
        localProperties: Set<String>,
        allowsHeaderBackedMembers: Bool
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
            guard shouldTrackSelfMember(
                firstMember,
                localProperties: localProperties,
                allowsHeaderBackedMembers: allowsHeaderBackedMembers
            ) else {
                continue
            }
            let beforeSelf = expression.substring(to: selfRange.location)
            if wrappedSelfClosingRange.location != NSNotFound,
               wrappedSelfClosingRange.length > 0,
               !allowsWrappedSelfChainStart(beforeSelf) {
                continue
            }
            let suffix = expression.substring(from: match.range.upperBound)
            if suffixStartsWithCall(suffix) || suffixContainsNestedMemberAccess(suffix) {
                continue
            }
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

    fileprivate static func shouldTrackSelfMember(
        _ name: String,
        localProperties: Set<String>,
        allowsHeaderBackedMembers: Bool
    ) -> Bool {
        if localProperties.contains(name) {
            return true
        }
        guard allowsHeaderBackedMembers else {
            return false
        }

        // Objective-C implementations can rely on properties declared in an imported
        // header that the runtime highlighter cannot load. Keep a lexical fallback
        // for header-backed self members, while avoiding macro-shaped declarations
        // that Xcode leaves plain in the current fixtures.
        return !isUppercaseMacroLikeIdentifier(name)
    }

    private static func suffixStartsWithCall(_ suffix: String) -> Bool {
        var index = suffix.startIndex
        while index < suffix.endIndex {
            if let nextIndex = indexAfterSkippableTriviaOrLiteral(startingAt: index, in: suffix) {
                index = nextIndex
                continue
            }
            let character = suffix[index]
            if character.isWhitespace {
                index = suffix.index(after: index)
                continue
            }
            return character == "("
        }
        return false
    }

    private static func suffixContainsNestedMemberAccess(_ suffix: String) -> Bool {
        var index = suffix.startIndex
        while index < suffix.endIndex {
            if let nextIndex = indexAfterSkippableTriviaOrLiteral(startingAt: index, in: suffix) {
                index = nextIndex
                continue
            }
            let character = suffix[index]
            if character == "." {
                return true
            }
            if character == "-" {
                let nextIndex = suffix.index(after: index)
                if nextIndex < suffix.endIndex, suffix[nextIndex] == ">" {
                    return true
                }
            }
            index = suffix.index(after: index)
        }
        return false
    }

    private static func memberAccessExpressionPrefix(before range: NSRange, in source: NSString) -> String? {
        guard let operatorRange = memberAccessOperatorRange(before: range, in: source) else {
            return nil
        }

        let start = expressionBoundaryBefore(location: operatorRange.location, in: source)
        guard start < operatorRange.location else {
            return nil
        }
        return source.substring(with: NSRange(location: start, length: operatorRange.location - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func memberAccessOperatorRange(before range: NSRange, in source: NSString) -> NSRange? {
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

        return NSRange(location: operatorStart, length: range.location - operatorStart)
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
            rawCaptureName: EditorSyntaxCapture.rawCaptureName(syntaxID: syntaxID, language: .objectiveC),
            isSemanticOverlay: true
        )
    }

    private static func preparedOverlayInput(
        from tokens: [SyntaxHighlightToken],
        source: NSString,
        targetRange: NSRange?,
        tokenPrefixMaxUpperBounds: [Int]? = nil,
        preparesFullIndex: Bool = true
    ) -> ObjectiveCOverlayPreparation {
        if let targetRange, !preparesFullIndex {
            return preparedPartialTaggedOverlayInput(
                from: tokens,
                source: source,
                targetRange: targetRange,
                tokenPrefixMaxUpperBounds: tokenPrefixMaxUpperBounds
            )
        }

        if targetRange != nil, tokens.contains(where: \.isSemanticOverlay) {
            return preparedTaggedOverlayInput(
                from: tokens,
                source: source,
                targetRange: targetRange,
                tokenPrefixMaxUpperBounds: tokenPrefixMaxUpperBounds,
                preparesFullIndex: preparesFullIndex
            )
        }

        let indexRange = preparesFullIndex ? nil : targetRange
        var syntaxIDsByRange: [ObjectiveCRangeKey: ObjectiveCSyntaxIDMask] = [:]
        for token in tokens where token.language == .objectiveC || token.language == nil {
            syntaxIDsByRange[ObjectiveCRangeKey(token.range), default: []]
                .formUnion(ObjectiveCSyntaxIDMask(syntaxID: token.syntaxID))
        }
        let preprocessorRanges = tokens.compactMap { token -> NSRange? in
            guard (token.language == .objectiveC || token.language == nil),
                  token.syntaxID == .preprocessor else {
                return nil
            }
            return token.range
        }

        var baseTokensForIndex: [SyntaxHighlightToken] = []
        var outputBaseTokens: [SyntaxHighlightToken] = []
        var preservedOverlayTokens: [SyntaxHighlightToken] = []
        baseTokensForIndex.reserveCapacity(preparesFullIndex ? tokens.count : 256)
        outputBaseTokens.reserveCapacity(tokens.count)
        preservedOverlayTokens.reserveCapacity(tokens.count / 4)

        for token in tokens {
            let syntaxIDs = syntaxIDsByRange[ObjectiveCRangeKey(token.range)] ?? []
            let preparesTokenForIndex = indexRange.map {
                rangesIntersect(token.range, $0)
            } ?? true
            let isOverlayToken = isObjectiveCSemanticOverlayToken(
                token,
                syntaxIDsAtSameRange: syntaxIDs,
                source: source,
                preprocessorRanges: preprocessorRanges,
                strippingSemanticOverlaysIn: nil
            )
            if preparesTokenForIndex && !isOverlayToken {
                baseTokensForIndex.append(token)
            }

            let stripsFromOutput = targetRange.map { stripRange in
                isObjectiveCSemanticOverlayToken(
                    token,
                    syntaxIDsAtSameRange: syntaxIDs,
                    source: source,
                    preprocessorRanges: preprocessorRanges,
                    strippingSemanticOverlaysIn: stripRange
                )
            } ?? isOverlayToken
            if !stripsFromOutput {
                if isOverlayToken {
                    preservedOverlayTokens.append(token)
                } else {
                    outputBaseTokens.append(token)
                }
            }
        }

        return ObjectiveCOverlayPreparation(
            baseTokensForIndex: baseTokensForIndex,
            outputBaseTokens: outputBaseTokens,
            preservedOverlayTokens: preservedOverlayTokens,
            nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex(
                tokens: baseTokensForIndex,
                sourceLength: source.length
            ),
            tokenIndex: ObjectiveCTokenIndex(tokens: baseTokensForIndex, source: source),
            partialMergeTargetRange: nil,
            partialMergeTokenRange: nil
        )
    }

    private static func preparedTaggedOverlayInput(
        from tokens: [SyntaxHighlightToken],
        source: NSString,
        targetRange: NSRange?,
        tokenPrefixMaxUpperBounds: [Int]?,
        preparesFullIndex: Bool
    ) -> ObjectiveCOverlayPreparation {
        if let targetRange, !preparesFullIndex {
            return preparedPartialTaggedOverlayInput(
                from: tokens,
                source: source,
                targetRange: targetRange,
                tokenPrefixMaxUpperBounds: tokenPrefixMaxUpperBounds
            )
        }

        let indexRange = preparesFullIndex ? nil : targetRange
        var baseTokensForIndex: [SyntaxHighlightToken] = []
        var outputBaseTokens: [SyntaxHighlightToken] = []
        var preservedOverlayTokens: [SyntaxHighlightToken] = []
        baseTokensForIndex.reserveCapacity(preparesFullIndex ? tokens.count : 256)
        outputBaseTokens.reserveCapacity(tokens.count)
        preservedOverlayTokens.reserveCapacity(tokens.count / 4)

        for token in tokens {
            let preparesTokenForIndex = indexRange.map {
                rangesIntersect(token.range, $0)
            } ?? true
            if preparesTokenForIndex && !token.isSemanticOverlay {
                baseTokensForIndex.append(token)
            }

            let stripsFromOutput = targetRange.map {
                token.isSemanticOverlay && rangesIntersect(token.range, $0)
            } ?? token.isSemanticOverlay
            guard !stripsFromOutput else {
                continue
            }
            if token.isSemanticOverlay {
                preservedOverlayTokens.append(token)
            } else {
                outputBaseTokens.append(token)
            }
        }

        return ObjectiveCOverlayPreparation(
            baseTokensForIndex: baseTokensForIndex,
            outputBaseTokens: outputBaseTokens,
            preservedOverlayTokens: preservedOverlayTokens,
            nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex(
                tokens: baseTokensForIndex,
                sourceLength: source.length
            ),
            tokenIndex: ObjectiveCTokenIndex(tokens: baseTokensForIndex, source: source),
            partialMergeTargetRange: nil,
            partialMergeTokenRange: nil
        )
    }

    private static func preparedPartialTaggedOverlayInput(
        from tokens: [SyntaxHighlightToken],
        source: NSString,
        targetRange: NSRange,
        tokenPrefixMaxUpperBounds: [Int]?
    ) -> ObjectiveCOverlayPreparation {
        let clampedTargetRange = SyntaxEditorRangeUtilities.clampedRange(
            targetRange,
            utf16Length: source.length
        )
        let tokenRange = tokenIndexRangeForPartialMerge(
            in: tokens,
            targetRange: clampedTargetRange,
            tokenPrefixMaxUpperBounds: tokenPrefixMaxUpperBounds
        )
        var baseTokensForIndex: [SyntaxHighlightToken] = []
        baseTokensForIndex.reserveCapacity(tokenRange.count)

        for token in tokens[tokenRange] where !token.isSemanticOverlay {
            guard rangesIntersect(token.range, clampedTargetRange) else { continue }
            baseTokensForIndex.append(token)
        }

        return ObjectiveCOverlayPreparation(
            baseTokensForIndex: baseTokensForIndex,
            outputBaseTokens: [],
            preservedOverlayTokens: [],
            nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex(
                tokens: baseTokensForIndex,
                sourceLength: source.length
            ),
            tokenIndex: ObjectiveCTokenIndex(tokens: baseTokensForIndex, source: source),
            partialMergeTargetRange: clampedTargetRange,
            partialMergeTokenRange: tokenRange
        )
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

    private static func partialMergedTokens(
        existingTokens: [SyntaxHighlightToken],
        replacementOverlayTokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        tokenRange: Range<Int>
    ) -> [SyntaxHighlightToken] {
        var baseSegment: [SyntaxHighlightToken] = []
        var overlaySegment: [SyntaxHighlightToken] = []
        baseSegment.reserveCapacity(tokenRange.count)
        overlaySegment.reserveCapacity(tokenRange.count + replacementOverlayTokens.count)
        for token in existingTokens[tokenRange] {
            if token.isSemanticOverlay {
                guard !rangesIntersect(token.range, targetRange) else {
                    continue
                }
                overlaySegment.append(token)
            } else {
                baseSegment.append(token)
            }
        }
        overlaySegment.append(contentsOf: replacementOverlayTokens)
        let segment = deduplicated(mergedTokens(baseTokens: baseSegment, overlayTokens: overlaySegment))

        var merged = existingTokens
        merged.replaceSubrange(tokenRange, with: segment)
        return merged
    }

    private static func tokenIndexRangeForPartialMerge(
        in tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        tokenPrefixMaxUpperBounds: [Int]?
    ) -> Range<Int> {
        guard targetRange.length > 0 else { return 0..<0 }

        let prefixMaxUpperBounds = if let tokenPrefixMaxUpperBounds,
                                      tokenPrefixMaxUpperBounds.count == tokens.count {
            tokenPrefixMaxUpperBounds
        } else {
            prefixMaxUpperBounds(for: tokens)
        }
        let startIndex = firstTokenIndex(
            intersecting: targetRange,
            prefixMaxUpperBounds: prefixMaxUpperBounds
        )
        var upperBound = lowerBoundForTokenLocation(targetRange.upperBound, in: tokens)
        while upperBound < tokens.count,
              tokens[upperBound].range.location < targetRange.upperBound {
            upperBound += 1
        }
        return startIndex..<upperBound
    }

    private static func prefixMaxUpperBounds(for tokens: [SyntaxHighlightToken]) -> [Int] {
        var prefixMaxUpperBounds: [Int] = []
        prefixMaxUpperBounds.reserveCapacity(tokens.count)
        var maxUpperBound = 0
        for token in tokens {
            maxUpperBound = max(maxUpperBound, token.range.upperBound)
            prefixMaxUpperBounds.append(maxUpperBound)
        }
        return prefixMaxUpperBounds
    }

    private static func firstTokenIndex(
        intersecting range: NSRange,
        prefixMaxUpperBounds: [Int]
    ) -> Int {
        var lowerBound = 0
        var upperBound = prefixMaxUpperBounds.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if prefixMaxUpperBounds[middle] <= range.location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private static func lowerBoundForTokenLocation(
        _ location: Int,
        in tokens: [SyntaxHighlightToken]
    ) -> Int {
        var lowerBound = 0
        var upperBound = tokens.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if tokens[middle].range.location < location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private static func isObjectiveCSemanticOverlayToken(
        _ token: SyntaxHighlightToken,
        syntaxIDsAtSameRange: ObjectiveCSyntaxIDMask,
        source: NSString,
        preprocessorRanges: [NSRange],
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
        case .plain:
            guard token.range.upperBound <= source.length else {
                return false
            }
            let text = source.substring(with: token.range)
            return (text == "Class" && syntaxIDsAtSameRange.contains(.keyword))
                || objectiveCTypeIdentifierShouldStayPlain(token.range, text: text, in: source)
        case .declarationType,
             .identifierConstantSystem:
            return true
        case .identifierTypeSystem:
            guard token.range.upperBound <= source.length else {
                return false
            }
            return objectiveCTypeIdentifierShouldStayPlain(
                token.range,
                text: source.substring(with: token.range),
                in: source
            )
        case .string:
            guard token.range.location >= 0,
                  token.range.length > 0,
                  token.range.upperBound <= source.length,
                  source.substring(with: NSRange(location: token.range.location, length: 1)) == "\"" else {
                return false
            }
            return lineStartsWithPreprocessorDirective(containing: token.range, in: source)
                && rangeIsContainedInPreprocessorToken(token.range, preprocessorRanges: preprocessorRanges)
        case .preprocessor:
            guard syntaxIDsAtSameRange.contains(.plain) else {
                return false
            }
            let text = source.substring(with: token.range)
            return !preprocessorObjectiveCMacroIdentifiers.contains(text)
                && !lineStartsWithPreprocessorDirective(containing: token.range, in: source)
        case .number:
            return isBoxedExpressionDelimiterRange(token.range, in: source)
                || isBoxedBooleanLiteralRange(token.range, in: source)
                || isPotentialStaleBoxedLiteralNumberRange(token.range, in: source)
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
            guard token.range.upperBound <= source.length else {
                return false
            }
            if appleMacroFunctionNames.contains(source.substring(with: token.range)) {
                return true
            }
            return isCFunctionCallName(token.range, in: source)
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

    private static func lineStartsWithPreprocessorDirective(containing range: NSRange, in source: NSString) -> Bool {
        guard range.location >= 0,
              range.location <= source.length else {
            return false
        }
        let location = min(range.location, max(source.length - 1, 0))
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let line = source.substring(with: lineRange)
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    private static func rangeIsContainedInPreprocessorToken(
        _ range: NSRange,
        preprocessorRanges: [NSRange]
    ) -> Bool {
        preprocessorRanges.contains { preprocessorRange in
            preprocessorRange != range
                && preprocessorRange.location <= range.location
                && preprocessorRange.upperBound >= range.upperBound
        }
    }

    private static func isBoxedExpressionDelimiterRange(_ range: NSRange, in source: NSString) -> Bool {
        guard range.length == 1,
              range.location >= 0,
              range.upperBound <= source.length else {
            return false
        }
        let character = source.substring(with: range)
        if character == "@" {
            return range.upperBound < source.length
                && source.substring(with: NSRange(location: range.upperBound, length: 1)) == "("
        }
        if character == "(" {
            return range.location > 0
                && source.substring(with: NSRange(location: range.location - 1, length: 1)) == "@"
        }
        if character == ")" {
            return boxedExpressionOpeningParenLocation(closingAt: range.location, in: source) != nil
        }
        return false
    }

    private static func isPotentialStaleBoxedExpressionDelimiterRange(_ range: NSRange, in source: NSString) -> Bool {
        guard range.length == 1,
              range.location >= 0,
              range.upperBound <= source.length else {
            return false
        }
        let character = source.substring(with: range)
        return character == "(" || character == ")"
    }

    private static func isPotentialStaleBoxedLiteralNumberRange(_ range: NSRange, in source: NSString) -> Bool {
        guard range.location >= 0,
              range.length > 0,
              range.upperBound <= source.length else {
            return false
        }
        if isPotentialStaleBoxedExpressionDelimiterRange(range, in: source) {
            return true
        }
        let text = source.substring(with: range)
        if ["@", "{", "}", "[", "]"].contains(text) {
            return false
        }
        return objectiveCNumericLiteralTextRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        ) == nil
    }

    private static func isBoxedBooleanLiteralRange(_ range: NSRange, in source: NSString) -> Bool {
        guard range.location >= 0,
              range.upperBound <= source.length else {
            return false
        }
        let text = source.substring(with: range)
        if text == "@NO" || text == "@YES" {
            return true
        }
        guard text == "NO" || text == "YES",
              range.location > 0 else {
            return false
        }
        return source.substring(with: NSRange(location: range.location - 1, length: 1)) == "@"
    }

    private static func matchingCloseParenRange(openingAt openParenLocation: Int, in source: NSString) -> NSRange? {
        guard openParenLocation >= 0,
              openParenLocation < source.length,
              source.substring(with: NSRange(location: openParenLocation, length: 1)) == "(" else {
            return nil
        }

        var depth = 0
        var cursor = openParenLocation
        while cursor < source.length {
            if let nextCursor = locationAfterSkippedCommentOrLiteral(startingAt: cursor, in: source) {
                cursor = nextCursor
                continue
            }

            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return NSRange(location: cursor, length: 1)
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func boxedExpressionOpeningParenLocation(closingAt closeParenLocation: Int, in source: NSString) -> Int? {
        guard closeParenLocation > 0,
              closeParenLocation < source.length,
              source.substring(with: NSRange(location: closeParenLocation, length: 1)) == ")" else {
            return nil
        }

        var depth = 0
        var cursor = closeParenLocation
        while cursor >= 0 {
            let character = source.substring(with: NSRange(location: cursor, length: 1))
            if character == ")" {
                depth += 1
            } else if character == "(" {
                depth -= 1
                if depth == 0 {
                    guard cursor > 0,
                          source.substring(with: NSRange(location: cursor - 1, length: 1)) == "@" else {
                        return nil
                    }
                    return cursor
                }
            }
            if cursor == 0 {
                break
            }
            cursor -= 1
        }
        return nil
    }

    private static func locationAfterSkippedCommentOrLiteral(startingAt location: Int, in source: NSString) -> Int? {
        guard location >= 0,
              location < source.length else {
            return nil
        }
        let character = source.substring(with: NSRange(location: location, length: 1))
        let next = location + 1 < source.length
            ? source.substring(with: NSRange(location: location + 1, length: 1))
            : ""

        if character == "\"" || character == "'" {
            var cursor = location + 1
            while cursor < source.length {
                if source.substring(with: NSRange(location: cursor, length: 1)) == character,
                   !isEscaped(cursor, in: source) {
                    return cursor + 1
                }
                cursor += 1
            }
            return source.length
        }

        if character == "/", next == "/" {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            return lineRange.upperBound
        }

        if character == "/", next == "*" {
            var cursor = location + 2
            while cursor + 1 < source.length {
                let current = source.substring(with: NSRange(location: cursor, length: 1))
                let following = source.substring(with: NSRange(location: cursor + 1, length: 1))
                if current == "*", following == "/" {
                    return cursor + 2
                }
                cursor += 1
            }
            return source.length
        }

        return nil
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
        pattern: #"(?m)^\s*(?:@(?:class|end|implementation|interface|property|protocol)|typedef\b|static\b(?![^\n;{}]*\([^;{}]*\)\s*[;{])[^;\n{}]*(?:=|;)|[-+]\s*\(|[A-Za-z_][A-Za-z0-9_ <>,_*]*\([^;{}]*\)\s*[;{]|[A-Za-z_][A-Za-z0-9_ <>,_*]*\*+\s*[A-Za-z_][A-Za-z0-9_]*\s*;)|\bNS_(?:ENUM|OPTIONS)\b|^\s*#"#
    )

    private static let objectiveCVariableDeclarationLineRegex = try! NSRegularExpression(
        pattern: #"^\s*(?!(?:return|if|for|while|switch|case|break|continue|goto|else|do)\b)[A-Za-z_][A-Za-z0-9_ <>,_*]*[ \t*]+[A-Za-z_][A-Za-z0-9_]*\s*(?:=|;)"#
    )

    private static let objectiveCForLoopVariableDeclarationLineRegex = try! NSRegularExpression(
        pattern: #"\bfor\s*\(\s*[A-Za-z_][A-Za-z0-9_ <>,_*]*[ \t*]+[A-Za-z_][A-Za-z0-9_]*\s*(?:=|in\b)"#
    )

    private static let objectiveCSemanticIndexFunctionSignatureLineRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:[-+]\s*\(|(?:static\s+)?[A-Za-z_][A-Za-z0-9_ <>,_*]*[ \t*]+[A-Za-z_][A-Za-z0-9_]*\s*\()"#
    )

    private static let objectiveCSemanticIndexSplitFunctionNameLineRegex = try! NSRegularExpression(
        pattern: #"^\s*(?!(?:return|if|for|while|switch|case|break|continue|goto|else|do|sizeof)\b)[A-Za-z_][A-Za-z0-9_]*\s*\([^;{}=]*\)"#
    )

    private static let preprocessorQuotedStringRegex = try! NSRegularExpression(
        pattern: #"@?"(?:\\.|[^"\\])*""#
    )

    private static let boxedBooleanLiteralRegex = try! NSRegularExpression(
        pattern: #"@(YES|NO)\b"#
    )

    private static let objectiveCNumericLiteralTextRegex = try! NSRegularExpression(
        pattern: #"^(?:0[xX][0-9A-Fa-f_]+|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+-]?[0-9_]+)?)[uUlLfF]*$"#
    )

    private static let preprocessorObjectiveCMacroRegex = try! NSRegularExpression(
        pattern: #"\b(?:NS_ASSUME_NONNULL_BEGIN|NS_ASSUME_NONNULL_END|NS_ENUM|NS_OPTIONS|NS_SWIFT_NAME)\b"#
    )

    private static let macroLikeObjectiveCIdentifierRegex = try! NSRegularExpression(
        pattern: #"\b[A-Z][A-Z0-9_]*_[A-Z0-9_]+\b"#
    )

    private static let appleMacroFunctionNames: Set<String> = [
        "NS_ENUM",
        "NS_OPTIONS",
    ]

    private static let preprocessorObjectiveCMacroIdentifiers: Set<String> = [
        "NS_ASSUME_NONNULL_BEGIN",
        "NS_ASSUME_NONNULL_END",
        "NS_ENUM",
        "NS_OPTIONS",
        "NS_SWIFT_NAME",
    ]

    private static let knownObjectiveCSystemFunctionNames: Set<String> = [
        "NSClassFromString",
        "NSLog",
        "NSMakeRange",
        "NSSelectorFromString",
        "NSStringFromSelector",
        "calloc",
        "dispatch_once",
        "dlsym",
        "free",
        "objc_msgSend",
        "sel_getName",
        "strcmp",
        "strstr",
    ]

    private static let knownObjectiveCFunctionPointerCastCallees: Set<String> = [
        "objc_msgSend",
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
    var localMacros = Set<String>()
    var fileScopeVariables = Set<String>()
    var ivars = Set<String>()
    var typeDeclarations: [(name: String, range: NSRange)] = []
    var propertyDeclarations: [(name: String, range: NSRange)] = []
    var fileScopeVariableDeclarations: [(name: String, range: NSRange)] = []
    var ivarDeclarations: [(name: String, range: NSRange)] = []
    var selfMemberNameRangeKeys = Set<ObjectiveCRangeKey>()
    var selfMemberCandidates: [(member: String, fieldRange: NSRange)] = []
    var selfChainMemberNameRangeKeys = Set<ObjectiveCRangeKey>()
    var selfChainCandidates: [(firstMember: String, fieldRange: NSRange)] = []
}

private struct ObjectiveCFileSymbolIndex {
    let localTypes: Set<String>
    let localFunctions: Set<String>
    let localProperties: Set<String>
    private let localMacros: Set<String>
    private let fileScopeVariables: Set<String>
    private let ivars: Set<String>
    private let allowsHeaderBackedSelfMembers: Bool
    private let typeDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>
    private let propertyDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>
    private let fileScopeVariableDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>
    private let ivarDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>
    private let shadowedVariableRangeKeys: Set<ObjectiveCRangeKey>
    private let selfMemberNameRangeKeys: Set<ObjectiveCRangeKey>
    private let selfChainMemberNameRangeKeys: Set<ObjectiveCRangeKey>
    private let selfMemberAccessOperatorRangeKeys: Set<ObjectiveCRangeKey>

    init?(
        source: NSString,
        tokenIndex: ObjectiveCTokenIndex,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex,
        rootNode: Node? = nil,
        allowsCancellation: Bool = false
    ) {
        if allowsCancellation, Task.isCancelled {
            return nil
        }
        let treeFacts: ObjectiveCTreeSymbolFacts
        if let rootNode {
            guard let facts = Self.collectTreeSymbolFacts(
                from: rootNode,
                source: source,
                tokenIndex: tokenIndex,
                allowsCancellation: allowsCancellation
            ) else {
                return nil
            }
            treeFacts = facts
        } else {
            treeFacts = ObjectiveCTreeSymbolFacts()
        }

        var localTypes = treeFacts.localTypes
        var localFunctions = treeFacts.localFunctions
        let localMacros = Self.scanDefinedMacroNames(
            source: source,
            nonCodeRangeIndex: nonCodeRangeIndex
        ).union(treeFacts.localMacros)
        var fileScopeVariables = treeFacts.fileScopeVariables
        var ivars = treeFacts.ivars
        var typeDeclarations = treeFacts.typeDeclarations
        var propertyDeclarations = treeFacts.propertyDeclarations
        var fileScopeVariableDeclarations = treeFacts.fileScopeVariableDeclarations
        var ivarDeclarations = treeFacts.ivarDeclarations
        let allowsHeaderBackedSelfMembers = Self.hasQuotedHeaderImport(in: source)
        let zeroArgumentMethodNameRanges = rootNode == nil ? Self.zeroArgumentMethodNameRanges(in: source) : []
        var localProperties = treeFacts.localProperties
        localProperties.formUnion(propertyDeclarations.map(\.name))
        let scannedLocalTypes = Self.scanLocalTypes(source: source, nonCodeRangeIndex: nonCodeRangeIndex)
        localTypes.formUnion(scannedLocalTypes.names)
        typeDeclarations.append(contentsOf: scannedLocalTypes.declarations)
        let scannedFileScopeVariables = Self.scanFileScopeVariableDeclarations(
            source: source,
            nonCodeRangeIndex: nonCodeRangeIndex
        )
        fileScopeVariables.formUnion(scannedFileScopeVariables.map(\.name))
        fileScopeVariableDeclarations.append(contentsOf: scannedFileScopeVariables)
        let scannedIvars = Self.scanImplementationIvarDeclarations(
            source: source,
            nonCodeRangeIndex: nonCodeRangeIndex
        )
        ivars.formUnion(scannedIvars.map(\.name))
        ivarDeclarations.append(contentsOf: scannedIvars)
        let shadowedVariableRangeKeys = Self.scanVariableShadowRanges(
            source: source,
            shadowedNames: fileScopeVariables.union(ivars),
            nonCodeRangeIndex: nonCodeRangeIndex
        )

        if rootNode == nil {
            propertyDeclarations.append(contentsOf: Self.scanLocalPropertyDeclarations(source: source, tokenIndex: tokenIndex))
            localProperties.formUnion(propertyDeclarations.map(\.name))
        }

        for token in tokenIndex.identifierTokens {
            if allowsCancellation, Task.isCancelled {
                return nil
            }
            let text = source.substring(with: token.range)

            switch token.syntaxID {
            case .identifierType:
                localTypes.insert(text)
            case .identifierFunction:
                if ObjectiveCSyntaxOverlayTokenProvider.isObjectiveCCFunctionDeclarationName(token.range, in: source) {
                    localFunctions.insert(text)
                }
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

        var selfMemberNameRangeKeys = treeFacts.selfMemberNameRangeKeys
        for candidate in treeFacts.selfMemberCandidates
            where ObjectiveCSyntaxOverlayTokenProvider.shouldTrackSelfMember(
                candidate.member,
                localProperties: localProperties,
                allowsHeaderBackedMembers: allowsHeaderBackedSelfMembers
            ) {
            selfMemberNameRangeKeys.insert(ObjectiveCRangeKey(candidate.fieldRange))
        }

        var selfChainMemberNameRangeKeys = treeFacts.selfChainMemberNameRangeKeys
        for candidate in treeFacts.selfChainCandidates
            where ObjectiveCSyntaxOverlayTokenProvider.shouldTrackSelfMember(
                candidate.firstMember,
                localProperties: localProperties,
                allowsHeaderBackedMembers: allowsHeaderBackedSelfMembers
            ) {
            selfChainMemberNameRangeKeys.insert(ObjectiveCRangeKey(candidate.fieldRange))
        }

        for token in tokenIndex.identifierTokens {
            if allowsCancellation, Task.isCancelled {
                return nil
            }
            let text = source.substring(with: token.range)
            if ObjectiveCSyntaxOverlayTokenProvider.shouldTrackSelfMember(
                text,
                localProperties: localProperties,
                allowsHeaderBackedMembers: allowsHeaderBackedSelfMembers
            ),
               ObjectiveCSyntaxOverlayTokenProvider.isSelfMemberName(token.range, in: source) {
                selfMemberNameRangeKeys.insert(ObjectiveCRangeKey(token.range))
                continue
            }
            if ObjectiveCSyntaxOverlayTokenProvider.isMemberNameInKnownSelfChain(
                token.range,
                in: source,
                localProperties: localProperties,
                allowsHeaderBackedMembers: allowsHeaderBackedSelfMembers
            ) {
                selfChainMemberNameRangeKeys.insert(ObjectiveCRangeKey(token.range))
            }
        }

        self.localTypes = localTypes
        self.localFunctions = localFunctions
        self.localProperties = localProperties
        self.localMacros = localMacros
        self.fileScopeVariables = fileScopeVariables
        self.ivars = ivars
        self.allowsHeaderBackedSelfMembers = allowsHeaderBackedSelfMembers
        self.typeDeclarationNameRangeKeys = Set(typeDeclarations.map { ObjectiveCRangeKey($0.range) })
        self.propertyDeclarationNameRangeKeys = Set(propertyDeclarations.map { ObjectiveCRangeKey($0.range) })
        self.fileScopeVariableDeclarationNameRangeKeys = Set(fileScopeVariableDeclarations.map { ObjectiveCRangeKey($0.range) })
        self.ivarDeclarationNameRangeKeys = Set(ivarDeclarations.map { ObjectiveCRangeKey($0.range) })
        self.shadowedVariableRangeKeys = shadowedVariableRangeKeys
        self.selfMemberNameRangeKeys = selfMemberNameRangeKeys
        self.selfChainMemberNameRangeKeys = selfChainMemberNameRangeKeys
        self.selfMemberAccessOperatorRangeKeys = Self.memberAccessOperatorRangeKeys(
            before: selfMemberNameRangeKeys.union(selfChainMemberNameRangeKeys),
            in: source
        )
    }

    private init(
        localTypes: Set<String>,
        localFunctions: Set<String>,
        localProperties: Set<String>,
        localMacros: Set<String>,
        fileScopeVariables: Set<String>,
        ivars: Set<String>,
        allowsHeaderBackedSelfMembers: Bool,
        typeDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>,
        propertyDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>,
        fileScopeVariableDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>,
        ivarDeclarationNameRangeKeys: Set<ObjectiveCRangeKey>,
        shadowedVariableRangeKeys: Set<ObjectiveCRangeKey>,
        selfMemberNameRangeKeys: Set<ObjectiveCRangeKey>,
        selfChainMemberNameRangeKeys: Set<ObjectiveCRangeKey>,
        selfMemberAccessOperatorRangeKeys: Set<ObjectiveCRangeKey>
    ) {
        self.localTypes = localTypes
        self.localFunctions = localFunctions
        self.localProperties = localProperties
        self.localMacros = localMacros
        self.fileScopeVariables = fileScopeVariables
        self.ivars = ivars
        self.allowsHeaderBackedSelfMembers = allowsHeaderBackedSelfMembers
        self.typeDeclarationNameRangeKeys = typeDeclarationNameRangeKeys
        self.propertyDeclarationNameRangeKeys = propertyDeclarationNameRangeKeys
        self.fileScopeVariableDeclarationNameRangeKeys = fileScopeVariableDeclarationNameRangeKeys
        self.ivarDeclarationNameRangeKeys = ivarDeclarationNameRangeKeys
        self.shadowedVariableRangeKeys = shadowedVariableRangeKeys
        self.selfMemberNameRangeKeys = selfMemberNameRangeKeys
        self.selfChainMemberNameRangeKeys = selfChainMemberNameRangeKeys
        self.selfMemberAccessOperatorRangeKeys = selfMemberAccessOperatorRangeKeys
    }

    func shifted(
        by mutation: SyntaxHighlightMutation,
        sourceUTF16Length nextSourceUTF16Length: Int
    ) -> ObjectiveCFileSymbolIndex? {
        guard let shiftedTypeDeclarationNameRangeKeys = Self.shiftedRangeKeys(
            typeDeclarationNameRangeKeys,
            by: mutation,
            sourceUTF16Length: nextSourceUTF16Length
        ),
              let shiftedPropertyDeclarationNameRangeKeys = Self.shiftedRangeKeys(
                propertyDeclarationNameRangeKeys,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
              ),
              let shiftedFileScopeVariableDeclarationNameRangeKeys = Self.shiftedRangeKeys(
                fileScopeVariableDeclarationNameRangeKeys,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
              ),
              let shiftedIvarDeclarationNameRangeKeys = Self.shiftedRangeKeys(
                ivarDeclarationNameRangeKeys,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
              ),
              let shiftedShadowedVariableRangeKeys = Self.shiftedRangeKeys(
                shadowedVariableRangeKeys,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
              ),
              let shiftedSelfMemberNameRangeKeys = Self.shiftedRangeKeys(
                selfMemberNameRangeKeys,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
              ),
              let shiftedSelfChainMemberNameRangeKeys = Self.shiftedRangeKeys(
                selfChainMemberNameRangeKeys,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
              ),
              let shiftedSelfMemberAccessOperatorRangeKeys = Self.shiftedRangeKeys(
                selfMemberAccessOperatorRangeKeys,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
              ) else {
            return nil
        }

        return ObjectiveCFileSymbolIndex(
            localTypes: localTypes,
            localFunctions: localFunctions,
            localProperties: localProperties,
            localMacros: localMacros,
            fileScopeVariables: fileScopeVariables,
            ivars: ivars,
            allowsHeaderBackedSelfMembers: allowsHeaderBackedSelfMembers,
            typeDeclarationNameRangeKeys: shiftedTypeDeclarationNameRangeKeys,
            propertyDeclarationNameRangeKeys: shiftedPropertyDeclarationNameRangeKeys,
            fileScopeVariableDeclarationNameRangeKeys: shiftedFileScopeVariableDeclarationNameRangeKeys,
            ivarDeclarationNameRangeKeys: shiftedIvarDeclarationNameRangeKeys,
            shadowedVariableRangeKeys: shiftedShadowedVariableRangeKeys,
            selfMemberNameRangeKeys: shiftedSelfMemberNameRangeKeys,
            selfChainMemberNameRangeKeys: shiftedSelfChainMemberNameRangeKeys,
            selfMemberAccessOperatorRangeKeys: shiftedSelfMemberAccessOperatorRangeKeys
        )
    }

    func containsTypeDeclarationNameRange(_ range: NSRange) -> Bool {
        typeDeclarationNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsPropertyDeclarationNameRange(_ range: NSRange) -> Bool {
        propertyDeclarationNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsFileScopeVariableName(_ name: String) -> Bool {
        fileScopeVariables.contains(name)
    }

    func containsFileScopeVariableDeclarationNameRange(_ range: NSRange) -> Bool {
        fileScopeVariableDeclarationNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsIvarName(_ name: String) -> Bool {
        ivars.contains(name)
    }

    func containsIvarDeclarationNameRange(_ range: NSRange) -> Bool {
        ivarDeclarationNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsShadowedVariableRange(_ range: NSRange) -> Bool {
        shadowedVariableRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsLocalMacroName(_ name: String) -> Bool {
        localMacros.contains(name)
    }

    func containsSelfMemberNameRange(_ range: NSRange) -> Bool {
        selfMemberNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func containsSelfChainMemberNameRange(_ range: NSRange) -> Bool {
        selfChainMemberNameRangeKeys.contains(ObjectiveCRangeKey(range))
    }

    func mutationTouchesSelfMemberAccessOperator(_ mutation: SyntaxHighlightMutation) -> Bool {
        guard mutation.length > 0 else {
            return false
        }
        let replacedRange = NSRange(location: mutation.location, length: mutation.length)
        return selfMemberAccessOperatorRangeKeys.contains(where: {
            SyntaxEditorRangeUtilities.intersection(
                of: replacedRange,
                and: NSRange(location: $0.location, length: $0.length)
            ).length > 0
        })
    }

    func shouldTrackSelfMemberName(_ name: String) -> Bool {
        ObjectiveCSyntaxOverlayTokenProvider.shouldTrackSelfMember(
            name,
            localProperties: localProperties,
            allowsHeaderBackedMembers: allowsHeaderBackedSelfMembers
        )
    }

    static func containingFunctionLikeScopeRange(containing location: Int, in source: NSString) -> NSRange? {
        functionLikeScopes(in: source)
            .first { scope in
                scope.location <= location && location < scope.upperBound
            }
            .map { scope in
                NSRange(location: scope.location, length: scope.upperBound - scope.location)
            }
    }

    private static func shiftedRangeKeys(
        _ keys: Set<ObjectiveCRangeKey>,
        by mutation: SyntaxHighlightMutation,
        sourceUTF16Length nextSourceUTF16Length: Int
    ) -> Set<ObjectiveCRangeKey>? {
        var shifted = Set<ObjectiveCRangeKey>()
        shifted.reserveCapacity(keys.count)
        for key in keys {
            let range = NSRange(location: key.location, length: key.length)
            guard let shiftedRange = shiftedRange(
                range,
                by: mutation,
                sourceUTF16Length: nextSourceUTF16Length
            ) else {
                return nil
            }
            shifted.insert(ObjectiveCRangeKey(shiftedRange))
        }
        return shifted
    }

    private static func memberAccessOperatorRangeKeys(
        before fieldRangeKeys: Set<ObjectiveCRangeKey>,
        in source: NSString
    ) -> Set<ObjectiveCRangeKey> {
        var operatorRangeKeys = Set<ObjectiveCRangeKey>()
        operatorRangeKeys.reserveCapacity(fieldRangeKeys.count)
        for key in fieldRangeKeys {
            let range = NSRange(location: key.location, length: key.length)
            guard let operatorRange = ObjectiveCSyntaxOverlayTokenProvider.memberAccessOperatorRange(
                before: range,
                in: source
            ) else {
                continue
            }
            operatorRangeKeys.insert(ObjectiveCRangeKey(operatorRange))
        }
        return operatorRangeKeys
    }

    private static func shiftedRange(
        _ range: NSRange,
        by mutation: SyntaxHighlightMutation,
        sourceUTF16Length nextSourceUTF16Length: Int
    ) -> NSRange? {
        let replacementLength = mutation.replacement.utf16.count
        let replacedRange = NSRange(location: mutation.location, length: mutation.length)
        let oldUpperBound = mutation.location + mutation.length
        let delta = replacementLength - mutation.length

        if range.upperBound <= mutation.location {
            return range
        }
        if mutation.length == 0,
           replacementLength > 0,
           range.location < mutation.location,
           mutation.location < range.upperBound {
            return nil
        }
        if range.location >= oldUpperBound {
            let shiftedLocation = range.location + delta
            guard shiftedLocation >= 0,
                  shiftedLocation + range.length <= nextSourceUTF16Length else {
                return nil
            }
            return NSRange(location: shiftedLocation, length: range.length)
        }
        if SyntaxEditorRangeUtilities.intersection(of: range, and: replacedRange).length > 0 {
            return nil
        }
        return range
    }

    private static func hasQuotedHeaderImport(in source: NSString) -> Bool {
        quotedHeaderImportRegex.firstMatch(
            in: source as String,
            range: NSRange(location: 0, length: source.length)
        ) != nil
    }

    private static func collectTreeSymbolFacts(
        from rootNode: Node,
        source: NSString,
        tokenIndex: ObjectiveCTokenIndex,
        allowsCancellation: Bool
    ) -> ObjectiveCTreeSymbolFacts? {
        var facts = ObjectiveCTreeSymbolFacts()
        guard collectTreeSymbolFacts(
            from: rootNode,
            source: source,
            tokenIndex: tokenIndex,
            allowsCancellation: allowsCancellation,
            into: &facts
        ) else {
            return nil
        }
        return facts
    }

    @discardableResult
    private static func collectTreeSymbolFacts(
        from node: Node,
        source: NSString,
        tokenIndex: ObjectiveCTokenIndex,
        allowsCancellation: Bool,
        into facts: inout ObjectiveCTreeSymbolFacts
    ) -> Bool {
        if allowsCancellation, Task.isCancelled {
            return false
        }
        switch node.nodeType {
        case "class_interface", "class_implementation", "protocol_declaration":
            if let nameNode = primaryTypeIdentifier(in: node, source: source) {
                let name = source.substring(with: nameNode.range)
                facts.localTypes.insert(name)
                facts.typeDeclarations.append((name: name, range: nameNode.range))
            }
        case "class_declaration", "protocol_forward_declaration":
            for nameNode in directIdentifierChildren(in: node) {
                let name = source.substring(with: nameNode.range)
                facts.localTypes.insert(name)
                facts.typeDeclarations.append((name: name, range: nameNode.range))
            }
        case "type_definition":
            collectTypeDefinitionFacts(from: node, source: source, into: &facts)
        case "enum_specifier", "struct_specifier", "union_specifier":
            if let nameNode = node.child(byFieldName: "name") ?? directChild(in: node, nodeType: "type_identifier") {
                facts.localTypes.insert(source.substring(with: nameNode.range))
            }
        case "property_declaration":
            collectPropertyFacts(from: node, source: source, tokenIndex: tokenIndex, into: &facts)
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
            guard collectTreeSymbolFacts(
                from: child,
                source: source,
                tokenIndex: tokenIndex,
                allowsCancellation: allowsCancellation,
                into: &facts
            ) else {
                return false
            }
        }
        return true
    }

    private static func collectTypeDefinitionFacts(
        from node: Node,
        source: NSString,
        into facts: inout ObjectiveCTreeSymbolFacts
    ) {
        let declaration = source.substring(with: node.range) as NSString
        if let declaredName = nsEnumOptionsTypedefDeclaredName(in: declaration) {
            facts.localTypes.insert(declaredName.name)
            facts.typeDeclarations.append((
                name: declaredName.name,
                range: NSRange(
                    location: node.range.location + declaredName.range.location,
                    length: declaredName.range.length
                )
            ))
            return
        }
        for declarator in children(in: node, fieldName: "declarator") {
            if let identifier = declaratorIdentifier(in: declarator, preferredTypes: ["type_identifier", "identifier"]) {
                let name = source.substring(with: identifier.range)
                facts.localTypes.insert(name)
                facts.typeDeclarations.append((name: name, range: identifier.range))
            }
        }
    }

    private static func collectPropertyFacts(
        from node: Node,
        source: NSString,
        tokenIndex: ObjectiveCTokenIndex,
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
        for range in tokenIndex.declarationOtherIdentifierRanges(in: declarationRange) {
            let name = source.substring(with: range)
            facts.localProperties.insert(name)
            facts.propertyDeclarations.append((name: name, range: range))
            didCollectFromToken = true
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
        if propertyReferenceShouldBeTracked(name: name, range: relativeNameRange, in: declaration) {
            facts.localProperties.insert(name)
        }
        guard !didCollectFromToken else {
            return
        }
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
            facts.selfMemberCandidates.append((
                member: source.substring(with: fieldNode.range),
                fieldRange: fieldNode.range
            ))
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

    private static func scanLocalTypes(
        source: NSString,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex
    ) -> (names: Set<String>, declarations: [(name: String, range: NSRange)]) {
        let string = source as String
        let fullRange = NSRange(location: 0, length: source.length)
        var names = Set<String>()
        var declarations: [(name: String, range: NSRange)] = []

        for regex in localTypeRegexes {
            for match in regex.matches(in: string, range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let range = match.range(at: 1)
                guard range.location != NSNotFound,
                      !nonCodeRangeIndex.intersects(range) else { continue }
                let name = source.substring(with: range)
                if isIdentifier(name) {
                    names.insert(name)
                    declarations.append((name: name, range: range))
                }
            }
        }

        for match in typedefRegex.matches(in: string, range: fullRange) {
            let range = match.range
            guard !nonCodeRangeIndex.intersects(range) else { continue }
            let declaration = source.substring(with: range) as NSString
            if let name = typedefDeclaredName(in: declaration) {
                let relativeRange = declaration.range(of: name, options: [.backwards])
                guard relativeRange.location != NSNotFound else {
                    continue
                }
                names.insert(name)
                declarations.append((
                    name: name,
                    range: NSRange(location: range.location + relativeRange.location, length: relativeRange.length)
                ))
            }
        }

        return (names, declarations)
    }

    private static func scanDefinedMacroNames(
        source: NSString,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex
    ) -> Set<String> {
        let string = source as String
        let fullRange = NSRange(location: 0, length: source.length)
        var names = Set<String>()
        for match in definedMacroNameRegex.matches(in: string, range: fullRange) {
            let range = match.range(at: 1)
            guard range.location != NSNotFound,
                  !nonCodeRangeIndex.intersects(range) else {
                continue
            }
            names.insert(source.substring(with: range))
        }
        return names
    }

    private static func scanFileScopeVariableDeclarations(
        source: NSString,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex
    ) -> [(name: String, range: NSRange)] {
        var declarations: [(name: String, range: NSRange)] = []
        var location = 0
        var braceDepth = 0
        var isInBlockComment = false
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange) as NSString
            let depthBeforeLine = braceDepth
            defer {
                let result = objectiveCBraceDepth(
                    afterScanning: line,
                    startingAt: braceDepth,
                    isInBlockComment: isInBlockComment
                )
                braceDepth = result.depth
                isInBlockComment = result.isInBlockComment
                let nextLocation = lineRange.upperBound
                location = nextLocation > location ? nextLocation : source.length
            }

            let codeStart = firstNonWhitespaceLocation(in: line)
            let afterStatic = codeStart + "static".utf16.count
            guard depthBeforeLine == 0,
                  !isInBlockComment,
                  codeStart < line.length,
                  line.length - codeStart >= "static".utf16.count,
                  line.substring(with: NSRange(location: codeStart, length: "static".utf16.count)) == "static",
                  afterStatic == line.length || !isASCIIIdentifierContinue(line.character(at: afterStatic)) else {
                continue
            }
            let statementEnd = firstLocation(ofAny: [";"], in: line, before: line.length)
            let firstTerminator = firstLocation(ofAny: ["=", ";"], in: line, before: line.length)
            guard statementEnd != NSNotFound,
                  firstTerminator != NSNotFound,
                  line.range(of: "(", options: [], range: NSRange(location: 0, length: firstTerminator)).location == NSNotFound else {
                continue
            }
            for relativeRange in declarationNameRanges(in: line, statementEnd: statementEnd) {
                let absoluteRange = NSRange(
                    location: lineRange.location + relativeRange.location,
                    length: relativeRange.length
                )
                let name = line.substring(with: relativeRange)
                guard !typedefIgnoredIdentifiers.contains(name),
                      name != "const",
                      name != "static",
                      !nonCodeRangeIndex.intersects(absoluteRange) else {
                    continue
                }
                declarations.append((
                    name: name,
                    range: absoluteRange
                ))
            }
        }
        return declarations
    }

    private static func firstNonWhitespaceLocation(in line: NSString) -> Int {
        var cursor = 0
        while cursor < line.length {
            if !isWhitespaceCodeUnit(line.character(at: cursor)) {
                return cursor
            }
            cursor += 1
        }
        return line.length
    }

    static func declarationNameRanges(in declaration: NSString, statementEnd: Int) -> [NSRange] {
        let upperBound = min(max(0, statementEnd), declaration.length)
        var ranges: [NSRange] = []
        var segmentStart = 0
        var cursor = 0
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var angleDepth = 0
        while cursor < upperBound {
            if let nextCursor = indexAfterCommentOrQuotedLiteral(startingAt: cursor, in: declaration) {
                cursor = min(nextCursor, upperBound)
                continue
            }
            let character = declaration.character(at: cursor)
            if character == commaCodeUnit,
               parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               angleDepth == 0 {
                if let range = declarationNameRange(
                    in: NSRange(location: segmentStart, length: cursor - segmentStart),
                    declaration: declaration
                ) {
                    ranges.append(range)
                }
                segmentStart = cursor + 1
                cursor += 1
                continue
            }
            updateDeclarationDelimiterDepth(
                character: character,
                next: cursor + 1 < declaration.length
                    ? declaration.character(at: cursor + 1)
                    : 0,
                parenDepth: &parenDepth,
                bracketDepth: &bracketDepth,
                braceDepth: &braceDepth,
                angleDepth: &angleDepth
            )
            cursor += 1
        }
        if let range = declarationNameRange(
            in: NSRange(location: segmentStart, length: upperBound - segmentStart),
            declaration: declaration
        ) {
            ranges.append(range)
        }
        return ranges
    }

    private static func declarationNameRange(in segmentRange: NSRange, declaration: NSString) -> NSRange? {
        let searchEnd = declarationAssignmentLocation(in: segmentRange, declaration: declaration) ?? segmentRange.upperBound
        var end = min(searchEnd, declaration.length)
        while end > segmentRange.location,
              isWhitespaceCodeUnit(declaration.character(at: end - 1)) {
            end -= 1
        }
        guard let range = identifierRange(before: end, in: declaration) else {
            return nil
        }
        let name = declaration.substring(with: range)
        guard isIdentifier(name),
              !typedefIgnoredIdentifiers.contains(name),
              name != "const",
              name != "static" else {
            return nil
        }
        return range
    }

    private static func declarationAssignmentLocation(in segmentRange: NSRange, declaration: NSString) -> Int? {
        var cursor = max(0, segmentRange.location)
        let upperBound = min(segmentRange.upperBound, declaration.length)
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var angleDepth = 0
        while cursor < upperBound {
            if let nextCursor = indexAfterCommentOrQuotedLiteral(startingAt: cursor, in: declaration) {
                cursor = min(nextCursor, upperBound)
                continue
            }
            let character = declaration.character(at: cursor)
            if character == equalsCodeUnit,
               parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               angleDepth == 0 {
                return cursor
            }
            updateDeclarationDelimiterDepth(
                character: character,
                next: cursor + 1 < declaration.length
                    ? declaration.character(at: cursor + 1)
                    : 0,
                parenDepth: &parenDepth,
                bracketDepth: &bracketDepth,
                braceDepth: &braceDepth,
                angleDepth: &angleDepth
            )
            cursor += 1
        }
        return nil
    }

    private static let backslashCodeUnit: unichar = 92
    private static let colonCodeUnit: unichar = 58
    private static let commaCodeUnit: unichar = 44
    private static let doubleQuoteCodeUnit: unichar = 34
    private static let equalsCodeUnit: unichar = 61
    private static let greaterThanCodeUnit: unichar = 62
    private static let lessThanCodeUnit: unichar = 60
    private static let openBraceCodeUnit: unichar = 123
    private static let openBracketCodeUnit: unichar = 91
    private static let openParenCodeUnit: unichar = 40
    private static let closeBraceCodeUnit: unichar = 125
    private static let closeBracketCodeUnit: unichar = 93
    private static let closeParenCodeUnit: unichar = 41
    private static let semicolonCodeUnit: unichar = 59
    private static let singleQuoteCodeUnit: unichar = 39
    private static let slashCodeUnit: unichar = 47
    private static let starCodeUnit: unichar = 42

    private static func singleUTF16CodeUnit(_ text: String) -> unichar? {
        var iterator = text.utf16.makeIterator()
        guard let first = iterator.next(),
              iterator.next() == nil else {
            return nil
        }
        return first
    }

    private static func isWhitespaceCodeUnit(_ codeUnit: unichar) -> Bool {
        switch codeUnit {
        case 9, 10, 11, 12, 13, 32:
            return true
        default:
            return false
        }
    }

    private static func updateDeclarationDelimiterDepth(
        character: unichar,
        next: unichar,
        parenDepth: inout Int,
        bracketDepth: inout Int,
        braceDepth: inout Int,
        angleDepth: inout Int
    ) {
        if character == openParenCodeUnit {
            parenDepth += 1
        } else if character == closeParenCodeUnit {
            parenDepth = max(0, parenDepth - 1)
        } else if character == openBracketCodeUnit {
            bracketDepth += 1
        } else if character == closeBracketCodeUnit {
            bracketDepth = max(0, bracketDepth - 1)
        } else if character == openBraceCodeUnit {
            braceDepth += 1
        } else if character == closeBraceCodeUnit {
            braceDepth = max(0, braceDepth - 1)
        } else if character == lessThanCodeUnit,
                  next != lessThanCodeUnit,
                  parenDepth == 0,
                  bracketDepth == 0,
                  braceDepth == 0 {
            angleDepth += 1
        } else if character == greaterThanCodeUnit,
                  angleDepth > 0,
                  next != greaterThanCodeUnit {
            angleDepth -= 1
        }
    }

    private static func updateDeclarationDelimiterDepth(
        character: String,
        next: String,
        parenDepth: inout Int,
        bracketDepth: inout Int,
        braceDepth: inout Int,
        angleDepth: inout Int
    ) {
        if character == "(" {
            parenDepth += 1
        } else if character == ")" {
            parenDepth = max(0, parenDepth - 1)
        } else if character == "[" {
            bracketDepth += 1
        } else if character == "]" {
            bracketDepth = max(0, bracketDepth - 1)
        } else if character == "{" {
            braceDepth += 1
        } else if character == "}" {
            braceDepth = max(0, braceDepth - 1)
        } else if character == "<",
                  next != "<",
                  parenDepth == 0,
                  bracketDepth == 0,
                  braceDepth == 0 {
            angleDepth += 1
        } else if character == ">",
                  angleDepth > 0,
                  next != ">" {
            angleDepth -= 1
        }
    }

    private static func scanVariableShadowRanges(
        source: NSString,
        shadowedNames: Set<String>,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex
    ) -> Set<ObjectiveCRangeKey> {
        guard !shadowedNames.isEmpty else {
            return []
        }

        var ranges = Set<ObjectiveCRangeKey>()
        for scope in functionLikeScopes(in: source) {
            var parameterShadowStarts: [String: Int] = [:]
            collectParameterShadows(
                in: NSRange(location: scope.location, length: scope.bodyOpenLocation - scope.location),
                source: source,
                shadowedNames: shadowedNames,
                nonCodeRangeIndex: nonCodeRangeIndex,
                into: &parameterShadowStarts
            )
            var shadowScopes = parameterShadowStarts.compactMap { name, start -> (name: String, range: NSRange)? in
                guard start < scope.upperBound else { return nil }
                return (name, NSRange(location: start, length: scope.upperBound - start))
            }
            collectLocalVariableShadows(
                in: scope,
                source: source,
                shadowedNames: shadowedNames,
                nonCodeRangeIndex: nonCodeRangeIndex,
                into: &shadowScopes
            )

            for shadowScope in shadowScopes {
                for range in identifierRanges(named: shadowScope.name, in: shadowScope.range, source: source) {
                    guard !nonCodeRangeIndex.intersects(range) else { continue }
                    ranges.insert(ObjectiveCRangeKey(range))
                }
            }
        }
        return ranges
    }

    private static func functionLikeScopes(in source: NSString) -> [(location: Int, bodyOpenLocation: Int, upperBound: Int)] {
        var scopes: [(location: Int, bodyOpenLocation: Int, upperBound: Int)] = []
        var pendingStart: Int?
        var pendingSplitCFunctionStart: Int?
        var location = 0

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange) as NSString
            let lineString = line as String
            defer {
                let nextLocation = lineRange.upperBound
                location = nextLocation > location ? nextLocation : source.length
            }

            if pendingStart == nil,
               objectiveCFunctionLikeSignatureLineRegex.firstMatch(
                in: lineString,
                range: NSRange(location: 0, length: line.length)
               ) != nil {
                pendingStart = lineRange.location
                pendingSplitCFunctionStart = nil
            } else if pendingStart == nil,
                      let splitStart = pendingSplitCFunctionStart,
                      isObjectiveCSplitCFunctionNameLine(line) {
                pendingStart = splitStart
                pendingSplitCFunctionStart = nil
            } else if pendingStart == nil,
                      isObjectiveCSplitCFunctionReturnTypeLine(line) {
                pendingSplitCFunctionStart = lineRange.location
            } else if pendingStart == nil {
                pendingSplitCFunctionStart = nil
            }

            guard let start = pendingStart else {
                continue
            }

            if let openBraceRange = firstBraceRange(in: line, brace: "{") {
                let openBraceLocation = lineRange.location + openBraceRange.location
                if let closeBraceLocation = matchingClosingBraceLocation(in: source, openBraceLocation: openBraceLocation) {
                    scopes.append((
                        location: start,
                        bodyOpenLocation: openBraceLocation,
                        upperBound: closeBraceLocation + 1
                    ))
                }
                pendingStart = nil
            } else if firstCodeCharacterRange(in: line, character: ";") != nil {
                pendingStart = nil
            }
        }

        return scopes
    }

    private static func isObjectiveCSplitCFunctionReturnTypeLine(_ line: NSString) -> Bool {
        let trimmed = (line as String).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("@"),
              !trimmed.hasPrefix("-"),
              !trimmed.hasPrefix("+"),
              !trimmed.hasPrefix("//"),
              !trimmed.hasPrefix("/*"),
              !trimmed.contains("("),
              !trimmed.contains(")"),
              !trimmed.contains("="),
              !trimmed.contains(";"),
              !trimmed.contains("{"),
              !trimmed.contains("}") else {
            return false
        }

        let nsTrimmed = trimmed as NSString
        guard let firstIdentifier = identifierRegex.firstMatch(
            in: trimmed,
            range: NSRange(location: 0, length: nsTrimmed.length)
        ) else {
            return false
        }
        let leadingIdentifier = nsTrimmed.substring(with: firstIdentifier.range)
        return !objectiveCStatementLeadingIdentifiers.contains(leadingIdentifier)
    }

    private static func isObjectiveCSplitCFunctionNameLine(_ line: NSString) -> Bool {
        let string = line as String
        let fullRange = NSRange(location: 0, length: line.length)
        guard objectiveCSplitCFunctionNameLineRegex.firstMatch(in: string, range: fullRange) != nil,
              firstLocation(ofAny: ["="], in: line, before: line.length) == NSNotFound else {
            return false
        }
        return true
    }

    private static func collectParameterShadows(
        in headerRange: NSRange,
        source: NSString,
        shadowedNames: Set<String>,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex,
        into shadowStarts: inout [String: Int]
    ) {
        guard headerRange.length > 0 else { return }
        let header = source.substring(with: headerRange) as NSString
        let matches = identifierRegex.matches(in: header as String, range: NSRange(location: 0, length: header.length))
        for match in matches {
            let name = header.substring(with: match.range)
            guard shadowedNames.contains(name),
                  methodParameterNameRange(match.range, in: header)
                    || cParameterNameRange(match.range, in: header) else {
                continue
            }
            let absoluteLocation = headerRange.location + match.range.location
            guard !nonCodeRangeIndex.intersects(
                NSRange(location: absoluteLocation, length: match.range.length)
            ) else {
                continue
            }
            shadowStarts[name] = min(shadowStarts[name] ?? absoluteLocation, absoluteLocation)
        }
    }

    private static func collectLocalVariableShadows(
        in scope: (location: Int, bodyOpenLocation: Int, upperBound: Int),
        source: NSString,
        shadowedNames: Set<String>,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex,
        into shadowScopes: inout [(name: String, range: NSRange)]
    ) {
        let bodyStart = min(source.length, scope.bodyOpenLocation + 1)
        let bodyEnd = max(bodyStart, min(source.length, scope.upperBound - 1))
        let bodyRange = NSRange(location: bodyStart, length: bodyEnd - bodyStart)
        let body = source.substring(with: bodyRange) as NSString
        for match in objectiveCLocalVariableShadowDeclarationRegex.matches(
            in: body as String,
            range: NSRange(location: 0, length: body.length)
        ) {
            let anchorRange = match.range(at: 1)
            guard anchorRange.location != NSNotFound else { continue }
            let absoluteLineRange = source.lineRange(
                for: NSRange(location: bodyRange.location + anchorRange.location, length: 0)
            )
            let line = source.substring(with: absoluteLineRange) as NSString
            let statementEnd = firstLocation(ofAny: [";"], in: line, before: line.length)
            let firstTerminator = firstLocation(ofAny: ["=", ";"], in: line, before: line.length)
            guard statementEnd != NSNotFound,
                  firstTerminator != NSNotFound,
                  line.range(of: "(", options: [], range: NSRange(location: 0, length: firstTerminator)).location == NSNotFound else {
                continue
            }
            for nameRange in declarationNameRanges(in: line, statementEnd: statementEnd) {
                let absoluteLocation = absoluteLineRange.location + nameRange.location
                guard !nonCodeRangeIndex.intersects(
                    NSRange(location: absoluteLocation, length: nameRange.length)
                ) else {
                    continue
                }
                let name = line.substring(with: nameRange)
                guard shadowedNames.contains(name) else { continue }
                let upperBound = localVariableShadowUpperBound(startingAt: absoluteLocation, in: source, scope: scope)
                shadowScopes.append((
                    name: name,
                    range: NSRange(location: absoluteLocation, length: max(0, upperBound - absoluteLocation))
                ))
            }
        }

        for match in objectiveCForLoopVariableShadowDeclarationRegex.matches(
            in: body as String,
            range: NSRange(location: 0, length: body.length)
        ) {
            let matchRange = NSRange(location: bodyRange.location + match.range.location, length: match.range.length)
            let upperBound = forLoopShadowUpperBound(
                matchRange: matchRange,
                source: source,
                nonCodeRangeIndex: nonCodeRangeIndex,
                scopeUpperBound: scope.upperBound
            )
            for nameRange in forLoopDeclarationNameRanges(
                matchRange: matchRange,
                source: source
            ) {
                let absoluteLocation = nameRange.location
                guard !nonCodeRangeIndex.intersects(nameRange) else {
                    continue
                }
                let name = source.substring(with: nameRange)
                guard shadowedNames.contains(name) else { continue }
                shadowScopes.append((
                    name: name,
                    range: NSRange(location: absoluteLocation, length: max(0, upperBound - absoluteLocation))
                ))
            }
        }
    }

    private static func localVariableShadowUpperBound(
        startingAt location: Int,
        in source: NSString,
        scope: (location: Int, bodyOpenLocation: Int, upperBound: Int)
    ) -> Int {
        guard let openBrace = innermostOpenBraceLocation(
            containing: location,
            lowerBound: scope.bodyOpenLocation,
            in: source
        ),
              let closeBrace = matchingClosingBraceLocation(in: source, openBraceLocation: openBrace) else {
            return scope.upperBound
        }
        return min(scope.upperBound, closeBrace + 1)
    }

    private static func forLoopShadowUpperBound(
        matchRange: NSRange,
        source: NSString,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex,
        scopeUpperBound: Int
    ) -> Int {
        guard let openParen = nextLocation(ofAny: ["("], after: matchRange.location, in: source),
              let closeParen = matchingCloseParenLocation(openingAt: openParen, in: source) else {
            return min(scopeUpperBound, matchRange.upperBound)
        }

        var cursor = closeParen + 1
        let upperBound = min(scopeUpperBound, source.length)
        while cursor < upperBound {
            if let nextCursor = nonCodeRangeIndex.upperBoundOfRange(containing: cursor) {
                cursor = min(nextCursor, upperBound)
                continue
            }
            let character = source.character(at: cursor)
            if isWhitespaceCodeUnit(character) {
                cursor += 1
                continue
            }
            if character == openBraceCodeUnit,
               let closeBrace = matchingClosingBraceLocation(in: source, openBraceLocation: cursor) {
                return min(scopeUpperBound, closeBrace + 1)
            }
            if character == semicolonCodeUnit {
                return min(scopeUpperBound, cursor + 1)
            }
            cursor += 1
        }
        return scopeUpperBound
    }

    private static func forLoopDeclarationNameRanges(matchRange: NSRange, source: NSString) -> [NSRange] {
        guard let openParen = nextLocation(ofAny: ["("], after: matchRange.location, in: source),
              let closeParen = matchingCloseParenLocation(openingAt: openParen, in: source),
              openParen < closeParen else {
            return []
        }
        let clauseRange = NSRange(location: openParen + 1, length: closeParen - openParen - 1)
        let clause = source.substring(with: clauseRange) as NSString
        let declarationEnd = forLoopDeclarationEnd(in: clause)
        guard declarationEnd != NSNotFound else {
            return []
        }
        return declarationNameRanges(in: clause, statementEnd: declarationEnd)
            .map { NSRange(location: clauseRange.location + $0.location, length: $0.length) }
    }

    private static func forLoopDeclarationEnd(in clause: NSString) -> Int {
        var cursor = 0
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var angleDepth = 0
        while cursor < clause.length {
            if let nextCursor = indexAfterCommentOrQuotedLiteral(startingAt: cursor, in: clause) {
                cursor = nextCursor
                continue
            }
            let character = clause.character(at: cursor)
            updateDeclarationDelimiterDepth(
                character: character,
                next: cursor + 1 < clause.length
                    ? clause.character(at: cursor + 1)
                    : 0,
                parenDepth: &parenDepth,
                bracketDepth: &bracketDepth,
                braceDepth: &braceDepth,
                angleDepth: &angleDepth
            )
            if parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               angleDepth == 0 {
                if character == semicolonCodeUnit {
                    return cursor
                }
                if clauseHasStandaloneIn(at: cursor, in: clause) {
                    return cursor
                }
            }
            cursor += 1
        }
        return NSNotFound
    }

    private static func clauseHasStandaloneIn(at location: Int, in clause: NSString) -> Bool {
        let keywordLength = "in".utf16.count
        guard location + keywordLength <= clause.length,
              clause.substring(with: NSRange(location: location, length: keywordLength)) == "in" else {
            return false
        }
        let before = location == 0 ? nil : clause.character(at: location - 1)
        let afterLocation = location + keywordLength
        let after = afterLocation < clause.length ? clause.character(at: afterLocation) : nil
        return before.map(isASCIIIdentifierContinue) != true
            && after.map(isASCIIIdentifierContinue) != true
    }

    private static func innermostOpenBraceLocation(
        containing location: Int,
        lowerBound: Int,
        in source: NSString
    ) -> Int? {
        let upperBound = min(max(0, location), source.length)
        var stack: [Int] = []
        var cursor = min(max(0, lowerBound), upperBound)
        while cursor < upperBound {
            if let nextCursor = indexAfterCommentOrQuotedLiteral(startingAt: cursor, in: source) {
                cursor = min(nextCursor, upperBound)
                continue
            }
            let character = source.character(at: cursor)
            if character == openBraceCodeUnit {
                stack.append(cursor)
            } else if character == closeBraceCodeUnit {
                _ = stack.popLast()
            }
            cursor += 1
        }
        return stack.last
    }

    private static func identifierRanges(named name: String, in range: NSRange, source: NSString) -> [NSRange] {
        identifierRegex
            .matches(in: source as String, range: range)
            .compactMap { match in
                source.substring(with: match.range) == name ? match.range : nil
            }
    }

    private static func methodParameterNameRange(_ range: NSRange, in header: NSString) -> Bool {
        guard let closeParen = previousNonWhitespaceLocation(before: range.location, in: header),
              header.character(at: closeParen) == closeParenCodeUnit,
              let openParen = matchingOpeningParenLocation(before: closeParen, in: header),
              let beforeType = previousNonWhitespaceLocation(before: openParen, in: header) else {
            return false
        }
        return header.character(at: beforeType) == colonCodeUnit
    }

    private static func cParameterNameRange(_ range: NSRange, in header: NSString) -> Bool {
        guard let delimiterBefore = previousLocation(ofAny: ["(", ","], before: range.location, in: header),
              let delimiterAfter = nextLocation(ofAny: [")", ","], after: range.upperBound, in: header),
              delimiterBefore < range.location,
              range.upperBound <= delimiterAfter else {
            return false
        }
        let segmentRange = NSRange(location: delimiterBefore + 1, length: delimiterAfter - delimiterBefore - 1)
        let segment = header.substring(with: segmentRange) as NSString
        guard let relativeNameRange = identifierRange(before: segment.length, in: segment) else {
            return false
        }
        return segmentRange.location + relativeNameRange.location == range.location
            && relativeNameRange.length == range.length
    }

    private static func previousNonWhitespaceLocation(before location: Int, in text: NSString) -> Int? {
        guard location > 0 else { return nil }
        var cursor = min(location, text.length) - 1
        while cursor >= 0 {
            let character = text.character(at: cursor)
            if !isWhitespaceCodeUnit(character) {
                return cursor
            }
            if cursor == 0 { break }
            cursor -= 1
        }
        return nil
    }

    private static func matchingOpeningParenLocation(before closeParen: Int, in text: NSString) -> Int? {
        var depth = 0
        var cursor = closeParen
        while cursor >= 0 {
            let character = text.character(at: cursor)
            if character == closeParenCodeUnit {
                depth += 1
            } else if character == openParenCodeUnit {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            if cursor == 0 { break }
            cursor -= 1
        }
        return nil
    }

    private static func previousLocation(ofAny needles: [String], before location: Int, in text: NSString) -> Int? {
        let needleCodeUnits = needles.compactMap(singleUTF16CodeUnit)
        guard location > 0 else { return nil }
        var cursor = min(location, text.length) - 1
        while cursor >= 0 {
            let character = text.character(at: cursor)
            if needleCodeUnits.contains(character) {
                return cursor
            }
            if cursor == 0 { break }
            cursor -= 1
        }
        return nil
    }

    private static func nextLocation(ofAny needles: [String], after location: Int, in text: NSString) -> Int? {
        let needleCodeUnits = needles.compactMap(singleUTF16CodeUnit)
        var cursor = min(max(0, location), text.length)
        while cursor < text.length {
            let character = text.character(at: cursor)
            if needleCodeUnits.contains(character) {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func matchingCloseParenLocation(openingAt openParen: Int, in text: NSString) -> Int? {
        var depth = 0
        var cursor = openParen
        while cursor < text.length {
            if let nextCursor = indexAfterCommentOrQuotedLiteral(startingAt: cursor, in: text) {
                cursor = nextCursor
                continue
            }
            let character = text.character(at: cursor)
            if character == openParenCodeUnit {
                depth += 1
            } else if character == closeParenCodeUnit {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func matchingClosingBraceLocation(in source: NSString, openBraceLocation: Int) -> Int? {
        var cursor = openBraceLocation + 1
        var depth = 1
        while cursor < source.length {
            if let nextCursor = indexAfterCommentOrQuotedLiteral(startingAt: cursor, in: source) {
                cursor = nextCursor
                continue
            }
            let character = source.character(at: cursor)
            if character == openBraceCodeUnit, depth == 0 {
                depth = 1
            } else if character == openBraceCodeUnit {
                depth += 1
            } else if character == closeBraceCodeUnit {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func indexAfterCommentOrQuotedLiteral(startingAt location: Int, in text: NSString) -> Int? {
        guard location >= 0,
              location < text.length else {
            return nil
        }
        let character = text.character(at: location)
        let next = location + 1 < text.length
            ? text.character(at: location + 1)
            : 0
        if character == doubleQuoteCodeUnit || character == singleQuoteCodeUnit {
            return indexAfterQuotedLiteral(startingAt: location, quote: character, in: text)
        }
        if character == slashCodeUnit, next == slashCodeUnit {
            return text.lineRange(for: NSRange(location: location, length: 0)).upperBound
        }
        if character == slashCodeUnit, next == starCodeUnit {
            var cursor = location + 2
            while cursor + 1 < text.length {
                let current = text.character(at: cursor)
                let following = text.character(at: cursor + 1)
                if current == starCodeUnit, following == slashCodeUnit {
                    return cursor + 2
                }
                cursor += 1
            }
            return text.length
        }
        return nil
    }

    private static func isInsideCommentOrLiteral(_ range: NSRange, in text: NSString) -> Bool {
        var cursor = 0
        while cursor < min(range.location, text.length) {
            if let nextCursor = indexAfterCommentOrQuotedLiteral(startingAt: cursor, in: text) {
                if nextCursor > range.location {
                    return true
                }
                cursor = nextCursor
                continue
            }
            cursor += 1
        }
        return false
    }

    private static func objectiveCBraceDepth(
        afterScanning line: NSString,
        startingAt depth: Int,
        isInBlockComment: Bool
    ) -> (depth: Int, isInBlockComment: Bool) {
        var result = depth
        var isInBlockComment = isInBlockComment
        var cursor = 0
        while cursor < line.length {
            let character = line.character(at: cursor)
            let nextLocation = cursor + 1
            let next = nextLocation < line.length
                ? line.character(at: nextLocation)
                : 0
            if isInBlockComment {
                if character == starCodeUnit, next == slashCodeUnit {
                    isInBlockComment = false
                    cursor += 2
                    continue
                }
                cursor += 1
                continue
            }
            if character == slashCodeUnit, next == slashCodeUnit {
                break
            }
            if character == slashCodeUnit, next == starCodeUnit {
                isInBlockComment = true
                cursor += 2
                continue
            }
            if character == doubleQuoteCodeUnit || character == singleQuoteCodeUnit {
                cursor = indexAfterQuotedLiteral(startingAt: cursor, quote: character, in: line)
                continue
            }
            if character == openBraceCodeUnit {
                result += 1
            } else if character == closeBraceCodeUnit {
                result = max(0, result - 1)
            }
            cursor += 1
        }
        return (result, isInBlockComment)
    }

    private static func indexAfterQuotedLiteral(startingAt quoteLocation: Int, quote: String, in text: NSString) -> Int {
        guard let quote = singleUTF16CodeUnit(quote) else {
            return min(text.length, quoteLocation + 1)
        }
        return indexAfterQuotedLiteral(startingAt: quoteLocation, quote: quote, in: text)
    }

    private static func indexAfterQuotedLiteral(startingAt quoteLocation: Int, quote: unichar, in text: NSString) -> Int {
        var cursor = quoteLocation + 1
        var isEscaped = false
        while cursor < text.length {
            let character = text.character(at: cursor)
            if isEscaped {
                isEscaped = false
            } else if character == backslashCodeUnit {
                isEscaped = true
            } else if character == quote {
                return cursor + 1
            }
            cursor += 1
        }
        return text.length
    }

    private static func scanImplementationIvarDeclarations(
        source: NSString,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex
    ) -> [(name: String, range: NSRange)] {
        var declarations: [(name: String, range: NSRange)] = []
        var location = 0
        var awaitingIvarBlock = false
        var isInIvarBlock = false

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange) as NSString
            let trimmed = (line as String).trimmingCharacters(in: .whitespacesAndNewlines)
            defer {
                let nextLocation = lineRange.upperBound
                location = nextLocation > location ? nextLocation : source.length
            }

            if isInIvarBlock {
                let closeBraceRange = firstBraceRange(in: line, brace: "}")
                let ivarSegmentLength = closeBraceRange?.location ?? line.length
                appendImplementationIvarDeclarations(
                    in: line.substring(with: NSRange(location: 0, length: ivarSegmentLength)) as NSString,
                    lineOffset: lineRange.location,
                    nonCodeRangeIndex: nonCodeRangeIndex,
                    to: &declarations
                )
                if closeBraceRange != nil {
                    isInIvarBlock = false
                    awaitingIvarBlock = false
                }
                continue
            }

            if awaitingIvarBlock {
                if let openBraceRange = firstBraceRange(in: line, brace: "{") {
                    let segmentStart = openBraceRange.upperBound
                    let closeBraceRange = firstBraceRange(in: line, brace: "}", after: segmentStart)
                    let segmentUpperBound = closeBraceRange?.location ?? line.length
                    appendImplementationIvarDeclarations(
                        in: line.substring(with: NSRange(location: segmentStart, length: segmentUpperBound - segmentStart)) as NSString,
                        lineOffset: lineRange.location + segmentStart,
                        nonCodeRangeIndex: nonCodeRangeIndex,
                        to: &declarations
                    )
                    isInIvarBlock = closeBraceRange == nil
                    awaitingIvarBlock = closeBraceRange == nil
                } else if !trimmed.isEmpty && !isObjectiveCCommentOnlyLine(trimmed) {
                    awaitingIvarBlock = false
                }
                continue
            }

            guard trimmed.hasPrefix("@implementation") else {
                continue
            }
            if let openBraceRange = firstBraceRange(in: line, brace: "{") {
                let segmentStart = openBraceRange.upperBound
                let closeBraceRange = firstBraceRange(in: line, brace: "}", after: segmentStart)
                let segmentUpperBound = closeBraceRange?.location ?? line.length
                appendImplementationIvarDeclarations(
                    in: line.substring(with: NSRange(location: segmentStart, length: segmentUpperBound - segmentStart)) as NSString,
                    lineOffset: lineRange.location + segmentStart,
                    nonCodeRangeIndex: nonCodeRangeIndex,
                    to: &declarations
                )
                isInIvarBlock = closeBraceRange == nil
                awaitingIvarBlock = false
            } else {
                awaitingIvarBlock = true
            }
        }
        return declarations
    }

    private static func isObjectiveCCommentOnlyLine(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("//")
            || trimmedLine.hasPrefix("/*")
            || trimmedLine.hasPrefix("*")
            || trimmedLine.hasPrefix("*/")
    }

    private static func firstBraceRange(in line: NSString, brace: String, after location: Int = 0) -> NSRange? {
        guard let brace = singleUTF16CodeUnit(brace) else { return nil }
        return firstCodeCharacterRange(in: line, character: brace, after: location)
    }

    private static func firstCodeCharacterRange(in line: NSString, character: String, after location: Int = 0) -> NSRange? {
        guard let character = singleUTF16CodeUnit(character) else { return nil }
        return firstCodeCharacterRange(in: line, character: character, after: location)
    }

    private static func firstCodeCharacterRange(in line: NSString, character: unichar, after location: Int = 0) -> NSRange? {
        var cursor = min(max(0, location), line.length)
        while cursor < line.length {
            if let nextCursor = indexAfterCommentOrQuotedLiteral(startingAt: cursor, in: line) {
                cursor = nextCursor
                continue
            }
            if line.character(at: cursor) == character {
                return NSRange(location: cursor, length: 1)
            }
            cursor += 1
        }
        return nil
    }

    private static func appendImplementationIvarDeclarations(
        in segment: NSString,
        lineOffset: Int,
        nonCodeRangeIndex: ObjectiveCNonCodeRangeIndex,
        to declarations: inout [(name: String, range: NSRange)]
    ) {
        var statementStart = 0
        while statementStart < segment.length {
            let searchRange = NSRange(location: statementStart, length: segment.length - statementStart)
            let semicolonRange = segment.range(of: ";", options: [], range: searchRange)
            guard semicolonRange.location != NSNotFound else {
                return
            }

            let statementRange = NSRange(
                location: statementStart,
                length: semicolonRange.upperBound - statementStart
            )
            let statement = segment.substring(with: statementRange) as NSString
            for relativeRange in implementationIvarNameRanges(in: statement) {
                let absoluteRange = NSRange(
                    location: lineOffset + statementStart + relativeRange.location,
                    length: relativeRange.length
                )
                guard !nonCodeRangeIndex.intersects(absoluteRange) else {
                    continue
                }
                let name = statement.substring(with: relativeRange)
                declarations.append((
                    name: name,
                    range: absoluteRange
                ))
            }
            statementStart = semicolonRange.upperBound
        }
    }

    private static func implementationIvarNameRanges(in line: NSString) -> [NSRange] {
        let semicolonRange = line.range(of: ";")
        guard semicolonRange.location != NSNotFound,
              line.range(of: "(", options: [], range: NSRange(location: 0, length: semicolonRange.location)).location == NSNotFound else {
            return []
        }
        return declarationNameRanges(in: line, statementEnd: semicolonRange.location)
    }

    private static func firstLocation(ofAny needles: [String], in text: NSString, before end: Int) -> Int {
        var result = NSNotFound
        let range = NSRange(location: 0, length: max(0, min(end, text.length)))
        for needle in needles {
            let match = text.range(of: needle, options: [], range: range)
            if match.location != NSNotFound,
               result == NSNotFound || match.location < result {
                result = match.location
            }
        }
        return result
    }

    static func typedefDeclaredName(in declaration: NSString) -> String? {
        if let declaredName = nsEnumOptionsTypedefDeclaredName(in: declaration) {
            return declaredName.name
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

    private static func nsEnumOptionsTypedefDeclaredName(in declaration: NSString) -> (name: String, range: NSRange)? {
        let string = declaration as String
        guard let match = nsEnumOptionsTypedefNameRegex.firstMatch(
            in: string,
            range: NSRange(location: 0, length: declaration.length)
        ) else {
            return nil
        }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else {
            return nil
        }
        return (declaration.substring(with: range), range)
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
        tokenIndex: ObjectiveCTokenIndex
    ) -> [(name: String, range: NSRange)] {
        let string = source as String
        let fullRange = NSRange(location: 0, length: source.length)
        var declarations: [(name: String, range: NSRange)] = []

        for match in propertyDeclarationRegex.matches(in: string, range: fullRange) {
            let propertyKeywordRange = NSRange(location: match.range.location, length: "@property".count)
            guard tokenIndex.containsPropertyKeywordRange(propertyKeywordRange) else {
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
               tokenIndex.containsIdentifierRange(range) {
                declarations.append((name: name, range: range))
            }
        }

        return declarations
    }

    static func propertyDeclaredNameRange(in declaration: NSString) -> NSRange? {
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

    private static func propertyReferenceShouldBeTracked(
        name: String,
        range: NSRange,
        in declaration: NSString
    ) -> Bool {
        guard isUppercaseIdentifier(name),
              name.contains("_") else {
            return true
        }

        let trailingStart = range.upperBound
        guard trailingStart < declaration.length else {
            return true
        }
        let trailing = declaration.substring(from: trailingStart)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trailing.isEmpty == false,
              trailing != ";" else {
            return true
        }
        return false
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

    static func isIdentifierRange(_ range: NSRange, in source: NSString) -> Bool {
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

    private static let definedMacroNameRegex = try! NSRegularExpression(
        pattern: #"(?m)^\s*#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)"#
    )

    private static let objectiveCFunctionLikeSignatureLineRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:[-+]\s*\(|(?:static\s+)?[A-Za-z_][A-Za-z0-9_ <>,_*]*[ \t*]+[A-Za-z_][A-Za-z0-9_]*\s*\()"#
    )

    private static let objectiveCSplitCFunctionNameLineRegex = try! NSRegularExpression(
        pattern: #"^\s*(?!(?:return|if|for|while|switch|case|break|continue|goto|else|do|sizeof)\b)[A-Za-z_][A-Za-z0-9_]*\s*\([^;{}=]*\)"#
    )

    private static let objectiveCLocalVariableShadowDeclarationRegex = try! NSRegularExpression(
        pattern: #"(?m)^\s*(?:static\s+)?(?!(?:return|if|for|while|switch|case|break|continue|goto|else|do)\b)[A-Za-z_][A-Za-z0-9_ <>,_*]*[ \t*]+([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|;)"#
    )

    private static let objectiveCForLoopVariableShadowDeclarationRegex = try! NSRegularExpression(
        pattern: #"\bfor\s*\(\s*[A-Za-z_][A-Za-z0-9_ <>,_*]*[ \t*]+([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|in\b)"#
    )

    private static let nsEnumOptionsTypedefNameRegex = try! NSRegularExpression(
        pattern: #"\btypedef\s+NS_(?:ENUM|OPTIONS)\s*\([^,]+,\s*([A-Za-z_][A-Za-z0-9_]*)"#
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

    static let identifierRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z_][A-Za-z0-9_]*"#
    )

    static let typedefIgnoredIdentifiers: Set<String> = [
        "NS_ENUM", "NS_OPTIONS", "typedef", "struct", "union", "enum",
        "const", "unsigned", "signed", "short", "long", "int", "char",
        "void", "id", "BOOL", "NSInteger", "NSUInteger", "NSString",
        "NSError", "NSRange", "nullable", "nonnull", "_Nullable", "_Nonnull"
    ]

    private static let objectiveCStatementLeadingIdentifiers: Set<String> = [
        "return", "if", "for", "while", "switch", "case", "break", "continue",
        "goto", "else", "do", "sizeof"
    ]

    private static let quotedHeaderImportRegex = try! NSRegularExpression(
        pattern: #"(?m)^\s*#\s*(?:import|include)\s*"[^"]+\.h""#
    )
}
