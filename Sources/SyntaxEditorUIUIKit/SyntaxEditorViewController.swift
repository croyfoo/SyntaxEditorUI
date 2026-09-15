#if canImport(UIKit)
import SyntaxEditorCore
import UIKit

/// A UIKit view controller whose root view is a ``SyntaxEditorView-6lnwr``.
///
/// Use this controller when integrating the editor through view-controller
/// containment. The supplied model remains the document and configuration owner.
@MainActor
public final class SyntaxEditorViewController: UIViewController {
    /// The model currently displayed by the controller's editor.
    ///
    /// Use ``update(model:)`` to switch both the controller and its editor to
    /// another model.
    public private(set) var model: SyntaxEditorModel

    /// The editor installed as the controller's root view.
    public let editorView: SyntaxEditorView

    /// Creates a controller and its editor for the supplied model.
    ///
    /// - Parameter model: The model to display and update through user editing.
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

    /// Switches the controller and its editor to another model instance.
    ///
    /// Passing the current instance has no effect. Switching models clears the
    /// editor's undo history; see ``SyntaxEditorView-6lnwr/update(model:)``.
    ///
    /// - Parameter nextModel: The model to display and observe.
    public func update(model nextModel: SyntaxEditorModel) {
        guard model !== nextModel else { return }

        model = nextModel
        editorView.update(model: nextModel)
    }
}
#endif
