import Foundation

struct SyntaxLanguageTextEdit {
    let range: NSRange
    let replacement: String
}

enum SyntaxLanguageSelectionBoundaryAffinity {
    case forward
    case backward
}

struct SyntaxLanguageLineInfo {
    let lineRange: NSRange
    let contentRange: NSRange
    let firstNonWhitespaceOffset: Int?
    let isBlank: Bool
    let hasLineComment: Bool
}

struct SyntaxLanguageCSSWrappedCommentBounds {
    let openLocation: Int
    let closeLocation: Int
}

enum SyntaxLanguageTextUtilities {
    static func toggleLineComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        let nsSource = source as NSString
        let safeSelection = SyntaxEditorRangeUtilities.clampedRange(selection, utf16Length: nsSource.length)
        let lineRanges = selectedLineRanges(in: nsSource, selection: safeSelection)
        guard !lineRanges.isEmpty else { return nil }

        let lines = lineRanges.map { lineInfo(in: nsSource, lineRange: $0) }
        let actionable = lines.filter { !$0.isBlank }
        guard !actionable.isEmpty else { return nil }

        let shouldUncomment = actionable.allSatisfy(\.hasLineComment)
        var edits: [SyntaxLanguageTextEdit] = []

        for line in actionable {
            guard let firstNonWhitespaceOffset = line.firstNonWhitespaceOffset else { continue }
            if shouldUncomment {
                let afterSlashOffset = firstNonWhitespaceOffset + 2
                var removeLength = 2
                if let next = character(in: nsSource, at: afterSlashOffset), next == " " {
                    removeLength += 1
                }
                edits.append(
                    SyntaxLanguageTextEdit(
                        range: NSRange(location: firstNonWhitespaceOffset, length: removeLength),
                        replacement: ""
                    )
                )
            } else {
                edits.append(
                    SyntaxLanguageTextEdit(
                        range: NSRange(location: firstNonWhitespaceOffset, length: 0),
                        replacement: "// "
                    )
                )
            }
        }

