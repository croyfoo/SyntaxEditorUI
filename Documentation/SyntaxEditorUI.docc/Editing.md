# Editing commands

Use built-in text editing and keyboard shortcuts.

## Code-aware editing

Syntax-highlighted languages support bracket and quote pairing, smart newline indentation, line indentation, pair-aware backspace, and matching-bracket highlighting. Comment toggling uses each language's comment syntax.

Plain Text keeps typing literal: it disables syntax highlighting and code-aware transforms, while selection, find, undo, and ordinary text editing remain available. JSON has highlighting and pairing but no comment-toggling syntax.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Tab | Insert spaces at the caret; indent selected lines in code modes |
| Shift+Tab | Outdent in code modes |
| Cmd+] / Cmd+[ | Indent / outdent selected lines |
| Cmd+/ | Toggle comments in languages with comment syntax |
| Ctrl+Shift+Cmd+L | Toggle line wrapping |
| Cmd++ / Cmd+- | Increase / decrease font size |
| Ctrl+Cmd+0 | Reset the font-size adjustment |
| Cmd+Z / Shift+Cmd+Z | Undo / redo |
| Cmd+F | Show Find |
| Cmd+G / Shift+Cmd+G | Find next / previous |

The editor must be focused to receive these commands. Use ``SyntaxEditorMenu`` to expose editor commands in your app's menu. Native integration guides explain where to install it.

## Control editing

Set `model.isEditable = false` for a read-only editor that still supports selection and copying. Set `model.lineWrappingEnabled` to choose between wrapped lines and horizontal scrolling.

The editor manages undo for user edits. Loading a replacement document or switching models resets its editing history. Programmatic model updates are intended for your app's state changes, rather than as a replacement for the editor's undo commands.
