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
        bindModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func bindModel() {
        configurationObservations.observe(model) { [weak self] _, _ in
            self?.renderDetail()
        }
        bindEditorModel()
    }

    private func bindEditorModel() {
        editorObservations.observe(model.editorConfiguration) { [weak self] _, configuration in
            self?.updateOverflowMenu(
                lineWrappingEnabled: configuration.lineWrappingEnabled,
                selectedThemePreset: configuration.colorTheme.preset ?? .default
            )
        }
    }

    private func renderDetail() {
        let editorDocument = model.editorDocument
        let editorConfiguration = model.editorConfiguration
        if let editorViewController {
            editorViewController.update(
                document: editorDocument,
                configuration: editorConfiguration
            )
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

    private func makeOverflowItems(
        lineWrappingEnabled: Bool? = nil,
        selectedThemePreset: SyntaxEditorColorTheme.Preset? = nil
    ) -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { [weak self] completion in
            Task { @MainActor in
                guard let self else {
                    completion([])
                    return
                }

                let lineWrappingEnabled = lineWrappingEnabled
                    ?? self.model.editorConfiguration.lineWrappingEnabled
                let selectedThemePreset = selectedThemePreset ?? self.model.selectedThemePreset
                let lineWrappingAction = UIAction(
                    title: "Line Wrapping",
                    image: UIImage(systemName: "text.alignleft")
                ) { [weak self] _ in
                    self?.toggleLineWrapping()
                }
                lineWrappingAction.state = lineWrappingEnabled ? .on : .off

                let themeActions = SyntaxEditorColorTheme.Preset.allCases.map { preset in
                    let action = UIAction(title: preset.displayName) { [weak self] _ in
                        self?.model.selectedThemePreset = preset
                    }
                    action.state = selectedThemePreset == preset ? .on : .off
                    return action
                }
                let themeMenu = UIMenu(
                    title: "Theme",
                    image: UIImage(systemName: "paintpalette"),
                    children: themeActions
                )

                completion([themeMenu, lineWrappingAction])
            }
        }
    }

    private func updateOverflowMenu(
        lineWrappingEnabled: Bool? = nil,
        selectedThemePreset: SyntaxEditorColorTheme.Preset? = nil
    ) {
        detailViewController?.navigationItem.additionalOverflowItems = makeOverflowItems(
            lineWrappingEnabled: lineWrappingEnabled,
            selectedThemePreset: selectedThemePreset
        )
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
    }

    private func bindModel() {
        configurationObservations.observe(model) { [weak self] _, _ in
            self?.renderDetail()
        }
    }

    private func renderDetail() {
        let editorDocument = model.editorDocument
        let editorConfiguration = model.editorConfiguration
        if let editorViewController {
            editorViewController.update(
                document: editorDocument,
                configuration: editorConfiguration
            )
            editorViewController.title = model.currentPreset.title
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
