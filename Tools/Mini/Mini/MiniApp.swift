import SyntaxEditorUI

#if canImport(UIKit)
import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MiniSplitViewController(
            model: MiniContentViewModel(configuration: .current)
        )
        self.window = window
        window.makeKeyAndVisible()
    }
}
#elseif canImport(AppKit)
import AppKit
import ObservationBridge

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MiniWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let windowController = MiniWindowController(
            model: MiniContentViewModel(configuration: .current)
        )
        self.windowController = windowController
        windowController.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class MiniWindowController: NSWindowController, NSToolbarDelegate {
    private let model: MiniContentViewModel
    private let splitViewController: MiniSplitViewController
    private let modelObservations = ObservationScope()
    private let editorObservations = ObservationScope()
    private var lineWrappingButton: NSButton?

    init(model: MiniContentViewModel) {
        self.model = model
        self.splitViewController = MiniSplitViewController(model: model)

        let window = NSWindow(contentViewController: splitViewController)
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = model.currentPreset.title

        super.init(window: window)

        configureToolbar()
        bindModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: .miniToolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window?.toolbar = toolbar
    }

    private func bindModel() {
        modelObservations.update {
            model.observe([\.currentPresetID, \.editorModel]) { [weak self] in
                self?.renderWindowState()
                self?.bindEditorModel()
            }
            .store(in: modelObservations)
        }
        bindEditorModel()
    }

    private func bindEditorModel() {
        editorObservations.update {
            model.editorModel.observe(\.lineWrappingEnabled) { [weak self] _ in
                self?.updateLineWrappingButton()
            }
            .store(in: editorObservations)
        }
    }

    private func renderWindowState() {
        window?.title = model.currentPreset.title
        updateLineWrappingButton()
    }

    private func updateLineWrappingButton() {
        lineWrappingButton?.state = model.editorModel.lineWrappingEnabled ? .on : .off
    }

    @objc private func toggleLineWrapping() {
        model.editorModel.lineWrappingEnabled.toggle()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .lineWrapping]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .lineWrapping]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == .lineWrapping else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Line Wrapping"
        item.paletteLabel = "Line Wrapping"
        item.toolTip = "Line Wrapping"

        let image = NSImage(
            systemSymbolName: "text.alignleft",
            accessibilityDescription: "Line Wrapping"
        ) ?? NSImage()
        let button = NSButton(
            image: image,
            target: self,
            action: #selector(toggleLineWrapping)
        )
        button.setButtonType(.toggle)
        button.bezelStyle = .texturedRounded
        button.setAccessibilityIdentifier("mini.toolbar.lineWrapping")
        item.view = button
        lineWrappingButton = button
        updateLineWrappingButton()
        return item
    }
}

private extension NSToolbar.Identifier {
    static let miniToolbar = NSToolbar.Identifier("MiniToolbar")
}

private extension NSToolbarItem.Identifier {
    static let lineWrapping = NSToolbarItem.Identifier("LineWrapping")
}
#endif
