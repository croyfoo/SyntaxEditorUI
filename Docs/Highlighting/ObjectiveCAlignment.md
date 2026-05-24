# Objective-C Highlighting Alignment

Objective-C should be aligned against Xcode, but it should not simply reuse the
Swift semantic model. The current evidence points to a more lexical
DVT/xclangspec-driven path for Objective-C.

## Current Runtime Shape

- Query file:
  `Sources/SyntaxEditorCore/Resources/ObjectiveCQueries/highlights.scm`
- Grammar dependency:
  `tree-sitter-grammars/tree-sitter-objc`
- Verification:
  - `EditorSpecTool diff` for SourceModel range/spec investigation.
  - `EditorSpecTool rendered-diff` and `xcode-dvt-rendered-tokens` for visible
    Xcode editor color.

`classification-diff` is Swift-focused and should not be treated as the ObjC
oracle.

## What We Learned

### DVT Rendered Tokens Are the Better Visual Oracle

SourceModel often reports structural Objective-C buckets:

- `xcode.lang.objc.classname` -> `name.type`
- method punctuation -> `name.partial`
- category names and parentheses -> `name.partial`
- `NS_ENUM(...)` container -> `name.tree`

DVT rendered tokens show many of these ranges as ordinary identifier/plain
color in Xcode's visible editor. For example, class names, Foundation type
names, method names, property names, and category names are generally not
colored like Swift's semantic type/function buckets.

Runtime implication:

- Do not force Objective-C identifiers into `.identifierTypeSystem` or
  `.identifierFunctionSystem` just because SourceModel uses `name.*`.
- Keep most non-keyword identifiers as `.identifier`.

### Objective-C Keyword Set Is Mostly xclangspec-Driven

The current query treats language keywords and common Objective-C pseudo-keyword
identifiers as keywords, including:

- `self`, `super`, `_cmd`
- `id`, `instancetype`, `Class`, `SEL`, `IMP`, `BOOL`
- nullability and ownership qualifiers such as `nullable`, `nonnull`,
  `__weak`, `__strong`
- property attributes such as `nonatomic`, `copy`, `assign`, and getter/setter
  option names

This fixes the previous over-coloring where identifiers were pushed into type
or function system buckets.

### Preprocessor Is Still Hard

SourceModel and DVT both understand preprocessor regions, but tree-sitter-objc
often exposes macro bodies as broad `preproc_arg` ranges. That means a query
alone cannot always reproduce Xcode's finer behavior inside:

```objc
#define ReferenceLog(format, ...) NSLog((@"[Reference] " format), ##__VA_ARGS__)
```

Known gap:

- Xcode can identify macro-body identifiers and strings more precisely.
- The current query colors the broad preprocessor range and cannot split every
  nested string/identifier without a custom overlay/scanner.

### NS_ENUM Is a Grammar Limitation

`tree-sitter-objc` currently parses `typedef NS_ENUM(NSInteger, Name) { ... }`
poorly in the reference header. In observed parses it can become a bogus
`function_definition` with an `ERROR`, which also affects following declarations.

Current mitigation:

- Query-level special cases keep `typedef` keyword-colored.
- `NS_ENUM` names and surrounding structural ranges remain imperfect.

Possible future work:

- Fork/fix `tree-sitter-objc` grammar for `NS_ENUM`/`NS_OPTIONS`.
- Or add an Objective-C overlay scanner for the common Apple macro forms.

## Current Fixture Policy

The ObjC reference sample should include more than a tiny header/implementation.
It now includes cases borrowed from `SourceModelBridge` patterns:

- `NSError **`
- `NSRange *`
- block typedefs
- generic Foundation containers
- dictionary literals
- `objc_msgSend` function pointer casts
- dynamic selector calls
- protocols, class extensions, and categories

This gives the query and DVT diff enough surface to catch regressions.

## Useful Verification Commands

```sh
swift run EditorSpecTool diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.h \
  --language objectiveC --pretty

swift run EditorSpecTool diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.m \
  --language objectiveC --pretty

swift run EditorSpecTool rendered-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.m \
  --language objectiveC --pretty

swift test --filter SyntaxHighlighterEngine
```

## Known Limits

- No ObjC semantic overlay equivalent to Swift yet.
- No method/property resolution.
- Preprocessor macro body token splitting is incomplete.
- `NS_ENUM`/`NS_OPTIONS` require grammar work or a small overlay if exact Xcode
  behavior is required.

