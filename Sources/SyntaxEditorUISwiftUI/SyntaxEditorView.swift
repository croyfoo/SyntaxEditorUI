import SwiftUI
import SyntaxEditorCore

#if canImport(UIKit)
import SyntaxEditorUIUIKit
#elseif canImport(AppKit)
import SyntaxEditorUIAppKit
#endif

#if canImport(UIKit)
private struct SyntaxEditorContainer: UIViewRepresentable {
    let document: SyntaxEditorDocument
    let configuration: SyntaxEditorConfiguration

    func makeUIView(context: Context) -> SyntaxEditorView {
        SyntaxEditorView(document: document, configuration: configuration)
    }

    func updateUIView(_ uiView: SyntaxEditorView, context: Context) {
        uiView.update(document: document, configuration: configuration)
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
        nsView.update(document: document, configuration: configuration)
    }
}
#endif

@MainActor
public struct SyntaxEditor: View {
    @State private var defaultDocument = SyntaxEditorDocument()
    @State private var defaultConfiguration = SyntaxEditorConfiguration()

    private let providedDocument: SyntaxEditorDocument?
    private let providedConfiguration: SyntaxEditorConfiguration?

    public init() {
        self.providedDocument = nil
        self.providedConfiguration = nil
    }

    public init(document: SyntaxEditorDocument) {
        self.providedDocument = document
        self.providedConfiguration = nil
    }

    public init(configuration: SyntaxEditorConfiguration) {
        self.providedDocument = nil
        self.providedConfiguration = configuration
    }

    public init(
        document: SyntaxEditorDocument,
        configuration: SyntaxEditorConfiguration
    ) {
        self.providedDocument = document
        self.providedConfiguration = configuration
    }

    public var body: some View {
        let document = providedDocument ?? defaultDocument
        let configuration = providedConfiguration ?? defaultConfiguration

        SyntaxEditorContainer(document: document, configuration: configuration)
    }
}
