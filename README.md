# SyntaxEditorUI

`SyntaxEditorUI` is a Swift package for building editable, syntax-highlighted code views on iOS and macOS.
It provides SwiftUI, UIKit, and AppKit entry points with built-in language support, editor shortcuts, and common code-editing behavior.

## Features

- Editable code views for SwiftUI, UIKit, and AppKit apps.
- Syntax highlighting for CSS, HTML, JavaScript, JSON, Objective-C, Swift, TOML, and XML.
- Embedded JavaScript and CSS highlighting inside HTML.
- Code-aware editing behavior:
  - bracket and quote auto-pairing
  - smart newline indentation
  - line indent and outdent
  - comment toggling for supported languages
  - pair-aware backspace deletion
  - matching bracket highlight
- Keyboard shortcuts for common editor actions.
- iOS accessory controls for undo, redo, and keyboard dismissal.
- Programmatic control over text, language, editability, line wrapping, and color theme.

## Shortcuts

- `Tab`: Insert spaces at the caret; indent selected lines
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

### iPad Pointer Input

Apps that use `SyntaxEditorView` on iPadOS should enable `UIApplicationSupportsIndirectInputEvents` in their `Info.plist`. With this key enabled, mouse and trackpad click-drags are handled by UIKit text selection instead of scroll dragging, while finger drag scrolling and trackpad or mouse wheel scrolling continue to work.

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
