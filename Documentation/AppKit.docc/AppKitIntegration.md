# Integrating with AppKit

Host the editor in a macOS window or view-controller hierarchy.

## Create a native editor

```swift
import AppKit
import SyntaxEditorUI

@MainActor
func makeEditor() -> SyntaxEditorViewController {
    let model = SyntaxEditorModel(
        text: "let answer = 42",
        language: .swift
    )
    return SyntaxEditorViewController(model: model)
}
```

Use the controller as a window's content controller or embed it in your app's existing container. Its `editorView` is also the scroll view. If your container already owns a view controller, create ``SyntaxEditorView`` directly.

Keep document state in ``SyntaxEditorModel``. The editor uses TextKit 2 and does not expose an underlying `NSTextView`.

## Add an Editor menu

Insert the editor commands after your application has created its main menu:

```swift
if let mainMenu = NSApp.mainMenu {
    SyntaxEditorMenu.insert(into: mainMenu)
}
```

The commands follow the responder chain to the focused editor. See <doc:Editing> for the shortcuts and ``SyntaxEditorMenu`` for menu construction.

## Find and replace

The editor supports the standard Find commands and an AppKit find bar. Use `Cmd+F` to show Find, `Cmd+G` for the next match, and `Shift+Cmd+G` for the previous match. Editing and replacement remain subject to the model's `isEditable` setting.
