import Foundation

package final class LineMetricsIndex {
    private var lineStartOffsets: [Int] = [0]
    private var lineColumns: [Int] = [0]
    private let tabWidth: Int

    package private(set) var fullRebuildCount = 0

    package init(source: String = "", tabWidth: Int) {
        self.tabWidth = max(1, tabWidth)
        reset(source: source)
    }

    package func reset(source: String) {
        fullRebuildCount += 1
        let metrics = Self.metrics(in: source, baseOffset: 0, tabWidth: tabWidth)
        lineStartOffsets = metrics.starts
        lineColumns = metrics.columns
    }

    package func apply(edits: [SyntaxEditorTextEdit], previousSource: String) {
        guard !edits.isEmpty else { return }
        guard let affected = affectedRange(for: edits, in: previousSource) else {
            reset(source: SyntaxEditorDocument.applying(edits, to: previousSource))
            return
        }

        let nsSource = previousSource as NSString
        let oldSegment = nsSource.substring(with: affected.range)
        let localEdits = edits.map {
            SyntaxEditorTextEdit(
                range: NSRange(location: $0.range.location - affected.range.location, length: $0.range.length),
                replacement: $0.replacement
            )
        }
        let newSegment = SyntaxEditorDocument.applying(localEdits, to: oldSegment)
        var metrics = Self.metrics(in: newSegment, baseOffset: affected.range.location, tabWidth: tabWidth)
        if affected.range.upperBound < nsSource.length,
           Self.endsWithLineBreak(newSegment),
           metrics.starts.count > 1 {
            metrics.starts.removeLast()
            metrics.columns.removeLast()
        }

        let startIndex = lineIndex(containingUTF16Offset: affected.range.location)
        let endIndex = oldLineEndIndex(for: affected.range, sourceUTF16Length: nsSource.length)
        lineStartOffsets.replaceSubrange(startIndex..<endIndex, with: metrics.starts)
        lineColumns.replaceSubrange(startIndex..<endIndex, with: metrics.columns)

        let delta = newSegment.utf16.count - affected.range.length
        guard delta != 0 else { return }
        let adjustmentStart = startIndex + metrics.starts.count
        guard adjustmentStart < lineStartOffsets.count else { return }
        for index in adjustmentStart..<lineStartOffsets.count {
            lineStartOffsets[index] += delta
        }
    }

    package func horizontalDocumentWidth(
        columnWidth: CGFloat,
        textContainerInset: CGFloat,
        lineFragmentPadding: CGFloat
    ) -> CGFloat {
        let maxColumns = lineColumns.max() ?? 0
        return ceil(CGFloat(maxColumns) * columnWidth + lineFragmentPadding * 2 + textContainerInset)
    }
}

private extension LineMetricsIndex {
    func affectedRange(for edits: [SyntaxEditorTextEdit], in source: String) -> (range: NSRange, includesLineBreakMutation: Bool)? {
        let nsSource = source as NSString
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        guard let first = sorted.first, let last = sorted.last else { return nil }

        let lower = max(0, min(first.range.location, nsSource.length))
        let upper = min(nsSource.length, max(last.range.location + last.range.length, lower))
        var range = nsSource.lineRange(for: NSRange(location: lower, length: max(0, upper - lower)))

        let touchesLineBreak = sorted.contains { edit in
            edit.replacement.contains(where: Self.isLineBreak)
                || nsSource.substring(with: edit.range).contains(where: Self.isLineBreak)
        }
        if touchesLineBreak, range.upperBound < nsSource.length {
            let nextLineRange = nsSource.lineRange(for: NSRange(location: range.upperBound, length: 0))
            range.length = nextLineRange.upperBound - range.location
        }
        return (range, touchesLineBreak)
    }

    func lineIndex(containingUTF16Offset offset: Int) -> Int {
        var lower = 0
        var upper = lineStartOffsets.count
        while lower < upper {
            let mid = (lower + upper) / 2
            if lineStartOffsets[mid] <= offset {
                lower = mid + 1
            } else {
                upper = mid
            }
        }
        return max(0, lower - 1)
    }

    func oldLineEndIndex(for range: NSRange, sourceUTF16Length: Int) -> Int {
        guard !lineStartOffsets.isEmpty else { return 0 }
        let lookup = range.length == 0
            ? range.location
            : max(range.location, min(sourceUTF16Length, range.upperBound) - 1)
        return min(lineStartOffsets.count, lineIndex(containingUTF16Offset: lookup) + 1)
    }

    static func metrics(in source: String, baseOffset: Int, tabWidth: Int) -> (starts: [Int], columns: [Int]) {
        var starts = [baseOffset]
        var columns: [Int] = []
        var currentColumns = 0
        var utf16Offset = baseOffset

        for character in source {
            let utf16Length = character.utf16.count
            if isLineBreak(character) {
                columns.append(currentColumns)
                currentColumns = 0
                starts.append(utf16Offset + utf16Length)
            } else {
                currentColumns += SyntaxEditorDisplayColumnUtilities.columnWidth(
                    for: character,
                    currentColumn: currentColumns,
                    tabWidth: tabWidth
                )
            }
            utf16Offset += utf16Length
        }

        columns.append(currentColumns)
        return (starts, columns)
    }

    static func endsWithLineBreak(_ source: String) -> Bool {
        source.last.map(isLineBreak) ?? false
    }

    static func isLineBreak(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.value == 10 || scalar.value == 13
        }
    }
}

private extension NSRange {
    var upperBound: Int {
        location + length
    }
}
