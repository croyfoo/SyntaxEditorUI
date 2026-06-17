import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// Syntactic-layer plumbing for the highlighting session: layer construction,
/// content readers, input edits, envelope computation, capture queries with
/// envelope clipping, and mutation validation. Mechanical helpers are ported
/// verbatim from the previous engine; the two NEW behaviors are documented at
/// `patchEnvelope` and `validateMutation`.
enum SyntacticPatcher {
    static func layeredSource(for source: String, setup: HighlightingSetup) -> String {
        setup.usesHTMLPreprocessing
            ? HTMLLanguage.sourceByMaskingUnsupportedEmbeddedContent(source)
            : source
    }

    /// The patch envelope for an edit: the union of the parse invalidation set
    /// and the mutation's replacement extent, expanded to whole lines. The set
    /// is edit-local in steady state (tree-sitter changedRanges ∪ edited range);
    /// transient restructurings (unbalanced braces) legitimately widen it.
    static func patchEnvelope(
        invalidated: IndexSet,
        mutation: SyntaxEditorTextChange.Replacement,
        source: String,
        sourceUTF16Length: Int
    ) -> NSRange {
        let queryRange = SyntaxEditorHighlighting.Invalidation.queryRange(
            invalidatedSet: invalidated,
            mutation: mutation,
            sourceUTF16Length: sourceUTF16Length
        )
        let replacementLength = mutation.replacement.utf16.count
        let materialization = NSRange(
            location: min(max(0, mutation.location), sourceUTF16Length),
            length: 0
        )
        let editEnvelope = NSRange(
            location: materialization.location,
            length: min(sourceUTF16Length - materialization.location, max(1, replacementLength + 1))
        )
        return lineEnvelopeRange(containing: union(queryRange, editEnvelope), source: source)
    }

    static func lineEnvelope(containing range: NSRange, source: String) -> NSRange {
        lineEnvelopeRange(containing: range, source: source)
    }

    /// Capture query with envelope clipping. Query patterns rooted at large
    /// container nodes (source_file/class_body property patterns) defeat
    /// tree-sitter's byte-range restriction and return matches across the whole
    /// document; tokens that do not intersect `clipTo` are unchanged by this
    /// edit (the invalidation set covers every structural change) and are
    /// dropped instead of widening the patch.
    static func highlightTokens(
        in range: NSRange,
        layer: LanguageLayer,
        source: String,
        language: SyntaxLanguage,
        clipTo: NSRange?
    ) -> [SyntaxEditorHighlighting.Token] {
        guard range.length > 0 else { return [] }
        do {
            let sourceUTF16Length = source.utf16.count
            var tokens: [SyntaxEditorHighlighting.Token] = []
            for namedRange in try layer.highlights(in: range, provider: source.predicateTextProvider) {
                guard let tokenRange = Self.utf16Range(
                    fromByteRange: namedRange.tsRange.bytes,
                    sourceUTF16Length: sourceUTF16Length
                ), tokenRange.length > 0 else {
                    continue
                }
                if let clipTo,
                   !(tokenRange.location < clipTo.upperBound && tokenRange.upperBound > clipTo.location) {
                    continue
                }
                let classification = EditorSourceSyntax.Capture.parse(
                    rawCaptureName: namedRange.name,
                    rootLanguage: language
                )
                tokens.append(SyntaxEditorHighlighting.Token(
                    range: tokenRange,
                    syntaxID: classification.syntaxID,
                    language: classification.language ?? language,
                    rawCaptureName: namedRange.name
                ))
            }
            return tokens.sorted(by: SyntaxHighlightTokenOrdering.displayOrder)
        } catch {
            return []
        }
    }

    enum MutationValidation {
        case valid
        case mismatch
    }

    /// Exact mutation validation: `previous` spliced with the mutation must
    /// equal `next`. Boundary-window probes were tried here and are not sound —
    /// a session that silently missed an earlier length-neutral edit farther
    /// than the window still passed, and the parser buffer, line table, and
    /// token planes then drifted from the document with no recovery signal.
    /// The splice costs one buffer copy and a memcmp-class compare (~0.1ms at
    /// 478KB), and mismatches keep falling back to the full-diff recovery.
    static func validateMutation(
        _ mutation: SyntaxEditorTextChange.Replacement,
        previousSource: String,
        nextSource: String
    ) -> MutationValidation {
        let previous = previousSource as NSString
        let next = nextSource as NSString
        let replacementLength = mutation.replacement.utf16.count
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location + mutation.length <= previous.length,
              next.length == previous.length - mutation.length + replacementLength
        else {
            return .mismatch
        }
        let expected = previous.replacingCharacters(
            in: NSRange(location: mutation.location, length: mutation.length),
            with: mutation.replacement
        )
        return next.isEqual(to: expected) ? .valid : .mismatch
    }

