import SwiftUI
import SyntaxEditorCore

#if canImport(UIKit)
import SyntaxEditorUIUIKit
#elseif canImport(AppKit)
import SyntaxEditorUIAppKit
#endif

#if canImport(UIKit)
private struct SyntaxEditorContainer: UIViewRepresentable {
    let model: SyntaxEditorModel

    func makeUIView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(model: model)
    }

    func updateUIView(_ uiView: SyntaxEditorView, context: Context) {
        uiView.update(model: model)
    }
}
#elseif canImport(AppKit)
private struct SyntaxEditorContainer: NSViewRepresentable {
    let model: SyntaxEditorModel

    func makeNSView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(model: model)
    }

    func updateNSView(_ nsView: SyntaxEditorView, context: Context) {
        nsView.update(model: model)
    }
}
#endif

@MainActor
public struct SyntaxEditor: View {
    private let model: SyntaxEditorModel

    public init(_ model: SyntaxEditorModel) {
        self.model = model
    }

    public var body: some View {
        SyntaxEditorContainer(model: model)
    }
}
