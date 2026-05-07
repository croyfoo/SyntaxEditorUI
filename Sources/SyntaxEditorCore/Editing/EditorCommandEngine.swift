import Foundation

package struct EditorCommandResult {
    package let text: String
    package let selectedRange: NSRange
    package let refreshStartUTF16: Int

    package init(text: String, selectedRange: NSRange, refreshStartUTF16: Int) {
        self.text = text
        self.selectedRange = selectedRange
        self.refreshStartUTF16 = refreshStartUTF16
    }
}

package final class EditorCommandEngine {
    private let indentUnit = "    "
    private var pendingTOMLMultilineDelimiter: PendingTOMLMultilineDelimiter?

    package enum DeletionIntent {
        case unspecified
        case backward
    }

    package init() {}

    private struct PendingTOMLMultilineDelimiter {
        let cursorLocation: Int
        let quote: Character
    }

    package func invalidateTransientState() {
        pendingTOMLMultilineDelimiter = nil
    }

    package func transformInput(
        source: String,
        range: NSRange,
        replacementText: String,
        language: SyntaxLanguage,
        deletionIntent: DeletionIntent = .unspecified
    ) -> EditorCommandResult? {
        let nsSource = source as NSString
        let safeRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: nsSource.length)
        let singleCharacterInput = replacementText.utf16.count == 1 ? replacementText.first : nil

        if !(singleCharacterInput.map(isQuote) ?? false) {
            invalidateTransientState()
        }

        if replacementText == "\n" {
            return smartNewline(source: source, range: safeRange)
        }

        if deletionIntent == .backward, replacementText.isEmpty, safeRange.length == 1 {
            if let result = pairAwareBackspace(source: source, range: safeRange) {
                return result
            }
        }

        if replacementText.utf16.count == 1, let input = replacementText.first {
            if let result = autoPair(
                source: source,
                range: safeRange,
                input: input,
                language: language
            ) {
                return result
            }
        }

        return nil
    }

    package func indentSelection(source: String, selection: NSRange) -> EditorCommandResult? {
        invalidateTransientState()
        let nsSource = source as NSString
        let safeSelection = SyntaxEditorRangeUtilities.clampedRange(selection, utf16Length: nsSource.length)
        let lineStarts = SyntaxLanguageTextUtilities.lineStartOffsets(in: nsSource, selection: safeSelection)
        guard !lineStarts.isEmpty else { return nil }

        let edits = lineStarts.map {
            SyntaxLanguageTextEdit(range: NSRange(location: $0, length: 0), replacement: indentUnit)
        }

        return wrap(
            SyntaxLanguageTextUtilities.applyEdits(edits, source: source, selection: safeSelection),
            refreshStartUTF16: lineStarts[0]
        )
    }

    package func outdentSelection(source: String, selection: NSRange) -> EditorCommandResult? {
        invalidateTransientState()
        let nsSource = source as NSString
        let safeSelection = SyntaxEditorRangeUtilities.clampedRange(selection, utf16Length: nsSource.length)
        let lineStarts = SyntaxLanguageTextUtilities.lineStartOffsets(in: nsSource, selection: safeSelection)
        guard !lineStarts.isEmpty else { return nil }

        var edits: [SyntaxLanguageTextEdit] = []
        edits.reserveCapacity(lineStarts.count)

        for lineStart in lineStarts {
            let lineRange = nsSource.lineRange(for: NSRange(location: lineStart, length: 0))
            let removable = SyntaxLanguageTextUtilities.removableIndentLength(
                in: nsSource,
                lineRange: lineRange,
                indentUnit: indentUnit
            )
            guard removable > 0 else { continue }
            edits.append(SyntaxLanguageTextEdit(range: NSRange(location: lineStart, length: removable), replacement: ""))
        }

        guard !edits.isEmpty else { return nil }
        return wrap(
            SyntaxLanguageTextUtilities.applyEdits(edits, source: source, selection: safeSelection),
            refreshStartUTF16: lineStarts[0]
        )
    }

    package func toggleComment(
        source: String,
        selection: NSRange,
        language: SyntaxLanguage
    ) -> EditorCommandResult? {
        invalidateTransientState()
        let nsSource = source as NSString
        let safeSelection = SyntaxEditorRangeUtilities.clampedRange(selection, utf16Length: nsSource.length)
        guard let edit = language.toggleComment(source: source, selection: safeSelection) else { return nil }
        let refreshStartUTF16 = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
            in: source,
            around: safeSelection.location
        )
        return wrap(edit, refreshStartUTF16: refreshStartUTF16)
    }
}

