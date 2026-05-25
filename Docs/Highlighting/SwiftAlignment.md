# Swift Highlighting Alignment

Swift highlighting is currently a combination of tree-sitter query captures and
a Swift-only semantic overlay. The public package API does not expose Xcode
private framework details.

## Current Runtime Shape

- Base lexical tokens come from `Sources/SyntaxEditorCore/Resources/SwiftQueries/highlights.scm`.
- Swift semantic corrections live in:
  - `Sources/SyntaxEditorCore/Highlighting/SwiftFileSymbolIndex.swift`
  - `Sources/SyntaxEditorCore/Highlighting/SwiftSyntaxOverlayTokenProvider.swift`
- The overlay is internal to `SyntaxEditorCore` and is recalculated over the
  full token array after incremental edits so declaration changes do not leave
  stale distant references.
- The tree-sitter Swift grammar fork is pinned as a fetchable SwiftPM
  dependency.

## What We Learned

### Xcode Uses More Than xclangspec for Swift

The xclangspec-derived layer is not enough for Xcode-like Swift coloring.
Xcode's visible Swift editor behavior is influenced by `SourceEditor` and
`SymbolCache`, especially for project/external semantic buckets.

Runtime implication:

- Keep Xcode private frameworks in `EditorSpecTool` only.
- Implement runtime behavior from local syntax and generated/static knowledge,
  not by linking private frameworks.

### Project vs External Scope

The current approximation is file-local:

- Symbols declared in the same source file are treated as project/local.
- Symbols not declared in the file are treated as external only when the syntax
  context is clear enough, such as type positions, callable positions, or macro
  invocations.
- Unknown labels, attribute arguments, comments, strings, and arbitrary member
  chains are kept plain or left to the base query to avoid false positives.

This intentionally does not reproduce workspace-wide `SymbolCache`.

### Attributes and Macros

Important behavior captured so far:

- Built-in attributes stay keyword-like when the query already knows them.
- Same-file macro declarations/invocations can be marked as local macro.
- Same-file type-like attributes and property wrappers can be marked as local
  type.
- Unknown external attributes are intentionally conservative unless the context
  is clear.

### Contextual Keywords

Contextual keywords should not be blanket-colored everywhere. The current
direction is to color them only when grammar/query context supports it and leave
plain/identifier behavior outside that context.

### SDK and Stdlib Members

Cases such as `min`, `max`, `lowerBound`, `upperBound`, `first`, and `map` need
oracle-backed classification before runtime tables are introduced.

Current policy:

- Do not infer SDK/stdlib member colors from screenshots alone.
- Use `--semantic-depth sdk` style oracle work as the next step before adding a
  small generated table.
- If a table is added, key it by name plus receiver/type context to avoid broad
  false positives.

## Known Limits

- No workspace-wide or module-wide symbol resolution in runtime.
- No private Xcode framework dependency in runtime.
- SDK/stdlib semantic coloring is not complete.
- Delayed semantic passes in the real Xcode editor may still show more detail
  than the current SourceEditor + SymbolCache current-file probe.

## Useful Verification Commands

```sh
swift run EditorSpecTool classification-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool rendered-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift test --filter SyntaxHighlighterEngine
```
