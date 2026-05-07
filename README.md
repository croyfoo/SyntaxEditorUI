# SyntaxEditorUI

`SyntaxEditorUI` is a lightweight cross-platform code editor package for iOS/macOS.
Its internal `SyntaxEditorCore` target keeps the non-UI editor model, language definitions, editing logic, and highlighting engine separated from platform UI code.

## Features

- `@Observable` state model (`SyntaxEditorModel`)
- SwiftUI entry point (`SyntaxEditor`)
- UIKit/AppKit native view API (`SyntaxEditorView`)
- UIKit/AppKit controller wrapper API (`SyntaxEditorViewController`)
- concrete language selection (`SyntaxLanguage`)
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
    language: .javascript
)

let editor = SyntaxEditor(model: model)
let editorView = SyntaxEditorView(model: model)
```

Supported languages are available through `SyntaxLanguage`: CSS, HTML, JavaScript, JSON, Objective-C, Swift, TOML, and XML.

## Testing

```bash
swift test
xcrun simctl list devices available
DESTINATION='platform=iOS Simulator,id=<simulator-udid>'
xcodebuild test -workspace SyntaxEditorUI.xcworkspace -scheme SyntaxEditorUITests -testPlan SyntaxEditorUITests -only-testing:SyntaxEditorCorePlatformTests -only-testing:SyntaxEditorUITests -destination "$DESTINATION" -enableCodeCoverage NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1
```

GitHub Actions runs `swift test` on macOS for package-wide coverage, then runs `SyntaxEditorCorePlatformTests` and `SyntaxEditorUITests` on the latest available iOS simulator for UIKit-specific coverage.

`Mini` is a lightweight manual verification app for iOS/macOS. It is not a public product and does not own package regression tests.

## Migration

### v0.5.0

These notes apply when upgrading from `v0.4.x` or earlier to `v0.5.0`.

- Starting with `v0.5.0`, non-UI implementation has moved into the internal `SyntaxEditorCore` target. `SyntaxEditorCore` is not a public package product; clients should keep importing `SyntaxEditorUI` only.
- `SyntaxEditorModel`, `SyntaxLanguage`, and related non-UI APIs remain available from `SyntaxEditorUI` via module re-export.
- `SyntaxLanguage` is now a concrete enum of supported languages. Use `SyntaxLanguage.javascript` or shorthand `.javascript` instead of `BuiltinSyntaxLanguages.javascript`.
- `BuiltinSyntaxLanguages` has been removed without a compatibility shim.
- Custom `SyntaxLanguage` conformers are no longer supported. `SyntaxTreeSitterSupport`, custom query directories, and custom highlight cache keys are no longer public API.
- HTML embedded JavaScript/CSS highlighting remains supported through `SyntaxLanguage.html`.
- Up to `v0.4.x` on iOS, `SyntaxEditorView` embedded a `UITextView` that was exposed through `SyntaxEditorView.textView` and `SyntaxEditorViewController.textView`.
- Starting with `v0.5.0` on iOS, `SyntaxEditorView` is the single native text input and scroll view. Use `SyntaxEditorView` / `SyntaxEditorViewController.editorView` directly for text, selection, editability, wrapping, and scrolling.
