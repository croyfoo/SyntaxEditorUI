import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

package struct SyntaxHighlightToken: Equatable, Sendable {
    package let range: NSRange
    package let syntaxID: EditorSourceSyntaxID
    package let language: SyntaxLanguage?
    package let rawCaptureName: String

    package init(
        range: NSRange,
        rawCaptureName: String,
        language: SyntaxLanguage = .swift
    ) {
        let classification = EditorSyntaxCapture.parse(
            rawCaptureName: rawCaptureName,
            rootLanguage: language
        )
        self.init(
            range: range,
            syntaxID: classification.syntaxID,
            language: classification.language ?? language,
            rawCaptureName: rawCaptureName
        )
    }

    package init(
        range: NSRange,
        syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage?,
        rawCaptureName: String
    ) {
        self.range = range
        self.syntaxID = syntaxID
        self.language = language
        self.rawCaptureName = rawCaptureName
    }
}

package struct SyntaxHighlightMutation: Equatable, Sendable {
    package let location: Int
    package let length: Int
    package let replacement: String

    package init(location: Int, length: Int, replacement: String) {
        self.location = location
        self.length = length
        self.replacement = replacement
    }

    package init(_ mutation: TextMutation) {
        self.init(
            location: mutation.range.location,
            length: mutation.range.length,
            replacement: mutation.replacement
        )
    }
}

private struct SyntaxHighlightTokenKey: Hashable {
    let location: Int
    let length: Int
    let syntaxID: EditorSourceSyntaxID
    let language: SyntaxLanguage?
    let rawCaptureName: String

    init(_ token: SyntaxHighlightToken) {
        location = token.range.location
        length = token.range.length
        syntaxID = token.syntaxID
        language = token.language
        rawCaptureName = token.rawCaptureName
    }
}

private struct SemanticClassificationResult {
    let tokens: [SyntaxHighlightToken]
    let refreshRangeOverride: NSRange?
    let isCancelled: Bool
}

package enum SyntaxHighlightPhase: Equatable, Sendable {
    case syntacticFastPass
    case complete
}

package struct SyntaxHighlightResult: Sendable {
    package let tokens: [SyntaxHighlightToken]
    package let source: String
    package let language: SyntaxLanguage
    package let revision: Int
    package let refreshRange: NSRange
    package let phase: SyntaxHighlightPhase

    package init(
        tokens: [SyntaxHighlightToken],
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        refreshRange: NSRange,
        phase: SyntaxHighlightPhase = .complete
    ) {
        self.tokens = tokens
        self.source = source
        self.language = language
        self.revision = revision
        self.refreshRange = refreshRange
        self.phase = phase
    }
}

package enum SyntaxHighlightInvalidation {
    // SwiftTreeSitter's LanguageLayer converts Tree-sitter byte ranges through
    // Range<UInt32>.range before returning an IndexSet, so these ranges are
    // already in NSRange/UTF-16 coordinates.
    package static func queryRange(
        invalidatedSet: IndexSet,
        mutation: SyntaxHighlightMutation,
        sourceUTF16Length: Int
    ) -> NSRange {
        let replacementLength = mutation.replacement.utf16.count
        var lower = min(max(0, mutation.location), sourceUTF16Length)
        var upper = min(max(lower, mutation.location + replacementLength), sourceUTF16Length)

        for range in invalidatedSet.rangeView {
            lower = min(lower, max(0, min(range.lowerBound, sourceUTF16Length)))
            upper = max(upper, max(0, min(range.upperBound, sourceUTF16Length)))
        }

        if lower == upper, sourceUTF16Length > 0 {
            if upper < sourceUTF16Length {
                upper += 1
            } else {
                lower -= 1
            }
        }

        return NSRange(location: lower, length: upper - lower)
    }
}

