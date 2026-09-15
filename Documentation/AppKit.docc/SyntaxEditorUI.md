# ``SyntaxEditorUI``

Build editable code and plain-text views for AppKit and SwiftUI.

## Overview

Import `SyntaxEditorUI` and create a ``SyntaxEditorModel`` for each document. Pass that model to ``SyntaxEditor``, ``SyntaxEditorView``, or ``SyntaxEditorViewController``.

This reference covers macOS 15+ with Swift 6.3 or later. The app decides when to load and save text; the model owns the current editor state.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:AppKitIntegration>
- ``SyntaxEditor``
- ``SyntaxEditorView``
- ``SyntaxEditorViewController``

### Editor state

- ``SyntaxEditorModel``
- ``SyntaxEditorTextChange``

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
