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
        configuration.sceneClass = UIWindowScene.self
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
    private static var sharedDelegate: AppDelegate?
    private var windowController: MiniWindowController?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        sharedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStandardMainMenuIfNeeded()

        let windowController = MiniWindowController(
            model: MiniContentViewModel(configuration: .current)
        )
        self.windowController = windowController
        windowController.showWindow(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installStandardMainMenuIfNeeded() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName

        let mainMenu = NSMenu(title: "Main Menu")

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(
            withTitle: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let deleteItem = NSMenuItem(
            title: "Delete",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSDeleteCharacter)!))
        )
        deleteItem.keyEquivalentModifierMask = []
        editMenu.addItem(deleteItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(textFinderMenuItem(title: "Find...", finderAction: .showFindInterface, keyEquivalent: "f"))
        findMenu.addItem(
            textFinderMenuItem(
                title: "Find and Replace...",
                finderAction: .showReplaceInterface,
                keyEquivalent: "f",
                modifiers: [.command, .option]
            )
        )
        findMenu.addItem(.separator())
        findMenu.addItem(textFinderMenuItem(title: "Find Next", finderAction: .nextMatch, keyEquivalent: "g"))
        findMenu.addItem(
            textFinderMenuItem(
                title: "Find Previous",
                finderAction: .previousMatch,
                keyEquivalent: "g",
                modifiers: [.command, .shift]
            )
        )
        findMenu.addItem(
            textFinderMenuItem(title: "Use Selection for Find", finderAction: .setSearchString, keyEquivalent: "e")
        )
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.servicesMenu = servicesMenu
        NSApp.windowsMenu = windowMenu
    }

    private func textFinderMenuItem(
        title: String,
        finderAction: NSTextFinder.Action,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(NSResponder.performTextFinderAction(_:)),
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = modifiers
        item.tag = finderAction.rawValue
        return item
    }
}

@MainActor
final class MiniWindowController: NSWindowController, NSToolbarDelegate {
    private let model: MiniContentViewModel
    private let splitViewController: MiniSplitViewController
    private let modelObservations = ObservationScope()
    private let editorObservations = ObservationScope()
    private var lineWrappingItem: NSToolbarItemGroup?

    init(model: MiniContentViewModel) {
        self.model = model
        self.splitViewController = MiniSplitViewController(model: model)

        let window = NSWindow(contentViewController: splitViewController)
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.minSize = NSSize(width: 760, height: 480)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .automatic
//        window.titleVisibility = .hidden
//        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.title = model.currentPreset.title
        window.center()

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
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
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
                self?.updateLineWrappingItem()
            }
            .store(in: editorObservations)
        }
    }

    private func renderWindowState() {
        window?.title = model.currentPreset.title
        updateLineWrappingItem()
    }

    private func updateLineWrappingItem() {
        lineWrappingItem?.setSelected(model.editorModel.lineWrappingEnabled, at: 0)
    }

    @objc private func toggleLineWrapping() {
        model.editorModel.lineWrappingEnabled.toggle()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace, .lineWrapping]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace, .lineWrapping]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == .sidebarTrackingSeparator {
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitViewController.splitView,
                dividerIndex: 0
            )
        }

        guard itemIdentifier == .lineWrapping else { return nil }

        let image = NSImage(
            systemSymbolName: "text.alignleft",
            accessibilityDescription: "Wrap Lines"
        ) ?? NSImage()
        let item = NSToolbarItemGroup(
            itemIdentifier: itemIdentifier,
            images: [image],
            selectionMode: .selectAny,
            labels: ["Wrap Lines"],
            target: self,
            action: #selector(toggleLineWrapping)
        )
        item.label = "Wrap Lines"
        item.paletteLabel = "Wrap Lines"
        item.toolTip = "Toggle line wrapping"
        item.controlRepresentation = .expanded
        item.view?.setAccessibilityIdentifier("mini.toolbar.lineWrapping")

        lineWrappingItem = item
        updateLineWrappingItem()
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
