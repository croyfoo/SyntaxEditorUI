import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// The highlighting engine: one actor per editor document.
///
/// Ground-up rebuild. The synchronous pipeline per edit is strictly edit-local:
/// tree-sitter incremental reparse, an envelope-clipped capture query, a per-line
/// base-plane patch (unedited lines shift algebraically), then the language's
/// semantic pass. Stage S1 ships every language on the conservative semantic
/// path (full-document merge per update — correct by construction); locality
/// lands per-language in later stages behind the same seam.
package actor SyntaxHighlighterEngine: SyntaxHighlighting {
    private var session: HighlightSession?
    private let registry: LanguageConfigurationRegistry
    private var visibleRangeHint: NSRange?

    package init() {
        registry = .shared
    }

    // MARK: - SyntaxHighlighting

    package func reset(source: String, language: SyntaxLanguage, revision: Int) async -> SyntaxHighlightResult {
        await reset(source: source, language: language, revision: revision, emitFastPass: nil)
    }

    package func resetPhases(
        source: String,
        language: SyntaxLanguage,
        revision: Int
    ) async -> AsyncStream<SyntaxHighlightResult> {
        AsyncStream { continuation in
            let task = Task {
                let result = await self.reset(
                    source: source,
                    language: language,
                    revision: revision,
                    emitFastPass: { continuation.yield($0) }
                )
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                continuation.yield(result)
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    package func update(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> SyntaxHighlightResult {
        await update(source: source, language: language, mutation: mutation, revision: revision, emitFastPass: nil)
    }

    package func updatePhases(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> AsyncStream<SyntaxHighlightResult> {
        AsyncStream { continuation in
            let task = Task {
                let result = await self.update(
                    source: source,
                    language: language,
                    mutation: mutation,
                    revision: revision,
                    emitFastPass: { continuation.yield($0) }
                )
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                continuation.yield(result)
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    package func setVisibleRange(_ range: NSRange?) {
        visibleRangeHint = range
        session?.visibleRangeHint = range
    }

    // MARK: - Internals

    private func reset(
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        emitFastPass: ((SyntaxHighlightResult) -> Void)?
    ) async -> SyntaxHighlightResult {
        let setup = await registry.highlightingSetup(for: language)
        guard !Task.isCancelled else {
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }
        guard let setup else {
            session = nil
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }

        // Always a fresh session: a half-built one is never installed (a cancelled
        // reset keeps the previous session usable — pinned behavior).
        let nextSession = HighlightSession(language: language, setup: setup)
        nextSession.visibleRangeHint = visibleRangeHint
        let result = nextSession.reset(source: source, revision: revision, emitFastPass: emitFastPass)
        guard !Task.isCancelled, let result else {
            return SyntaxHighlightResult(
                tokens: [],
                source: source,
                language: language,
                revision: revision,
                refreshRange: NSRange(location: 0, length: source.utf16.count)
            )
        }
        session = nextSession
        return result
    }

    private func update(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int,
        emitFastPass: ((SyntaxHighlightResult) -> Void)?
    ) async -> SyntaxHighlightResult {
        if let session,
           let result = session.update(
               source: source,
               language: language,
               mutation: mutation,
               revision: revision,
               emitFastPass: emitFastPass
           ) {
            return result
        }
        return await reset(source: source, language: language, revision: revision, emitFastPass: emitFastPass)
    }

    package func render(source: String, language: SyntaxLanguage) async -> [SyntaxHighlightToken] {
        await reset(source: source, language: language, revision: 0).tokens
    }

    package func currentTokensForTesting() -> [SyntaxHighlightToken] {
        session?.currentTokens() ?? []
    }
}

/// Per-document highlighting state. Confined to the engine actor; all methods
/// are synchronous (no suspension points inside an update).
final class HighlightSession {
    let setup: HighlightingSetup
    let language: SyntaxLanguage
    var visibleRangeHint: NSRange?

    private var source = ""
    private var layeredSource = ""
    /// UTF-16 image of `layeredSource` for zero-copy parser reads; kept in
    /// sync at every commit point (reset, committed update).
    private let sourceBuffer = UTF16SourceBuffer()
    private var layer: LanguageLayer?
    private let styleTable = HighlightStyleTable()
    private let lineTable = HighlightLineTable()
    private let planes: LineTokenPlanes
    private var semanticPass: SemanticPass?
    /// Committed-but-undelivered refresh obligations (results dropped by
    /// cancellation); unioned into the next emitted result.
    private var refreshDebt = EditedRangeSet()

    init(language: SyntaxLanguage, setup: HighlightingSetup) {
        self.language = language
        self.setup = setup
        planes = LineTokenPlanes(styles: styleTable)
        semanticPass = SemanticPassFactory.make(language: language)
    }

    func currentTokens() -> [SyntaxHighlightToken] {
        planes.tokens(lineTable: lineTable)
    }

    // MARK: - Reset

    /// Full highlight of `source`. Returns nil when cancelled before completion
    /// (the engine then refuses to install this session).
    func reset(
        source: String,
        revision: Int,
        emitFastPass: ((SyntaxHighlightResult) -> Void)?
    ) -> SyntaxHighlightResult? {
        self.source = source
        layeredSource = SyntacticPatcher.layeredSource(for: source, setup: setup)
        sourceBuffer.reset(layeredSource)
        lineTable.reset(source: layeredSource)
        semanticPass?.invalidate()
        refreshDebt.clear()

        guard !layeredSource.isEmpty else {
            layer = nil
            planes.clear(lineCount: lineTable.lineCount)
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }

        do {
            let nextLayer = try SyntacticPatcher.makeLayer(setup: setup)
            guard let fullEdit = SyntacticPatcher.fullReplacementInputEdit(for: layeredSource) else {
                layer = nil
                planes.clear(lineCount: lineTable.lineCount)
                return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
            }
            _ = nextLayer.didChangeContent(
                SyntacticPatcher.layerContent(buffer: sourceBuffer, source: layeredSource),
                using: fullEdit,
                resolveSublayers: true
            )
            layer = nextLayer

            let fullRange = NSRange(location: 0, length: layeredSource.utf16.count)
            let baseTokens = SyntacticPatcher.highlightTokens(
                in: fullRange,
                layer: nextLayer,
                source: layeredSource,
                language: language,
                clipTo: nil
            )
            planes.reset(tokens: baseTokens, lineTable: lineTable)

            emitFastPassIfNeeded(
                tokens: baseTokens,
                source: source,
                revision: revision,
                refreshRange: NSRange(location: 0, length: source.utf16.count),
                tokenPayload: .fullSnapshot,
                emitFastPass: emitFastPass
            )

            if let semanticPass {
                let outcome = semanticPass.fullMerge(
                    tokens: baseTokens,
                    source: layeredSource,
                    rootNode: semanticRootNodeSnapshot()
                )
                guard !outcome.isCancelled, !Task.isCancelled else {
                    layer = nil
                    self.semanticPass?.invalidate()
                    planes.clear(lineCount: lineTable.lineCount)
                    return nil
                }
                planes.reset(tokens: outcome.tokens, lineTable: lineTable)
            } else if Task.isCancelled {
                layer = nil
                planes.clear(lineCount: lineTable.lineCount)
                return nil
            }
        } catch {
            layer = nil
            planes.clear(lineCount: lineTable.lineCount)
        }

        return SyntaxHighlightResult(
            tokens: planes.tokens(lineTable: lineTable),
            source: source,
            language: language,
            revision: revision,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }

    // MARK: - Update

    /// Incremental update. Returns nil when preconditions fail; the engine then
    /// falls back to a full reset.
    func update(
        source nextSource: String,
        language nextLanguage: SyntaxLanguage,
        mutation originalMutation: SyntaxHighlightMutation,
        revision: Int,
        emitFastPass: ((SyntaxHighlightResult) -> Void)?
    ) -> SyntaxHighlightResult? {
        guard nextLanguage == language, let layer else {
            return nil
        }

        // Mutation validation: cheap probes (length consistency, replacement
        // match, boundary windows); a mismatch coalesces via full diff — the
        // legacy recovery behavior without its per-keystroke O(N) compares.
        let effectiveMutation: SyntaxHighlightMutation
        switch SyntacticPatcher.validateMutation(originalMutation, previousSource: source, nextSource: nextSource) {
        case .valid:
            effectiveMutation = originalMutation
        case .mismatch:
            guard let coalesced = TextMutation.diff(from: source, to: nextSource) else {
                return nil
            }
            effectiveMutation = SyntaxHighlightMutation(coalesced)
        }

        let nextLayeredSource = SyntacticPatcher.layeredSource(for: nextSource, setup: setup)
        let layeredMutation: SyntaxHighlightMutation
        if setup.usesHTMLPreprocessing {
            guard let masked = TextMutation.diff(from: layeredSource, to: nextLayeredSource) else {
                return nil
            }
            layeredMutation = SyntaxHighlightMutation(masked)
        } else {
            layeredMutation = effectiveMutation
        }

        if setup.supportsLayeredHighlighting,
           SyntacticPatcher.mutationTouchesMarkupBoundary(
               mutation: layeredMutation,
               previousSource: layeredSource,
               nextSource: nextLayeredSource
           ) {
            // Injection-boundary edits re-resolve sublayers via a full reset.
            return nil
        }

        let previousLayeredSource = layeredSource
        guard let inputEdit = SyntacticPatcher.inputEdit(
            mutation: layeredMutation,
            previousSource: previousLayeredSource,
            nextSource: nextLayeredSource,
            lineTable: lineTable
        ) else {
            return nil
        }

        guard !Task.isCancelled else {
            return cancelledResult(revision: revision)
        }

        // ---- Critical section: the invalidation set is a one-shot product of
        // this reparse; no cancellation or nil-return until the base plane,
        // line table, and session sources are committed together. ----
        sourceBuffer.apply(mutation: layeredMutation)
        let invalidated = layer.didChangeContent(
            SyntacticPatcher.layerContent(buffer: sourceBuffer, source: nextLayeredSource),
            using: inputEdit,
            resolveSublayers: setup.supportsLayeredHighlighting
        )
        let nextLength = nextLayeredSource.utf16.count
        let envelope = SyntacticPatcher.patchEnvelope(
            invalidated: invalidated,
            mutation: layeredMutation,
            source: nextLayeredSource,
            sourceUTF16Length: nextLength
        )
        let replacementTokens = SyntacticPatcher.highlightTokens(
            in: envelope,
            layer: layer,
            source: nextLayeredSource,
            language: language,
            clipTo: envelope
        )

        let editResult = planes.applyEdit(
            layeredMutation,
            previousSource: previousLayeredSource,
            lineTable: lineTable
        )
        lineTable.apply(mutation: layeredMutation, previousSource: previousLayeredSource)
        let baseChanged = planes.replaceTokens(
            in: envelope,
            with: replacementTokens,
            plane: .base,
            lineTable: lineTable
        )
        source = nextSource
        layeredSource = nextLayeredSource
        refreshDebt.splice(
            location: layeredMutation.location,
            oldLength: layeredMutation.length,
            newLength: layeredMutation.replacement.utf16.count,
            documentLength: nextLength
        )
        // ---- End critical section. ----

        // The edited extent itself always refreshes (replacement + one unit so a
        // pure deletion still repaints the join point) — but NOT the whole line:
        // sub-line refresh ranges are pinned by the test suite.
        let editedExtent = SyntaxEditorRangeUtilities.clampedRange(
            NSRange(
                location: layeredMutation.location,
                length: max(1, layeredMutation.replacement.utf16.count + 1)
            ),
            utf16Length: nextLength
        )
        var syntacticRefresh = baseChanged.map { SyntacticPatcher.union($0, editedExtent) }
            ?? editedExtent
        if let dropped = editResult.droppedLines,
           let droppedRange = wholeLineRange(ofLines: dropped, sourceUTF16Length: nextLength) {
            syntacticRefresh = SyntacticPatcher.union(syntacticRefresh, droppedRange)
        }
        if !refreshDebt.isEmpty {
            for range in refreshDebt.ranges.rangeView {
                syntacticRefresh = SyntacticPatcher.union(
                    syntacticRefresh,
                    NSRange(location: range.lowerBound, length: range.count)
                )
            }
            refreshDebt.clear()
        }
        syntacticRefresh = SyntaxEditorRangeUtilities.clampedRange(syntacticRefresh, utf16Length: nextLength)

        emitFastPassIfNeeded(
            tokens: planes.tokens(in: syntacticRefresh, lineTable: lineTable),
            source: nextSource,
            revision: revision,
            refreshRange: syntacticRefresh,
            tokenPayload: .replacement,
            emitFastPass: emitFastPass
        )

        var resultRefresh = syntacticRefresh
        if let semanticPass {
            let rootNode = semanticRootNodeSnapshot()
            let planEnvelope = SyntacticPatcher.lineEnvelope(
                containing: SyntacticPatcher.union(syntacticRefresh, envelope),
                source: nextLayeredSource
            )
            var runConservative = true
            if let plan = semanticPass.plannedUpdate(
                mutation: layeredMutation,
                envelope: planEnvelope,
                source: nextLayeredSource,
                rootNode: rootNode
            ) {
                switch plan {
                case .full:
                    runConservative = true
                case .reuse, .targets:
                    var targets: [NSRange] = [planEnvelope]
                    if case .targets(let bounded) = plan {
                        targets.append(contentsOf: bounded.map {
                            SyntacticPatcher.lineEnvelope(
                                containing: SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: nextLength),
                                source: nextLayeredSource
                            )
                        })
                    }
                    let merged = Self.mergedRanges(targets)
                    let totalLength = merged.reduce(0) { $0 + $1.length }
                    if totalLength * 2 > nextLength {
                        // Fan-out exceeds half the document: the full merge is cheaper
                        // and strictly more complete.
                        runConservative = true
                    } else {
                        runConservative = false
                        var cancelled = false
                        for target in merged {
                            if Task.isCancelled {
                                cancelled = true
                                break
                            }
                            let baseTokens = planes.tokens(in: target, lineTable: lineTable)
                                .filter { !$0.isSemanticOverlay }
                            let overlays = semanticPass.overlayTokens(
                                in: target,
                                baseTokens: baseTokens,
                                source: nextLayeredSource
                            )
                            if let diff = planes.replaceTokens(
                                in: target,
                                with: overlays,
                                plane: .overlay,
                                lineTable: lineTable
                            ) {
                                resultRefresh = SyntacticPatcher.union(resultRefresh, diff)
                            }
                        }
                        if cancelled {
                            semanticPass.invalidate()
                            refreshDebt.insert(resultRefresh)
                        }
                    }
                }
            }
            if runConservative {
                // Passes receive base-plane tokens only and re-derive every overlay:
                // feeding stale overlays back in tripped the ObjC provider's
                // preservation heuristics into keeping shifted leftovers.
                let merged = semanticPass.fullMerge(
                    tokens: planes.tokens(lineTable: lineTable).filter { !$0.isSemanticOverlay },
                    source: nextLayeredSource,
                    rootNode: rootNode
                )
                if merged.isCancelled || Task.isCancelled {
                    semanticPass.invalidate()
                    refreshDebt.insert(resultRefresh)
                } else {
                    let fullRange = NSRange(location: 0, length: nextLength)
                    if let semanticChanged = planes.replaceTokens(
                        in: fullRange,
                        with: merged.tokens,
                        plane: .both,
                        lineTable: lineTable
                    ) {
                        resultRefresh = SyntacticPatcher.union(resultRefresh, semanticChanged)
                    }
                }
            }
        }
        resultRefresh = SyntaxEditorRangeUtilities.clampedRange(resultRefresh, utf16Length: nextSource.utf16.count)

        return SyntaxHighlightResult(
            tokens: resultTokens(
                from: planes.tokens(in: resultRefresh, lineTable: lineTable),
                refreshRange: resultRefresh,
                tokenPayload: .replacement
            ),
            source: nextSource,
            language: language,
            revision: revision,
            refreshRange: resultRefresh,
            tokenPayload: .replacement
        )
    }

    // MARK: - Helpers


    /// Sorts and merges overlapping/adjacent ranges.
    static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        guard ranges.count > 1 else { return ranges.filter { $0.length > 0 } }
        let sorted = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in sorted {
            if let last = merged.last, range.location <= last.upperBound {
                merged[merged.count - 1] = NSRange(
                    location: last.location,
                    length: max(last.upperBound, range.upperBound) - last.location
                )
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private func semanticRootNodeSnapshot() -> Node? {
        guard language == .swift || language == .objectiveC else { return nil }
        return layer?.snapshot()?.rootSnapshot.tree.rootNode
    }

    private var usesDeferredSemanticHighlighting: Bool {
        language == .swift || language == .objectiveC
    }

    private func emitFastPassIfNeeded(
        tokens: [SyntaxHighlightToken],
        source: String,
        revision: Int,
        refreshRange: NSRange,
        tokenPayload: SyntaxHighlightTokenPayload,
        emitFastPass: ((SyntaxHighlightResult) -> Void)?
    ) {
        guard usesDeferredSemanticHighlighting, let emitFastPass else { return }
        emitFastPass(
            SyntaxHighlightResult(
                tokens: resultTokens(from: tokens, refreshRange: refreshRange, tokenPayload: tokenPayload),
                source: source,
                language: language,
                revision: revision,
                refreshRange: refreshRange,
                phase: .syntacticFastPass,
                tokenPayload: tokenPayload
            )
        )
    }

    private func resultTokens(
        from tokens: [SyntaxHighlightToken],
        refreshRange: NSRange,
        tokenPayload: SyntaxHighlightTokenPayload
    ) -> [SyntaxHighlightToken] {
        switch tokenPayload {
        case .fullSnapshot:
            return tokens
        case .replacement:
            return tokens.filter {
                $0.range.location < refreshRange.upperBound && $0.range.upperBound > refreshRange.location
            }
        }
    }

    /// Cancelled results are dropped before the phase streams yield them; carry
    /// no tokens and a no-op refresh range (never materialize the store here).
    private func cancelledResult(revision: Int) -> SyntaxHighlightResult {
        SyntaxHighlightResult(
            tokens: [],
            source: source,
            language: language,
            revision: revision,
            refreshRange: NSRange(location: 0, length: 0),
            tokenPayload: .replacement
        )
    }

    private func wholeLineRange(ofLines lines: Range<Int>, sourceUTF16Length: Int) -> NSRange? {
        guard !lines.isEmpty else { return nil }
        let lower = lineTable.lineStartOffset(at: max(0, lines.lowerBound))
        let upperLine = min(lines.upperBound, lineTable.lineCount) - 1
        guard upperLine >= 0 else { return nil }
        let upper = min(max(lower, lineTable.lineEndOffset(at: upperLine)), sourceUTF16Length)
        return NSRange(location: min(lower, sourceUTF16Length), length: max(0, upper - min(lower, sourceUTF16Length)))
    }
}
