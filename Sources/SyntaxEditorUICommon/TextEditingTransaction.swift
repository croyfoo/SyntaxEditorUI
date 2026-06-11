#if canImport(UIKit) || canImport(AppKit)
import Foundation
import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
package enum TextEditingTransaction {
    package static func perform(
        on textContentStorage: NSTextContentStorage,
        _ body: (NSTextStorage) -> Void
    ) {
        textContentStorage.performEditingTransaction {
            guard let textStorage = textContentStorage.textStorage else { return }
            body(textStorage)
        }
    }
}
#endif
