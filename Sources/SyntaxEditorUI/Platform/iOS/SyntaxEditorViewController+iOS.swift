#if canImport(UIKit)
import Observation
import ObservationBridge
import SyntaxEditorCore
import UIKit

@MainActor
@Observable
public final class SyntaxEditorViewController: UIViewController {
    public private(set) var document: SyntaxEditorDocument
    public private(set) var configuration: SyntaxEditorConfiguration
    @ObservationIgnored
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
}
#endif
