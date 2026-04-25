import SwiftUI
import SyntaxEditorUI

#if canImport(UIKit)
import UIKit

@MainActor
struct MiniEditorHostView: UIViewRepresentable {
    let model: SyntaxEditorModel

    func makeUIView(context: Context) -> SyntaxEditorView {
        let editorView = SyntaxEditorView(model: model)
        editorView.accessibilityIdentifier = "mini.editor"
        return editorView
    }

    func updateUIView(_ uiView: SyntaxEditorView, context: Context) {
        uiView.accessibilityIdentifier = "mini.editor"
    }
}
#elseif canImport(AppKit)
import AppKit

@MainActor
struct MiniEditorHostView: NSViewRepresentable {
    let model: SyntaxEditorModel

    func makeNSView(context: Context) -> SyntaxEditorView {
        let editorView = SyntaxEditorView(model: model)
        editorView.textView.setAccessibilityIdentifier("mini.editor")
        return editorView
    }

    func updateNSView(_ nsView: SyntaxEditorView, context: Context) {
        nsView.textView.setAccessibilityIdentifier("mini.editor")
    }
}
#endif
