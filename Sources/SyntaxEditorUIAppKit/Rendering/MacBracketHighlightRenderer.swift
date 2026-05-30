#if canImport(AppKit)
import AppKit
import SyntaxEditorCore

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
        matchedBracketRanges = newRanges
        textView.updateBracketHighlights(
            ranges: newRanges,
            color: NSColor.syntaxEditorAlpha(resolvedColorTheme().bracketBackground, alpha: 0.24)
        )
        textView.setNeedsDisplayForTextRanges(previousRanges + newRanges)
    }

    func clearMatchingBracketHighlight() {
        guard !matchedBracketRanges.isEmpty else { return }

        let previousRanges = matchedBracketRanges
        matchedBracketRanges = []
        textView.updateBracketHighlights(ranges: [], color: nil)
        textView.setNeedsDisplayForTextRanges(previousRanges)
    }
}
#endif
