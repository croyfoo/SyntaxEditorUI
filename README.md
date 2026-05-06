# SyntaxEditorUI

`SyntaxEditorUI` is a lightweight cross-platform code editor package for iOS/macOS.
Its internal `SyntaxEditorCore` target keeps the non-UI editor model, language definitions, editing logic, and highlighting engine separated from platform UI code.

## Features

- `@Observable` state model (`SyntaxEditorModel`)
- SwiftUI entry point (`SyntaxEditor`)
- UIKit/AppKit native view API (`SyntaxEditorView`)
- UIKit/AppKit controller wrapper API (`SyntaxEditorViewController`)
- protocol-based language definitions (`SyntaxLanguage`)
- tree-sitter based syntax highlighting for:
  - CSS
  - HTML (including embedded JavaScript and CSS highlighting)
  - JavaScript
  - JSON
  - Objective-C
  - Swift
  - TOML
  - XML
- Core editing capabilities:
  - Auto-pair insertion: `() [] {} "" '' ```
  - Smart newline indentation (4 spaces)
  - Line indent / outdent (`Tab`, `Shift-Tab`, `Cmd+]`, `Cmd+[`)
  - Comment toggle (`Cmd+/`) for HTML, JavaScript, CSS, Objective-C, Swift, TOML, and XML
  - JSON comment toggle is intentionally no-op
  - Pair-aware backspace deletion
  - Matching bracket highlight
- iOS input accessory actions: `Undo`, `Redo`, `Dismiss Keyboard`

## Shortcuts

- `Tab`: Indent
- `Shift-Tab`: Outdent
- `Cmd+]`: Indent
- `Cmd+[` : Outdent
- `Cmd+/`: Toggle comment (HTML/JavaScript/CSS/Objective-C/Swift/TOML/XML)
- `Cmd+Z`: Undo
- `Shift+Cmd+Z`: Redo

## Usage

```swift
import SyntaxEditorUI

let model = SyntaxEditorModel(
    text: "const answer = 42;",
    language: BuiltinSyntaxLanguages.javascript
)

let editor = SyntaxEditor(model: model)
let editorView = SyntaxEditorView(model: model)
```

HTML is also available as a builtin language:

```swift
let htmlModel = SyntaxEditorModel(
    text: "<div class=\"message\">Hello</div>",
    language: BuiltinSyntaxLanguages.html
)
```

XML is also available as a builtin language:

```swift
let xmlModel = SyntaxEditorModel(
    text: "<?xml version=\"1.0\"?><note priority=\"high\">Hello</note>",
    language: BuiltinSyntaxLanguages.xml
)
```

Objective-C is also available as a builtin language:

```swift
let objectiveCModel = SyntaxEditorModel(
    text: "#import <Foundation/Foundation.h>\n@interface Example : NSObject\n@end",
    language: BuiltinSyntaxLanguages.objectiveC
)
```

TOML is also available as a builtin language:

```swift
let tomlModel = SyntaxEditorModel(
    text: "[package]\nname = \"SyntaxEditorUI\"\nenabled = true",
    language: BuiltinSyntaxLanguages.toml
)
```

Custom languages can provide both editor rules and highlighting by conforming to `SyntaxLanguage`.

```swift
struct CustomJSONLanguage: SyntaxLanguage {
    var identifier: String { "custom-json" }
    var displayName: String { "Custom JSON" }
    var treeSitterSupport: SyntaxTreeSitterSupport {
        BuiltinSyntaxLanguages.json.treeSitterSupport
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        nil
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        false
    }
}
```

## Testing

```bash
swift test
xcodebuild test -workspace SyntaxEditorUI.xcworkspace -scheme SyntaxEditorUITests -destination 'platform=macOS'
xcodebuild test -workspace SyntaxEditorUI.xcworkspace -scheme SyntaxEditorUITests -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

`Mini` is a lightweight manual verification app for iOS/macOS. It is not a public product and does not own package regression tests.

## Breaking API Notes

- Non-UI implementation moved into the internal `SyntaxEditorCore` target. `SyntaxEditorCore` is not a public package product; clients should keep importing `SyntaxEditorUI` only.
- `SyntaxEditorModel`, `BuiltinSyntaxLanguages`, `SyntaxLanguage`, and related non-UI APIs remain available from `SyntaxEditorUI` via module re-export.
- On iOS, `SyntaxEditorView` is now the single native text input and scroll view. The previous embedded `UITextView` API has been removed.
- On iOS, use `SyntaxEditorView` / `SyntaxEditorViewController.editorView` directly for text, selection, editability, wrapping, and scrolling. `SyntaxEditorView.textView` and `SyntaxEditorViewController.textView` are no longer available.
