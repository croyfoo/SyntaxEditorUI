import Foundation

/// Two-plane packed per-line token store.
///
/// The base plane holds tree-sitter capture tokens, the overlay plane semantic
/// tokens. Segments are line-relative; splicing the line array on an edit shifts
/// every untouched line implicitly (never re-tokenized). Multi-line logical
/// tokens are split into per-line segments linked by continuation flags and
/// re-joined at materialization by per-boundary (plane, style) order matching —
/// replacing the old per-segment groupID dictionaries.
///
/// Patch APIs report the union UTF-16 range of lines whose stored segments
/// actually changed; that diff is what keeps refresh ranges edit-local.
/// `tokens(in:)` is the system's single merge point: cross-plane dedup and the
/// legacy display order are applied here, so the full and incremental paths
/// materialize identically by construction.
package final class LineTokenPlanes {
    package struct PackedSegment: Equatable {
        var startCol: UInt32
        var endCol: UInt32
        var styleID: UInt16
        var flags: UInt16

        static let continuesFromPrevious: UInt16 = 1 << 0
        static let continuesToNext: UInt16 = 1 << 1

        var continuesFromPrevious: Bool { flags & Self.continuesFromPrevious != 0 }
        var continuesToNext: Bool { flags & Self.continuesToNext != 0 }
    }

    private struct Line {
        var base: ContiguousArray<PackedSegment> = []
        var overlay: ContiguousArray<PackedSegment> = []

        var isEmpty: Bool { base.isEmpty && overlay.isEmpty }
    }

    package struct EditResult {
        /// Post-edit line indices whose stored tokens were dropped by the edit,
        /// including continuation-chain spill into neighboring lines.
        package let droppedLines: Range<Int>?
        /// Pre-edit line span that was replaced, and the replacement line count —
        /// mirrors the line-table splice so parallel per-line structures stay in
        /// lockstep.
        package let replacedLines: Range<Int>
        package let replacementLineCount: Int
    }

    package let styles: HighlightStyleTable
    private var lines: ContiguousArray<Line> = [Line()]

    package init(styles: HighlightStyleTable) {
        self.styles = styles
    }

    package var lineCount: Int { lines.count }

    // MARK: - Whole-document writes

    package func reset(tokens: [SyntaxHighlightToken], lineTable: HighlightLineTable) {
        lines = ContiguousArray(repeating: Line(), count: max(1, lineTable.lineCount))
        insert(tokens: tokens, lineTable: lineTable)
        sortAllLines()
    }

    package func clear(lineCount: Int = 1) {
        lines = ContiguousArray(repeating: Line(), count: max(1, lineCount))
    }

    // MARK: - Edit application

    /// Drops every logical token touching the edited lines (both planes,
    /// following continuation chains into neighbors) and splices the line array.
    /// CONTRACT: `lineTable` must still describe the PRE-edit text. The edited
    /// line envelope uses the legacy store rules (widen one line only when the
    /// deleted text contains a break AND the deletion ends exactly at a line
    /// end), which differ from the line table's own envelope; only the resulting
    /// line COUNTS must agree, and they do because both splice the same text.
    package func applyEdit(
        _ mutation: SyntaxHighlightMutation,
        previousSource: String,
        lineTable: HighlightLineTable
    ) -> EditResult {
        let nsSource = previousSource as NSString
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location <= nsSource.length,
              mutation.location + mutation.length <= nsSource.length else {
            let previousCount = lines.count
            clear(lineCount: lineTable.lineCount)
            return EditResult(droppedLines: nil, replacedLines: 0..<previousCount, replacementLineCount: lines.count)
        }

        var replaced = lineTable.lineRange(
            containingUTF16Range: NSRange(location: mutation.location, length: mutation.length)
        )
        let deletedText = nsSource.substring(
            with: NSRange(location: mutation.location, length: mutation.length)
        )
        if LineOffsetTable.containsLineBreak(deletedText),
           replaced.upperBound < lines.count,
           replaced.upperBound > replaced.lowerBound,
           mutation.location + mutation.length == lineTable.lineEndOffset(at: replaced.upperBound - 1) {
            replaced = replaced.lowerBound..<(replaced.upperBound + 1)
        }

        let lowerOffset = lineTable.lineStartOffset(at: replaced.lowerBound)
        let upperOffset = replaced.upperBound < lineTable.lineCount
            ? lineTable.lineStartOffset(at: replaced.upperBound)
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
           LineOffsetTable.endsWithLineBreak(newSegment),
           replacementLineCount > 1 {
            replacementLineCount -= 1
        }

        let lower = min(max(0, replaced.lowerBound), lines.count)
        let upper = min(max(lower, replaced.upperBound), lines.count)
        let replacementCount = max(1, replacementLineCount)

        var droppedLower = lower
        var droppedUpper = upper
        let hadTokens = (lower..<upper).contains { !lines[$0].isEmpty }

        // Sever and drop upward continuation chains entering the replaced span.
        if lower > 0, lower <= lines.count {
            let seedBase = lines[lower - 1].base.indices.filter { lines[lower - 1].base[$0].continuesToNext }
            let seedOverlay = lines[lower - 1].overlay.indices.filter { lines[lower - 1].overlay[$0].continuesToNext }
            if !seedBase.isEmpty || !seedOverlay.isEmpty {
                droppedLower = min(droppedLower, dropChains(
                    from: lower - 1,
                    direction: -1,
                    seedBase: seedBase,
                    seedOverlay: seedOverlay
                ))
            }
        }
        // Downward chains leaving the replaced span.
        if upper < lines.count {
            let seedBase = lines[upper].base.indices.filter { lines[upper].base[$0].continuesFromPrevious }
            let seedOverlay = lines[upper].overlay.indices.filter { lines[upper].overlay[$0].continuesFromPrevious }
            if !seedBase.isEmpty || !seedOverlay.isEmpty {
                droppedUpper = max(droppedUpper, dropChains(
                    from: upper,
                    direction: 1,
                    seedBase: seedBase,
                    seedOverlay: seedOverlay
                ) + 1)
            }
        }

        lines.replaceSubrange(lower..<upper, with: repeatElement(Line(), count: replacementCount))
        if lines.isEmpty {
            lines = [Line()]
        }

        let lineDelta = replacementCount - (upper - lower)
        let dropped: Range<Int>?
        if hadTokens || droppedLower < lower || droppedUpper > upper {
            let mappedUpper = droppedUpper > upper ? droppedUpper + lineDelta : lower + replacementCount
            let clampedLower = min(max(0, droppedLower), lines.count)
            let clampedUpper = min(max(mappedUpper, clampedLower + 1), lines.count)
            dropped = clampedLower < clampedUpper ? clampedLower..<clampedUpper : nil
        } else {
            dropped = nil
        }
        return EditResult(
            droppedLines: dropped,
            replacedLines: lower..<upper,
            replacementLineCount: replacementCount
        )
    }

    /// Removes continuation chains starting at `line` walking in `direction`,
    /// seeded by the given segment indices. Returns the furthest line touched.
    private func dropChains(
        from line: Int,
        direction: Int,
        seedBase: [Int],
        seedOverlay: [Int]
    ) -> Int {
        var current = line
        var baseSeeds = seedBase
        var overlaySeeds = seedOverlay
        var furthest = line

        while lines.indices.contains(current), !(baseSeeds.isEmpty && overlaySeeds.isEmpty) {
            furthest = current
            // Determine which removed segments continue further, matching by
            // (style, order) across the next boundary.
            var nextBaseStyles = continuationStyles(lines[current].base, indices: baseSeeds, direction: direction)
            var nextOverlayStyles = continuationStyles(lines[current].overlay, indices: overlaySeeds, direction: direction)

            removeSegments(at: baseSeeds, line: current, overlayPlane: false)
            removeSegments(at: overlaySeeds, line: current, overlayPlane: true)

            let next = current + direction
            guard lines.indices.contains(next) else { break }
            baseSeeds = matchContinuations(in: lines[next].base, styles: &nextBaseStyles, direction: direction)
            overlaySeeds = matchContinuations(in: lines[next].overlay, styles: &nextOverlayStyles, direction: direction)
            current = next
        }
        return furthest
    }

    /// Styles (in segment order) of removed segments that continue across the
    /// next boundary in `direction`.
    private func continuationStyles(
        _ segments: ContiguousArray<PackedSegment>,
        indices: [Int],
        direction: Int
    ) -> [UInt16: Int] {
        var counts: [UInt16: Int] = [:]
        for index in indices {
            let segment = segments[index]
            let continues = direction < 0 ? segment.continuesFromPrevious : segment.continuesToNext
            if continues {
                counts[segment.styleID, default: 0] += 1
            }
        }
        return counts
    }

    /// Segments on the adjacent line that are the matched continuations of the
    /// removed ones (consumes from the per-style counts, in segment order).
    private func matchContinuations(
        in segments: ContiguousArray<PackedSegment>,
        styles counts: inout [UInt16: Int],
        direction: Int
    ) -> [Int] {
        guard !counts.isEmpty else { return [] }
        var matched: [Int] = []
        for (index, segment) in segments.enumerated() {
            let connectsBack = direction < 0 ? segment.continuesToNext : segment.continuesFromPrevious
            guard connectsBack, let remaining = counts[segment.styleID], remaining > 0 else { continue }
            counts[segment.styleID] = remaining - 1
            matched.append(index)
        }
        return matched
    }

    private func removeSegments(at indices: [Int], line: Int, overlayPlane: Bool) {
        guard !indices.isEmpty else { return }
        let removal = Set(indices)
        if overlayPlane {
            lines[line].overlay = ContiguousArray(lines[line].overlay.enumerated()
                .filter { !removal.contains($0.offset) }
                .map(\.element))
        } else {
            lines[line].base = ContiguousArray(lines[line].base.enumerated()
                .filter { !removal.contains($0.offset) }
                .map(\.element))
        }
    }

    // MARK: - Patch APIs

    package enum Plane {
        case base
        case overlay
        case both
    }

    /// Replaces tokens of `plane` intersecting `range` with `tokens` (full
    /// logical-token removal, unclipped insertion). Returns the union UTF-16
    /// whole-line range of lines whose segments changed, or nil.
    package func replaceTokens(
        in range: NSRange,
        with tokens: [SyntaxHighlightToken],
        plane: Plane,
        lineTable: HighlightLineTable
    ) -> NSRange? {
        ensureLineCount(lineTable.lineCount)
        let lineRange = lineTable.lineRange(containingUTF16Range: range)
        let lower = min(max(0, lineRange.lowerBound), lines.count)
        let upper = min(max(lower, lineRange.upperBound), lines.count)
        guard lower < upper else { return nil }

        // Snapshot for the diff: chain removal and insertion can spill beyond the
        // patched lines; track every touched line lazily.
        var snapshots: [Int: Line] = [:]
        func snapshot(_ line: Int) {
            guard snapshots[line] == nil, lines.indices.contains(line) else { return }
            snapshots[line] = lines[line]
        }
        for line in lower..<upper { snapshot(line) }

        if plane != .overlay {
            removeTokens(intersecting: range, lineRange: lower..<upper, overlayPlane: false, lineTable: lineTable, willTouch: snapshot)
        }
        if plane != .base {
            removeTokens(intersecting: range, lineRange: lower..<upper, overlayPlane: true, lineTable: lineTable, willTouch: snapshot)
        }
        insert(tokens: tokens, lineTable: lineTable, willTouch: snapshot)

        var touched = Set(snapshots.keys)
        for line in lower..<upper { touched.insert(line) }
        sortLines(touched)

        var changed: NSRange?
        for (line, before) in snapshots {
            guard lines.indices.contains(line) else { continue }
            let after = lines[line]
            if before.base == after.base && before.overlay == after.overlay { continue }
            let lineStart = lineTable.lineStartOffset(at: line)
            // Sub-line refresh: only the extents of segments present on one side
            // but not the other need repainting (whole-line spans broke the
            // strict `refreshRange < document` pins on single-line documents).
            var lower = Int.max
            var upper = Int.min
            func accumulate(_ beforeSegments: ContiguousArray<PackedSegment>, _ afterSegments: ContiguousArray<PackedSegment>) {
                for segment in beforeSegments where !afterSegments.contains(segment) {
                    lower = min(lower, Int(segment.startCol))
                    upper = max(upper, Int(segment.endCol))
                }
                for segment in afterSegments where !beforeSegments.contains(segment) {
                    lower = min(lower, Int(segment.startCol))
                    upper = max(upper, Int(segment.endCol))
                }
            }
            accumulate(before.base, after.base)
            accumulate(before.overlay, after.overlay)
            guard lower < upper else { continue }
            let span = NSRange(location: lineStart + lower, length: upper - lower)
            changed = changed.map { union($0, span) } ?? span
        }
        return changed
    }

    private func removeTokens(
        intersecting range: NSRange,
        lineRange: Range<Int>,
        overlayPlane: Bool,
        lineTable: HighlightLineTable,
        willTouch: (Int) -> Void
    ) {
        var line = lineRange.lowerBound
        while line < lineRange.upperBound {
            defer { line += 1 }
            guard line >= 0, line < lines.count else { continue }
            let lineStart = lineTable.lineStartOffset(at: line)
            let segments = overlayPlane ? lines[line].overlay : lines[line].base
            var removal: [Int] = []
            var index = 0
            while index < segments.count {
                let segment = segments[index]
                let location = lineStart + Int(segment.startCol)
                let upperBound = lineStart + Int(segment.endCol)
                if location < range.upperBound, upperBound > range.location {
                    removal.append(index)
                }
                index += 1
            }
            guard !removal.isEmpty else { continue }
            willTouch(line)

            // Sever chains: removed segments may continue into neighbors.
            let upSeeds = removal.filter { segments[$0].continuesFromPrevious }
            let downSeeds = removal.filter { segments[$0].continuesToNext }
            if !upSeeds.isEmpty, line > 0 {
                var styleCounts: [UInt16: Int] = [:]
                for index in upSeeds { styleCounts[segments[index].styleID, default: 0] += 1 }
                let neighborSegments = overlayPlane ? lines[line - 1].overlay : lines[line - 1].base
                var counts = styleCounts
                let matched = matchContinuations(in: neighborSegments, styles: &counts, direction: -1)
                if !matched.isEmpty {
                    touchAndDrop(from: line - 1, direction: -1, seeds: matched, overlayPlane: overlayPlane, willTouch: willTouch)
                }
            }
            if !downSeeds.isEmpty, line + 1 < lines.count {
                var styleCounts: [UInt16: Int] = [:]
                for index in downSeeds { styleCounts[segments[index].styleID, default: 0] += 1 }
                let neighborSegments = overlayPlane ? lines[line + 1].overlay : lines[line + 1].base
                var counts = styleCounts
                let matched = matchContinuations(in: neighborSegments, styles: &counts, direction: 1)
                if !matched.isEmpty {
                    touchAndDrop(from: line + 1, direction: 1, seeds: matched, overlayPlane: overlayPlane, willTouch: willTouch)
                }
            }
            removeSegments(at: removal, line: line, overlayPlane: overlayPlane)
        }
    }

    private func touchAndDrop(
        from line: Int,
        direction: Int,
        seeds: [Int],
        overlayPlane: Bool,
        willTouch: (Int) -> Void
    ) {
        var current = line
        var currentSeeds = seeds
        while lines.indices.contains(current), !currentSeeds.isEmpty {
            willTouch(current)
            let segments = overlayPlane ? lines[current].overlay : lines[current].base
            var counts = continuationStyles(segments, indices: currentSeeds, direction: direction)
            removeSegments(at: currentSeeds, line: current, overlayPlane: overlayPlane)
            let next = current + direction
            guard lines.indices.contains(next), !counts.isEmpty else { break }
            let nextSegments = overlayPlane ? lines[next].overlay : lines[next].base
            currentSeeds = matchContinuations(in: nextSegments, styles: &counts, direction: direction)
            current = next
        }
    }

    // MARK: - Insertion

    private func insert(
        tokens: [SyntaxHighlightToken],
        lineTable: HighlightLineTable,
        willTouch: (Int) -> Void = { _ in }
    ) {
        var tokenIndex = 0
        while tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            tokenIndex += 1
            guard token.range.length > 0 else { continue }
            let styleID = styles.intern(token)
            let tokenLines = lineTable.lineRange(containingUTF16Range: token.range)
            guard !tokenLines.isEmpty else { continue }
            let overlayPlane = styles[styleID].isSemanticOverlay
            var line = max(0, tokenLines.lowerBound)
            let lineLimit = min(tokenLines.upperBound, lines.count)
            var lineStart = lineTable.lineStartOffset(at: line)
            while line < lineLimit {
                let lineEnd = lineStart + lineTable.lineLength(at: line)
                let segmentStart = max(token.range.location, lineStart)
                let segmentEnd = min(token.range.upperBound, lineEnd)
                if segmentEnd > segmentStart {
                    willTouch(line)
                    var flags: UInt16 = 0
                    if line > tokenLines.lowerBound {
                        flags |= PackedSegment.continuesFromPrevious
                    }
                    if line < tokenLines.upperBound - 1, segmentEnd < token.range.upperBound {
                        flags |= PackedSegment.continuesToNext
                    }
                    let segment = PackedSegment(
                        startCol: UInt32(segmentStart - lineStart),
                        endCol: UInt32(segmentEnd - lineStart),
                        styleID: styleID,
                        flags: flags
                    )
                    if overlayPlane {
                        lines[line].overlay.append(segment)
                    } else {
                        lines[line].base.append(segment)
                    }
                }
                line += 1
                lineStart = lineEnd
            }
        }
    }

    // MARK: - Materialization (the single merge point)

    /// Materializes whole logical tokens for `range` (nil = whole document):
    /// continuation joining, cross-plane dedup by (range, rawCaptureName) with
    /// overlay winning, sorted by the legacy display order. Tokens may extend
    /// beyond the requested range.
    package func tokens(
        in range: NSRange? = nil,
        lineTable: HighlightLineTable
    ) -> [SyntaxHighlightToken] {
        guard !lines.isEmpty else { return [] }
        let lineRange: Range<Int>
        if let range {
            lineRange = lineTable.lineRange(containingUTF16Range: range)
        } else {
            lineRange = 0..<lines.count
        }
        let lower = min(max(0, lineRange.lowerBound), lines.count)
        var upper = min(max(lower, lineRange.upperBound), lines.count)
        guard lower < upper else { return [] }

        // Expand to cover whole logical tokens crossing the boundaries.
        var start = lower
        while start > 0, crossesBoundary(above: start) {
            start -= 1
        }
        while upper < lines.count, crossesBoundary(above: upper) {
            upper += 1
        }

        var results: [(range: NSRange, styleID: UInt16)] = []
        var openBase: [(start: Int, end: Int, styleID: UInt16)] = []
        var openOverlay: [(start: Int, end: Int, styleID: UInt16)] = []

        for line in start..<upper {
            let lineStart = lineTable.lineStartOffset(at: line)
            joinPlane(
                segments: lines[line].base,
                lineStart: lineStart,
                open: &openBase,
                results: &results
            )
            joinPlane(
                segments: lines[line].overlay,
                lineStart: lineStart,
                open: &openOverlay,
                results: &results
            )
        }
        for token in openBase { results.append((NSRange(location: token.start, length: token.end - token.start), token.styleID)) }
        for token in openOverlay { results.append((NSRange(location: token.start, length: token.end - token.start), token.styleID)) }

        // Cross-plane dedup: identical (range, rawCaptureName) collapses to the
        // overlay token so incremental and full passes materialize identically.
        var bestByKey: [DedupKey: Int] = [:]
        bestByKey.reserveCapacity(results.count)
        var keep = [Bool](repeating: true, count: results.count)
        for (index, entry) in results.enumerated() {
            let style = styles[entry.styleID]
            let key = DedupKey(location: entry.range.location, length: entry.range.length, name: style.rawCaptureName)
            if let existing = bestByKey[key] {
                let existingIsOverlay = styles[results[existing].styleID].isSemanticOverlay
                if style.isSemanticOverlay && !existingIsOverlay {
                    keep[existing] = false
                    bestByKey[key] = index
                } else {
                    keep[index] = false
                }
            } else {
                bestByKey[key] = index
            }
        }

        var tokens: [SyntaxHighlightToken] = []
        tokens.reserveCapacity(results.count)
        var order: [(range: NSRange, styleID: UInt16)] = []
        order.reserveCapacity(results.count)
        for (index, entry) in results.enumerated() where keep[index] {
            order.append(entry)
        }
        order.sort { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            if lhs.range.length != rhs.range.length {
                return lhs.range.length > rhs.range.length
            }
            return styles.displayOrder(of: lhs.styleID, before: rhs.styleID)
        }
        for entry in order {
            let style = styles[entry.styleID]
            tokens.append(SyntaxHighlightToken(
                range: entry.range,
                syntaxID: style.syntaxID,
                language: style.language,
                rawCaptureName: style.rawCaptureName,
                isSemanticOverlay: style.isSemanticOverlay
            ))
        }
        return tokens
    }

    private struct DedupKey: Hashable {
        let location: Int
        let length: Int
        let name: String
    }

    private func joinPlane(
        segments: ContiguousArray<PackedSegment>,
        lineStart: Int,
        open: inout [(start: Int, end: Int, styleID: UInt16)],
        results: inout [(range: NSRange, styleID: UInt16)]
    ) {
        var stillOpen: [(start: Int, end: Int, styleID: UInt16)] = []
        var consumed = [Bool](repeating: false, count: open.count)

        for segment in segments {
            let absoluteStart = lineStart + Int(segment.startCol)
            let absoluteEnd = lineStart + Int(segment.endCol)
            if segment.continuesFromPrevious {
                // Match the first unconsumed open token with the same style.
                var matched = false
                for index in open.indices where !consumed[index] && open[index].styleID == segment.styleID {
                    consumed[index] = true
                    var token = open[index]
                    token.end = absoluteEnd
                    if segment.continuesToNext {
                        stillOpen.append(token)
                    } else {
                        results.append((NSRange(location: token.start, length: token.end - token.start), token.styleID))
                    }
                    matched = true
                    break
                }
                if matched { continue }
                // Orphaned continuation (chain was severed): treat as a fresh token.
            }
            if segment.continuesToNext {
                stillOpen.append((absoluteStart, absoluteEnd, segment.styleID))
            } else {
                results.append((NSRange(location: absoluteStart, length: absoluteEnd - absoluteStart), segment.styleID))
            }
        }
        // Unconsumed opens were severed mid-chain; close them as-is.
        for index in open.indices where !consumed[index] {
            let token = open[index]
            results.append((NSRange(location: token.start, length: token.end - token.start), token.styleID))
        }
        open = stillOpen
    }

    private func crossesBoundary(above line: Int) -> Bool {
        guard line > 0, lines.indices.contains(line) else { return false }
        let prev = lines[line - 1]
        return prev.base.contains { $0.continuesToNext } || prev.overlay.contains { $0.continuesToNext }
    }

    // MARK: - Helpers

    private func ensureLineCount(_ lineCount: Int) {
        let lineCount = max(1, lineCount)
        if lines.count < lineCount {
            lines.append(contentsOf: repeatElement(Line(), count: lineCount - lines.count))
        } else if lines.count > lineCount {
            lines.removeSubrange(lineCount..<lines.count)
        }
    }

    private func sortAllLines() {
        sortLines(Set(lines.indices))
    }

    private func sortLines(_ touched: Set<Int>) {
        for index in touched where lines.indices.contains(index) {
            if lines[index].base.count > 1 {
                sortSegments(&lines[index].base)
            }
            if lines[index].overlay.count > 1 {
                sortSegments(&lines[index].overlay)
            }
        }
    }

    private func sortSegments(_ segments: inout ContiguousArray<PackedSegment>) {
        segments.sort { lhs, rhs in
            if lhs.startCol != rhs.startCol {
                return lhs.startCol < rhs.startCol
            }
            if lhs.endCol != rhs.endCol {
                return lhs.endCol > rhs.endCol
            }
            return styles.displayOrder(of: lhs.styleID, before: rhs.styleID)
        }
    }

    private func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let lower = min(lhs.location, rhs.location)
        let upper = max(lhs.upperBound, rhs.upperBound)
        return NSRange(location: lower, length: upper - lower)
    }
}
