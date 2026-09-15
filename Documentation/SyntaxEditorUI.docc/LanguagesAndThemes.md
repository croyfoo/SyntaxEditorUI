# Languages and themes

Choose highlighting, comment syntax, and editor appearance through the model.

## Select a language

Set `model.language` to a ``SyntaxLanguage`` value. Use `SyntaxLanguage.allCases` for a language picker and `SyntaxLanguage(identifier:)` to resolve a name or extension. Unknown identifiers return `nil`; your app decides what language to use in that case.

| Language | Value | Comment toggle |
| --- | --- | --- |
| Plain Text | `.plainText` | Unavailable |
| ARM Assembly | `.assemblyARM` | `//` |
| CSS | `.css` | `/* ... */` |
| HTML | `.html` | HTML or embedded-language comments |
| JavaScript | `.javascript` | `//` |
| JSON | `.json` | Unavailable |
| Objective-C | `.objectiveC` | `//` |
| Swift | `.swift` | `//` |
| TOML | `.toml` | `#` |
| XML | `.xml` | `<!-- ... -->` |

HTML includes highlighting for embedded JavaScript and CSS. ARM Assembly provides basic ARM/ARM64 token highlighting; it does not validate instructions or cover every assembler dialect. Its aliases include `asm`, `s`, `arm64`, and `aarch64`.

## Prepare highlighting

If your app knows which languages it will display, prepare their highlighting configuration before opening editors:

```swift
Task.detached {
    await SyntaxEditorHighlighting.prepare([.swift, .html])
}
```

Preparation is optional. Editors also initialize highlighting on first use. See ``SyntaxEditorHighlighting``.

## Set the appearance

Update the existing model to change appearance without replacing the document:

```swift
model.theme = .dusk
model.fontSizeDelta = 2
model.drawsBackground = false
```

A ``SyntaxEditorTheme`` supplies fonts and colors. Choose a built-in preset or use its initializer to provide your own colors and font. `fontSizeDelta` adjusts the theme's base point size; `increaseFontSize()`, `decreaseFontSize()`, and `resetFontSize()` provide the same controls used by the editor's font-size commands.

Set `drawsBackground` to `false` when the surrounding view should provide the background. Syntax colors and editor decorations remain active.
