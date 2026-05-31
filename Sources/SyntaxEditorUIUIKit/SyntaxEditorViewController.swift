#if canImport(UIKit)
import SyntaxEditorCore
import UIKit

@MainActor
public final class SyntaxEditorViewController: UIViewController {
    public private(set) var model: SyntaxEditorModel
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

    public func update(model nextModel: SyntaxEditorModel) {
        guard model !== nextModel else { return }

        model = nextModel
        editorView.update(model: nextModel)
    }
}
#endif
