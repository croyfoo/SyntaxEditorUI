# SyntaxEditorUI

`SyntaxEditorUI` is a lightweight cross-platform code editor package for iOS/macOS.

## Features

- `@Observable` state model (`SyntaxEditorModel`)
- SwiftUI entry point (`SyntaxEditorView`)
- UIKit/AppKit controller API (`SyntaxEditorViewController`)
- protocol-based language definitions (`SyntaxLanguage`)
- tree-sitter based syntax highlighting for:
  - CSS
  - HTML (including embedded JavaScript and CSS highlighting)
  - JavaScript
  - JSON
  - Objective-C
  - Swift
  - XML
- Core editing capabilities:
  - Auto-pair insertion: `() [] {} "" '' ```
  - Smart newline indentation (4 spaces)
  - Line indent / outdent (`Tab`, `Shift-Tab`, `Cmd+]`, `Cmd+[`)
  - Comment toggle (`Cmd+/`) for HTML, JavaScript, CSS, Objective-C, Swift, and XML
  - JSON comment toggle is intentionally no-op
  - Pair-aware backspace deletion
  - Matching bracket highlight
- iOS input accessory actions: `Undo`, `Redo`, `Dismiss Keyboard`

## Shortcuts

- `Tab`: Indent
- `Shift-Tab`: Outdent
- `Cmd+]`: Indent
- `Cmd+[` : Outdent
- `Cmd+/`: Toggle comment (HTML/JavaScript/CSS/Objective-C/Swift/XML)
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
xcodebuild test -workspace SyntaxEditorUI.xcworkspace -scheme SyntaxEditorUITests -destination 'platform=macOS'
xcodebuild test -workspace SyntaxEditorUI.xcworkspace -scheme SyntaxEditorUITests -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
xcodebuild test -workspace SyntaxEditorUI.xcworkspace -scheme MiniUITests -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

`Mini` is a lightweight manual verification app for iOS/macOS and an iOS UITest harness for the editor package. It launches a concrete `SyntaxEditorUI` surface instead of the generated template UI, so it can be used to validate real editor behavior.
