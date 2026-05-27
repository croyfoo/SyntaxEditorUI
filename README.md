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
- Programmatic control over text, language, editability, line wrapping, color theme, font size, and background drawing.

## Shortcuts

- `Tab`: Insert spaces at the caret; indent selected lines
- `Shift-Tab`: Outdent
- `Cmd+]`: Indent
- `Cmd+[` : Outdent
- `Cmd+/`: Toggle comment (HTML/JavaScript/CSS/Objective-C/Swift/TOML/XML)
- `Ctrl+Shift+Cmd+L`: Toggle line wrapping
- `Cmd++`: Increase font size
- `Cmd+-`: Decrease font size
- `Ctrl+Cmd+0`: Reset font size
- `Cmd+Z`: Undo
- `Shift+Cmd+Z`: Redo
- `Cmd+F`: Find
- `Cmd+G`: Find next
- `Shift+Cmd+G`: Find previous

## Usage

```swift
import SyntaxEditorUI

let document = SyntaxEditorDocument(text: "const answer = 42;")
let configuration = SyntaxEditorConfiguration(
    language: .javascript
)

let editor = SyntaxEditor(document: document, configuration: configuration)
let editorView = SyntaxEditorView(document: document, configuration: configuration)
```

Supported languages are available through `SyntaxLanguage`: CSS, HTML, JavaScript, JSON, Objective-C, Swift, TOML, and XML.

Set `configuration.drawsBackground = false` when the surrounding view should provide the editor background while syntax colors and editor decorations remain active. Use `configuration.fontSizeDelta`, `increaseFontSize()`, `decreaseFontSize()`, and `resetFontSize()` for Xcode-style point-size adjustments relative to the selected theme.

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

### Next

- `SyntaxEditorView.font` has been removed from the public iOS API. Use `SyntaxEditorConfiguration.fontSizeDelta` or the font-size command methods to adjust editor text size.

### v0.8.0

These notes apply when upgrading from `v0.7.x` or earlier to `v0.8.0`.

- `SyntaxEditorColorTheme.xcode` has been removed. Use `SyntaxEditorColorTheme.default`, shorthand `.default`, or `SyntaxEditorColorTheme.preset(_:)` instead.
- `SyntaxEditorColorTheme.id` is now a `String` instead of a `UUID`. If your app stores or compares theme IDs, migrate those values to strings.

### v0.7.0

These notes apply when upgrading from `v0.6.x` or earlier to `v0.7.0`.

- `SyntaxEditorModel` has been replaced by separate `SyntaxEditorDocument` and `SyntaxEditorConfiguration` objects.
- Store editor text in `SyntaxEditorDocument`. Read the current text with `textSnapshot()` and replace it with `replaceText(_:selectedRange:)`.
- Store editor settings in `SyntaxEditorConfiguration`: `language`, `isEditable`, `lineWrappingEnabled`, and `colorTheme`.
- Replace `SyntaxEditor(model:)` with `SyntaxEditor(document:configuration:)`. `SyntaxEditor()` is also available when the default document and configuration are enough.
- Replace `SyntaxEditorView(model:)` and `SyntaxEditorViewController(model:)` with `SyntaxEditorView(document:configuration:)` and `SyntaxEditorViewController(document:configuration:)`.
- If your app observed `SyntaxEditorModel`, observe `SyntaxEditorDocument` for text changes and `SyntaxEditorConfiguration` for configuration changes. `SyntaxEditorDocument` exposes `revision` and `latestChange` for tracking committed edits.
- `SyntaxEditorModel` and the model-based initializers have been removed without a compatibility shim.

### v0.5.0

These notes apply when upgrading from `v0.4.x` or earlier to `v0.5.0`.

- Starting with `v0.5.0`, non-UI implementation has moved into the internal `SyntaxEditorCore` target. `SyntaxEditorCore` is not a public package product; clients should keep importing `SyntaxEditorUI` only.
- In `v0.5.0`, `SyntaxEditorModel`, `SyntaxLanguage`, and related non-UI APIs remained available from `SyntaxEditorUI` via module re-export. `SyntaxEditorModel` was removed in `v0.7.0`; see the `v0.7.0` notes above.
- `SyntaxLanguage` is now a concrete enum of supported languages. Use `SyntaxLanguage.javascript` or shorthand `.javascript` instead of `BuiltinSyntaxLanguages.javascript`.
- `BuiltinSyntaxLanguages` has been removed without a compatibility shim.
- Custom `SyntaxLanguage` conformers are no longer supported. `SyntaxTreeSitterSupport`, custom query directories, and custom highlight cache keys are no longer public API.
- HTML embedded JavaScript/CSS highlighting remains supported through `SyntaxLanguage.html`.
- Up to `v0.4.x` on iOS, `SyntaxEditorView` embedded a `UITextView` that was exposed through `SyntaxEditorView.textView` and `SyntaxEditorViewController.textView`.
- Starting with `v0.5.0` on iOS, `SyntaxEditorView` is the single native text input and scroll view. Use `SyntaxEditorView` / `SyntaxEditorViewController.editorView` directly for text, selection, editability, wrapping, and scrolling.
