import Foundation

package enum HighlightTokenQuality: Int, Sendable {
    case editGuess
    case viewportGuess
    case accurate
}

package final class HighlightLineTokenStore {
    private struct StoredToken {
        var startOffsetInLine: Int
        var endOffsetInLine: Int
        let syntaxID: EditorSourceSyntaxID
        let language: SyntaxLanguage?
        let rawCaptureName: String
        let isSemanticOverlay: Bool
        let quality: HighlightTokenQuality
        let groupID: Int
    }

    private var lines: [[StoredToken]] = [[]]
    private var nextGroupID = 1

    package init() {}

    package var lineCount: Int {
        lines.count
    }

    package func reset(
        tokens: [SyntaxHighlightToken],
        lineIndex: SyntaxHighlightLineIndex,
        quality: HighlightTokenQuality = .accurate
    ) {
        lines = Array(repeating: [], count: max(1, lineIndex.lineCount))
        nextGroupID = 1
        append(tokens: tokens, lineIndex: lineIndex, quality: quality)
    }

    package func clear(lineCount: Int = 1) {
        lines = Array(repeating: [], count: max(1, lineCount))
        nextGroupID = 1
    }

    package func applyEdit(
        _ mutation: SyntaxHighlightMutation,
        previousSource: String,
        lineIndex: SyntaxHighlightLineIndex
    ) {
        let nsSource = previousSource as NSString
        guard nsSource.length >= 0,
              mutation.location >= 0,
              mutation.length >= 0,
              mutation.location <= nsSource.length,
              mutation.location + mutation.length <= nsSource.length else {
            clear(lineCount: lineIndex.lineCount)
            return
        }

        var oldLineRange = lineIndex.lineRange(
            containingUTF16Range: NSRange(location: mutation.location, length: mutation.length)
        )
        let deletedText = nsSource.substring(
            with: NSRange(location: mutation.location, length: mutation.length)
        )
        if deletedText.utf16.contains(10),
           oldLineRange.upperBound < lines.count,
           oldLineRange.upperBound > oldLineRange.lowerBound,
           mutation.location + mutation.length == lineIndex.lineEndOffset(at: oldLineRange.upperBound - 1) {
            oldLineRange = oldLineRange.lowerBound..<(oldLineRange.upperBound + 1)
        }

        let lowerOffset = lineIndex.lineStartOffset(at: oldLineRange.lowerBound)
        let upperOffset = oldLineRange.upperBound < lineIndex.lineCount
            ? lineIndex.lineStartOffset(at: oldLineRange.upperBound)
            : nsSource.length
        let affectedRange = NSRange(location: lowerOffset, length: max(0, upperOffset - lowerOffset))
        let oldSegment = nsSource.substring(with: affectedRange)
        let newSegment = SyntaxEditorModel.applying([
            SyntaxEditorTextEdit(
                range: NSRange(
                    location: mutation.location - affectedRange.location,
                    length: mutation.length
                ),
                replacement: mutation.replacement
            ),
        ], to: oldSegment)
        var replacementLineCount = LineOffsetTable.lineLengths(in: newSegment).count
        if affectedRange.upperBound < nsSource.length,
           newSegment.utf16.last == 10,
           replacementLineCount > 1 {
            replacementLineCount -= 1
        }
        removeTokenGroupsTouchingLines(oldLineRange)
        let replacementLines = Array(repeating: [StoredToken](), count: max(1, replacementLineCount))
        replaceLineRange(oldLineRange, with: replacementLines)
    }

    package func replaceTokens(
        in range: NSRange,
        with tokens: [SyntaxHighlightToken],
        lineIndex: SyntaxHighlightLineIndex,
        quality: HighlightTokenQuality = .accurate
    ) {
        removeTokens(intersecting: range, lineIndex: lineIndex)
        append(tokens: tokens, lineIndex: lineIndex, quality: quality)
    }

    package func tokens(
        in range: NSRange? = nil,
        lineIndex: SyntaxHighlightLineIndex
    ) -> [SyntaxHighlightToken] {
        guard !lines.isEmpty else { return [] }
        let lineRange: Range<Int>
        if let range {
            lineRange = lineIndex.lineRange(containingUTF16Range: range)
        } else {
            lineRange = 0..<lines.count
        }
        return materializedTokens(in: lineRange, lineIndex: lineIndex)
    }

    package func tokenCount(in range: NSRange? = nil, lineIndex: SyntaxHighlightLineIndex) -> Int {
        tokens(in: range, lineIndex: lineIndex).count
    }

    private func replaceLineRange(_ range: Range<Int>, with replacementLines: [[StoredToken]]) {
        let lower = min(max(0, range.lowerBound), lines.count)
        let upper = min(max(lower, range.upperBound), lines.count)
        lines.replaceSubrange(lower..<upper, with: replacementLines)
        if lines.isEmpty {
            lines = [[]]
        }
    }

    private func append(
        tokens: [SyntaxHighlightToken],
        lineIndex: SyntaxHighlightLineIndex,
        quality: HighlightTokenQuality
    ) {
        guard !tokens.isEmpty else { return }
        ensureLineCount(lineIndex.lineCount)

        var touchedLines = Set<Int>()
        for token in tokens.sorted(by: SyntaxHighlightTokenOrdering.displayOrder) {
            guard token.range.length > 0 else { continue }
            let tokenLineRange = lineIndex.lineRange(containingUTF16Range: token.range)
            guard !tokenLineRange.isEmpty else { continue }
            let groupID = nextGroupID
            nextGroupID += 1

            for line in tokenLineRange where lines.indices.contains(line) {
                let lineStart = lineIndex.lineStartOffset(at: line)
                let lineEnd = lineIndex.lineEndOffset(at: line)
                let segmentStart = max(token.range.location, lineStart)
                let segmentEnd = min(token.range.upperBound, lineEnd)
                guard segmentEnd > segmentStart else { continue }
                lines[line].append(
                    StoredToken(
                        startOffsetInLine: segmentStart - lineStart,
                        endOffsetInLine: segmentEnd - lineStart,
                        syntaxID: token.syntaxID,
                        language: token.language,
                        rawCaptureName: token.rawCaptureName,
                        isSemanticOverlay: token.isSemanticOverlay,
                        quality: quality,
                        groupID: groupID
                    )
                )
                touchedLines.insert(line)
            }
        }
        sortLines(touchedLines)
    }

    private func removeTokens(intersecting range: NSRange, lineIndex: SyntaxHighlightLineIndex) {
        guard range.length > 0, !lines.isEmpty else { return }
        ensureLineCount(lineIndex.lineCount)
        let lineRange = lineIndex.lineRange(containingUTF16Range: range)
        guard !lineRange.isEmpty else { return }

        var groupIDsToRemove = Set<Int>()
        for line in lineRange where lines.indices.contains(line) {
            let lineStart = lineIndex.lineStartOffset(at: line)
            for token in lines[line] {
                let absoluteRange = NSRange(
                    location: lineStart + token.startOffsetInLine,
                    length: token.endOffsetInLine - token.startOffsetInLine
                )
                if SyntaxEditorRangeUtilities.intersection(of: absoluteRange, and: range).length > 0 {
                    groupIDsToRemove.insert(token.groupID)
                }
            }
        }

        guard !groupIDsToRemove.isEmpty else { return }
        removeGroups(groupIDsToRemove, expandingFrom: lineRange)
    }

    private func removeTokenGroupsTouchingLines(_ lineRange: Range<Int>) {
        let lineRange = clampedLineRange(lineRange)
        guard !lineRange.isEmpty else { return }

        var groupIDsToRemove = Set<Int>()
        for line in lineRange {
            for token in lines[line] {
                groupIDsToRemove.insert(token.groupID)
            }
        }

        guard !groupIDsToRemove.isEmpty else { return }
        removeGroups(groupIDsToRemove, expandingFrom: lineRange)
    }

    private func removeGroups(_ groupIDs: Set<Int>, expandingFrom lineRange: Range<Int>) {
        let lineRange = clampedLineRange(lineRange)
        guard !lineRange.isEmpty, !groupIDs.isEmpty else { return }

        removeGroups(groupIDs, from: lineRange)

        var lowerLine = lineRange.lowerBound - 1
        while lines.indices.contains(lowerLine) {
            guard removeGroups(groupIDs, from: lowerLine..<(lowerLine + 1)) else { break }
            lowerLine -= 1
        }

        var upperLine = lineRange.upperBound
        while lines.indices.contains(upperLine) {
            guard removeGroups(groupIDs, from: upperLine..<(upperLine + 1)) else { break }
            upperLine += 1
        }
    }

    @discardableResult
    private func removeGroups(_ groupIDs: Set<Int>, from lineRange: Range<Int>) -> Bool {
        var removedAny = false
        for line in clampedLineRange(lineRange) {
            let previousCount = lines[line].count
            lines[line].removeAll { groupIDs.contains($0.groupID) }
            removedAny = removedAny || lines[line].count != previousCount
        }
        return removedAny
    }

    private func clampedLineRange(_ lineRange: Range<Int>) -> Range<Int> {
        let lower = min(max(0, lineRange.lowerBound), lines.count)
        let upper = min(max(lower, lineRange.upperBound), lines.count)
        return lower..<upper
    }

    private func materializedTokens(
        in lineRange: Range<Int>,
        lineIndex: SyntaxHighlightLineIndex
    ) -> [SyntaxHighlightToken] {
        var groups: [Int: (range: NSRange, token: StoredToken)] = [:]
        let lower = min(max(0, lineRange.lowerBound), lines.count)
        let upper = min(max(lower, lineRange.upperBound), lines.count)
        guard lower < upper else { return [] }

        for line in lower..<upper {
            let lineStart = lineIndex.lineStartOffset(at: line)
            for token in lines[line] {
                let absoluteRange = NSRange(
                    location: lineStart + token.startOffsetInLine,
                    length: token.endOffsetInLine - token.startOffsetInLine
                )
                if var group = groups[token.groupID] {
                    let nextLower = min(group.range.location, absoluteRange.location)
                    let nextUpper = max(group.range.upperBound, absoluteRange.upperBound)
                    group.range = NSRange(location: nextLower, length: nextUpper - nextLower)
                    groups[token.groupID] = group
                } else {
                    groups[token.groupID] = (absoluteRange, token)
                }
            }
        }

        return groups.values.map { group in
            SyntaxHighlightToken(
                range: group.range,
                syntaxID: group.token.syntaxID,
                language: group.token.language,
                rawCaptureName: group.token.rawCaptureName,
                isSemanticOverlay: group.token.isSemanticOverlay
            )
        }
        .sorted(by: SyntaxHighlightTokenOrdering.displayOrder)
    }

    private func ensureLineCount(_ lineCount: Int) {
        let lineCount = max(1, lineCount)
        if lines.count < lineCount {
            lines.append(contentsOf: repeatElement([], count: lineCount - lines.count))
        } else if lines.count > lineCount {
            lines.removeSubrange(lineCount..<lines.count)
        }
    }

    private func sortLines(_ touchedLines: Set<Int>) {
        for index in touchedLines where lines.indices.contains(index) && lines[index].count > 1 {
            lines[index].sort {
                if $0.startOffsetInLine != $1.startOffsetInLine {
                    return $0.startOffsetInLine < $1.startOffsetInLine
                }
                if $0.endOffsetInLine != $1.endOffsetInLine {
                    return $0.endOffsetInLine > $1.endOffsetInLine
                }
                return $0.groupID < $1.groupID
            }
        }
    }
}