private extension EditorCommandEngine {
    func wrap(_ edit: SyntaxLanguageEdit, refreshStartUTF16: Int) -> EditorCommandResult {
        EditorCommandResult(
            text: edit.text,
            selectedRange: edit.selectedRange,
            refreshStartUTF16: max(0, refreshStartUTF16)
        )
    }

    func autoPair(
        source: String,
        range: NSRange,
        input: Character,
        language: SyntaxLanguage
    ) -> EditorCommandResult? {
        let nsSource = source as NSString
        let openingPairs: [Character: Character] = [
            "(": ")",
            "[": "]",
            "{": "}",
            "\"": "\"",
            "'": "'",
            "`": "`",
        ]
        let closingPairs: [Character: Character] = [
            ")": "(",
            "]": "[",
            "}": "{",
            "\"": "\"",
            "'": "'",
            "`": "`",
        ]

        if shouldInsertPendingTOMLMultilineDelimiter(
            range: range,
            input: input,
            language: language
        ) {
            pendingTOMLMultilineDelimiter = nil
            let updated = nsSource.replacingCharacters(in: range, with: String(input))
            return EditorCommandResult(
                text: updated,
                selectedRange: NSRange(location: range.location + 1, length: 0),
                refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: source, around: range.location)
            )
        }

        pendingTOMLMultilineDelimiter = nil

