# SyntaxEditorUI

`SyntaxEditorUI` is a Swift package for building editable plain-text and syntax-highlighted code views on iOS and macOS.
It provides SwiftUI, UIKit, and AppKit entry points with built-in language support, editor shortcuts, and common code-editing behavior.

## Features

- Editable code views for SwiftUI, UIKit, and AppKit apps.
- Plain Text editing plus syntax highlighting for CSS, HTML, JavaScript, JSON, Objective-C, Swift, TOML, and XML.
- Embedded JavaScript and CSS highlighting inside HTML.
- Code-aware editing behavior for supported syntax-highlighted languages:
  - bracket and quote auto-pairing
  - smart newline indentation
  - line indent and outdent
  - comment toggling for supported languages
  - pair-aware backspace deletion
  - matching bracket highlight
- Keyboard shortcuts for common editor actions.
- iOS accessory controls for undo, redo, and keyboard dismissal.
- Programmatic control over text, language, editability, line wrapping, theme, font size, and background drawing.

## Requirements

- Swift 6.3+
- iOS 18+
- macOS 15+

## Shortcuts

- `Tab`: Insert spaces at the caret; indent selected lines in syntax-highlighted language modes
- `Shift-Tab`: Outdent in syntax-highlighted language modes
- `Cmd+]`: Indent in syntax-highlighted language modes
- `Cmd+[` : Outdent in syntax-highlighted language modes
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

### SwiftUI

```swift
import SwiftUI
import SyntaxEditorUI

struct EditorView: View {
    @State private var model = SyntaxEditorModel(
        text: "const answer = 42;",
        language: .javascript
    )

    var body: some View {
        SyntaxEditor(model)
            .onChange(of: model.text) {
                print("Edited text:", model.text)
            }
    }
}
```

### UIKit / AppKit

```swift
import SyntaxEditorUI

let model = SyntaxEditorModel(
    text: "const answer = 42;",
    language: .javascript
)

let editorView = SyntaxEditorView(model: model)
let editorViewController = SyntaxEditorViewController(model: model)
```

Use `SyntaxLanguage.plainText` when an editor should behave as strict plain text without syntax highlighting or code-aware editing transforms:

```swift
let notesModel = SyntaxEditorModel(text: "Notes", language: .plainText)
```

Supported languages are available through `SyntaxLanguage`: Plain Text, CSS, HTML, JavaScript, JSON, Objective-C, Swift, TOML, and XML.
Use `SyntaxLanguage(identifier:)` when resolving user input or file metadata, and `SyntaxLanguage.allCases` when presenting every built-in language.

To move first-use highlighting setup out of the editor load path, prepare the languages your app expects to show:

```swift
Task.detached {
    await SyntaxEditorHighlighting.prepare([.swift, .html])
}
```

Set `model.drawsBackground = false` when the surrounding view should provide the editor background while syntax colors and editor decorations remain active. Use `model.fontSizeDelta`, `increaseFontSize()`, `decreaseFontSize()`, and `resetFontSize()` for Xcode-style point-size adjustments relative to the selected theme.

Use `SyntaxEditorMenu` when an app wants to expose editor shortcuts in an `Editor` menu. On iOS 26 and later, install it from the app delegate's main menu configuration:

```swift
if #available(iOS 26.0, *) {
    UIMainMenuSystem.shared.setBuildConfiguration(UIMainMenuSystem.Configuration()) { builder in
        SyntaxEditorMenu.insert(into: builder)
    }
}
```

On iPadOS, first-responder key commands can also appear under Help > Other Keyboard Shortcuts; install the `Editor` menu through the main menu builder when the commands should appear as a menu bar menu.

On macOS, insert the menu item into the app's main menu:

```swift
SyntaxEditorMenu.insert(into: NSApp.mainMenu!)
```

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

## Performance Benchmarks

Highlighting performance benchmarks are exposed through the SwiftPM `benchmark` plugin:

