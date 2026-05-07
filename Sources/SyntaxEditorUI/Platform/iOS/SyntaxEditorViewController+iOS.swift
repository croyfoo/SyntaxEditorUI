#if canImport(UIKit)
import Observation
import ObservationBridge
import SyntaxEditorCore
import UIKit

@MainActor
@Observable
public final class SyntaxEditorViewController: UIViewController {
    public private(set) var model: SyntaxEditorModel
    @ObservationIgnored
    public let editorView: SyntaxEditorView

    public init(model: SyntaxEditorModel) {
        self.model = model
        self.editorView = SyntaxEditorView(model: model)

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
