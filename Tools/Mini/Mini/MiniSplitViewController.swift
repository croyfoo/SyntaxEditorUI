import ObservationBridge
import SyntaxEditorUI

#if canImport(UIKit)
import UIKit

@MainActor
final class MiniSplitViewController: UISplitViewController {
    private let model: MiniContentViewModel
    private let presetListViewController: MiniPresetListViewController
    private let configurationObservations = ObservationScope()
    private let editorObservations = ObservationScope()
    private var editorViewController: SyntaxEditorViewController?
    private var detailViewController: MiniEditorContainerViewController?

    init(model: MiniContentViewModel) {
        self.model = model
        self.presetListViewController = MiniPresetListViewController(model: model)

        super.init(style: .doubleColumn)

        preferredSplitBehavior = .tile
        preferredDisplayMode = .oneBesideSecondary
        presentsWithGesture = true

        let sidebarNavigationController = UINavigationController(
            rootViewController: presetListViewController
        )
        setViewController(sidebarNavigationController, for: .primary)
        renderDetail()
        bindModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func bindModel() {
        configurationObservations.update {
            model.observe([\.currentPresetID, \.editorDocument, \.editorConfiguration]) { [weak self] in
                self?.renderDetail()
                self?.bindEditorModel()
            }
            .store(in: configurationObservations)
        }
        bindEditorModel()
    }

    private func bindEditorModel() {
        editorObservations.update {
            model.editorConfiguration.observe(\.lineWrappingEnabled) { [weak self] _ in
                self?.updateOverflowMenu()
            }
            .store(in: editorObservations)
        }
    }

    private func renderDetail() {
        let editorDocument = model.editorDocument
        let editorConfiguration = model.editorConfiguration
        if let currentDocument = editorViewController?.document,
           currentDocument === editorDocument
        {
            detailViewController?.title = model.currentPreset.title
            updateOverflowMenu()
            return
        }

        let editorViewController = SyntaxEditorViewController(
            document: editorDocument,
            configuration: editorConfiguration
        )
        let detailViewController = MiniEditorContainerViewController(
            editorViewController: editorViewController
        )
        detailViewController.title = model.currentPreset.title
        detailViewController.navigationItem.additionalOverflowItems = makeOverflowItems()

        let navigationController = UINavigationController(rootViewController: detailViewController)
        self.editorViewController = editorViewController
        self.detailViewController = detailViewController
        setViewController(navigationController, for: .secondary)
        if isCollapsed {
            show(.secondary)
        }
        updateOverflowMenu()
    }

    private func makeOverflowItems() -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { [weak self] completion in
            Task { @MainActor in
                guard let self else {
                    completion([])
                    return
                }

                let lineWrappingAction = UIAction(
                    title: "Line Wrapping",
                    image: UIImage(systemName: "text.alignleft")
                ) { [weak self] _ in
                    self?.toggleLineWrapping()
                }
                lineWrappingAction.state = self.model.editorConfiguration.lineWrappingEnabled ? .on : .off
                completion([lineWrappingAction])
            }
        }
    }

    private func updateOverflowMenu() {
        detailViewController?.navigationItem.additionalOverflowItems = makeOverflowItems()
    }

    private func toggleLineWrapping() {
        model.editorConfiguration.lineWrappingEnabled.toggle()
    }
}

@MainActor
private final class MiniEditorContainerViewController: UIViewController {
    private let editorViewController: SyntaxEditorViewController

    init(editorViewController: SyntaxEditorViewController) {
        self.editorViewController = editorViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(editorViewController)
        let editorView = editorViewController.view!
        editorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editorView)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
        ])
        editorViewController.didMove(toParent: self)
    }
}
#elseif canImport(AppKit)
import AppKit

@MainActor
final class MiniSplitViewController: NSSplitViewController {
    private let model: MiniContentViewModel
    private let presetListViewController: MiniPresetListViewController
    private let configurationObservations = ObservationScope()
    private var editorViewController: SyntaxEditorViewController?
    private var detailSplitViewItem: NSSplitViewItem?

    init(model: MiniContentViewModel) {
        self.model = model
        self.presetListViewController = MiniPresetListViewController(model: model)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureSplitItems()
        bindModel()
    }

    private func configureSplitItems() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: presetListViewController)
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 260
        sidebarItem.preferredThicknessFraction = 0.22
        sidebarItem.titlebarSeparatorStyle = .none
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)
        renderDetail()
    }

    private func bindModel() {
        configurationObservations.update {
            model.observe([\.currentPresetID, \.editorDocument, \.editorConfiguration]) { [weak self] in
                self?.renderDetail()
            }
            .store(in: configurationObservations)
        }
    }

    private func renderDetail() {
        let editorDocument = model.editorDocument
        let editorConfiguration = model.editorConfiguration
        if let currentDocument = editorViewController?.document,
           currentDocument === editorDocument
        {
            editorViewController?.title = model.currentPreset.title
            return
        }

        if let detailSplitViewItem {
            removeSplitViewItem(detailSplitViewItem)
        }

        let editorViewController = SyntaxEditorViewController(
            document: editorDocument,
            configuration: editorConfiguration
        )
        editorViewController.title = model.currentPreset.title
        editorViewController.scrollView.automaticallyAdjustsContentInsets = true

        let detailItem = NSSplitViewItem(viewController: editorViewController)
        detailItem.minimumThickness = 320
        if #available(macOS 26.0, *) {
            detailItem.automaticallyAdjustsSafeAreaInsets = true
        }
        addSplitViewItem(detailItem)

        self.editorViewController = editorViewController
        self.detailSplitViewItem = detailItem
    }
}
#endif
