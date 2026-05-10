import SwiftUI
import SyntaxEditorCore

#if canImport(UIKit)
private struct SyntaxEditorContainer: UIViewRepresentable {
    let document: SyntaxEditorDocument
    let configuration: SyntaxEditorConfiguration

    func makeUIView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(document: document, configuration: configuration)
    }

    func updateUIView(_ uiView: SyntaxEditorView, context: Context) {
        // Document/configuration observation keeps the native view synchronized.
    }
}
#elseif canImport(AppKit)
private struct SyntaxEditorContainer: NSViewRepresentable {
    let document: SyntaxEditorDocument
    let configuration: SyntaxEditorConfiguration

    func makeNSView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(document: document, configuration: configuration)
    }

    func updateNSView(_ nsView: SyntaxEditorView, context: Context) {
        // Document/configuration observation keeps the native view synchronized.
    }
}
#endif

@MainActor
public struct SyntaxEditor: View {
    let document: SyntaxEditorDocument
    let configuration: SyntaxEditorConfiguration

    public init(
        document: SyntaxEditorDocument = SyntaxEditorDocument(),
        configuration: SyntaxEditorConfiguration = SyntaxEditorConfiguration()
    ) {
        self.document = document
        self.configuration = configuration
    }

    public var body: some View {
        SyntaxEditorContainer(document: document, configuration: configuration)
            .id(ObjectIdentifier(document))
    }
}
