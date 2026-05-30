#if canImport(AppKit)
import AppKit
import Foundation

@MainActor
struct MacHighlightRenderer {
    let layoutManager: NSLayoutManager
    let textStorage: NSTextStorage

    func invalidateDisplay(forCharacterRanges ranges: [NSRange]) {
        let textLength = textStorage.length
        guard textLength > 0 else { return }

        for range in ranges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            layoutManager.invalidateDisplay(forCharacterRange: clamped)
        }
    }
}

@MainActor
struct MacBracketHighlightRenderer {
    let layoutManager: NSLayoutManager
    let textStorage: NSTextStorage

    func apply(oldRanges: [NSRange], newRanges: [NSRange], color: NSColor) {
        let textLength = textStorage.length
        guard textLength > 0 else { return }

        for range in oldRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: clamped)
        }

        for range in newRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: color,
                forCharacterRange: clamped
            )
        }
    }

    func clear(ranges: [NSRange]) {
        let textLength = textStorage.length
        guard textLength > 0 else { return }

        for range in ranges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: clamped)
        }
    }

    func invalidateDisplay(for ranges: [NSRange]) {
        MacHighlightRenderer(
            layoutManager: layoutManager,
            textStorage: textStorage
        )
        .invalidateDisplay(forCharacterRanges: ranges)
    }
}
#endif
