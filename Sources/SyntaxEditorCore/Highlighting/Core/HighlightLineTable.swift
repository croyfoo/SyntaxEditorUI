import Foundation
import SwiftTreeSitter

/// Chunked line-offset table for the highlighting session.
///
/// Lines are stored in chunks of ~64 with per-chunk *cumulative* end offsets
/// (UTF-16, including the trailing line break) and cached chunk prefixes, so
/// `lineStartOffset` is O(log #chunks) with an O(1) in-chunk lookup — the token
/// planes call it per segment, which made per-query partial sums the dominant
/// debug-build cost. Edge rules (line containment, EOF handling,
/// trailing-empty-line drop, widening) are identical to the replaced
/// `SyntaxHighlightLineIndex`; line-break detection reuses `LineOffsetTable`'s
/// definition (any Character containing scalar 10 or 13; CRLF is one Character).
package final class HighlightLineTable {
    private static let targetChunkSize = 64

    private struct Chunk {
        /// endOffsets[i] = sum of line lengths through local line i; the last
        /// entry is the chunk's UTF-16 total.
        var endOffsets: ContiguousArray<Int32>

        init(lengths: ArraySlice<Int32>) {
            var offsets = ContiguousArray(lengths)
            offsets.withUnsafeMutableBufferPointer { buffer in
                var running: Int32 = 0
                var index = 0
                while index < buffer.count {
                    running += buffer[index]
                    buffer[index] = running
                    index += 1
                }
            }
            endOffsets = offsets
        }

        var lineCount: Int { endOffsets.count }
        var utf16Total: Int { Int(endOffsets[endOffsets.count - 1]) }

        func startOffset(ofLocal local: Int) -> Int {
            local == 0 ? 0 : Int(endOffsets[local - 1])
        }

        func length(ofLocal local: Int) -> Int {
            Int(endOffsets[local]) - startOffset(ofLocal: local)
        }

        /// First local line whose end offset exceeds `offset` (clamped to the
        /// last line) — the line containing the in-chunk offset.
        func localLine(containing offset: Int) -> Int {
            var lower = 0
            var upper = endOffsets.count - 1
            while lower < upper {
                let middle = (lower + upper) / 2
                if Int(endOffsets[middle]) <= offset {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return lower
        }

        func lengths(localRange: Range<Int>) -> [Int32] {
            var result: [Int32] = []
            result.reserveCapacity(localRange.count)
            var index = localRange.lowerBound
            while index < localRange.upperBound {
                result.append(Int32(length(ofLocal: index)))
                index += 1
            }
            return result
        }
    }

    private var chunks: [Chunk] = [Chunk(lengths: [0][...])]
    /// chunkLineStart[i] = global index of the first line in chunk i; one extra
    /// trailing entry = lineCount. Same shape for offsets.
    private var chunkLineStart: [Int] = [0, 1]
    private var chunkOffsetStart: [Int] = [0, 0]

    package init() {}

    package var lineCount: Int {
        chunkLineStart[chunks.count]
    }

    package var totalUTF16Length: Int {
        chunkOffsetStart[chunks.count]
    }

    // MARK: - Construction

    package func reset(source: String) {
        let lengths = LineOffsetTable.lineLengths(in: source)
        chunks = Self.chunked(lengths.map(Int32.init))
        rebuildPrefixes()
    }

    // MARK: - Queries (semantics identical to the legacy table)

    package func lineStartOffset(at index: Int) -> Int {
        let clamped = min(max(0, index), lineCount)
        let (chunkIndex, local) = locateLine(clamped)
        guard chunkIndex < chunks.count else { return totalUTF16Length }
        return chunkOffsetStart[chunkIndex] + chunks[chunkIndex].startOffset(ofLocal: local)
    }

    package func lineEndOffset(at index: Int) -> Int {
        guard lineCount > 0 else { return 0 }
        let clamped = min(max(0, index), lineCount - 1)
        return lineStartOffset(at: clamped + 1)
    }

    package func lineLength(at index: Int) -> Int {
        guard index >= 0, index < lineCount else { return 0 }
        let (chunkIndex, local) = locateLine(index)
        return chunks[chunkIndex].length(ofLocal: local)
    }

    package func lineIndex(containingUTF16Offset offset: Int) -> Int {
        let clampedOffset = min(max(0, offset), totalUTF16Length)
        // Binary search the chunk whose offset span contains the position; an
        // offset exactly at a line start belongs to that line.
        var lower = 0
        var upper = chunks.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if chunkOffsetStart[middle + 1] <= clampedOffset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower >= chunks.count {
            return max(0, lineCount - 1)
        }
        // An offset equal to the total stays on the last line.
        let local = chunks[lower].localLine(containing: clampedOffset - chunkOffsetStart[lower])
        return min(chunkLineStart[lower] + local, lineCount - 1)
    }

    package func lineRange(containingUTF16Range range: NSRange) -> Range<Int> {
        guard lineCount > 0 else { return 0..<0 }
        let textLength = totalUTF16Length
        let lower = min(max(0, range.location), textLength)
        let upper = min(max(lower, range.upperBound), textLength)
        let startIndex = lineIndex(containingUTF16Offset: lower)
        let endLookup: Int
        if range.length == 0 {
            endLookup = lower
        } else if upper == textLength {
            endLookup = upper
        } else {
            endLookup = max(lower, upper - 1)
        }
        let endIndex = lineIndex(containingUTF16Offset: endLookup)
        return startIndex..<(min(lineCount, endIndex + 1))
    }

    /// tree-sitter Point for an offset: column is in BYTES under UTF-16 encoding
    /// (UTF-16 column × 2), matching the engine's InputEdit convention.
    package func point(at utf16Offset: Int) -> Point {
        let clampedOffset = max(0, utf16Offset)
        let index = lineIndex(containingUTF16Offset: clampedOffset)
        let lineStart = lineStartOffset(at: index)
        return Point(row: index, column: max(0, clampedOffset - lineStart) * 2)
    }

    // MARK: - Edits

    /// Applies a text mutation. CONTRACT: `self` currently describes
    /// `previousSource` (the pre-edit text); mutation coordinates are pre-edit.
    /// Returns the replaced line span and replacement line count so callers
    /// (token planes, name maps) can splice parallel structures identically.
    @discardableResult
    package func apply(
        mutation: SyntaxHighlightMutation,
        previousSource: String
    ) -> (replacedLines: Range<Int>, replacementLineCount: Int) {
        let nsSource = previousSource as NSString
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location <= nsSource.length,
              mutation.location + mutation.length <= nsSource.length else {
            // Out-of-bounds mutations degrade to a full reset against the post-edit
            // text (legacy behavior: survivable, never throws).
            let next = SyntaxEditorModel.applying([
                SyntaxEditorTextEdit(
                    range: NSRange(
                        location: min(max(0, mutation.location), nsSource.length),
                        length: 0
                    ),
                    replacement: mutation.replacement
                ),
            ], to: previousSource)
            let previousCount = lineCount
            reset(source: next)
            return (0..<previousCount, lineCount)
        }

        // Affected whole-line envelope (legacy rules: +1 line when the deleted text
        // or replacement contains a line break and more lines follow).
        let startIndex = lineIndex(containingUTF16Offset: mutation.location)
        let endLocation = mutation.location + mutation.length
        let lookup = mutation.length == 0
            ? mutation.location
            : endLocation == nsSource.length
                ? endLocation
                : max(mutation.location, endLocation - 1)
        var endIndex = lineIndex(containingUTF16Offset: lookup) + 1
        let deletedText = nsSource.substring(
            with: NSRange(location: mutation.location, length: mutation.length)
        )
        if LineOffsetTable.containsLineBreak(deletedText) || LineOffsetTable.containsLineBreak(mutation.replacement),
           endIndex < lineCount {
            endIndex += 1
        }

        let lowerOffset = lineStartOffset(at: startIndex)
        let upperOffset = endIndex < lineCount ? lineStartOffset(at: endIndex) : nsSource.length
        let affectedRange = NSRange(location: lowerOffset, length: upperOffset - lowerOffset)
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
        var replacementLengths = LineOffsetTable.lineLengths(in: newSegment)
        if affectedRange.upperBound < nsSource.length,
           LineOffsetTable.endsWithLineBreak(newSegment),
           replacementLengths.count > 1 {
            replacementLengths.removeLast()
        }

        replaceLines(in: startIndex..<endIndex, with: replacementLengths)
        return (startIndex..<endIndex, replacementLengths.count)
    }

    package func replaceLines(in range: Range<Int>, with replacementLengths: [Int]) {
        let lower = min(max(0, range.lowerBound), lineCount)
        let upper = min(max(lower, range.upperBound), lineCount)
        let replacements = replacementLengths.isEmpty ? [0] : replacementLengths

        // Fast path: single line replaced by a single line inside one chunk.
        if upper - lower == 1, replacements.count == 1 {
            let (chunkIndex, local) = locateLine(lower)
            if chunkIndex < chunks.count, local < chunks[chunkIndex].lineCount {
                let delta = Int32(replacements[0] - chunks[chunkIndex].length(ofLocal: local))
                if delta != 0 {
                    chunks[chunkIndex].endOffsets.withUnsafeMutableBufferPointer { buffer in
                        var index = local
                        while index < buffer.count {
                            buffer[index] += delta
                            index += 1
                        }
                    }
                    var index = chunkIndex + 1
                    while index <= chunks.count {
                        chunkOffsetStart[index] += Int(delta)
                        index += 1
                    }
                }
                return
            }
        }

        // General path: rebuild the affected chunk span.
        let (startChunk, startLocal) = locateLine(lower)
        let (endChunkRaw, endLocalRaw) = locateLine(upper)
        let endChunk = min(endChunkRaw, chunks.count - 1)
        var merged: [Int32] = []
        if startChunk < chunks.count {
            merged.append(contentsOf: chunks[startChunk].lengths(localRange: 0..<startLocal))
        }
        merged.append(contentsOf: replacements.map(Int32.init))
        if endChunkRaw < chunks.count {
            let chunk = chunks[endChunkRaw]
            merged.append(contentsOf: chunk.lengths(localRange: min(endLocalRaw, chunk.lineCount)..<chunk.lineCount))
        }
        let replacementChunks = Self.chunked(merged)
        let spanEnd = min(endChunk + 1, chunks.count)
        if startChunk < chunks.count {
            chunks.replaceSubrange(startChunk..<spanEnd, with: replacementChunks)
        } else {
            chunks.append(contentsOf: replacementChunks)
        }
        if chunks.isEmpty {
            chunks = [Chunk(lengths: [0][...])]
        }
        rebuildPrefixes()
    }

    // MARK: - Internals

    private func locateLine(_ index: Int) -> (chunk: Int, local: Int) {
        var lower = 0
        var upper = chunks.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if chunkLineStart[middle + 1] <= index {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower >= chunks.count {
            return (chunks.count, 0)
        }
        return (lower, index - chunkLineStart[lower])
    }

    private func rebuildPrefixes() {
        chunkLineStart = Array(repeating: 0, count: chunks.count + 1)
        chunkOffsetStart = Array(repeating: 0, count: chunks.count + 1)
        var lines = 0
        var offset = 0
        var index = 0
        while index < chunks.count {
            chunkLineStart[index] = lines
            chunkOffsetStart[index] = offset
            lines += chunks[index].lineCount
            offset += chunks[index].utf16Total
            index += 1
        }
        chunkLineStart[chunks.count] = lines
        chunkOffsetStart[chunks.count] = offset
    }

    private static func chunked(_ lengths: [Int32]) -> [Chunk] {
        guard !lengths.isEmpty else { return [Chunk(lengths: [0][...])] }
        var result: [Chunk] = []
        result.reserveCapacity(lengths.count / targetChunkSize + 1)
        var index = 0
        while index < lengths.count {
            let end = min(index + targetChunkSize, lengths.count)
            result.append(Chunk(lengths: lengths[index..<end]))
            index = end
        }
        return result
    }
}
