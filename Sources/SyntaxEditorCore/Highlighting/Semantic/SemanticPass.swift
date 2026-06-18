import Foundation
import SwiftTreeSitter

/// The per-language semantic seam.
///
/// Stage S1: every language runs the conservative path — `fullMerge` produces
/// the complete merged token list for the whole document (identical to what a
/// fresh full pass yields, so incremental == full holds by construction).
/// Later stages add edit-local planning behind this same seam without touching
/// the engine pipeline.
protocol SemanticPass: AnyObject {
    /// Full-document semantic merge over the current base tokens.
    /// `tokens` is the store's merged materialization (base + stale overlays);
    /// passes strip/replace overlay tokens per their language's rules.
    func fullMerge(
        tokens: [SyntaxEditorHighlighting.Token],
        source: String,
        rootNode: Node?
    ) -> (tokens: [SyntaxEditorHighlighting.Token], isCancelled: Bool)

    /// Drops any cached state (after cancellation or reset).
    func invalidate()

    /// Edit-local planning: validate/maintain the language's semantic state for
    /// the committed edit and bound the reclassification targets. nil means the
    /// pass has no incremental support (the engine runs `fullMerge`).
    func plannedUpdate(
        mutation: SyntaxEditorTextChange.Replacement,
        envelope: NSRange,
        source: String,
        rootNode: Node?
    ) -> SemanticUpdatePlan?

    /// Overlay tokens for one target range (planned path). `baseTokens` are the
    /// store's base-plane tokens intersecting the target.
    func overlayTokens(
        in targetRange: NSRange,
        baseTokens: [SyntaxEditorHighlighting.Token],
        source: String
    ) -> [SyntaxEditorHighlighting.Token]

    /// True when the full-document pass can run as chunked `overlayTokens`
    /// calls over a debt set instead of one monolithic `fullMerge` — the
    /// engine then never blocks its actor for a document-sized pass.
    var supportsChunkedFullPass: Bool { get }

    /// Validates/rebuilds whatever state `overlayTokens` needs for a chunked
    /// full pass over the current text. Returns false when cancelled
    /// mid-build; the engine then leaves convergence to the next update.
    func prepareFullPass(source: String, rootNode: Node?) -> Bool
}

/// Outcome of `plannedUpdate`.
enum SemanticUpdatePlan {
    /// Semantic state survived the edit; only the edit envelope needs overlays.
    case reuse
    /// State updated; the envelope plus these scope-bounded ranges need overlays.
    case targets([NSRange])
    /// The edit's effects are not boundable; run the full-document merge.
    case full
}

extension SemanticPass {
    func plannedUpdate(
        mutation: SyntaxEditorTextChange.Replacement,
        envelope: NSRange,
        source: String,
        rootNode: Node?
    ) -> SemanticUpdatePlan? {
        nil
    }

    func overlayTokens(
        in targetRange: NSRange,
        baseTokens: [SyntaxEditorHighlighting.Token],
        source: String
    ) -> [SyntaxEditorHighlighting.Token] {
        []
    }

    var supportsChunkedFullPass: Bool { false }

    func prepareFullPass(source: String, rootNode: Node?) -> Bool {
        true
    }
}

enum SemanticPassFactory {
    static func make(language: SyntaxLanguage) -> SemanticPass? {
        switch language {
        case .swift:
            return SwiftSemanticPass()
        case .objectiveC:
            return ObjectiveCConservativeSemanticPass()
        case .css:
            return CSSSemanticPass(scanningRangesProvider: nil)
        case .html:
            return CSSSemanticPass(scanningRangesProvider: { source in
                HTMLLanguage.embeddedCSSRawTextRanges(in: source)
            })
        default:
            return nil
        }
    }
}

/// Swift semantic pass on the tree-derived scope index.
///
/// The classification rules (the color specification) live in
/// `SwiftSyntaxOverlayTokenProvider`; this pass owns state and locality:
/// in-place shift + bounded subtree rebuild validate the index per edit, and
/// the declaration diff bounds reclassification to the scopes that actually
/// changed (a declaration's influence cannot exceed its scope).
final class SwiftSemanticPass: SemanticPass {
    private var state: SwiftSemanticOverlayState?

    func fullMerge(
        tokens: [SyntaxEditorHighlighting.Token],
        source: String,
        rootNode: Node?
    ) -> (tokens: [SyntaxEditorHighlighting.Token], isCancelled: Bool) {
        let result = SwiftSyntaxOverlayTokenProvider.mergingOverlayResult(
            tokens: tokens,
            source: source,
            rootNode: rootNode,
            refreshRange: nil,
            state: &state
        )
        return (result.tokens, result.isCancelled)
    }

