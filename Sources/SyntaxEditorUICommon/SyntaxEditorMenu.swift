import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Creates and installs an Editor menu for the focused syntax editor.
///
/// The menu provides indentation, comment toggling, font-size adjustment, and
/// line-wrapping commands. Actions are routed through the platform's responder
/// chain, so the active editor determines their availability and state.
///
/// UIKit apps install the menu through a `UIMenuBuilder` for the main menu
/// system. AppKit apps insert it into their application menu bar's `NSMenu`.
@MainActor
public enum SyntaxEditorMenu {
    private static let editorMenuTitle = "Editor"
}

extension SyntaxEditorMenu {
package enum Command: CaseIterable {
    case shiftRight
    case shiftLeft
    case commentSelection
    case increaseFontSize
    case decreaseFontSize
    case resetFontSize
    case wrapLines

    package var title: String {
        switch self {
        case .shiftRight:
            "Shift Right"
        case .shiftLeft:
            "Shift Left"
        case .commentSelection:
            "Comment Selection"
        case .increaseFontSize:
            "Increase"
        case .decreaseFontSize:
            "Decrease"
        case .resetFontSize:
            "Reset"
        case .wrapLines:
            "Wrap Lines"
        }
    }

    package var selector: Selector {
        switch self {
        case .shiftRight:
            NSSelectorFromString("syntaxEditorShiftRight:")
        case .shiftLeft:
            NSSelectorFromString("syntaxEditorShiftLeft:")
        case .commentSelection:
            NSSelectorFromString("syntaxEditorCommentSelection:")
        case .increaseFontSize:
            NSSelectorFromString("syntaxEditorIncreaseFontSize:")
        case .decreaseFontSize:
            NSSelectorFromString("syntaxEditorDecreaseFontSize:")
        case .resetFontSize:
            NSSelectorFromString("syntaxEditorResetFontSize:")
        case .wrapLines:
            NSSelectorFromString("syntaxEditorToggleLineWrapping:")
        }
    }

    package var isEditingCommand: Bool {
        switch self {
        case .shiftRight, .shiftLeft, .commentSelection:
            true
        case .increaseFontSize, .decreaseFontSize, .resetFontSize, .wrapLines:
            false
        }
    }

    package init?(selector: Selector?) {
        guard let selector else { return nil }
        guard let command = Self.allCases.first(where: { $0.selector == selector }) else {
            return nil
        }
        self = command
    }
}
}

#if canImport(UIKit)
extension SyntaxEditorMenu {
    /// The identifier assigned to the UIKit Editor menu.
    public static let editorMenuIdentifier = UIMenu.Identifier("com.lynnswap.SyntaxEditorUI.editor")

    /// Creates a UIKit Editor menu with commands for the responder chain.
    ///
    /// - Returns: A new menu with ``editorMenuIdentifier``. Creating the menu
    ///   does not install it in a menu system.
    public static func makeMenu() -> UIMenu {
        UIMenu(
            title: editorMenuTitle,
            identifier: editorMenuIdentifier,
            children: [
                UIMenu(
                    title: "Structure",
                    children: [
                        makeInlineMenu(children: [
                            makeKeyCommand(for: .shiftRight),
                            makeKeyCommand(for: .shiftLeft),
                        ]),
                        makeInlineMenu(children: [
                            makeKeyCommand(for: .commentSelection),
                        ]),
                    ]
                ),
                UIMenu(
                    title: "Font Size",
                    children: [
                        makeInlineMenu(children: [
                            makeKeyCommand(for: .increaseFontSize),
                            makeKeyCommand(for: .decreaseFontSize),
                        ]),
                        makeInlineMenu(children: [
                            makeKeyCommand(for: .resetFontSize),
                        ]),
                    ]
                ),
                makeKeyCommand(for: .wrapLines),
            ]
        )
    }

    /// Adds the Editor menu while the app's main menu is being built.
    ///
    /// The menu is inserted after View, before Window if View is absent, or at
    /// the end of the root menu when neither exists. Builders for other menu
    /// systems are left unchanged.
    ///
    /// - Parameter builder: The builder supplied by the app's menu configuration.
    public static func insert(into builder: any UIMenuBuilder) {
        guard builder.system == UIMenuSystem.main else { return }

        let editorMenu = makeMenu()
        if builder.menu(for: .view) != nil {
            builder.insertSibling(editorMenu, afterMenu: .view)
        } else if builder.menu(for: .window) != nil {
            builder.insertSibling(editorMenu, beforeMenu: .window)
        } else {
            builder.insertChild(editorMenu, atEndOfMenu: .root)
        }
    }

    package static func makeKeyCommands(includeEditingCommands: Bool) -> [UIKeyCommand] {
        SyntaxEditorMenu.Command.allCases.compactMap { command in
            guard includeEditingCommands || !command.isEditingCommand else {
                return nil
            }
            return makeKeyCommand(for: command)
        }
    }

