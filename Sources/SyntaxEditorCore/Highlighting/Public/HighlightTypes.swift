import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

// Public highlighting types and the SyntaxHighlighting protocol, relocated
// verbatim from the previous engine file during the ground-up rebuild. The
// observable contracts (field semantics, phase ordering, payload rules) are
// pinned by the UI layers and the test suite.

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
    /// Viewport hint: progressive opens and background semantic drains process
    /// the chunk nearest this range first. Purely an ordering hint — results
    /// and convergence are identical without it.
    func setVisibleRange(_ range: NSRange?) async
}

package extension SyntaxHighlighting {
    func setVisibleRange(_ range: NSRange?) async {}

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

extension SyntaxHighlightResult {
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
