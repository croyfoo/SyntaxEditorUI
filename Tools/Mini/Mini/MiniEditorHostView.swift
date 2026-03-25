import SwiftUI
import SyntaxEditorUI

#if canImport(UIKit)
import UIKit

@MainActor
struct MiniEditorHostView: UIViewControllerRepresentable {
    let model: SyntaxEditorModel

    func makeUIViewController(context: Context) -> SyntaxEditorViewController {
        let controller = SyntaxEditorViewController(model: model)
        controller.textView.accessibilityIdentifier = "mini.editor"
        return controller
    }

    func updateUIViewController(_ uiViewController: SyntaxEditorViewController, context: Context) {
        uiViewController.textView.accessibilityIdentifier = "mini.editor"
    }
}
#elseif canImport(AppKit)
import AppKit

@MainActor
struct MiniEditorHostView: NSViewControllerRepresentable {
    let model: SyntaxEditorModel

    func makeNSViewController(context: Context) -> SyntaxEditorViewController {
        let controller = SyntaxEditorViewController(model: model)
        controller.textView.setAccessibilityIdentifier("mini.editor")
        return controller
    }

    func updateNSViewController(_ nsViewController: SyntaxEditorViewController, context: Context) {
        nsViewController.textView.setAccessibilityIdentifier("mini.editor")
    }
}
#endif
