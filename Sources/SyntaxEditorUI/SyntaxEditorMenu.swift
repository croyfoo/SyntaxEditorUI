import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
public enum SyntaxEditorMenu {
    private static let editorMenuTitle = "Editor"
}

enum SyntaxEditorMenuCommand: CaseIterable {
    case shiftRight
    case shiftLeft
    case commentSelection
    case increaseFontSize
    case decreaseFontSize
    case resetFontSize
    case wrapLines

    var title: String {
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

    var selector: Selector {
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

    var isEditingCommand: Bool {
        switch self {
        case .shiftRight, .shiftLeft, .commentSelection:
            true
        case .increaseFontSize, .decreaseFontSize, .resetFontSize, .wrapLines:
            false
        }
    }

    init?(selector: Selector?) {
        guard let selector else { return nil }
        guard let command = Self.allCases.first(where: { $0.selector == selector }) else {
            return nil
        }
        self = command
    }
}

#if canImport(UIKit)
extension SyntaxEditorMenu {
    public static let editorMenuIdentifier = UIMenu.Identifier("com.lynnswap.SyntaxEditorUI.editor")

    public static func makeEditorMenu() -> UIMenu {
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

    public static func insertEditorMenu(into builder: any UIMenuBuilder) {
        guard builder.system == UIMenuSystem.main else { return }

        let editorMenu = makeEditorMenu()
        if builder.menu(for: .view) != nil {
            builder.insertSibling(editorMenu, afterMenu: .view)
        } else if builder.menu(for: .window) != nil {
            builder.insertSibling(editorMenu, beforeMenu: .window)
        } else {
            builder.insertChild(editorMenu, atEndOfMenu: .root)
        }
    }

    static func makeKeyCommands(includeEditingCommands: Bool) -> [UIKeyCommand] {
        SyntaxEditorMenuCommand.allCases.compactMap { command in
            guard includeEditingCommands || !command.isEditingCommand else {
                return nil
            }
            return makeKeyCommand(for: command)
        }
    }

    static func makeKeyCommand(for command: SyntaxEditorMenuCommand) -> UIKeyCommand {
        let keyCommand = UIKeyCommand(
            title: command.title,
            image: nil,
            action: command.selector,
            input: command.input,
            modifierFlags: command.modifierFlags
        )
        keyCommand.discoverabilityTitle = command.title
        keyCommand.wantsPriorityOverSystemBehavior = true
        return keyCommand
    }

    private static func makeInlineMenu(children: [UIMenuElement]) -> UIMenu {
        UIMenu(title: "", options: .displayInline, children: children)
    }
}

private extension SyntaxEditorMenuCommand {
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

#if canImport(AppKit)
extension SyntaxEditorMenu {
    private static let editorMenuItemIdentifier = NSUserInterfaceItemIdentifier("com.lynnswap.SyntaxEditorUI.editor")

    public static func makeEditorMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: editorMenuTitle, action: nil, keyEquivalent: "")
        item.identifier = editorMenuItemIdentifier
        item.submenu = makeEditorMenu()
        return item
    }

    public static func insertEditorMenuItem(into mainMenu: NSMenu) {
        let item = makeEditorMenuItem()
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

    private static func makeEditorMenu() -> NSMenu {
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

    static func makeMenuItem(for command: SyntaxEditorMenuCommand) -> NSMenuItem {
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

private extension SyntaxEditorMenuCommand {
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
