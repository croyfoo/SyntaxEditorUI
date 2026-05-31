#if canImport(UIKit) || canImport(AppKit)
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
package final class EditorTextSystem {
    package let textContentStorage: NSTextContentStorage
    package let layoutManager: NSTextLayoutManager
    package let container: NSTextContainer
    package let styleStore: HighlightStyleStore

    package init(
        textContentStorage: NSTextContentStorage = NSTextContentStorage(),
        layoutManager: NSTextLayoutManager = NSTextLayoutManager(),
        container: NSTextContainer = NSTextContainer(),
        styleStore: HighlightStyleStore = HighlightStyleStore()
    ) {
        self.textContentStorage = textContentStorage
        self.layoutManager = layoutManager
        self.container = container
        self.styleStore = styleStore

        layoutManager.textContainer = container
        textContentStorage.addTextLayoutManager(layoutManager)
        textContentStorage.primaryTextLayoutManager = layoutManager
    }

    package var textStorage: NSTextStorage {
        guard let textStorage = textContentStorage.textStorage else {
            fatalError("EditorTextSystem requires NSTextContentStorage-backed NSTextStorage")
        }
        return textStorage
    }

    package var rangeConverter: TextRangeConverter {
        TextRangeConverter(textContentStorage: textContentStorage, utf16Length: textStorage.length)
    }

    package func textLocation(forUTF16Offset offset: Int) -> NSTextLocation? {
        rangeConverter.textLocation(forUTF16Offset: offset)
    }

    package func utf16Offset(for textLocation: NSTextLocation) -> Int {
        rangeConverter.utf16Offset(for: textLocation)
    }

    package func textRange(forUTF16Range range: NSRange) -> NSTextRange? {
        rangeConverter.textRange(forUTF16Range: range)
    }

    package func utf16Range(for textRange: NSTextRange) -> NSRange {
        rangeConverter.utf16Range(for: textRange)
    }

    package func utf16Range(for layoutFragment: NSTextLayoutFragment) -> NSRange {
        rangeConverter.utf16Range(for: layoutFragment)
    }

}
#endif