    package static func makeKeyCommand(for command: SyntaxEditorMenu.Command) -> UIKeyCommand {
        let keyCommand = UIKeyCommand(
            title: command.title,
            image: nil,
            action: command.selector,
            input: command.input,
            modifierFlags: command.modifierFlags,
            propertyList: nil
        )
        keyCommand.discoverabilityTitle = command.title
        keyCommand.wantsPriorityOverSystemBehavior = true
        return keyCommand
    }

    private static func makeInlineMenu(children: [UIMenuElement]) -> UIMenu {
        UIMenu(title: "", options: .displayInline, children: children)
    }
}

private extension SyntaxEditorMenu.Command {
    var input: String {
        switch self {
        case .shiftRight:
            "]"
        case .shiftLeft:
            "["
        case .commentSelection:
            "/"
        case .increaseFontSize:
            "+"
        case .decreaseFontSize:
            "-"
        case .resetFontSize:
            "0"
        case .wrapLines:
            "l"
        }
    }

    var modifierFlags: UIKeyModifierFlags {
        switch self {
        case .shiftRight, .shiftLeft, .commentSelection, .increaseFontSize, .decreaseFontSize:
            [.command]
        case .resetFontSize:
            [.control, .command]
        case .wrapLines:
            [.control, .shift, .command]
        }
    }
}
#endif

#if os(macOS) && !targetEnvironment(macCatalyst) && canImport(AppKit)
extension SyntaxEditorMenu {
    private static let editorMenuItemIdentifier = NSUserInterfaceItemIdentifier("com.lynnswap.SyntaxEditorUI.editor")

    private static func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: editorMenuTitle, action: nil, keyEquivalent: "")
        item.identifier = editorMenuItemIdentifier
        item.submenu = makeMenu()
        return item
    }

    /// Installs the Editor menu in an AppKit menu bar.
    ///
    /// An existing menu installed by this method is replaced at the same index.
    /// Otherwise, the menu is inserted after View or Edit, before Window, or at
    /// the end, using the first matching placement in that order.
    ///
    /// - Parameter mainMenu: The application's main menu, typically `NSApp.mainMenu`.
    public static func insert(into mainMenu: NSMenu) {
        let item = makeMenuItem()
        if let existingIndex = mainMenu.items.firstIndex(where: { $0.identifier == editorMenuItemIdentifier }) {
            mainMenu.removeItem(at: existingIndex)
            mainMenu.insertItem(item, at: existingIndex)
            return
        }

        if let viewIndex = mainMenu.items.firstIndex(where: { $0.title == "View" }) {
            mainMenu.insertItem(item, at: viewIndex + 1)
        } else if let editIndex = mainMenu.items.firstIndex(where: { $0.title == "Edit" }) {
            mainMenu.insertItem(item, at: editIndex + 1)
        } else if let windowIndex = mainMenu.items.firstIndex(where: { $0.title == "Window" }) {
            mainMenu.insertItem(item, at: windowIndex)
        } else {
            mainMenu.addItem(item)
        }
    }

    /// Creates an AppKit Editor menu with commands for the responder chain.
    ///
    /// - Returns: A new submenu for an `NSMenuItem`. Creating the menu does not
    ///   install it in the application's menu bar.
    public static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: editorMenuTitle)

        let structureItem = NSMenuItem(title: "Structure", action: nil, keyEquivalent: "")
        let structureMenu = NSMenu(title: "Structure")
        structureMenu.addItem(makeMenuItem(for: .shiftRight))
        structureMenu.addItem(makeMenuItem(for: .shiftLeft))
        structureMenu.addItem(NSMenuItem.separator())
        structureMenu.addItem(makeMenuItem(for: .commentSelection))
        structureItem.submenu = structureMenu
        menu.addItem(structureItem)

        let fontSizeItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        let fontSizeMenu = NSMenu(title: "Font Size")
        fontSizeMenu.addItem(makeMenuItem(for: .increaseFontSize))
        fontSizeMenu.addItem(makeMenuItem(for: .decreaseFontSize))
        fontSizeMenu.addItem(NSMenuItem.separator())
        fontSizeMenu.addItem(makeMenuItem(for: .resetFontSize))
        fontSizeItem.submenu = fontSizeMenu
        menu.addItem(fontSizeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(for: .wrapLines))
        return menu
    }

    package static func makeMenuItem(for command: SyntaxEditorMenu.Command) -> NSMenuItem {
        let item = NSMenuItem(
            title: command.title,
            action: command.selector,
            keyEquivalent: command.keyEquivalent
        )
        item.keyEquivalentModifierMask = command.modifierFlags
        item.target = nil
        return item
    }
}

private extension SyntaxEditorMenu.Command {
    var keyEquivalent: String {
        switch self {
        case .shiftRight:
            "]"
        case .shiftLeft:
            "["
        case .commentSelection:
            "/"
        case .increaseFontSize:
            "+"
        case .decreaseFontSize:
            "-"
        case .resetFontSize:
            "0"
        case .wrapLines:
            "l"
        }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        switch self {
        case .shiftRight, .shiftLeft, .commentSelection, .increaseFontSize, .decreaseFontSize:
            [.command]
        case .resetFontSize:
            [.control, .command]
        case .wrapLines:
            [.control, .shift, .command]
        }
    }
}
#endif
