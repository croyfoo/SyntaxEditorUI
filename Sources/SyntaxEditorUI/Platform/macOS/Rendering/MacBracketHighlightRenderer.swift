#if canImport(AppKit)
import AppKit

extension SyntaxEditorView {
    func applyMatchingBracketHighlight(force: Bool = false) {
        let source = textView.string
        let selection = textView.selectedRange()

        guard selection.length == 0 else {
            clearMatchingBracketHighlight()
            return
        }

        let newRanges = BracketMatcher.matchedRanges(
            in: source,
            caretUTF16Offset: selection.location
        )

        guard force || newRanges != matchedBracketRanges else {
            return
        }

        let previousRanges = matchedBracketRanges
        let renderer = MacBracketHighlightRenderer(layoutManager: layoutManager, textStorage: textStorage)
        renderer.apply(
            oldRanges: previousRanges,
            newRanges: newRanges,
            color: NSColor.syntaxEditorAlpha(resolvedColorTheme().bracketBackground, alpha: 0.24)
        )
        matchedBracketRanges = newRanges
        renderer.invalidateDisplay(for: previousRanges + newRanges)
    }

    func clearMatchingBracketHighlight() {
        guard !matchedBracketRanges.isEmpty else { return }

        let previousRanges = matchedBracketRanges
        let renderer = MacBracketHighlightRenderer(layoutManager: layoutManager, textStorage: textStorage)
        renderer.clear(ranges: previousRanges)
        matchedBracketRanges = []
        renderer.invalidateDisplay(for: previousRanges)
    }
}
#endif
