import SwiftUI
import SyntaxEditorCore

#if canImport(UIKit)
private struct SyntaxEditorContainer: UIViewRepresentable {
    let model: SyntaxEditorModel

    func makeUIView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(model: model)
    }

    func updateUIView(_ uiView: SyntaxEditorView, context: Context) {
        // Model observation keeps the native view synchronized.
    }
}
#elseif canImport(AppKit)
private struct SyntaxEditorContainer: NSViewRepresentable {
    let model: SyntaxEditorModel

    func makeNSView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(model: model)
    }

    func updateNSView(_ nsView: SyntaxEditorView, context: Context) {
        // Model observation keeps the native view synchronized.
    }
}
#endif

@MainActor
public struct SyntaxEditor: View {
    let model: SyntaxEditorModel

    public init(model: SyntaxEditorModel) {
        self.model = model
    }

    public var body: some View {
        SyntaxEditorContainer(model: model)
            .id(ObjectIdentifier(model))
    }
}