```bash
swift package benchmark list --target HighlightBenchmark
swift package benchmark run --target HighlightBenchmark --filter 'fixture-swift-structural-edit/highlight/incremental-update' --time-units microseconds --no-progress
swift package --allow-writing-to-package-directory benchmark baseline update before --target HighlightBenchmark --filter 'fixture-swift-structural-edit/highlight/incremental-update'
swift package benchmark baseline compare before --target HighlightBenchmark --filter 'fixture-swift-structural-edit/highlight/incremental-update'
SYNTAX_EDITOR_BENCHMARK_FILE=/path/to/file.swift swift package benchmark run --target HighlightBenchmark
```

The benchmark suite uses bundled reference samples by default and repeats them to at least 10,000 lines. Large cases repeat to at least 50,000 lines. Set `SYNTAX_EDITOR_BENCHMARK_FILE` to benchmark a custom file, and optionally set `SYNTAX_EDITOR_BENCHMARK_LANGUAGE`, `SYNTAX_EDITOR_BENCHMARK_REPEAT_SOURCE`, `SYNTAX_EDITOR_BENCHMARK_ITERATIONS`, `SYNTAX_EDITOR_BENCHMARK_TYPING_EDITS`, `SYNTAX_EDITOR_BENCHMARK_TYPING_ANCHOR`, `SYNTAX_EDITOR_BENCHMARK_TYPE_TEXT`, `SYNTAX_EDITOR_BENCHMARK_TYPE_AFTER`, or `SYNTAX_EDITOR_BENCHMARK_TYPE_REPEAT` to adjust the run. `SYNTAX_EDITOR_BENCHMARK_REPEAT_SOURCE` overrides the default sample amplification.

Benchmarks are intended for local development and are not part of regular CI. Performance regression checks should run on a dedicated machine or a manually triggered workflow to avoid shared-runner noise.

## Migration

### Unreleased

These notes apply when upgrading from `v0.13.x` or earlier.

- `SyntaxEditorTextEdit` has been replaced by `SyntaxEditorTextChange.Replacement`.
- `SyntaxEditorTextChange.edits` has been renamed to `replacements`.
- `SyntaxEditorTextChange.revision` has been renamed to `textRevision`.
- `SyntaxEditorModel.latestChange` has been renamed to `latestTextChange`.
- `SyntaxEditorTextChange.Kind.replacement` has been renamed to `wholeDocumentReplacement`.
- Platform color and font aliases now live under `SyntaxEditorTheme` as `SyntaxEditorTheme.Color` and `SyntaxEditorTheme.Font`.
- `SyntaxEditorMenu.makeEditorMenu()` and `SyntaxEditorMenu.makeEditorMenuItem()` have been replaced by `SyntaxEditorMenu.makeMenu()`.
- `SyntaxEditorMenu.insertEditorMenu(into:)` and `SyntaxEditorMenu.insertEditorMenuItem(into:)` have been replaced by `SyntaxEditorMenu.insert(into:)`.
- `SyntaxLanguage.named(_:)` has been replaced by `SyntaxLanguage.init?(identifier:)`.
- `SyntaxLanguage.all` has been removed. Use `SyntaxLanguage.allCases`.

### v0.12.0

These notes apply when upgrading from `v0.11.x` or earlier to `v0.12.0`.

- `SyntaxEditorColorTheme` has been renamed to `SyntaxEditorTheme`.
- `SyntaxEditorModel.colorTheme` and the `colorTheme:` initializer argument have been renamed to `theme` and `theme:`.
- Custom `SyntaxEditorTheme` values must include a `font`. Themes now own editor font size; the editor no longer falls back to a package-level default point size.

### v0.11.0

These notes apply when upgrading from `v0.10.x` or earlier to `v0.11.0`.

