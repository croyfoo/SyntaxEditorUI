# ``SyntaxEditorUI``

Build editable code and plain-text views with SwiftUI, UIKit, and AppKit.

## Overview

Import `SyntaxEditorUI` and create a ``SyntaxEditorModel`` for each document. Pass the model to ``SyntaxEditor`` in SwiftUI or choose a native editor for your platform.

The package requires Swift 6.3 or later, with iOS 18+, Mac Catalyst 18+, visionOS 2+, or macOS 15+. The app owns loading and saving; the model owns the current editor state.

## Topics

### Essentials

- <doc:GettingStarted>
- ``SyntaxEditor``

### Editor state

- ``SyntaxEditorModel``
- ``SyntaxEditorTextChange``

### UIKit

- <doc:UIKitIntegration>
- ``SyntaxEditorView-6lnwr``
- ``SyntaxEditorViewController-j7tv``

### AppKit

- <doc:AppKitIntegration>
- ``SyntaxEditorView-77bw3``
- ``SyntaxEditorViewController-16tjt``

### Languages and appearance

- <doc:LanguagesAndThemes>
- ``SyntaxLanguage``
- ``SyntaxEditorTheme``
- ``SyntaxEditorHighlighting``

### Editing commands

- <doc:Editing>
- ``SyntaxEditorMenu``

### Upgrading

- <doc:Migration>
