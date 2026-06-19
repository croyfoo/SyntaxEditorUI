#if canImport(UIKit) && !os(visionOS)
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class SyntaxEditorKeyboardAccessoryModel {
    var isUndoable = false
    var isRedoable = false

    @ObservationIgnored
    private let onUndo: () -> Void
    @ObservationIgnored
    private let onRedo: () -> Void
    @ObservationIgnored
    private let onDismissKeyboard: () -> Void

    init(
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void,
        onDismissKeyboard: @escaping () -> Void
    ) {
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onDismissKeyboard = onDismissKeyboard
    }

    func performUndo() {
        guard isUndoable else { return }
        onUndo()
    }

    func performRedo() {
        guard isRedoable else { return }
        onRedo()
    }

    func dismissKeyboard() {
        onDismissKeyboard()
    }
}

@MainActor
final class SyntaxEditorKeyboardAccessoryView: UIInputView {
    private var hostingController: UIHostingController<SyntaxEditorKeyboardAccessoryContent>?

    init(model: SyntaxEditorKeyboardAccessoryModel) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        allowsSelfSizing = true

        let swiftUIView = SyntaxEditorKeyboardAccessoryContent(model: model)
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        self.hostingController = hostingController

        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }
}

private struct SyntaxEditorKeyboardAccessoryContent: View {
    var model: SyntaxEditorKeyboardAccessoryModel

    var body: some View {
        HStack {
            iconButton(
                systemName: "arrow.uturn.backward",
                action: model.performUndo
            )
            .accessibilityLabel("Undo")
            .disabled(!model.isUndoable)
            iconButton(
                systemName: "arrow.uturn.forward",
                action: model.performRedo
            )
            .accessibilityLabel("Redo")
            .disabled(!model.isRedoable)
            Spacer(minLength: 0)
            iconButton(
                systemName: "chevron.down",
                action: model.dismissKeyboard
            )
            .accessibilityLabel("Dismiss Keyboard")
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 8)
    }
    @ViewBuilder
    private func iconButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                Image(systemName: systemName)
            }
        }
        .tint(.primary)
        .buttonBorderShape(.capsule)
        .buttonStyle(.borderless)
    }
}

#if DEBUG
#Preview("Keyboard Accessory (Focused UIKit)") {
    SyntaxEditorKeyboardAccessoryPreviewViewController()
}

@MainActor
private final class SyntaxEditorKeyboardAccessoryPreviewViewController: UIViewController {
    private let textField = UITextField(frame: .zero)
    private let accessoryModel = SyntaxEditorKeyboardAccessoryModel(
        onUndo: {},
        onRedo: {},
        onDismissKeyboard: {}
    )
    private var didFocusOnce = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        accessoryModel.isUndoable = true
        accessoryModel.isRedoable = false

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .roundedRect
        textField.placeholder = "Type something"
        textField.inputAccessoryView = SyntaxEditorKeyboardAccessoryView(model: accessoryModel)
        view.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            textField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didFocusOnce else { return }
        didFocusOnce = true
        textField.becomeFirstResponder()
    }
}
#endif
#endif