    static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let lower = min(lhs.location, rhs.location)
        let upper = max(lhs.upperBound, rhs.upperBound)
        return NSRange(location: lower, length: upper - lower)
    }

    static func makeLayer(setup: HighlightingSetup) throws -> LanguageLayer {
        let layerConfiguration = LanguageLayer.Configuration(
            maximumLanguageDepth: setup.supportsLayeredHighlighting ? 4 : 0,
            languageProvider: { [provider = setup.injectedLanguageProvider] name in
                provider.configuration(named: name)
            }
        )
        return try LanguageLayer(
            languageConfig: setup.rootConfiguration,
            configuration: layerConfiguration
        )
    }

    static func lineEnvelopeRange(containing range: NSRange, source: String) -> NSRange {
        let nsSource = source as NSString
        guard nsSource.length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: nsSource.length)
        if clampedRange.length > 0 {
            return nsSource.lineRange(for: clampedRange)
        }

        let location = min(clampedRange.location, nsSource.length - 1)
        return nsSource.lineRange(for: NSRange(location: location, length: 0))
    }

    static func inputEdit(
        mutation: SyntaxEditorTextChange.Replacement,
        previousSource: String,
        nextSource: String,
        lineTable: HighlightLineTable
    ) -> InputEdit? {
        let previousLength = previousSource.utf16.count
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location <= previousLength,
              mutation.location + mutation.length <= previousLength else {
            return nil
        }

        let replacementLength = mutation.replacement.utf16.count
        let oldEnd = mutation.location + mutation.length
        let newEnd = mutation.location + replacementLength

        guard oldEnd <= previousLength,
              newEnd <= nextSource.utf16.count,
              mutation.location <= Int(UInt32.max / 2),
              oldEnd <= Int(UInt32.max / 2),
              newEnd <= Int(UInt32.max / 2) else {
            return nil
        }

        return InputEdit(
            startByte: mutation.location * 2,
            oldEndByte: oldEnd * 2,
            newEndByte: newEnd * 2,
            startPoint: lineTable.point(at: mutation.location),
            oldEndPoint: lineTable.point(at: oldEnd),
            newEndPoint: Self.advancedPoint(
                from: lineTable.point(at: mutation.location),
                by: mutation.replacement
            )
        )
    }

    static func fullReplacementInputEdit(for source: String) -> InputEdit? {
        let length = source.utf16.count
        guard length <= Int(UInt32.max / 2) else {
            return nil
        }
        return InputEdit(
            startByte: 0,
            oldEndByte: 0,
            newEndByte: length * 2,
            startPoint: .zero,
            oldEndPoint: .zero,
            newEndPoint: advancedPoint(from: .zero, by: source)
        )
    }

    /// Layer content over the session's UTF-16 buffer (zero-copy parser reads);
    /// `source` must be the same text, used only for predicate evaluation.
    static func layerContent(buffer: UTF16SourceBuffer, source: String) -> LanguageLayer.Content {
        LanguageLayer.Content(
            readHandler: buffer.readBlock(),
            textProvider: source.predicateTextProvider
        )
    }

    static func mutationTouchesMarkupBoundary(
        mutation: SyntaxEditorTextChange.Replacement,
        previousSource: String,
        nextSource: String
    ) -> Bool {
        let sourceLength = previousSource.utf16.count
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location + mutation.length <= sourceLength else {
            return true
        }

        let changedText = (previousSource as NSString).substring(
            with: NSRange(location: mutation.location, length: mutation.length)
        )
        return changedText.contains("<") ||
            changedText.contains(">") ||
            mutation.replacement.contains("<") ||
            mutation.replacement.contains(">") ||
            isInsideMarkupTag(in: previousSource, at: mutation.location) ||
            isInsideMarkupTag(in: previousSource, at: mutation.location + mutation.length) ||
            isInsideMarkupTag(in: nextSource, at: mutation.location) ||
            isInsideMarkupTag(in: nextSource, at: mutation.location + mutation.replacement.utf16.count)
    }

    static func isInsideMarkupTag(in source: String, at utf16Offset: Int) -> Bool {
        let nsSource = source as NSString
        let location = min(max(0, utf16Offset), nsSource.length)
        let prefixRange = NSRange(location: 0, length: location)
        let previousOpen = nsSource.range(
            of: "<",
            options: [.backwards],
            range: prefixRange
        )
        guard previousOpen.location != NSNotFound else {
            return false
        }

        let previousClose = nsSource.range(
            of: ">",
            options: [.backwards],
            range: prefixRange
        )
        guard previousClose.location == NSNotFound || previousOpen.location > previousClose.location else {
            return false
        }

        let suffixRange = NSRange(location: location, length: nsSource.length - location)
        let nextClose = nsSource.range(of: ">", options: [], range: suffixRange)
        guard nextClose.location != NSNotFound else {
            return false
        }

        let nextOpen = nsSource.range(of: "<", options: [], range: suffixRange)
        return nextOpen.location == NSNotFound || nextClose.location < nextOpen.location
    }

    static func advancedPoint(from point: Point, by source: String) -> Point {
        var row = point.row
        var column = point.column

        for character in source {
            if LineOffsetTable.isLineBreak(character) {
                row += 1
                column = 0
            } else {
                column += UInt32(character.utf16.count * 2)
            }
        }

        return Point(row: row, column: column)
    }

    static func utf16Range(
        fromByteRange byteRange: Range<UInt32>,
        sourceUTF16Length: Int
    ) -> NSRange? {
        guard byteRange.lowerBound % 2 == 0, byteRange.upperBound % 2 == 0 else {
            return nil
        }

        let start = Int(byteRange.lowerBound / 2)
        let end = Int(byteRange.upperBound / 2)
        guard start <= end, end <= sourceUTF16Length else {
            return nil
        }

        return NSRange(location: start, length: end - start)
    }
}
