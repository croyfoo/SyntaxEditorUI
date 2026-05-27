#if canImport(UIKit)
import SyntaxEditorCore
import UIKit

@MainActor
public final class SyntaxEditorViewController: UIViewController {
    public private(set) var document: SyntaxEditorDocument
    public private(set) var configuration: SyntaxEditorConfiguration
    public let editorView: SyntaxEditorView

    public init(
        document: SyntaxEditorDocument = SyntaxEditorDocument(),
        configuration: SyntaxEditorConfiguration = SyntaxEditorConfiguration()
    ) {
        self.document = document
        self.configuration = configuration
        self.editorView = SyntaxEditorView(document: document, configuration: configuration)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        view = editorView
    }

    public func update(
        document nextDocument: SyntaxEditorDocument,
        configuration nextConfiguration: SyntaxEditorConfiguration
    ) {
        let documentChanged = document !== nextDocument
        let configurationChanged = configuration !== nextConfiguration
        guard documentChanged || configurationChanged else { return }

        document = nextDocument
        configuration = nextConfiguration
        editorView.update(document: nextDocument, configuration: nextConfiguration)
    }
}
#endif
