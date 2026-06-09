import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

package struct SyntaxHighlightToken: Equatable, Sendable {
    package let range: NSRange
    package let syntaxID: EditorSourceSyntaxID
    package let language: SyntaxLanguage?
    package let rawCaptureName: String
    package let isSemanticOverlay: Bool

    package init(
        range: NSRange,
        rawCaptureName: String,
        language: SyntaxLanguage = .swift
    ) {
        self.init(
            range: range,
            rawCaptureName: rawCaptureName,
            language: language,
            isSemanticOverlay: false
        )
    }

    package init(
        range: NSRange,
        rawCaptureName: String,
        language: SyntaxLanguage,
        isSemanticOverlay: Bool
    ) {
        let classification = EditorSyntaxCapture.parse(
            rawCaptureName: rawCaptureName,
            rootLanguage: language
        )
        self.init(
            range: range,
            syntaxID: classification.syntaxID,
            language: classification.language ?? language,
            rawCaptureName: rawCaptureName,
            isSemanticOverlay: isSemanticOverlay
        )
    }

    package init(
        range: NSRange,
        syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage?,
        rawCaptureName: String
    ) {
        self.init(
            range: range,
            syntaxID: syntaxID,
            language: language,
            rawCaptureName: rawCaptureName,
            isSemanticOverlay: false
        )
    }

    package init(
        range: NSRange,
        syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage?,
        rawCaptureName: String,
        isSemanticOverlay: Bool
    ) {
        self.range = range
        self.syntaxID = syntaxID
        self.language = language
        self.rawCaptureName = rawCaptureName
        self.isSemanticOverlay = isSemanticOverlay
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

package enum SyntaxHighlightTokenPayload: Equatable, Sendable {
    case fullSnapshot
    case replacement
}

package struct SyntaxHighlightResult: Sendable {
    package let tokens: [SyntaxHighlightToken]
    package let source: String
    package let language: SyntaxLanguage
    package let revision: Int
    package let refreshRange: NSRange
    package let phase: SyntaxHighlightPhase
    package let tokenPayload: SyntaxHighlightTokenPayload

    package var containsCompleteTokenSnapshot: Bool {
        tokenPayload == .fullSnapshot
    }

    package init(
        tokens: [SyntaxHighlightToken],
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        refreshRange: NSRange,
        phase: SyntaxHighlightPhase = .complete,
        tokenPayload: SyntaxHighlightTokenPayload = .fullSnapshot
    ) {
        self.tokens = tokens
        self.source = source
        self.language = language
        self.revision = revision
        self.refreshRange = refreshRange
        self.phase = phase
        self.tokenPayload = tokenPayload
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

public enum SyntaxEditorHighlighting {
    public static func prepare(_ language: SyntaxLanguage) async {
        _ = await LanguageConfigurationRegistry.shared.highlightingSetup(for: language)
    }

    public static func prepare<S: Sequence>(_ languages: S) async where S.Element == SyntaxLanguage {
        let registry = LanguageConfigurationRegistry.shared
        for language in uniqueLanguages(languages) {
            _ = await registry.highlightingSetup(for: language)
        }
    }

    private static func uniqueLanguages<S: Sequence>(_ languages: S) -> [SyntaxLanguage]
        where S.Element == SyntaxLanguage
    {
        var seen = Set<SyntaxLanguage>()
        var result: [SyntaxLanguage] = []

        for language in languages where seen.insert(language).inserted {
            result.append(language)
        }

        return result
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
        let setup = await registry.highlightingSetup(for: language)
        guard !Task.isCancelled else {
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }

        guard let setup else {
            session = nil
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }

        let nextSession = SyntaxHighlightSession(language: language, setup: setup)
        let result = nextSession.reset(source: source, revision: revision, emitFastPass: emitFastPass)
        guard !Task.isCancelled else {
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }

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

    package func currentTokensForTesting() -> [SyntaxHighlightToken] {
        session?.currentTokensForTesting() ?? []
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
        guard language.supportsSyntaxHighlighting else {
            return nil
        }

        guard let rootConfiguration = resolver.configuration(for: language) else {
            return nil
        }

        guard let support = language.treeSitterSupport else {
            return nil
        }
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

private enum CachedHighlightingSetup: Sendable {
    case resolved(HighlightingSetup)
    case missing

    var setup: HighlightingSetup? {
        switch self {
        case .resolved(let setup):
            setup
        case .missing:
            nil
        }
    }
}

private final class SyntaxHighlightSession {
    private let setup: HighlightingSetup
    private(set) var language: SyntaxLanguage
    private var source = ""
    private var layeredSource = ""
    private var layer: LanguageLayer?
    private let lineIndex = SyntaxHighlightLineIndex()
    private let tokenStore = HighlightLineTokenStore()
    private var swiftSemanticState: SwiftSemanticOverlayState?
    private var objectiveCSemanticState: ObjectiveCSemanticOverlayState?

    init(language: SyntaxLanguage, setup: HighlightingSetup) {
        self.language = language
        self.setup = setup
    }

    func currentTokensForTesting() -> [SyntaxHighlightToken] {
        tokenStore.tokens(lineIndex: lineIndex)
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
            tokenStore.clear(lineCount: lineIndex.lineCount)
            return SyntaxHighlightResult.empty(source: source, language: language, revision: revision)
        }

        do {
            let layer = try makeLayer()
            guard let fullEdit = Self.fullReplacementInputEdit(for: layeredSource) else {
                self.layer = nil
                tokenStore.clear(lineCount: lineIndex.lineCount)
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
                tokenStore.clear(lineCount: lineIndex.lineCount)
                return SyntaxHighlightResult(
                    tokens: [],
                    source: source,
                    language: language,
                    revision: revision,
                    refreshRange: fullRange(for: source)
                )
            }
            let classifiedTokens = semanticResult.tokens

            tokenStore.reset(tokens: classifiedTokens, lineIndex: lineIndex)
        } catch {
            layer = nil
            tokenStore.clear(lineCount: lineIndex.lineCount)
        }

        return SyntaxHighlightResult(
            tokens: tokenStore.tokens(lineIndex: lineIndex),
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
                return nil
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
        let nextSourceLength = nextLayeredSource.utf16.count
        let queryRange = SyntaxHighlightInvalidation.queryRange(
            invalidatedSet: invalidatedSet,
            mutation: layeredMutation,
            sourceUTF16Length: nextSourceLength
        )
        let editMaterializationRange = Self.editMaterializationRange(
            mutation: layeredMutation,
            sourceUTF16Length: nextSourceLength
        )
        let parseRange = Self.lineEnvelopeRange(
            containing: Self.union(queryRange, editMaterializationRange),
            source: nextLayeredSource
        )
        let semanticPartialRefreshRange = Self.mutationDeletesSemanticStructuralText(
            layeredMutation,
            previousSource: previousLayeredSource,
            language: language
        )
            ? nil
            : semanticPartialRefreshRange(
                source: nextLayeredSource,
                refreshRange: parseRange,
                mutation: layeredMutation
            )
        let replacementHighlight = highlightTokensCoveringQueryRange(
            parseRange,
            source: nextLayeredSource
        )
        let replacementMergeRange = replacementHighlight.range
        let semanticOverlayRefreshRange = semanticPartialRefreshRange.map {
            Self.union($0, replacementMergeRange)
        }
        let semanticComparisonRange = semanticOverlayRefreshRange ?? replacementMergeRange
        let previousSemanticComparisonTokens = tokenStore.tokens(
            in: semanticComparisonRange,
            lineIndex: lineIndex
        )

        tokenStore.applyEdit(
            layeredMutation,
            previousSource: previousLayeredSource,
            lineIndex: lineIndex
        )
        lineIndex.apply(mutation: layeredMutation, previousSource: previousLayeredSource)
        tokenStore.replaceTokens(
            in: replacementMergeRange,
            with: replacementHighlight.tokens,
            lineIndex: lineIndex,
            quality: .accurate
        )

        let syntacticRefreshRange = replacementMergeRange
        let syntacticResultTokens = tokenStore.tokens(in: syntacticRefreshRange, lineIndex: lineIndex)
        emitSyntacticFastPassIfNeeded(
            tokens: syntacticResultTokens,
            source: nextSource,
            revision: revision,
            refreshRange: syntacticRefreshRange,
            tokenPayload: .replacement,
            emitFastPass: emitFastPass
        )
        let semanticInputTokens = semanticOverlayRefreshRange.map {
            tokenStore.tokens(in: $0, lineIndex: lineIndex)
        } ?? tokenStore.tokens(lineIndex: lineIndex)
        let semanticInputPrefixMaxUpperBounds = Self.prefixMaxUpperBounds(for: semanticInputTokens)
        let previousSwiftSemanticState = swiftSemanticState
        let previousObjectiveCSemanticState = objectiveCSemanticState
        var semanticResult = semanticClassifiedTokensIfNeeded(
            semanticInputTokens,
            source: nextLayeredSource,
            rootNode: semanticRootNodeSnapshot(),
            refreshRange: semanticOverlayRefreshRange,
            mutation: layeredMutation,
            tokenPrefixMaxUpperBounds: semanticInputPrefixMaxUpperBounds
        )
        if semanticOverlayRefreshRange != nil,
           semanticResult.refreshRangeOverride == nil,
           !semanticResult.isCancelled,
           !Task.isCancelled {
            swiftSemanticState = previousSwiftSemanticState
            objectiveCSemanticState = previousObjectiveCSemanticState
            let fullSemanticInputTokens = tokenStore.tokens(lineIndex: lineIndex)
            semanticResult = semanticClassifiedTokensIfNeeded(
                fullSemanticInputTokens,
                source: nextLayeredSource,
                rootNode: semanticRootNodeSnapshot(),
                refreshRange: nil,
                mutation: layeredMutation,
                tokenPrefixMaxUpperBounds: Self.prefixMaxUpperBounds(for: fullSemanticInputTokens)
            )
        }
        let classifiedTokens: [SyntaxHighlightToken]
        var resultRefreshRange: NSRange
        if semanticResult.isCancelled || Task.isCancelled {
            classifiedTokens = syntacticResultTokens
            resultRefreshRange = syntacticRefreshRange
        } else {
            classifiedTokens = semanticResult.tokens
            resultRefreshRange = semanticPartialRefreshRange.map {
                SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: nextSourceLength)
            } ?? semanticResult.refreshRangeOverride.map {
                SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: nextSourceLength)
            } ?? {
                let semanticDiffRefreshRange = semanticRefreshRange(
                    previousTokens: previousSemanticComparisonTokens,
                    classifiedTokens: classifiedTokens,
                    baseRefreshRange: syntacticRefreshRange,
                    sourceUTF16Length: nextSourceLength,
                    comparisonRange: semanticOverlayRefreshRange
                )
                if semanticDiffRefreshRange.length >= nextSourceLength,
                   syntacticRefreshRange.length < nextSourceLength {
                    return syntacticRefreshRange
                }
                return semanticDiffRefreshRange
            }()
            let semanticMaterializationRange = semanticOverlayRefreshRange.map {
                SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: nextSourceLength)
            } ?? resultRefreshRange
            let classifiedCoverageRange = Self.highlightCoverageRange(
                queryRange: semanticMaterializationRange,
                replacementTokens: classifiedTokens,
                sourceUTF16Length: nextSourceLength
            )
            let storePatchRange = Self.union(semanticMaterializationRange, classifiedCoverageRange)
            tokenStore.replaceTokens(
                in: storePatchRange,
                with: classifiedTokens,
                lineIndex: lineIndex,
                quality: .accurate
            )
        }

        source = nextSource
        layeredSource = nextLayeredSource

        return SyntaxHighlightResult(
            tokens: tokenStore.tokens(in: resultRefreshRange, lineIndex: lineIndex),
            source: nextSource,
            language: language,
            revision: revision,
            refreshRange: resultRefreshRange,
            tokenPayload: .replacement
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
        tokenPayload: SyntaxHighlightTokenPayload = .fullSnapshot,
        emitFastPass: ((SyntaxHighlightResult) -> Void)?
    ) {
        guard usesDeferredSemanticHighlighting, let emitFastPass else { return }
        emitFastPass(
            SyntaxHighlightResult(
                tokens: resultTokens(
                    from: tokens,
                    refreshRange: refreshRange,
                    tokenPayload: tokenPayload
                ),
                source: source,
                language: language,
                revision: revision,
                refreshRange: refreshRange,
                phase: .syntacticFastPass,
                tokenPayload: tokenPayload
            )
        )
    }

    func resultTokens(
        from tokens: [SyntaxHighlightToken],
        refreshRange: NSRange,
        tokenPayload: SyntaxHighlightTokenPayload
    ) -> [SyntaxHighlightToken] {
        switch tokenPayload {
        case .fullSnapshot:
            tokens
        case .replacement:
            Self.tokensIntersecting(refreshRange, in: tokens)
        }
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

    func cancelledUpdateResult(revision: Int) -> SyntaxHighlightResult {
        SyntaxHighlightResult(
            tokens: tokenStore.tokens(lineIndex: lineIndex),
            source: source,
            language: language,
            revision: revision,
            refreshRange: NSRange(location: 0, length: 0)
        )
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

    static func prefixMaxUpperBounds(for tokens: [SyntaxHighlightToken]) -> [Int] {
        var maxUpperBound = 0
        var prefix: [Int] = []
        prefix.reserveCapacity(tokens.count)
        for token in tokens {
            maxUpperBound = max(maxUpperBound, token.range.upperBound)
            prefix.append(maxUpperBound)
        }
        return prefix
    }

    func semanticClassifiedTokensIfNeeded(
        _ tokens: [SyntaxHighlightToken],
        source: String,
        rootNode: Node? = nil,
        refreshRange: NSRange? = nil,
        mutation: SyntaxHighlightMutation? = nil,
        tokenPrefixMaxUpperBounds: [Int]? = nil
    ) -> SemanticClassificationResult {
        switch language {
        case .swift:
            let result = SwiftSyntaxOverlayTokenProvider.mergingOverlayResult(
                tokens: tokens,
                source: source,
                rootNode: rootNode,
                refreshRange: refreshRange,
                mutation: mutation,
                tokenPrefixMaxUpperBounds: tokenPrefixMaxUpperBounds,
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
                mutation: mutation,
                tokenPrefixMaxUpperBounds: tokenPrefixMaxUpperBounds,
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
        refreshRange: NSRange,
        mutation: SyntaxHighlightMutation? = nil
    ) -> NSRange? {
        let nsSource = source as NSString
        switch language {
        case .swift:
            return SwiftSyntaxOverlayTokenProvider.semanticTargetRange(
                refreshRange,
                in: nsSource,
                mutation: mutation
            )
        case .objectiveC:
            return ObjectiveCSyntaxOverlayTokenProvider.semanticTargetRange(
                refreshRange,
                in: nsSource,
                mutation: mutation
            )
        default:
            return nil
        }
    }

    static func editMaterializationRange(
        mutation: SyntaxHighlightMutation,
        sourceUTF16Length: Int
    ) -> NSRange {
        let replacementLength = mutation.replacement.utf16.count
        let location = min(max(0, mutation.location), sourceUTF16Length)
        let materializationLength = max(1, replacementLength + 1)
        let upperBound = min(sourceUTF16Length, location + materializationLength)
        return NSRange(location: location, length: max(0, upperBound - location))
    }

    static func mutationDeletesSemanticStructuralText(
        _ mutation: SyntaxHighlightMutation,
        previousSource: String,
        language: SyntaxLanguage
    ) -> Bool {
        guard mutation.length > 0 else { return false }
        let structuralCharacters: CharacterSet
        switch language {
        case .objectiveC:
            structuralCharacters = CharacterSet(charactersIn: "#@{}")
        default:
            return false
        }

        let previousSource = previousSource as NSString
        guard mutation.location >= 0,
              mutation.location + mutation.length <= previousSource.length else {
            return true
        }
        let deletedText = previousSource.substring(
            with: NSRange(location: mutation.location, length: mutation.length)
        )
        return deletedText.rangeOfCharacter(from: structuralCharacters) != nil
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
        sourceUTF16Length: Int,
        comparisonRange: NSRange? = nil
    ) -> NSRange {
        switch language {
        case .swift, .objectiveC, .css, .html:
            Self.refreshRangeIncludingTokenChanges(
                from: previousTokens,
                to: classifiedTokens,
                baseRefreshRange: baseRefreshRange,
                sourceUTF16Length: sourceUTF16Length,
                comparisonRange: comparisonRange
            )
        default:
            baseRefreshRange
        }
    }

    static func refreshRangeIncludingTokenChanges(
        from previousTokens: [SyntaxHighlightToken],
        to classifiedTokens: [SyntaxHighlightToken],
        baseRefreshRange: NSRange,
        sourceUTF16Length: Int,
        comparisonRange: NSRange? = nil
    ) -> NSRange {
        let comparisonRange = comparisonRange.map {
            SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: sourceUTF16Length)
        }
        let previousTokensInScope = comparisonRange.map {
            tokensIntersecting($0, in: previousTokens)
        } ?? previousTokens
        let classifiedTokensInScope = comparisonRange.map {
            tokensIntersecting($0, in: classifiedTokens)
        } ?? classifiedTokens
        let previousKeys = Set(previousTokensInScope.map(SyntaxHighlightTokenKey.init))
        let classifiedKeys = Set(classifiedTokensInScope.map(SyntaxHighlightTokenKey.init))
        var refreshRange = SyntaxEditorRangeUtilities.clampedRange(
            baseRefreshRange,
            utf16Length: sourceUTF16Length
        )

        for token in previousTokensInScope where !classifiedKeys.contains(SyntaxHighlightTokenKey(token)) {
            refreshRange = union(
                refreshRange,
                SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: sourceUTF16Length)
            )
        }
        for token in classifiedTokensInScope where !previousKeys.contains(SyntaxHighlightTokenKey(token)) {
            refreshRange = union(
                refreshRange,
                SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: sourceUTF16Length)
            )
        }

        return SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: sourceUTF16Length)
    }

    static func tokensIntersecting(
        _ range: NSRange,
        in tokens: [SyntaxHighlightToken]
    ) -> [SyntaxHighlightToken] {
        guard range.length > 0, !tokens.isEmpty else { return [] }
        var startIndex = lowerBoundForTokenLocation(range.location, in: tokens)
        while startIndex > 0, tokens[startIndex - 1].range.upperBound > range.location {
            startIndex -= 1
        }
        var result: [SyntaxHighlightToken] = []
        result.reserveCapacity(min(tokens.count - startIndex, 128))

        for token in tokens[startIndex...] {
            guard token.range.location < range.upperBound else { break }
            guard SyntaxEditorRangeUtilities.intersection(of: token.range, and: range).length > 0 else {
                continue
            }
            result.append(token)
        }
        return result
    }

    static func lowerBoundForTokenLocation(
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

    static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let lower = min(lhs.location, rhs.location)
        let upper = max(lhs.upperBound, rhs.upperBound)
        return NSRange(location: lower, length: upper - lower)
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

package final class SyntaxHighlightLineIndex {
    private let lineOffsets = LineOffsetTable()

    var lineCount: Int {
        lineOffsets.lineCount
    }

    func reset(source: String) {
        lineOffsets.reset(source: source)
    }

    func apply(mutation: SyntaxHighlightMutation, previousSource: String) {
        guard let affectedRange = affectedRange(for: mutation, in: previousSource) else {
            reset(source: SyntaxEditorModel.applying([
                SyntaxEditorTextEdit(
                    range: NSRange(location: mutation.location, length: mutation.length),
                    replacement: mutation.replacement
                )
            ], to: previousSource))
            return
        }

        let nsSource = previousSource as NSString
        let oldSegment = nsSource.substring(with: affectedRange)
        let newSegment = SyntaxEditorModel.applying([
            SyntaxEditorTextEdit(
                range: NSRange(
                    location: mutation.location - affectedRange.location,
                    length: mutation.length
                ),
                replacement: mutation.replacement
            )
        ], to: oldSegment)
        var replacementLengths = LineOffsetTable.lineLengths(in: newSegment)
        if affectedRange.upperBound < nsSource.length,
           Self.endsWithLineBreak(newSegment),
           replacementLengths.count > 1 {
            replacementLengths.removeLast()
        }
        let startIndex = lineIndex(containingUTF16Offset: affectedRange.location)
        let endIndex = oldLineEndIndex(for: affectedRange, sourceUTF16Length: nsSource.length)
        lineOffsets.replaceLines(in: startIndex..<endIndex, with: replacementLengths)
    }

    func point(at utf16Offset: Int) -> Point {
        let clampedOffset = max(0, utf16Offset)
        let index = lineIndex(containingUTF16Offset: clampedOffset)
        let lineStart = lineOffsets.lineStartOffset(at: index)
        return Point(row: index, column: max(0, clampedOffset - lineStart) * 2)
    }

    func lineRange(containingUTF16Range range: NSRange) -> Range<Int> {
        lineOffsets.lineRange(containingUTF16Range: range)
    }

    func lineStartOffset(at index: Int) -> Int {
        lineOffsets.lineStartOffset(at: index)
    }

    func lineEndOffset(at index: Int) -> Int {
        lineOffsets.lineEndOffset(at: index)
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
           endIndex < lineOffsets.lineCount {
            endIndex += 1
        }

        let lower = lineOffsets.lineStartOffset(at: startIndex)
        let upper = endIndex < lineOffsets.lineCount
            ? lineOffsets.lineStartOffset(at: endIndex)
            : nsSource.length
        return NSRange(location: lower, length: upper - lower)
    }

    func lineIndex(containingUTF16Offset offset: Int) -> Int {
        lineOffsets.lineIndex(containingUTF16Offset: offset)
    }

    func oldLineEndIndex(for range: NSRange, sourceUTF16Length: Int) -> Int {
        guard lineOffsets.lineCount > 0 else { return 0 }
        let upperBound = min(sourceUTF16Length, range.upperBound)
        let lookup = range.length == 0
            ? range.location
            : upperBound == sourceUTF16Length
                ? upperBound
                : max(range.location, upperBound - 1)
        return min(lineOffsets.lineCount, lineIndex(containingUTF16Offset: lookup) + 1)
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
    private var layeredSetupCache: [SyntaxLanguage: CachedHighlightingSetup] = [:]
    private var setupTasks: [SyntaxLanguage: Task<HighlightingSetup?, Never>] = [:]

    func highlightingSetup(for language: SyntaxLanguage) async -> HighlightingSetup? {
        if let cached = layeredSetupCache[language] {
            return cached.setup
        }

        if let task = setupTasks[language] {
            return await task.value
        }

        let resolver = resolver
        let task = Task.detached {
            HighlightingSetup.resolved(for: language, resolver: resolver)
        }
        setupTasks[language] = task

        let setup = await task.value
        setupTasks[language] = nil
        cache(setup, for: language)
        return setup
    }

    private func cache(_ setup: HighlightingSetup?, for language: SyntaxLanguage) {
        guard let setup else {
            layeredSetupCache[language] = .missing
            return
        }

        layeredSetupCache[language] = .resolved(setup)
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

        guard let support = language.treeSitterSupport else {
            configurations[language] = .missing
            return nil
        }
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
