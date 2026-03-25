# SyntaxEditorUI

`SyntaxEditorUI` is a lightweight cross-platform code editor package for iOS/macOS.

## Features

- `@Observable` state model (`SyntaxEditorModel`)
- SwiftUI entry point (`SyntaxEditorView`)
- UIKit/AppKit controller API (`SyntaxEditorViewController`)
- protocol-based language definitions (`SyntaxLanguage`)
- tree-sitter based syntax highlighting for:
  - CSS
  - JavaScript
  - JSON
  - Swift
- Core editing capabilities:
  - Auto-pair insertion: `() [] {} "" '' ```
  - Smart newline indentation (4 spaces)
  - Line indent / outdent (`Tab`, `Shift-Tab`, `Cmd+]`, `Cmd+[`)
  - Comment toggle (`Cmd+/`) for JavaScript, CSS, and Swift
  - JSON comment toggle is intentionally no-op
  - Pair-aware backspace deletion
  - Matching bracket highlight
- iOS input accessory actions: `Undo`, `Redo`, `Dismiss Keyboard`

## Shortcuts

- `Tab`: Indent
- `Shift-Tab`: Outdent
- `Cmd+]`: Indent
- `Cmd+[` : Outdent
- `Cmd+/`: Toggle comment (JavaScript/CSS/Swift)
- `Cmd+Z`: Undo
- `Shift+Cmd+Z`: Redo

## Usage

```swift
let model = SyntaxEditorModel(
    text: "const answer = 42;",
    language: BuiltinSyntaxLanguages.javascript
)

let view = SyntaxEditorView(model: model)
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
xcodebuild -scheme SyntaxEditorUI -destination 'platform=macOS' test
xcodebuild -scheme SyntaxEditorUI -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' test
xcodebuild build -workspace SyntaxEditorUI.xcworkspace -scheme Mini -destination 'platform=macOS'
xcodebuild test -workspace SyntaxEditorUI.xcworkspace -scheme Mini -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

`Mini` is a lightweight manual verification app for iOS/macOS and an iOS UITest harness for the editor package. It launches a concrete `SyntaxEditorUI` surface instead of the generated template UI, so it can be used to validate real editor behavior.