package protocol SyntaxHighlighting: Sendable {
    func reset(source: String, language: SyntaxLanguage, revision: Int) async -> SyntaxHighlightResult
    func resetPhases(
        source: String,
        language: SyntaxLanguage,
        revision: Int
    ) async -> AsyncStream<SyntaxHighlightResult>
    func update(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> SyntaxHighlightResult
    func updatePhases(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> AsyncStream<SyntaxHighlightResult>
}

package extension SyntaxHighlighting {
    func resetPhases(
        source: String,
        language: SyntaxLanguage,
        revision: Int
    ) async -> AsyncStream<SyntaxHighlightResult> {
        AsyncStream { continuation in
            let task = Task {
                let result = await reset(source: source, language: language, revision: revision)
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

    func updatePhases(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> AsyncStream<SyntaxHighlightResult> {
        AsyncStream { continuation in
            let task = Task {
                let result = await update(
                    source: source,
                    language: language,
                    mutation: mutation,
                    revision: revision
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
}

package actor SyntaxHighlighterEngine: SyntaxHighlighting {
    private var session: SyntaxHighlightSession?
    private let registry: LanguageConfigurationRegistry

    package init() {
        self.registry = .shared
    }

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

    private func reset(
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        emitFastPass: ((SyntaxHighlightResult) -> Void)?
    ) async -> SyntaxHighlightResult {
        guard let setup = await registry.highlightingSetup(for: language) else {
            session = nil
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }

        let nextSession = SyntaxHighlightSession(language: language, setup: setup)
        let result = nextSession.reset(source: source, revision: revision, emitFastPass: emitFastPass)
        session = nextSession
        return result
    }

    package func update(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> SyntaxHighlightResult {
        await update(
            source: source,
            language: language,
            mutation: mutation,
            revision: revision,
            emitFastPass: nil
        )
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
}

private struct HighlightingSetup: Sendable {
    let rootConfiguration: LanguageConfiguration
    let injectedLanguageProvider: InjectedLanguageProvider
    let supportsLayeredHighlighting: Bool
    let usesHTMLPreprocessing: Bool
}

private extension HighlightingSetup {
    static func resolved(
        for language: SyntaxLanguage,
        resolver: LanguageConfigurationResolver = .shared
    ) -> HighlightingSetup? {
        guard let rootConfiguration = resolver.configuration(for: language) else {
            return nil
        }

        let support = language.treeSitterSupport
        let injectedAliases = resolver.supportedInjectedAliases(
            for: support,
            rootConfiguration: rootConfiguration
        )
        let injectedLanguageProvider = InjectedLanguageProvider(resolver: resolver)

        if let injectedAliases {
            for alias in injectedAliases {
                guard injectedLanguageProvider.configuration(named: alias) != nil else {
                    return HighlightingSetup(
                        rootConfiguration: rootConfiguration,
                        injectedLanguageProvider: injectedLanguageProvider,
                        supportsLayeredHighlighting: false,
                        usesHTMLPreprocessing: false
                    )
                }
            }
        }

        return HighlightingSetup(
            rootConfiguration: rootConfiguration,
            injectedLanguageProvider: injectedLanguageProvider,
            supportsLayeredHighlighting: injectedAliases?.isEmpty == false,
            usesHTMLPreprocessing: resolver.supportsHTMLRawTextPreprocessing(for: rootConfiguration.language)
        )
    }
}

private enum CachedLanguageConfiguration {
    case resolved(LanguageConfiguration)
    case missing
}

private final class SyntaxHighlightSession {
    private let setup: HighlightingSetup
    private(set) var language: SyntaxLanguage
    private var source = ""
    private var layeredSource = ""
    private var layer: LanguageLayer?
    private let lineIndex = SyntaxHighlightLineIndex()
    private var tokens: [SyntaxHighlightToken] = []
    private var swiftSemanticState: SwiftSemanticOverlayState?
    private var objectiveCSemanticState: ObjectiveCSemanticOverlayState?

    init(language: SyntaxLanguage, setup: HighlightingSetup) {
        self.language = language
        self.setup = setup
    }

    func reset(
        source: String,
        revision: Int,
        emitFastPass: ((SyntaxHighlightResult) -> Void)? = nil
    ) -> SyntaxHighlightResult {
        self.source = source
        layeredSource = layeredSource(for: source)
        lineIndex.reset(source: layeredSource)
        swiftSemanticState = nil
        objectiveCSemanticState = nil

        guard !layeredSource.isEmpty else {
            layer = nil
            tokens = []
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }

        do {
            let layer = try makeLayer()
            guard let fullEdit = Self.fullReplacementInputEdit(for: layeredSource) else {
                self.layer = nil
                tokens = []
                return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
            }
            _ = layer.didChangeContent(
                Self.layerContent(for: layeredSource),
                using: fullEdit,
                resolveSublayers: true
            )
            self.layer = layer
            let highlightTokens = highlightTokens(in: fullRange(for: layeredSource), source: layeredSource)
            emitSyntacticFastPassIfNeeded(
                tokens: highlightTokens,
                source: source,
                revision: revision,
                refreshRange: fullRange(for: source),
                emitFastPass: emitFastPass
            )
            let semanticResult = semanticClassifiedTokensIfNeeded(
                highlightTokens,
                source: layeredSource,
                rootNode: semanticRootNodeSnapshot()
            )
            guard !semanticResult.isCancelled, !Task.isCancelled else {
                self.layer = nil
                swiftSemanticState = nil
                objectiveCSemanticState = nil
                tokens = []
                return SyntaxHighlightResult(
                    tokens: [],
                    source: source,
                    language: language,
                    revision: revision,
                    refreshRange: fullRange(for: source)
                )
            }
            let classifiedTokens = semanticResult.tokens

            tokens = classifiedTokens
        } catch {
            layer = nil
            tokens = []
        }

        return SyntaxHighlightResult(
            tokens: tokens,
            source: source,
            language: language,
            revision: revision,
            refreshRange: fullRange(for: source)
        )
    }

    func update(
        source nextSource: String,
        language nextLanguage: SyntaxLanguage,
        mutation originalMutation: SyntaxHighlightMutation,
        revision: Int,
        emitFastPass: ((SyntaxHighlightResult) -> Void)? = nil
    ) -> SyntaxHighlightResult? {
        guard nextLanguage == language else {
            return nil
        }

        guard let layer else {
            return nil
        }

        let effectiveOriginalMutation: SyntaxHighlightMutation
        if Self.mutationMatchesSourceTransition(
            originalMutation,
            previousSource: source,
            nextSource: nextSource
        ) {
            effectiveOriginalMutation = originalMutation
        } else if let coalescedMutation = TextMutation.diff(from: source, to: nextSource) {
            effectiveOriginalMutation = SyntaxHighlightMutation(coalescedMutation)
        } else {
            return nil
        }

        let nextLayeredSource = layeredSource(for: nextSource)
        let layeredMutation: SyntaxHighlightMutation
        if setup.usesHTMLPreprocessing {
            guard let mutation = TextMutation.diff(from: layeredSource, to: nextLayeredSource) else {
                source = nextSource
                layeredSource = nextLayeredSource
                return SyntaxHighlightResult(
                    tokens: tokens,
                    source: nextSource,
                    language: language,
                    revision: revision,
                    refreshRange: refreshRange(
                        in: nextSource,
                        from: effectiveOriginalMutation.location
                    )
                )
            }
            layeredMutation = SyntaxHighlightMutation(mutation)
        } else {
            layeredMutation = effectiveOriginalMutation
        }

        if setup.supportsLayeredHighlighting,
           Self.mutationTouchesMarkupBoundary(
               mutation: layeredMutation,
               previousSource: layeredSource,
               nextSource: nextLayeredSource
           ) {
            return nil
        }

        let previousLayeredSource = layeredSource
        guard let inputEdit = Self.inputEdit(
            mutation: layeredMutation,
            previousSource: previousLayeredSource,
            nextSource: nextLayeredSource,
            lineIndex: lineIndex
        ) else {
            return nil
        }

        guard !Task.isCancelled else {
            return cancelledUpdateResult(revision: revision)
        }

        let invalidatedSet = layer.didChangeContent(
            Self.layerContent(for: nextLayeredSource),
            using: inputEdit,
            resolveSublayers: setup.supportsLayeredHighlighting
        )
        guard !Task.isCancelled else {
            return cancelledUpdateResultAfterInvalidatingIncrementalState(revision: revision)
        }
        let nextSourceLength = nextLayeredSource.utf16.count
        let queryRange = SyntaxHighlightInvalidation.queryRange(
            invalidatedSet: invalidatedSet,
            mutation: layeredMutation,
            sourceUTF16Length: nextSourceLength
        )
        let semanticRefreshSeedRange = Self.semanticRefreshSeedRange(
            mutation: layeredMutation,
            sourceUTF16Length: nextSourceLength
        )
        let semanticPartialRefreshRange = semanticPartialRefreshRange(
            source: nextLayeredSource,
            refreshRange: semanticRefreshSeedRange
        )
        let replacementHighlight = semanticPartialRefreshRange.flatMap {
            guard Self.range($0, contains: queryRange) else {
                return nil
            }
            return Self.lexicallyAdjustedReplacementHighlight(
                existingTokens: tokens,
                refreshedRange: $0,
                mutation: layeredMutation,
                previousSource: previousLayeredSource,
                nextSource: nextLayeredSource,
                language: language
            )
        } ?? highlightTokensCoveringQueryRange(
            queryRange,
            source: nextLayeredSource
        )
        guard !Task.isCancelled else {
            return cancelledUpdateResultAfterInvalidatingIncrementalState(revision: revision)
        }
        let replacementMergeRange = replacementHighlight.range
        let semanticOverlayRefreshRange = semanticPartialRefreshRange.map {
            Self.union($0, replacementMergeRange)
        }
        let mergedHighlight = Self.mergedHighlightTokens(
            existingTokens: tokens,
            replacementTokens: replacementHighlight.tokens,
            refreshedRange: replacementMergeRange,
            mutation: layeredMutation,
            previousSourceUTF16Length: previousLayeredSource.utf16.count,
            nextSourceUTF16Length: nextSourceLength
        )
        let refreshRange = mergedHighlight.refreshRange
        emitSyntacticFastPassIfNeeded(
            tokens: mergedHighlight.tokens,
            source: nextSource,
            revision: revision,
            refreshRange: refreshRange,
            emitFastPass: emitFastPass
        )
        let semanticResult = semanticClassifiedTokensIfNeeded(
            mergedHighlight.tokens,
            source: nextLayeredSource,
            rootNode: semanticRootNodeSnapshot(),
            refreshRange: semanticOverlayRefreshRange
        )
        guard !semanticResult.isCancelled, !Task.isCancelled else {
            return cancelledUpdateResultAfterInvalidatingIncrementalState(revision: revision)
        }
        let classifiedTokens = semanticResult.tokens
        let resultRefreshRange = semanticResult.refreshRangeOverride.map {
            SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: nextSourceLength)
        } ?? semanticRefreshRange(
            previousTokens: mergedHighlight.tokens,
            classifiedTokens: classifiedTokens,
            baseRefreshRange: refreshRange,
            sourceUTF16Length: nextSourceLength
        )

        source = nextSource
        layeredSource = nextLayeredSource
        lineIndex.apply(mutation: layeredMutation, previousSource: previousLayeredSource)
        tokens = classifiedTokens

        return SyntaxHighlightResult(
            tokens: tokens,
            source: nextSource,
            language: language,
            revision: revision,
            refreshRange: resultRefreshRange
        )
    }
}

private extension SyntaxHighlightSession {
    var usesDeferredSemanticHighlighting: Bool {
        language == .swift || language == .objectiveC
    }

    func emitSyntacticFastPassIfNeeded(
        tokens: [SyntaxHighlightToken],
        source: String,
        revision: Int,
        refreshRange: NSRange,
        emitFastPass: ((SyntaxHighlightResult) -> Void)?
    ) {
        guard usesDeferredSemanticHighlighting, let emitFastPass else { return }
        emitFastPass(
            SyntaxHighlightResult(
                tokens: tokens,
                source: source,
                language: language,
                revision: revision,
                refreshRange: refreshRange,
                phase: .syntacticFastPass
            )
        )
    }

    func makeLayer() throws -> LanguageLayer {
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

    func layeredSource(for source: String) -> String {
        setup.usesHTMLPreprocessing
            ? HTMLLanguage.sourceByMaskingUnsupportedEmbeddedContent(source)
            : source
    }

    func highlightTokens(in range: NSRange, source: String) -> [SyntaxHighlightToken] {
        guard range.length > 0, let layer else { return [] }

        do {
            let sourceUTF16Length = source.utf16.count
            return try layer.highlights(
                in: range,
                provider: source.predicateTextProvider
            ).compactMap {
                guard let range = Self.utf16Range(
                    fromByteRange: $0.tsRange.bytes,
                    sourceUTF16Length: sourceUTF16Length
                ),
                    range.length > 0
                else {
                    return nil
                }
                let classification = EditorSyntaxCapture.parse(
                    rawCaptureName: $0.name,
                    rootLanguage: language
                )
                return SyntaxHighlightToken(
                    range: range,
                    syntaxID: classification.syntaxID,
                    language: classification.language ?? language,
                    rawCaptureName: $0.name
                )
            }
                .sorted(by: SyntaxHighlightTokenOrdering.displayOrder)
        } catch {
            return []
        }
    }

    func highlightTokensCoveringQueryRange(
        _ queryRange: NSRange,
        source: String
    ) -> (tokens: [SyntaxHighlightToken], range: NSRange) {
        let sourceUTF16Length = source.utf16.count
        var range = SyntaxEditorRangeUtilities.clampedRange(
            queryRange,
            utf16Length: sourceUTF16Length
        )
        range = Self.lineEnvelopeRange(containing: range, source: source)

        while true {
            let tokens = highlightTokens(in: range, source: source)
            let coverageRange = Self.highlightCoverageRange(
                queryRange: range,
                replacementTokens: tokens,
                sourceUTF16Length: sourceUTF16Length
            )

            if coverageRange == range {
                return (tokens, range)
            }

            range = coverageRange
        }
    }

    func fullRange(for source: String) -> NSRange {
        NSRange(location: 0, length: source.utf16.count)
    }

    func refreshRange(in source: String, from location: Int) -> NSRange {
        let sourceLength = source.utf16.count
        let clampedLocation = min(max(0, location), sourceLength)
        let lineStart = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
            in: source,
            around: clampedLocation
        )
        return NSRange(location: lineStart, length: sourceLength - lineStart)
    }

    func cancelledUpdateResult(revision: Int) -> SyntaxHighlightResult {
        SyntaxHighlightResult(
            tokens: tokens,
            source: source,
            language: language,
            revision: revision,
            refreshRange: NSRange(location: 0, length: 0)
        )
    }

    func cancelledUpdateResultAfterInvalidatingIncrementalState(revision: Int) -> SyntaxHighlightResult {
        layer = nil
        swiftSemanticState = nil
        objectiveCSemanticState = nil
        return cancelledUpdateResult(revision: revision)
    }

    static func highlightCoverageRange(
        queryRange: NSRange,
        replacementTokens: [SyntaxHighlightToken],
        sourceUTF16Length: Int
    ) -> NSRange {
        var lower = queryRange.location
        var upper = queryRange.upperBound

        for token in replacementTokens {
            lower = min(lower, token.range.location)
            upper = max(upper, token.range.upperBound)
        }

        lower = min(max(0, lower), sourceUTF16Length)
        upper = min(max(lower, upper), sourceUTF16Length)
        return NSRange(location: lower, length: upper - lower)
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

    static func mergedHighlightTokens(
        existingTokens: [SyntaxHighlightToken],
        replacementTokens: [SyntaxHighlightToken],
        refreshedRange: NSRange,
        mutation: SyntaxHighlightMutation,
        previousSourceUTF16Length: Int,
        nextSourceUTF16Length: Int
    ) -> (tokens: [SyntaxHighlightToken], refreshRange: NSRange) {
        let oldRefreshRange = oldRange(
            correspondingTo: refreshedRange,
            mutation: mutation,
            previousSourceUTF16Length: previousSourceUTF16Length,
            nextSourceUTF16Length: nextSourceUTF16Length
        )
        var refreshRange = refreshedRange
        var before: [SyntaxHighlightToken] = []
        var after: [SyntaxHighlightToken] = []
        before.reserveCapacity(existingTokens.count)
        after.reserveCapacity(existingTokens.count)

        for token in existingTokens {
            let oldRange = SyntaxEditorRangeUtilities.clampedRange(
                token.range,
                utf16Length: previousSourceUTF16Length
            )
            if SyntaxEditorRangeUtilities.intersection(of: oldRange, and: oldRefreshRange).length > 0 {
                if let adjustedRange = rangeForRefreshAfterApplyingMutation(
                    oldRange,
                    mutation: mutation,
                    nextSourceUTF16Length: nextSourceUTF16Length
                ) {
                    refreshRange = union(refreshRange, adjustedRange)
                }
                continue
            }
            guard let adjustedRange = rangeAfterApplyingMutation(
                oldRange,
                mutation: mutation,
                nextSourceUTF16Length: nextSourceUTF16Length
            ) else {
                continue
            }
            let adjustedToken = SyntaxHighlightToken(
                range: adjustedRange,
                syntaxID: token.syntaxID,
                language: token.language,
                rawCaptureName: token.rawCaptureName
            )
            if adjustedRange.location < refreshedRange.location {
                before.append(adjustedToken)
            } else {
                after.append(adjustedToken)
            }
        }

        return ((before + replacementTokens + after).sorted(by: SyntaxHighlightTokenOrdering.displayOrder), refreshRange)
    }

    static func lexicallyAdjustedReplacementHighlight(
        existingTokens: [SyntaxHighlightToken],
        refreshedRange: NSRange,
        mutation: SyntaxHighlightMutation,
        previousSource: String,
        nextSource: String,
        language: SyntaxLanguage
    ) -> (tokens: [SyntaxHighlightToken], range: NSRange)? {
        guard language == .swift,
              mutation.replacement.rangeOfCharacter(from: .newlines) == nil
        else {
            return nil
        }

        let previousNSString = previousSource as NSString
        let nextNSString = nextSource as NSString
        guard mutation.location >= 0,
              mutation.location + mutation.length <= previousNSString.length,
              mutation.location + mutation.replacement.utf16.count <= nextNSString.length
        else {
            return nil
        }
        if mutation.length > 0 {
            let replacedText = previousNSString.substring(with: NSRange(location: mutation.location, length: mutation.length))
            guard replacedText.rangeOfCharacter(from: .newlines) == nil else {
                return nil
            }
        }

        let oldRefreshRange = oldRange(
            correspondingTo: refreshedRange,
            mutation: mutation,
            previousSourceUTF16Length: previousNSString.length,
            nextSourceUTF16Length: nextNSString.length
        )
        guard oldRefreshRange.length > 0 else {
            return nil
        }

        var affectedToken: SyntaxHighlightToken?
        for token in existingTokens where isSwiftLexicalFastPathSyntaxID(token.syntaxID) {
            guard token.language == .swift || token.language == nil,
                  token.range.location >= 0,
                  token.range.upperBound <= previousNSString.length,
                  tokenContainsMutation(token.range, mutation: mutation)
            else {
                continue
            }
            guard affectedToken == nil else {
                return nil
            }
            affectedToken = token
        }
        guard let affectedToken,
              let affectedNewRange = lexicalRangeAfterApplyingMutation(
                  affectedToken.range,
                  mutation: mutation,
                  nextSourceUTF16Length: nextNSString.length
              ),
              affectedNewRange.length > 0,
              swiftLexicalToken(
                  syntaxID: affectedToken.syntaxID,
                  remainsStableFrom: affectedToken.range,
                  in: previousNSString,
                  to: affectedNewRange,
                  in: nextNSString
              )
        else {
            return nil
        }

        var replacementTokens: [SyntaxHighlightToken] = []
        replacementTokens.reserveCapacity(32)

        for token in existingTokens {
            guard token.language == .swift || token.language == nil,
                  !isSwiftSemanticOverlaySyntaxID(token.syntaxID),
                  token.range.location >= 0,
                  token.range.upperBound <= previousNSString.length,
                  SyntaxEditorRangeUtilities.intersection(of: token.range, and: oldRefreshRange).length > 0
            else {
                continue
            }

            let adjustedRange: NSRange?
            if token.range == affectedToken.range,
               token.syntaxID == affectedToken.syntaxID,
               token.rawCaptureName == affectedToken.rawCaptureName {
                adjustedRange = affectedNewRange
            } else if SyntaxEditorRangeUtilities.intersection(
                of: token.range,
                and: NSRange(location: mutation.location, length: mutation.length)
            ).length > 0 {
                return nil
            } else {
                adjustedRange = rangeAfterApplyingMutation(
                    token.range,
                    mutation: mutation,
                    nextSourceUTF16Length: nextNSString.length
                )
            }

            guard let adjustedRange,
                  adjustedRange.length > 0,
                  adjustedRange.location >= refreshedRange.location,
                  adjustedRange.upperBound <= refreshedRange.upperBound
            else {
                return nil
            }
            replacementTokens.append(
                SyntaxHighlightToken(
                    range: adjustedRange,
                    syntaxID: token.syntaxID,
                    language: token.language,
                    rawCaptureName: token.rawCaptureName
                )
            )
        }

        guard replacementTokens.contains(where: {
            $0.range == affectedNewRange
                && $0.syntaxID == affectedToken.syntaxID
                && $0.rawCaptureName == affectedToken.rawCaptureName
        }) else {
            return nil
        }

        return (
            replacementTokens.sorted(by: SyntaxHighlightTokenOrdering.displayOrder),
            refreshedRange
        )
    }

    func semanticClassifiedTokensIfNeeded(
        _ tokens: [SyntaxHighlightToken],
        source: String,
        rootNode: Node? = nil,
        refreshRange: NSRange? = nil
    ) -> SemanticClassificationResult {
        switch language {
        case .swift:
            let result = SwiftSyntaxOverlayTokenProvider.mergingOverlayResult(
                tokens: tokens,
                source: source,
                rootNode: rootNode,
                refreshRange: refreshRange,
                state: &swiftSemanticState
            )
            return SemanticClassificationResult(
                tokens: result.tokens,
                refreshRangeOverride: result.refreshRangeOverride,
                isCancelled: result.isCancelled
            )
        case .objectiveC:
            let result = ObjectiveCSyntaxOverlayTokenProvider.mergingOverlayResult(
                tokens: tokens,
                source: source,
                rootNode: rootNode,
                refreshRange: refreshRange,
                state: &objectiveCSemanticState
            )
            return SemanticClassificationResult(
                tokens: result.tokens,
                refreshRangeOverride: result.refreshRangeOverride,
                isCancelled: result.isCancelled
            )
        case .css:
            return SemanticClassificationResult(
                tokens: CSSSyntaxOverlayTokenProvider.mergingOverlayTokens(
                    tokens: tokens,
                    source: source
                ),
                refreshRangeOverride: nil,
                isCancelled: false
            )
        case .html:
            return SemanticClassificationResult(
                tokens: CSSSyntaxOverlayTokenProvider.mergingOverlayTokens(
                    tokens: tokens,
                    source: source,
                    scanningRanges: HTMLLanguage.embeddedCSSRawTextRanges(in: source)
                ),
                refreshRangeOverride: nil,
                isCancelled: false
            )
        default:
            return SemanticClassificationResult(
                tokens: tokens,
                refreshRangeOverride: nil,
                isCancelled: false
            )
        }
    }

    func semanticPartialRefreshRange(
        source: String,
        refreshRange: NSRange
    ) -> NSRange? {
        let nsSource = source as NSString
        switch language {
        case .swift:
            return SwiftSyntaxOverlayTokenProvider.semanticTargetRange(refreshRange, in: nsSource)
        case .objectiveC:
            return ObjectiveCSyntaxOverlayTokenProvider.semanticTargetRange(refreshRange, in: nsSource)
        default:
            return nil
        }
    }

    static func semanticRefreshSeedRange(
        mutation: SyntaxHighlightMutation,
        sourceUTF16Length: Int
    ) -> NSRange {
        let replacementLength = mutation.replacement.utf16.count
        let location = min(max(0, mutation.location), sourceUTF16Length)
        let upperBound = min(max(location, mutation.location + replacementLength), sourceUTF16Length)
        return NSRange(location: location, length: upperBound - location)
    }

    func semanticRootNodeSnapshot() -> Node? {
        guard language == .swift || language == .objectiveC else {
            return nil
        }
        return layer?.snapshot()?.rootSnapshot.tree.rootNode
    }

    func semanticRefreshRange(
        previousTokens: [SyntaxHighlightToken],
        classifiedTokens: [SyntaxHighlightToken],
        baseRefreshRange: NSRange,
        sourceUTF16Length: Int
    ) -> NSRange {
        switch language {
        case .swift, .objectiveC, .css, .html:
            Self.refreshRangeIncludingTokenChanges(
                from: previousTokens,
                to: classifiedTokens,
                baseRefreshRange: baseRefreshRange,
                sourceUTF16Length: sourceUTF16Length
            )
        default:
            baseRefreshRange
        }
    }

    static func refreshRangeIncludingTokenChanges(
        from previousTokens: [SyntaxHighlightToken],
        to classifiedTokens: [SyntaxHighlightToken],
        baseRefreshRange: NSRange,
        sourceUTF16Length: Int
    ) -> NSRange {
        let previousKeys = Set(previousTokens.map(SyntaxHighlightTokenKey.init))
        let classifiedKeys = Set(classifiedTokens.map(SyntaxHighlightTokenKey.init))
        var refreshRange = SyntaxEditorRangeUtilities.clampedRange(
            baseRefreshRange,
            utf16Length: sourceUTF16Length
        )

        for token in previousTokens where !classifiedKeys.contains(SyntaxHighlightTokenKey(token)) {
            refreshRange = union(
                refreshRange,
                SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: sourceUTF16Length)
            )
        }
        for token in classifiedTokens where !previousKeys.contains(SyntaxHighlightTokenKey(token)) {
            refreshRange = union(
                refreshRange,
                SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: sourceUTF16Length)
            )
        }

        return SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: sourceUTF16Length)
    }

    static func oldRange(
        correspondingTo newRange: NSRange,
        mutation: SyntaxHighlightMutation,
        previousSourceUTF16Length: Int,
        nextSourceUTF16Length: Int
    ) -> NSRange {
        let lower = oldOffset(
            forNewOffset: newRange.location,
            mutation: mutation,
            previousSourceUTF16Length: previousSourceUTF16Length,
            nextSourceUTF16Length: nextSourceUTF16Length,
            usesUpperBoundary: false
        )
        let upper = oldOffset(
            forNewOffset: newRange.upperBound,
            mutation: mutation,
            previousSourceUTF16Length: previousSourceUTF16Length,
            nextSourceUTF16Length: nextSourceUTF16Length,
            usesUpperBoundary: true
        )
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    static func oldOffset(
        forNewOffset offset: Int,
        mutation: SyntaxHighlightMutation,
        previousSourceUTF16Length: Int,
        nextSourceUTF16Length: Int,
        usesUpperBoundary: Bool
    ) -> Int {
        let clampedOffset = min(max(0, offset), nextSourceUTF16Length)
        let oldEnd = mutation.location + mutation.length
        let newEnd = mutation.location + mutation.replacement.utf16.count
        let delta = mutation.replacement.utf16.count - mutation.length

        let oldOffset: Int
        if clampedOffset <= mutation.location {
            oldOffset = clampedOffset
        } else if clampedOffset <= newEnd {
            oldOffset = usesUpperBoundary ? oldEnd : mutation.location
        } else {
            oldOffset = clampedOffset - delta
        }

        return min(max(0, oldOffset), previousSourceUTF16Length)
    }

    static func rangeAfterApplyingMutation(
        _ range: NSRange,
        mutation: SyntaxHighlightMutation,
        nextSourceUTF16Length: Int
    ) -> NSRange? {
        let oldEnd = mutation.location + mutation.length
        let delta = mutation.replacement.utf16.count - mutation.length

        if range.upperBound <= mutation.location {
            return range
        }

        if range.location >= oldEnd {
            let location = range.location + delta
            guard location >= 0, location + range.length <= nextSourceUTF16Length else {
                return nil
            }
            return NSRange(location: location, length: range.length)
        }

        return nil
    }

    static func rangeForRefreshAfterApplyingMutation(
        _ range: NSRange,
        mutation: SyntaxHighlightMutation,
        nextSourceUTF16Length: Int
    ) -> NSRange? {
        let oldEnd = mutation.location + mutation.length
        let newEnd = mutation.location + mutation.replacement.utf16.count
        let delta = mutation.replacement.utf16.count - mutation.length

        if range.upperBound <= mutation.location {
            return SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: nextSourceUTF16Length)
        }

        if range.location >= oldEnd {
            return SyntaxEditorRangeUtilities.clampedRange(
                NSRange(location: range.location + delta, length: range.length),
                utf16Length: nextSourceUTF16Length
            )
        }

        let location = min(range.location, mutation.location)
        let upper = range.upperBound > oldEnd
            ? range.upperBound + delta
            : newEnd
        let clampedLocation = min(max(0, location), nextSourceUTF16Length)
        let clampedUpper = min(max(clampedLocation, upper), nextSourceUTF16Length)
        guard clampedUpper > clampedLocation else { return nil }
        return NSRange(location: clampedLocation, length: clampedUpper - clampedLocation)
    }

    static func tokenContainsMutation(_ range: NSRange, mutation: SyntaxHighlightMutation) -> Bool {
        let mutationUpperBound = mutation.location + mutation.length
        if mutation.length == 0 {
            return range.location <= mutation.location && mutation.location <= range.upperBound
        }
        return range.location <= mutation.location && mutationUpperBound <= range.upperBound
    }

    static func lexicalRangeAfterApplyingMutation(
        _ range: NSRange,
        mutation: SyntaxHighlightMutation,
        nextSourceUTF16Length: Int
    ) -> NSRange? {
        let replacementLength = mutation.replacement.utf16.count
        if mutation.length == 0,
           range.location <= mutation.location,
           mutation.location <= range.upperBound {
            let adjustedRange = NSRange(
                location: range.location,
                length: range.length + replacementLength
            )
            return SyntaxEditorRangeUtilities.clampedRange(
                adjustedRange,
                utf16Length: nextSourceUTF16Length
            )
        }
        return rangeForRefreshAfterApplyingMutation(
            range,
            mutation: mutation,
            nextSourceUTF16Length: nextSourceUTF16Length
        )
    }

    static func isSwiftLexicalFastPathSyntaxID(_ syntaxID: EditorSourceSyntaxID) -> Bool {
        syntaxID == .plain || syntaxID == .number
    }

    static func isSwiftSemanticOverlaySyntaxID(_ syntaxID: EditorSourceSyntaxID) -> Bool {
        switch syntaxID {
        case .identifierType,
             .identifierTypeSystem,
             .identifierClass,
             .identifierClassSystem,
             .identifierFunction,
             .identifierFunctionSystem,
             .identifierMacro,
             .identifierMacroSystem,
             .identifierConstant,
             .identifierConstantSystem,
             .identifierVariable,
             .identifierVariableSystem:
            true
        default:
            false
        }
    }

    static func swiftLexicalToken(
        syntaxID: EditorSourceSyntaxID,
        remainsStableFrom oldRange: NSRange,
        in previousSource: NSString,
        to newRange: NSRange,
        in nextSource: NSString
    ) -> Bool {
        guard oldRange.location >= 0,
              oldRange.upperBound <= previousSource.length,
              newRange.location >= 0,
              newRange.upperBound <= nextSource.length
        else {
            return false
        }

        let oldText = previousSource.substring(with: oldRange)
        let newText = nextSource.substring(with: newRange)
        switch syntaxID {
        case .plain:
            return isSwiftPlainIdentifierStableForLexicalFastPath(oldText)
                && isSwiftPlainIdentifierStableForLexicalFastPath(newText)
        case .number:
            return isSimpleDecimalNumber(oldText) && isSimpleDecimalNumber(newText)
        default:
            return false
        }
    }

    static func isSwiftPlainIdentifierStableForLexicalFastPath(_ text: String) -> Bool {
        isSimpleSwiftIdentifier(text) && !swiftKeywordLikePlainIdentifiers.contains(text)
    }

    static func isSimpleSwiftIdentifier(_ text: String) -> Bool {
        var iterator = text.utf8.makeIterator()
        guard let first = iterator.next(),
              first == 95 || (first >= 65 && first <= 90) || (first >= 97 && first <= 122)
        else {
            return false
        }

        while let byte = iterator.next() {
            guard byte == 95 || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) else {
                return false
            }
        }
        return true
    }

    private static let swiftKeywordLikePlainIdentifiers: Set<String> = [
        "Any",
        "GKInspectable",
        "IBAction",
        "IBDesignable",
        "IBInspectable",
        "IBOutlet",
        "IBSegueAction",
        "NSApplicationMain",
        "NSCopying",
        "NSManaged",
        "Protocol",
        "Self",
        "Sendable",
        "Type",
        "UIApplicationMain",
        "_implementationOnly",
        "_modify",
        "_read",
        "_spi",
        "actor",
        "actorIndependent",
        "any",
        "as",
        "associatedtype",
        "async",
        "asyncHandler",
        "attached",
        "autoclosure",
        "available",
        "await",
        "backDeployed",
        "break",
        "case",
        "catch",
        "class",
        "concurrent",
        "continue",
        "convenience",
        "convention",
        "defer",
        "deinit",
        "didSet",
        "discardableResult",
        "do",
        "dynamic",
        "dynamicCallable",
        "dynamicMemberLookup",
        "else",
        "enum",
        "escaping",
        "extension",
        "fallthrough",
        "false",
        "fileprivate",
        "final",
        "for",
        "freestanding",
        "frozen",
        "func",
        "get",
        "globalActor",
        "guard",
        "if",
        "implementation",
        "import",
        "in",
        "indirect",
        "infix",
        "init",
        "inlinable",
        "inline",
        "internal",
        "isolated",
        "lazy",
        "let",
        "macro",
        "main",
        "modify",
        "mutating",
        "nil",
        "none",
        "nonisolated",
        "nonmutating",
        "nonobjc",
        "noreturn",
        "objc",
        "objcMembers",
        "open",
        "operator",
        "optional",
        "override",
        "postfix",
        "preconcurrency",
        "precedencegroup",
        "prefix",
        "private",
        "propertyWrapper",
        "protocol",
        "public",
        "read",
        "required",
        "requires_stored_property_inits",
        "resultBuilder",
        "return",
        "retroactive",
        "rethrows",
        "right",
        "safe",
        "self",
        "set",
        "some",
        "specialized",
        "static",
        "storageRestrictions",
        "struct",
        "subscript",
        "super",
        "switch",
        "testable",
        "throw",
        "throws",
        "true",
        "try",
        "typealias",
        "unchecked",
        "unknown",
        "unowned",
        "unsafe",
        "usableFromInline",
        "var",
        "warn_unqualified_access",
        "weak",
        "where",
        "while",
        "willSet",
    ]

    static func isSimpleDecimalNumber(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }
        for byte in text.utf8 {
            guard byte >= 48 && byte <= 57 else {
                return false
            }
        }
        return true
    }

    static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let lower = min(lhs.location, rhs.location)
        let upper = max(lhs.upperBound, rhs.upperBound)
        return NSRange(location: lower, length: upper - lower)
    }

    static func range(_ outer: NSRange, contains inner: NSRange) -> Bool {
        inner.location >= outer.location && inner.upperBound <= outer.upperBound
    }

    static func inputEdit(
        mutation: SyntaxHighlightMutation,
        previousSource: String,
        nextSource: String,
        lineIndex: SyntaxHighlightLineIndex
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
            startPoint: lineIndex.point(at: mutation.location),
            oldEndPoint: lineIndex.point(at: oldEnd),
            newEndPoint: Self.advancedPoint(
                from: lineIndex.point(at: mutation.location),
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

    static func layerContent(for source: String) -> LanguageLayer.Content {
        let limit = source.utf16.count
        let chunkCodeUnits = 1024
        let encoding = nativeUTF16Encoding
        let readHandler: Parser.ReadBlock = { byteOffset, _ in
            guard byteOffset >= 0 else { return nil }
            let location = byteOffset / 2
            guard location < limit else { return nil }

            let end = min(location + chunkCodeUnits, limit)
            guard end > location else { return nil }

            guard let stringRange = Self.stringRangeForUTF16Chunk(
                location: location,
                proposedEnd: end,
                limit: limit,
                in: source
            ) else {
                return nil
            }
            return source[stringRange].data(using: encoding)
        }
        return LanguageLayer.Content(
            readHandler: readHandler,
            textProvider: source.predicateTextProvider
        )
    }

    static func stringRangeForUTF16Chunk(
        location: Int,
        proposedEnd: Int,
        limit: Int,
        in source: String
    ) -> Range<String.Index>? {
        guard location >= 0, location < limit else {
            return nil
        }

        let clampedEnd = min(max(location + 1, proposedEnd), limit)
        if let range = Range(NSRange(location..<clampedEnd), in: source) {
            return range
        }

        if clampedEnd > location + 1 {
            for end in stride(from: clampedEnd - 1, through: location + 1, by: -1) {
                if let range = Range(NSRange(location..<end), in: source) {
                    return range
                }
            }
        }

        if clampedEnd < limit {
            for end in (clampedEnd + 1)...limit {
                if let range = Range(NSRange(location..<end), in: source) {
                    return range
                }
            }
        }

        return nil
    }

    static var nativeUTF16Encoding: String.Encoding {
#if _endian(little)
        .utf16LittleEndian
#else
        .utf16BigEndian
#endif
    }

    static func mutationMatchesSourceTransition(
        _ mutation: SyntaxHighlightMutation,
        previousSource: String,
        nextSource: String
    ) -> Bool {
        let previousLength = previousSource.utf16.count
        let replacementLength = mutation.replacement.utf16.count
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location <= previousLength,
              mutation.location + mutation.length <= previousLength
        else {
            return false
        }

        let oldEnd = mutation.location + mutation.length
        let newEnd = mutation.location + replacementLength
        let suffixLength = previousLength - oldEnd
        guard nextSource.utf16.count == previousLength - mutation.length + replacementLength else {
            return false
        }

        let previous = previousSource as NSString
        let next = nextSource as NSString
        if mutation.location > 0 {
            let prefixRange = NSRange(location: 0, length: mutation.location)
            guard previous.substring(with: prefixRange) == next.substring(with: prefixRange) else {
                return false
            }
        }

        if replacementLength > 0 {
            guard next.substring(with: NSRange(location: mutation.location, length: replacementLength)) == mutation.replacement else {
                return false
            }
        }

        if suffixLength > 0 {
            guard previous.substring(with: NSRange(location: oldEnd, length: suffixLength)) ==
                next.substring(with: NSRange(location: newEnd, length: suffixLength))
            else {
                return false
            }
        }

        return true
    }

    static func mutationTouchesMarkupBoundary(
        mutation: SyntaxHighlightMutation,
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

        for codeUnit in source.utf16 {
            if codeUnit == 10 {
                row += 1
                column = 0
            } else {
                column += 2
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

private final class SyntaxHighlightLineIndex {
    private var lineStartOffsets: [Int] = [0]

    func reset(source: String) {
        lineStartOffsets = Self.lineStarts(in: source, baseOffset: 0)
    }

    func apply(mutation: SyntaxHighlightMutation, previousSource: String) {
        guard let affectedRange = affectedRange(for: mutation, in: previousSource) else {
            reset(source: SyntaxEditorDocument.applying([
                SyntaxEditorTextEdit(
                    range: NSRange(location: mutation.location, length: mutation.length),
                    replacement: mutation.replacement
                )
            ], to: previousSource))
            return
        }

        let nsSource = previousSource as NSString
        let oldSegment = nsSource.substring(with: affectedRange)
        let newSegment = SyntaxEditorDocument.applying([
            SyntaxEditorTextEdit(
                range: NSRange(
                    location: mutation.location - affectedRange.location,
                    length: mutation.length
                ),
                replacement: mutation.replacement
            )
        ], to: oldSegment)
        let starts = Self.lineStarts(in: newSegment, baseOffset: affectedRange.location)
        let replacementStarts = affectedRange.upperBound < nsSource.length && Self.endsWithLineBreak(newSegment)
            ? starts.dropLast()
            : starts[...]
        let startIndex = lineIndex(containingUTF16Offset: affectedRange.location)
        let endIndex = oldLineEndIndex(for: affectedRange, sourceUTF16Length: nsSource.length)
        lineStartOffsets.replaceSubrange(startIndex..<endIndex, with: replacementStarts)

        let delta = mutation.replacement.utf16.count - mutation.length
        guard delta != 0 else { return }
        let adjustmentStart = startIndex + replacementStarts.count
        guard adjustmentStart < lineStartOffsets.count else { return }
        for index in adjustmentStart..<lineStartOffsets.count {
            lineStartOffsets[index] += delta
        }
    }

    func point(at utf16Offset: Int) -> Point {
        let clampedOffset = max(0, utf16Offset)
        let index = lineIndex(containingUTF16Offset: clampedOffset)
        let lineStart = lineStartOffsets[index]
        return Point(row: index, column: max(0, clampedOffset - lineStart) * 2)
    }
}

private extension SyntaxHighlightLineIndex {
    func affectedRange(for mutation: SyntaxHighlightMutation, in source: String) -> NSRange? {
        let nsSource = source as NSString
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location <= nsSource.length,
              mutation.location + mutation.length <= nsSource.length else {
            return nil
        }

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
        if (Self.containsLineBreak(deletedText) || Self.containsLineBreak(mutation.replacement)),
           endIndex < lineStartOffsets.count {
            endIndex += 1
        }

        let lower = lineStartOffsets[startIndex]
        let upper = endIndex < lineStartOffsets.count
            ? lineStartOffsets[endIndex]
            : nsSource.length
        return NSRange(location: lower, length: upper - lower)
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
        return max(0, min(lineStartOffsets.count - 1, lower - 1))
    }

    func oldLineEndIndex(for range: NSRange, sourceUTF16Length: Int) -> Int {
        guard !lineStartOffsets.isEmpty else { return 0 }
        let upperBound = min(sourceUTF16Length, range.upperBound)
        let lookup = range.length == 0
            ? range.location
            : upperBound == sourceUTF16Length
                ? upperBound
                : max(range.location, upperBound - 1)
        return min(lineStartOffsets.count, lineIndex(containingUTF16Offset: lookup) + 1)
    }

    static func lineStarts(in source: String, baseOffset: Int) -> [Int] {
        var starts = [baseOffset]
        var utf16Offset = baseOffset
        for codeUnit in source.utf16 {
            if codeUnit == 10 {
                starts.append(utf16Offset + 1)
            }
            utf16Offset += 1
        }
        return starts
    }

    static func endsWithLineBreak(_ source: String) -> Bool {
        source.utf16.last == 10
    }

    static func containsLineBreak(_ source: String) -> Bool {
        source.utf16.contains(10)
    }
}

private actor LanguageConfigurationRegistry {
    static let shared = LanguageConfigurationRegistry()

    private let resolver = LanguageConfigurationResolver.shared
    private var layeredSetupCache: [SyntaxLanguage: HighlightingSetup?] = [:]

    func highlightingSetup(for language: SyntaxLanguage) -> HighlightingSetup? {
        if let cached = layeredSetupCache[language] {
            return cached
        }

        guard let setup = HighlightingSetup.resolved(for: language, resolver: resolver) else {
            layeredSetupCache[language] = nil
            return nil
        }
        layeredSetupCache[language] = setup
        return setup
    }
}

private final class InjectedLanguageProvider: @unchecked Sendable {
    private let resolver: LanguageConfigurationResolver
    private let lock = NSRecursiveLock()
    private var aliases: [String: CachedLanguageConfiguration] = [:]

    init(resolver: LanguageConfigurationResolver) {
        self.resolver = resolver
    }

    func configuration(named rawName: String) -> LanguageConfiguration? {
        let alias = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let language = SyntaxLanguage.named(alias) else {
            return nil
        }

        lock.lock()
        if let cached = aliases[alias] {
            lock.unlock()
            switch cached {
            case .resolved(let configuration):
                return configuration
            case .missing:
                return nil
            }
        }
        lock.unlock()

        guard let configuration = resolver.configuration(for: language) else {
            lock.lock()
            aliases[alias] = .missing
            lock.unlock()
            return nil
        }

        lock.lock()
        aliases[alias] = .resolved(configuration)
        lock.unlock()
        return configuration
    }
}

private final class LanguageConfigurationResolver: @unchecked Sendable {
    static let shared = LanguageConfigurationResolver()

    private let lock = NSRecursiveLock()
    private var configurations: [SyntaxLanguage: CachedLanguageConfiguration] = [:]
    private var queryDirectoryCandidateCache: [SyntaxLanguage: [URL]] = [:]

    private init() {}
}

private extension LanguageConfigurationResolver {
    func configuration(for language: SyntaxLanguage) -> LanguageConfiguration? {
        lock.lock()
        defer { lock.unlock() }

        switch configurations[language] {
        case .resolved(let configuration):
            return configuration
        case .missing:
            return nil
        case nil:
            break
        }

        let support = language.treeSitterSupport
        let configuration = makeConfiguration(for: language, support: support)
        if let configuration {
            configurations[language] = .resolved(configuration)
            return configuration
        }

        configurations[language] = .missing
        return nil
    }

    func makeConfiguration(
        for language: SyntaxLanguage,
        support: SyntaxTreeSitterSupport
    ) -> LanguageConfiguration? {
        let treeSitterLanguage = support.makeLanguage()

        for queriesURL in support.queryDirectories {
            if let configuration = makeConfiguration(
                treeSitterLanguage,
                support: support,
                queriesURL: queriesURL
            ) {
                return configuration
            }
        }

        if let configuration = try? LanguageConfiguration(
            treeSitterLanguage,
            name: support.name,
            bundleName: support.bundleName
        ), configuration.queries[.highlights] != nil {
            return configuration
        }

        for queriesURL in queryDirectoryCandidates(for: language, support: support) {
            if let configuration = makeConfiguration(
                treeSitterLanguage,
                support: support,
                queriesURL: queriesURL
            ) {
                return configuration
            }
        }

        return nil
    }

    func makeConfiguration(
        _ language: Language,
        support: SyntaxTreeSitterSupport,
        queriesURL: URL
    ) -> LanguageConfiguration? {
        let standardized = queriesURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            return nil
        }
        guard let configuration = try? LanguageConfiguration(
            language,
            name: support.name,
            queriesURL: standardized
        ), configuration.queries[.highlights] != nil else {
            return nil
        }
        return configuration
    }

    func supportedInjectedAliases(
        for support: SyntaxTreeSitterSupport,
        rootConfiguration: LanguageConfiguration
    ) -> Set<String>? {
        guard rootConfiguration.queries[.injections] != nil else {
            return nil
        }
        guard let querySource = injectionsQuerySource(for: support) else {
            return nil
        }
        guard querySource.contains("@injection.language") == false else {
            return nil
        }
        guard containsOnlySupportedInjectionCaptures(in: querySource) else {
            return nil
        }

        let aliases = explicitInjectedLanguages(in: querySource)
        guard aliases.isEmpty == false else {
            return nil
        }
        guard aliases.allSatisfy({ SyntaxLanguage.named($0) != nil }) else {
            return nil
        }

        return aliases
    }

    func injectionsQuerySource(for support: SyntaxTreeSitterSupport) -> String? {
        var candidates: [URL] = []
        var seenPaths = Set<String>()
        let bundleFilename = "\(support.bundleName).bundle"

        for queriesURL in support.queryDirectories {
            let standardized = queriesURL.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else {
                continue
            }
            candidates.append(standardized)
        }

        let bundleURLs =
            [Bundle.main.bundleURL] +
            Bundle.allBundles.map(\.bundleURL) +
            Bundle.allFrameworks.map(\.bundleURL)
        for bundleURL in bundleURLs where bundleURL.lastPathComponent == bundleFilename {
            for queriesURL in Self.bundleQueryDirectories(
                for: bundleURL,
                preferredSubdirectoryNames: Set([support.name.lowercased()])
            ) {
                let standardized = queriesURL.standardizedFileURL
                guard seenPaths.insert(standardized.path).inserted else {
                    continue
                }
                candidates.append(standardized)
            }
        }

        for queriesURL in queryDirectoryCandidates(for: nil, support: support) {
            let standardized = queriesURL.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else {
                continue
            }
            candidates.append(standardized)
        }

        for queriesURL in candidates {
            let injectionsURL = queriesURL.appendingPathComponent("injections.scm")
            if let source = try? String(contentsOf: injectionsURL, encoding: .utf8) {
                return source
            }
        }

        return nil
    }

    func containsOnlySupportedInjectionCaptures(in querySource: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"@[A-Za-z0-9_.-]+"#) else {
            return false
        }

        let sourceRange = NSRange(location: 0, length: querySource.utf16.count)
        return regex.matches(in: querySource, range: sourceRange).allSatisfy { match in
            guard let range = Range(match.range, in: querySource) else {
                return false
            }

            let capture = String(querySource[range])
            return capture == "@injection.content" || capture == "@injection.language" || capture.hasPrefix("@_")
        }
    }

    func explicitInjectedLanguages(in querySource: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: #"#set!\s+injection\.language\s+"([^"]+)""#
        ) else {
            return []
        }

        let sourceRange = NSRange(location: 0, length: querySource.utf16.count)
        let matches = regex.matches(in: querySource, range: sourceRange)
        return Set(matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: querySource)
            else {
                return nil
            }

            return String(querySource[range]).lowercased()
        })
    }

    func supportsHTMLRawTextPreprocessing(for language: Language) -> Bool {
        let requiredSymbols = Set(["raw_text", "script_element", "style_element"])
        var resolvedSymbols = Set<String>()

        for symbolID in 0..<language.symbolCount {
            guard let symbolName = language.symbolName(for: symbolID),
                  requiredSymbols.contains(symbolName)
            else {
                continue
            }

            resolvedSymbols.insert(symbolName)
            if resolvedSymbols == requiredSymbols {
                return true
            }
        }

        return false
    }

    func queryDirectoryCandidates(
        for language: SyntaxLanguage?,
        support: SyntaxTreeSitterSupport
    ) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        if let language, let cached = queryDirectoryCandidateCache[language] {
            return cached
        }

        let candidates = Self.queryDirectoryCandidates(for: support)
        if let language {
            queryDirectoryCandidateCache[language] = candidates
        }
        return candidates
    }

    static func queryDirectoryCandidates(for support: SyntaxTreeSitterSupport) -> [URL] {
        let bundleFilename = "\(support.bundleName).bundle"
        var roots: [URL] = []
        let fileManager = FileManager.default
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL)
        }
        roots.append(Bundle.main.bundleURL)
        roots.append(currentDirectoryURL)

        roots.append(contentsOf: Bundle.allBundles.map(\.bundleURL))
        roots.append(contentsOf: Bundle.allFrameworks.map(\.bundleURL))

        var seen = Set<String>()
        var uniqueRoots: [URL] = []
        for root in roots {
            for candidate in searchRoots(from: root) {
                if seen.insert(candidate.path).inserted {
                    uniqueRoots.append(candidate)
                }
            }
        }

        var candidates: [URL] = []
        let preferredSubdirectoryNames = Set([support.name.lowercased()])

        for root in uniqueRoots {
            let bundleURL = root.appendingPathComponent(bundleFilename, isDirectory: true)
            candidates.append(
                contentsOf: bundleQueryDirectories(
                    for: bundleURL,
                    preferredSubdirectoryNames: preferredSubdirectoryNames
                )
            )
        }

        let buildRoot = currentDirectoryURL.appendingPathComponent(".build", isDirectory: true)
        if fileManager.fileExists(atPath: buildRoot.path),
           let enumerator = fileManager.enumerator(
               at: buildRoot,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           )
        {
            for case let bundleURL as URL in enumerator {
                guard bundleURL.lastPathComponent == bundleFilename else {
                    continue
                }

                candidates.append(
                    contentsOf: bundleQueryDirectories(
                        for: bundleURL,
                        preferredSubdirectoryNames: preferredSubdirectoryNames
                    )
                )
                enumerator.skipDescendants()
            }
        }

        return candidates
    }

    static func searchRoots(from root: URL) -> [URL] {
        var result: [URL] = []
        var currentURL: URL? = root.standardizedFileURL

        for _ in 0..<6 {
            guard let current = currentURL else { break }
            result.append(current)

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                break
            }
            currentURL = parent
        }

        return result
    }

    static func bundleQueryDirectories(
        for bundleURL: URL,
        preferredSubdirectoryNames: Set<String>
    ) -> [URL] {
        let fileManager = FileManager.default
        var queryDirectories = [
            bundleURL.appendingPathComponent("queries", isDirectory: true),
            bundleURL.appendingPathComponent("Contents/Resources/queries", isDirectory: true),
        ]

        var searchRoots = [
            bundleURL,
            bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true),
        ]
        searchRoots.append(contentsOf: queryDirectories)

        var preferredDirectories: [URL] = []
        var fallbackDirectories: [URL] = []

        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children {
                guard let resourceValues = try? child.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true
                else {
                    continue
                }

                let hasHighlights = fileManager.fileExists(
                    atPath: child.appendingPathComponent("highlights.scm").path
                )
                let hasInjections = fileManager.fileExists(
                    atPath: child.appendingPathComponent("injections.scm").path
                )
                if hasHighlights || hasInjections {
                    if preferredSubdirectoryNames.contains(child.lastPathComponent.lowercased()) {
                        preferredDirectories.append(child)
                    } else {
                        fallbackDirectories.append(child)
                    }
                }
            }
        }

        queryDirectories.append(contentsOf: preferredDirectories)
        queryDirectories.append(contentsOf: fallbackDirectories)
        return queryDirectories.filter { fileManager.fileExists(atPath: $0.path) }
    }
}

private extension SyntaxHighlightResult {
    static func empty(source: String, language: SyntaxLanguage, revision: Int) -> SyntaxHighlightResult {
        SyntaxHighlightResult(
            tokens: [],
            source: source,
            language: language,
            revision: revision,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }
}
