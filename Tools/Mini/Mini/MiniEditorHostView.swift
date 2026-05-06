import SwiftUI
import SyntaxEditorUI

#if canImport(UIKit)
import UIKit

@MainActor
struct MiniEditorHostView: UIViewRepresentable {
    let model: SyntaxEditorModel

    func makeUIView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(model: model)
    }

    func updateUIView(_ uiView: SyntaxEditorView, context: Context) {
    }
}
#elseif canImport(AppKit)
import AppKit

@MainActor
struct MiniEditorHostView: NSViewRepresentable {
    let model: SyntaxEditorModel

    func makeNSView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(model: model)
    }

    func updateNSView(_ nsView: SyntaxEditorView, context: Context) {
    }
}
#endif