        if isQuote(input),
           range.length == 0,
           let next = SyntaxLanguageTextUtilities.character(in: nsSource, at: range.location),
           next == input
        {
            if shouldStartTOMLMultilineDelimiterPending(
                source: nsSource,
                range: range,
                input: input,
                language: language
            ) {
                pendingTOMLMultilineDelimiter = PendingTOMLMultilineDelimiter(
                    cursorLocation: range.location + 1,
                    quote: input
                )
            }

            return EditorCommandResult(
                text: source,
                selectedRange: NSRange(location: range.location + 1, length: 0),
                refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: source, around: range.location)
            )
        }

        if let open = openingPairs[input] {
            if isQuote(input),
               language.isInsideLiteralOrComment(source: source, location: range.location)
            {
                return nil
            }

            if range.length > 0 {
                let selected = nsSource.substring(with: range)
                let wrapped = String(input) + selected + String(open)
                let updated = nsSource.replacingCharacters(in: range, with: wrapped)
                let cursor = range.location + wrapped.utf16.count
                return EditorCommandResult(
                    text: updated,
                    selectedRange: NSRange(location: cursor, length: 0),
                    refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: source, around: range.location)
                )
            }

            let inserted = String(input) + String(open)
            let updated = nsSource.replacingCharacters(in: range, with: inserted)
            return EditorCommandResult(
                text: updated,
                selectedRange: NSRange(location: range.location + 1, length: 0),
                refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: source, around: range.location)
            )
        }

        if let pairOpen = closingPairs[input], range.length == 0 {
            if let next = SyntaxLanguageTextUtilities.character(in: nsSource, at: range.location), next == input {
                return EditorCommandResult(
                    text: source,
                    selectedRange: NSRange(location: range.location + 1, length: 0),
                    refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: source, around: range.location)
                )
            }

            if input == "}" {
                if let nextNonWhitespace = SyntaxLanguageTextUtilities.nextNonWhitespaceOffset(in: nsSource, from: range.location),
                   SyntaxLanguageTextUtilities.character(in: nsSource, at: nextNonWhitespace) == input
                {
                    return EditorCommandResult(
                        text: source,
                        selectedRange: NSRange(location: nextNonWhitespace + 1, length: 0),
                        refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: source, around: range.location)
                    )
                }

                if let result = outdentForClosingBrace(
                    source: source,
                    location: range.location,
                    expectedPairOpen: pairOpen
                ) {
                    return result
                }
            }
        }

        return nil
    }

    func pairAwareBackspace(source: String, range: NSRange) -> EditorCommandResult? {
        let nsSource = source as NSString
        guard range.length == 1 else { return nil }
        let deleteOffset = range.location
        let afterOffset = range.location + range.length
        guard let deleted = SyntaxLanguageTextUtilities.character(in: nsSource, at: deleteOffset),
              let after = SyntaxLanguageTextUtilities.character(in: nsSource, at: afterOffset)
        else {
            return nil
        }

        let pairs: [Character: Character] = [
            "(": ")",
            "[": "]",
            "{": "}",
            "\"": "\"",
            "'": "'",
            "`": "`",
        ]
        guard pairs[deleted] == after else { return nil }

        let removeRange = NSRange(location: deleteOffset, length: 2)
        let updated = nsSource.replacingCharacters(in: removeRange, with: "")
        return EditorCommandResult(
            text: updated,
            selectedRange: NSRange(location: deleteOffset, length: 0),
            refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: source, around: deleteOffset)
        )
    }

    func smartNewline(source: String, range: NSRange) -> EditorCommandResult? {
        guard range.length == 0 else { return nil }
        let nsSource = source as NSString

        let lineRange = nsSource.lineRange(for: NSRange(location: range.location, length: 0))
        let lineIndent = SyntaxLanguageTextUtilities.leadingIndent(in: nsSource, lineRange: lineRange)

        let previous = SyntaxLanguageTextUtilities.previousNonWhitespaceCharacter(in: nsSource, before: range.location)
        let next = SyntaxLanguageTextUtilities.character(in: nsSource, at: range.location)
        let openToClose: [Character: Character] = [
            "{": "}",
            "[": "]",
            "(": ")",
        ]

        let insertion: String
        let cursorOffset: Int

        if let previous, let pairClose = openToClose[previous], next == pairClose {
            insertion = "\n" + lineIndent + indentUnit + "\n" + lineIndent
            cursorOffset = ("\n" + lineIndent + indentUnit).utf16.count
        } else if let previous, openToClose[previous] != nil {
            insertion = "\n" + lineIndent + indentUnit
            cursorOffset = insertion.utf16.count
        } else {
            insertion = "\n" + lineIndent
            cursorOffset = insertion.utf16.count
        }

        let updated = nsSource.replacingCharacters(in: range, with: insertion)
        return EditorCommandResult(
            text: updated,
            selectedRange: NSRange(location: range.location + cursorOffset, length: 0),
            refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: source, around: range.location)
        )
    }

    func outdentForClosingBrace(
        source: String,
        location: Int,
        expectedPairOpen: Character
    ) -> EditorCommandResult? {
        let nsSource = source as NSString
        let lineRange = nsSource.lineRange(for: NSRange(location: location, length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: max(0, location - lineRange.location))
        let prefix = nsSource.substring(with: prefixRange)

        guard prefix.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        guard !prefix.isEmpty else { return nil }

        let removable = SyntaxLanguageTextUtilities.trailingIndentRemovalLength(prefix, indentUnit: indentUnit)
        guard removable > 0 else { return nil }

        let reducedPrefixLength = max(0, prefix.utf16.count - removable)
        let reducedPrefix = String(prefix.prefix(reducedPrefixLength))
        let replacement = reducedPrefix + String(closingCharacter(for: expectedPairOpen))
        let updated = nsSource.replacingCharacters(in: prefixRange, with: replacement)
        let cursor = lineRange.location + replacement.utf16.count

        return EditorCommandResult(
            text: updated,
            selectedRange: NSRange(location: cursor, length: 0),
            refreshStartUTF16: lineRange.location
        )
    }

    func isQuote(_ character: Character) -> Bool {
        character == "\"" || character == "'" || character == "`"
    }

    func shouldInsertPendingTOMLMultilineDelimiter(
        range: NSRange,
        input: Character,
        language: SyntaxLanguage
    ) -> Bool {
        guard language == .toml,
              let pendingTOMLMultilineDelimiter,
              range.length == 0,
              pendingTOMLMultilineDelimiter.cursorLocation == range.location,
              pendingTOMLMultilineDelimiter.quote == input
        else {
            return false
        }

        return true
    }

    func shouldStartTOMLMultilineDelimiterPending(
        source: NSString,
        range: NSRange,
        input: Character,
        language: SyntaxLanguage
    ) -> Bool {
        guard language == .toml,
              range.length == 0,
              input == "\"" || input == "'",
              range.location > 0,
              let previous = SyntaxLanguageTextUtilities.character(in: source, at: range.location - 1),
              let next = SyntaxLanguageTextUtilities.character(in: source, at: range.location)
        else {
            return false
        }

        return previous == input && next == input
    }

    func closingCharacter(for opening: Character) -> Character {
        switch opening {
        case "(":
            return ")"
        case "[":
            return "]"
        case "{":
            return "}"
        default:
            return "}"
        }
    }
}