    func plannedUpdate(
        mutation: SyntaxEditorTextChange.Replacement,
        envelope: NSRange,
        source: String,
        rootNode: Node?
    ) -> SemanticUpdatePlan? {
        // Every .full return discards state: a failed in-place shift leaves the
        // index partially mutated, and a kept-but-stale index would otherwise
        // slip past `prepareFullPass`'s length check on length-neutral edits.
        guard let rootNode else {
            state = nil
            return .full
        }
        let nsSource = source as NSString
        guard nsSource.length > 0 else {
            state = nil
            return .full
        }
        guard let index = state?.scopeIndex,
              index.shiftInPlace(by: mutation, sourceUTF16Length: nsSource.length)
        else {
            state = nil
            return .full
        }
        guard let update = index.applySubtreeUpdate(
            envelope: SyntaxEditorRangeUtilities.clampedRange(envelope, utf16Length: nsSource.length),
            rootNode: rootNode,
            source: nsSource
        ) else {
            // Cancelled mid-maintenance or unsplicable: the shifted index is
            // coordinate-correct but stale in the envelope — discard it.
            state = nil
            return .full
        }
        state = SwiftSemanticOverlayState(scopeIndex: index, indexedSourceUTF16Length: nsSource.length)
        if update.requiresFullPass {
            return .full
        }
        if update.boundedTargets.isEmpty {
            return .reuse
        }
        return .targets(update.boundedTargets)
    }

    func overlayTokens(
        in targetRange: NSRange,
        baseTokens: [SyntaxEditorHighlighting.Token],
        source: String
    ) -> [SyntaxEditorHighlighting.Token] {
        SwiftSyntaxOverlayTokenProvider.overlayTokens(
            in: targetRange,
            baseTokens: baseTokens,
            source: source,
            index: state?.scopeIndex
        )
    }

    var supportsChunkedFullPass: Bool { true }

    /// `.full` plans always discard state (see `plannedUpdate`), so a surviving
    /// index here is the requiresFullPass case — already shifted and rebuilt for
    /// this text. Anything else rebuilds from the current tree; nil = cancelled.
    func prepareFullPass(source: String, rootNode: Node?) -> Bool {
        let nsSource = source as NSString
        guard nsSource.length > 0 else { return false }
        if let existing = state, existing.scopeIndex != nil,
           existing.indexedSourceUTF16Length == nsSource.length {
            return true
        }
        guard let rootNode, let index = SwiftScopeIndex(rootNode: rootNode, source: nsSource) else {
            state = nil
            return false
        }
        state = SwiftSemanticOverlayState(scopeIndex: index, indexedSourceUTF16Length: nsSource.length)
        return true
    }

    func invalidate() {
        state = nil
    }
}

/// Objective-C conservative pass: same shape over the ObjC provider.
final class ObjectiveCConservativeSemanticPass: SemanticPass {
    private var state: ObjectiveCSemanticOverlayState?

    func fullMerge(
        tokens: [SyntaxEditorHighlighting.Token],
        source: String,
        rootNode: Node?
    ) -> (tokens: [SyntaxEditorHighlighting.Token], isCancelled: Bool) {
        let result = ObjectiveCSyntaxOverlayTokenProvider.mergingOverlayResult(
            tokens: tokens,
            source: source,
            rootNode: rootNode,
            refreshRange: nil,
            state: &state
        )
        return (result.tokens, result.isCancelled)
    }

    func invalidate() {
        state = nil
    }
}

/// CSS (and CSS-in-HTML) pass: the provider is pure and stateless; for HTML the
/// scanning ranges are the embedded `<style>` contents of the masked source.
final class CSSSemanticPass: SemanticPass {
    private let scanningRangesProvider: ((String) -> [NSRange])?

    init(scanningRangesProvider: ((String) -> [NSRange])?) {
        self.scanningRangesProvider = scanningRangesProvider
    }

    func fullMerge(
        tokens: [SyntaxEditorHighlighting.Token],
        source: String,
        rootNode: Node?
    ) -> (tokens: [SyntaxEditorHighlighting.Token], isCancelled: Bool) {
        if let scanningRangesProvider {
            return (
                CSSSyntaxOverlayTokenProvider.mergingOverlayTokens(
                    tokens: tokens,
                    source: source,
                    scanningRanges: scanningRangesProvider(source)
                ),
                false
            )
        }
        return (
            CSSSyntaxOverlayTokenProvider.mergingOverlayTokens(tokens: tokens, source: source),
            false
        )
    }

    func invalidate() {}
}
