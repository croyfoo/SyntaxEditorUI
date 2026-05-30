#if canImport(UIKit)
import UIKit

@MainActor
struct IOSBracketHighlightRenderer {
    static func apply(
        rects: [CGRect],
        color: CGColor?,
        to fragmentView: SyntaxEditorTextLayoutFragmentView
    ) {
        let colorChanged = !SyntaxEditorView.optionalColorsEqual(fragmentView.bracketHighlightColor, color)
        let rectsChanged = fragmentView.bracketHighlightRects != rects

        fragmentView.bracketHighlightRects = rects
        fragmentView.bracketHighlightColor = color
        if rectsChanged || colorChanged {
            fragmentView.setNeedsDisplay()
        }
    }
}

extension SyntaxEditorView {
    func applyMatchingBracketHighlight(force: Bool = false) {
        let source = text
        let selection = selectedRange

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

        let rangesToInvalidate = matchedBracketRanges + newRanges
        matchedBracketRanges = newRanges
        updateBracketHighlightFragmentViews()
        setNeedsDisplayForBracketHighlightRanges(rangesToInvalidate)
    }

    func clearMatchingBracketHighlight() {
        guard !matchedBracketRanges.isEmpty else { return }

        let rangesToInvalidate = matchedBracketRanges
        matchedBracketRanges = []
        updateBracketHighlightFragmentViews()
        setNeedsDisplayForBracketHighlightRanges(rangesToInvalidate)
    }

    func updateBracketHighlightFragmentViews() {
        for case let fragmentView as SyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            configureBracketHighlights(for: fragmentView, layoutFragmentFrame: fragmentView.layoutFragment.layoutFragmentFrame)
        }
    }

    func configureBracketHighlights(
        for fragmentView: SyntaxEditorTextLayoutFragmentView,
        layoutFragmentFrame: CGRect
    ) {
        let rects: [CGRect]
        if matchedBracketRanges.isEmpty {
            rects = []
        } else {
            let fragmentRange = textRange(for: fragmentView.layoutFragment)
            rects = textHighlightRects(
                in: layoutFragmentFrame,
                ranges: Self.ranges(matchedBracketRanges, intersecting: fragmentRange)
            )
        }
        let color = rects.isEmpty
            ? nil
            : UIColor
                .syntaxEditorAlpha(resolvedColorTheme().bracketBackground, alpha: 0.24)
                .resolvedColor(with: traitCollection)
                .cgColor

        IOSBracketHighlightRenderer.apply(rects: rects, color: color, to: fragmentView)
    }

    func setNeedsDisplayForBracketHighlightRanges(_ ranges: [NSRange]) {
        setNeedsDisplayForTextRanges(ranges)
    }
}
#endif