        guard !edits.isEmpty else { return nil }
        return applyEdits(edits, source: source, selection: safeSelection)
    }

    static func toggleCSSBlockComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        let nsSource = source as NSString
        let safeSelection = SyntaxEditorRangeUtilities.clampedRange(selection, utf16Length: nsSource.length)
        let targetLinesRange = selectedLineEnvelope(in: nsSource, selection: safeSelection)
        guard targetLinesRange.length > 0 else { return nil }

        let segment = nsSource.substring(with: targetLinesRange)
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if let wrappedComment = wrappedCSSCommentBounds(in: segment) {
            let openAbsolute = targetLinesRange.location + wrappedComment.openLocation
            let closeAbsolute = targetLinesRange.location + wrappedComment.closeLocation

            var openLength = 2
            if character(in: nsSource, at: openAbsolute + 2) == " " {
                openLength = 3
            }

            var closeRemovalLocation = closeAbsolute
            var closeRemovalLength = 2
            if character(in: nsSource, at: closeAbsolute - 1) == " " {
                closeRemovalLocation -= 1
                closeRemovalLength = 3
            }

            return applyEdits(
                [
                    SyntaxLanguageTextEdit(
                        range: NSRange(location: closeRemovalLocation, length: closeRemovalLength),
                        replacement: ""
                    ),
                    SyntaxLanguageTextEdit(
                        range: NSRange(location: openAbsolute, length: openLength),
                        replacement: ""
                    ),
                ],
                source: source,
                selection: safeSelection
            )
        }

        if trimmed.hasPrefix("/*"), trimmed.hasSuffix("*/") {
            return nil
        }

        if segment.range(of: "/*") != nil || segment.range(of: "*/") != nil {
            return nil
        }

        return applyEdits(
            [
                SyntaxLanguageTextEdit(
                    range: NSRange(location: targetLinesRange.location + targetLinesRange.length, length: 0),
                    replacement: " */"
                ),
                SyntaxLanguageTextEdit(
                    range: NSRange(location: targetLinesRange.location, length: 0),
                    replacement: "/* "
                ),
            ],
            source: source,
            selection: safeSelection
        )
    }

    static func applyEdits(
        _ edits: [SyntaxLanguageTextEdit],
        source: String,
        selection: NSRange
    ) -> SyntaxLanguageEdit {
        let sorted = edits.sorted { lhs, rhs in
            lhs.range.location > rhs.range.location
        }

        let mutable = NSMutableString(string: source)
        var selectionStart = selection.location
        var selectionEnd = selection.location + selection.length

        for edit in sorted {
            mutable.replaceCharacters(in: edit.range, with: edit.replacement)
            selectionStart = adjustedSelectionOffset(selectionStart, for: edit, affinity: .forward)
            selectionEnd = adjustedSelectionOffset(selectionEnd, for: edit, affinity: .backward)
        }

        let clampedStart = max(0, selectionStart)
        let clampedEnd = max(clampedStart, selectionEnd)
        return SyntaxLanguageEdit(
            text: mutable as String,
            selectedRange: NSRange(location: clampedStart, length: clampedEnd - clampedStart)
        )
    }

    static func adjustedSelectionOffset(
        _ offset: Int,
        for edit: SyntaxLanguageTextEdit,
        affinity: SyntaxLanguageSelectionBoundaryAffinity
    ) -> Int {
        let start = edit.range.location
        let oldEnd = start + edit.range.length
        let newEnd = start + edit.replacement.utf16.count

        if offset < start {
            return offset
        }

        if offset == start {
            switch affinity {
            case .forward:
                return newEnd
            case .backward:
                return start
            }
        }

        if offset < oldEnd {
            return newEnd
        }
        return offset + (newEnd - oldEnd)
    }

    static func selectedLineRanges(in source: NSString, selection: NSRange) -> [NSRange] {
        let envelope = selectedLineEnvelope(in: source, selection: selection)
        if envelope.length == 0 {
            return [envelope]
        }

        var ranges: [NSRange] = []
        var cursor = envelope.location
        let end = envelope.location + envelope.length

        while cursor < end {
            let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
            ranges.append(lineRange)
            cursor = lineRange.location + lineRange.length
        }

        return ranges
    }

    static func selectedLineEnvelope(in source: NSString, selection: NSRange) -> NSRange {
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }

        if selection.length == 0 {
            return source.lineRange(for: NSRange(location: selection.location, length: 0))
        }

        let startLine = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let lastTouchedOffset = max(selection.location, selection.location + selection.length - 1)
        let endLine = source.lineRange(for: NSRange(location: min(lastTouchedOffset, source.length - 1), length: 0))

        let start = startLine.location
        let end = endLine.location + endLine.length
        return NSRange(location: start, length: max(0, end - start))
    }

    static func lineStartOffsets(in source: NSString, selection: NSRange) -> [Int] {
        selectedLineRanges(in: source, selection: selection).map(\.location)
    }

    static func removableIndentLength(in source: NSString, lineRange: NSRange, indentUnit: String) -> Int {
        let content = lineContentRange(in: source, lineRange: lineRange)
        guard content.length > 0 else { return 0 }

        var cursor = content.location
        let end = content.location + content.length
        var removedWidth = 0
        var removedUTF16 = 0

        while cursor < end, removedWidth < indentUnit.utf16.count {
            let ch = source.character(at: cursor)
            if ch == 32 {
                removedWidth += 1
                removedUTF16 += 1
            } else if ch == 9 {
                removedWidth += indentUnit.utf16.count
                removedUTF16 += 1
            } else {
                break
            }
            cursor += 1
        }

        return removedUTF16
    }

    static func lineInfo(in source: NSString, lineRange: NSRange) -> SyntaxLanguageLineInfo {
        let contentRange = lineContentRange(in: source, lineRange: lineRange)

        var firstNonWhitespace: Int?
        var cursor = contentRange.location
        let end = contentRange.location + contentRange.length
        while cursor < end {
            let ch = source.character(at: cursor)
            if ch != 32, ch != 9 {
                firstNonWhitespace = cursor
                break
            }
            cursor += 1
        }

        let isBlank = firstNonWhitespace == nil
        let hasLineComment: Bool
        if let firstNonWhitespace {
            hasLineComment = character(in: source, at: firstNonWhitespace) == "/" &&
                character(in: source, at: firstNonWhitespace + 1) == "/"
        } else {
            hasLineComment = false
        }

        return SyntaxLanguageLineInfo(
            lineRange: lineRange,
            contentRange: contentRange,
            firstNonWhitespaceOffset: firstNonWhitespace,
            isBlank: isBlank,
            hasLineComment: hasLineComment
        )
    }

    static func lineContentRange(in source: NSString, lineRange: NSRange) -> NSRange {
        var length = lineRange.length
        if length > 0, source.character(at: lineRange.location + length - 1) == 10 {
            length -= 1
        }
        if length > 0, source.character(at: lineRange.location + length - 1) == 13 {
            length -= 1
        }
        return NSRange(location: lineRange.location, length: max(0, length))
    }

    static func leadingIndent(in source: NSString, lineRange: NSRange) -> String {
        let contentRange = lineContentRange(in: source, lineRange: lineRange)
        var cursor = contentRange.location
        let end = contentRange.location + contentRange.length
        while cursor < end {
            let ch = source.character(at: cursor)
            if ch != 32, ch != 9 {
                break
            }
            cursor += 1
        }
        return source.substring(with: NSRange(location: lineRange.location, length: cursor - lineRange.location))
    }

    static func trailingIndentRemovalLength(_ text: String, indentUnit: String) -> Int {
        let nsText = text as NSString
        var cursor = nsText.length - 1
        var removedWidth = 0
        var removedUTF16 = 0

        while cursor >= 0, removedWidth < indentUnit.utf16.count {
            let ch = nsText.character(at: cursor)
            if ch == 32 {
                removedWidth += 1
                removedUTF16 += 1
            } else if ch == 9 {
                removedWidth += indentUnit.utf16.count
                removedUTF16 += 1
            } else {
                break
            }
            cursor -= 1
        }
        return removedUTF16
    }

    static func previousNonWhitespaceCharacter(in source: NSString, before offset: Int) -> Character? {
        var cursor = offset - 1
        while cursor >= 0 {
            let ch = source.character(at: cursor)
            if ch == 32 || ch == 9 || ch == 10 || ch == 13 {
                cursor -= 1
                continue
            }
            return character(in: source, at: cursor)
        }
        return nil
    }

    static func nextNonWhitespaceOffset(in source: NSString, from offset: Int) -> Int? {
        var cursor = max(0, offset)
        while cursor < source.length {
            let ch = source.character(at: cursor)
            if ch == 32 || ch == 9 || ch == 10 || ch == 13 {
                cursor += 1
                continue
            }
            return cursor
        }
        return nil
    }

    static func character(in source: NSString, at offset: Int) -> Character? {
        guard offset >= 0, offset < source.length else { return nil }
        let composedRange = source.rangeOfComposedCharacterSequence(at: offset)
        guard composedRange.location != NSNotFound, composedRange.length > 0 else {
            return nil
        }
        return source.substring(with: composedRange).first
    }

    static func previousNonWhitespaceOffset(in source: NSString, before location: Int) -> Int? {
        var cursor = location - 1
        while cursor >= 0 {
            let codeUnit = source.character(at: cursor)
            if codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13 {
                cursor -= 1
                continue
            }
            return cursor
        }
        return nil
    }

    static func previousNonWhitespaceCodeUnit(in source: NSString, before location: Int) -> unichar? {
        var cursor = location - 1
        while cursor >= 0 {
            let codeUnit = source.character(at: cursor)
            if codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13 {
                cursor -= 1
                continue
            }
            return codeUnit
        }
        return nil
    }

    static func hasOddUnescapedQuote(in text: String, quote: Character) -> Bool {
        var count = 0
        var isEscaped = false
        for ch in text {
            if isEscaped {
                isEscaped = false
                continue
            }
            if ch == "\\" {
                isEscaped = true
                continue
            }
            if ch == quote {
                count += 1
            }
        }
        return count % 2 == 1
    }

    static func wrappedCSSCommentBounds(in segment: String) -> SyntaxLanguageCSSWrappedCommentBounds? {
        let nsSegment = segment as NSString
        guard nsSegment.length >= 4 else { return nil }

        var firstNonWhitespace = 0
        while firstNonWhitespace < nsSegment.length {
            let codeUnit = nsSegment.character(at: firstNonWhitespace)
            if codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13 {
                firstNonWhitespace += 1
                continue
            }
            break
        }
        guard firstNonWhitespace + 1 < nsSegment.length else { return nil }
        guard nsSegment.character(at: firstNonWhitespace) == 47,
              nsSegment.character(at: firstNonWhitespace + 1) == 42
        else {
            return nil
        }

        var lastNonWhitespace = nsSegment.length - 1
        while lastNonWhitespace >= 0 {
            let codeUnit = nsSegment.character(at: lastNonWhitespace)
            if codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13 {
                lastNonWhitespace -= 1
                continue
            }
            break
        }
        guard lastNonWhitespace - 1 >= 0 else { return nil }
        guard nsSegment.character(at: lastNonWhitespace - 1) == 42,
              nsSegment.character(at: lastNonWhitespace) == 47
        else {
            return nil
        }

        let openLocation = firstNonWhitespace
        let closeLocation = lastNonWhitespace - 1
        guard closeLocation > openLocation else { return nil }

        let closeSearchRange = NSRange(
            location: openLocation + 2,
            length: max(0, nsSegment.length - (openLocation + 2))
        )
        let firstCloseLocation = nsSegment.range(of: "*/", options: [], range: closeSearchRange).location
        guard firstCloseLocation == closeLocation else { return nil }

        return SyntaxLanguageCSSWrappedCommentBounds(openLocation: openLocation, closeLocation: closeLocation)
    }
}
