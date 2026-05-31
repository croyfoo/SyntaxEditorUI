#if canImport(UIKit) || canImport(AppKit)
import Foundation
import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
package struct TextRangeConverter {
    private let textContentStorage: NSTextContentStorage
    private let utf16Length: Int

    package init(textContentStorage: NSTextContentStorage, utf16Length: Int) {
        self.textContentStorage = textContentStorage
        self.utf16Length = max(0, utf16Length)
    }

    package func textLocation(forUTF16Offset offset: Int) -> NSTextLocation? {
        let clampedOffset = min(max(0, offset), utf16Length)
        return textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: clampedOffset
        )
    }

    package func utf16Offset(for textLocation: NSTextLocation) -> Int {
        textContentStorage.offset(
            from: textContentStorage.documentRange.location,
            to: textLocation
        )
    }

    package func textRange(forUTF16Range range: NSRange) -> NSTextRange? {
        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: utf16Length)
        guard let startLocation = textLocation(forUTF16Offset: clampedRange.location),
              let endLocation = textLocation(forUTF16Offset: clampedRange.location + clampedRange.length)
        else {
            return nil
        }
        return NSTextRange(location: startLocation, end: endLocation)
    }

    package func utf16Range(for textRange: NSTextRange) -> NSRange {
        let location = utf16Offset(for: textRange.location)
        let length = textContentStorage.offset(
            from: textRange.location,
            to: textRange.endLocation
        )
        return NSRange(location: location, length: max(0, length))
    }

    package func utf16Range(for layoutFragment: NSTextLayoutFragment) -> NSRange {
        let location = utf16Offset(for: layoutFragment.rangeInElement.location)
        let endLocation = utf16Offset(for: layoutFragment.rangeInElement.endLocation)
        return NSRange(location: location, length: max(0, endLocation - location))
    }
}
#endif