- `SyntaxEditorDocument` and `SyntaxEditorConfiguration` have been removed. Create and own a single `SyntaxEditorModel` for text, selection, language, editability, wrapping, theme, background drawing, and font-size state.
- `SyntaxLanguage.plainText` has been added. Update exhaustive switches over `SyntaxLanguage` to handle plain text, and use `.plainText` for editors that should not run syntax highlighting or code-aware editing transforms.
- `textSnapshot()` has been removed. Read, write, and observe `model.text` directly. Use `model.replaceText(_:selectedRange:)` when replacement and selection should be updated together.
- Replace `SyntaxEditor(document:configuration:)` with `SyntaxEditor(model)`.
- Replace `SyntaxEditorView(document:configuration:)` and `SyntaxEditorViewController(document:configuration:)` with `SyntaxEditorView(model:)` and `SyntaxEditorViewController(model:)`.
- `SyntaxEditorDocumentChange` has been renamed to `SyntaxEditorTextChange`. Use `change.kind == .incremental` or `change.kind == .wholeDocumentReplacement` instead of `isWholeDocumentReplacement`.
- UIKit and AppKit `text`, `selectedRange`, and `isEditable` properties remain available and now proxy to the view's `model`.
- On macOS, `SyntaxEditorView` no longer exposes the underlying editor as `NSTextView`. The editor surface is implemented directly with TextKit 2, matching the iOS architecture. Use `SyntaxEditorView.text`, `SyntaxEditorView.selectedRange`, `SyntaxEditorView.isEditable`, and `SyntaxEditorView.model` instead of reaching through `textView`.
- This is a breaking macOS API change: there is no replacement public `NSTextView` accessor. Code that previously customized `editorView.textView` should move editor state to `SyntaxEditorModel` or drive the editor through the public `SyntaxEditorView` properties above.
- `SyntaxEditorViewController.textView` is no longer public on macOS. Access the editor through `SyntaxEditorViewController.editorView` and `model`.

### v0.10.0

These notes apply when upgrading from `v0.9.x` or earlier to `v0.10.0`.

- `SyntaxEditorView.font` has been removed from the public iOS API. Use `SyntaxEditorModel.fontSizeDelta` or the font-size command methods to adjust editor text size.

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
- If your app observed `SyntaxEditorModel`, observe `SyntaxEditorDocument` for text changes and `SyntaxEditorConfiguration` for configuration changes. `SyntaxEditorDocument` exposes `textRevision` and `latestTextChange` for tracking committed text changes.
- `SyntaxEditorModel` and the model-based initializers have been removed without a compatibility shim.

### v0.5.0

These notes apply when upgrading from `v0.4.x` or earlier to `v0.5.0`.

- Starting with `v0.5.0`, non-UI implementation has moved into the internal `SyntaxEditorCore` target. `SyntaxEditorCore` is not a public package product; clients should keep importing `SyntaxEditorUI` only.
- In `v0.5.0`, `SyntaxEditorModel`, `SyntaxLanguage`, and related non-UI APIs remained available from `SyntaxEditorUI` via module re-export. `SyntaxEditorModel` was removed in `v0.7.0`; see the `v0.7.0` notes above.
- `SyntaxLanguage` is now a concrete enum of supported languages. Use `SyntaxLanguage.javascript` or shorthand `.javascript` instead of `BuiltinSyntaxLanguages.javascript`.
- `BuiltinSyntaxLanguages` has been removed without a compatibility shim.
- Custom `SyntaxLanguage` conformers are no longer supported. `SyntaxLanguage.TreeSitterSupport`, custom query directories, and custom highlight cache keys are no longer public API.
- HTML embedded JavaScript/CSS highlighting remains supported through `SyntaxLanguage.html`.
- Up to `v0.4.x` on iOS, `SyntaxEditorView` embedded a `UITextView` that was exposed through `SyntaxEditorView.textView` and `SyntaxEditorViewController.textView`.
- Starting with `v0.5.0` on iOS, `SyntaxEditorView` is the single native text input and scroll view. Use `SyntaxEditorView` / `SyntaxEditorViewController.editorView` directly for text, selection, editability, wrapping, and scrolling.
