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

### xclangspec Rules That Matter

`ObjectiveC.xclangspec` uses `name.*` syntax types for most of the visible
Objective-C structure:

- `xcode.lang.objc.classname` is `xcode.syntax.name.type`.
- `xcode.lang.objc.protocol.name` is also `xcode.syntax.name.type`.
- `xcode.lang.objc.partialname`, used for method selector pieces, is
  `xcode.syntax.name.other`.
- `xcode.lang.objc.function.name` is `xcode.syntax.name.other`.
- `xcode.lang.objc.property.name.actual` is `xcode.syntax.name.other`.
- `xcode.lang.objc.parameter.name.local` is
  `xcode.syntax.name.parameter.local`.
- function parameters are `xcode.syntax.name.parameter`.
- `@property` declarations are wrapped as
  `xcode.syntax.declaration.property`.
- `_Nullable` / `_Nonnull` and related ObjC type qualifiers are listed as
  ObjC identifier words with `xcode.syntax.keyword`.
- ObjC dictionary literal delimiters use `xcode.syntax.number` for the
  `@{` start rule and the `}` end rule.

Runtime implication:

- Class/interface/protocol declaration names should not be treated like Swift
  type references. They need a declaration/name-style color.
- Method and C function declaration names need a declaration/name-other color.
- Property names also need a declaration/name-other color, not a local variable
  reference color.
- Method parameter names are local parameter names, but arbitrary identifier
  references should not be promoted just because they look like parameters.
- `self.property` is a stronger signal than a bare identifier. Xcode colors it
  as a resolved member when the project/index can resolve it.

The current runtime maps these xclangspec `name.*` roles onto existing
`EditorSourceSyntaxID` values because the generated theme table does not yet
ship exact `xcode.syntax.name.*` slots:

- class/interface/protocol declaration name -> `.declarationType`
- method/C function declaration name -> `.declarationOther`
- same-file C function call -> `.identifierFunction`
- external C function or message selector -> `.identifierFunctionSystem`
- `self.` local property/getter -> `.identifierVariable`
- other dotted member -> `.identifierVariableSystem`
- Objective-C dictionary literal `@`, `{`, and `}` -> `.number`
- known external constants observed in Foundation-style contexts, such as
  `NSLocalizedDescriptionKey`, -> `.identifierConstantSystem`

This is a visual compatibility mapping, not a claim that Xcode's internal
syntax ID is identical.

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

However, standalone `DVTTextStorage` snapshots are not enough for project-aware
ObjC semantics. In current probes, `xcode-dvt-rendered-tokens` reports many
live-editor-colored ranges as plain identifiers because it does not have the
same indexed project/header context as an open Xcode editor.

The useful split is:

- `ObjectiveC.xclangspec`: reliable for lexical rule shape and role names.
- live Xcode editor in a real project: reliable for header/index-aware visual
  behavior.
- standalone DVT rendered probes: useful for theme/color extraction and shallow
  lexical checks, but not a complete ObjC semantic oracle.

### Runtime Overlay Shape

Objective-C now has a small internal overlay, separate from the Swift overlay.
It intentionally stays file-local and conservative:

- It builds a per-source symbol index from the current `.m`/`.h` text and the
  base query tokens.
- It records local type declarations from `@interface`, `@implementation`,
  `@protocol`, `@class`, `NS_ENUM`, `NS_OPTIONS`, and ordinary typedef forms.
- It records local C function and method declaration names.
- It records local properties from `@property` declarations and zero-argument
  getter methods.
- It strips broad ObjC semantic captures before applying overlay tokens, so
  stale incremental tokens do not accumulate.

Current overlay behavior:

- declaration class/interface/protocol names become `.declarationType`.
- superclass and Foundation/AppKit-style names remain `.identifierTypeSystem`.
- same-file C function calls become `.identifierFunction`.
- other C calls and message selector names become `.identifierFunctionSystem`.
- `self.property` is `.identifierVariable` when the property/getter is declared
  in the same source text.
- `object.property` / chained member names are `.identifierVariableSystem`.
- bare parameters, locals, labels, strings, comments, and preprocessor ranges
  remain plain or their base lexical classification.

This intentionally does not ingest companion headers. A `.m` file only uses
symbols that are present in the current source text or visible through the base
tokens. For Mini this means the visible `Reference.m` needs enough declarations
in the same text to approximate Xcode's indexed project behavior.

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
`Tools/Mini/Mini/ReferenceSamples/Reference.m` now includes cases borrowed from
`SourceModelBridge` patterns:

- `NSError **`
- `NSRange *`
- block typedefs
- generic Foundation containers
- dictionary literals
- `objc_msgSend` function pointer casts
- dynamic selector calls
- protocols, class extensions, and categories

This gives the query and DVT diff enough surface to catch regressions.

Mini has one important project-registration detail:

- `Reference.m` is registered as a real Objective-C source file in the Mini
  target so Xcode can associate it with `Reference.h` and index it like an
  implementation file.
- The app still needs the sample text at runtime. Do not put the same
  `Reference.m` file reference in both `Sources` and `Resources`; Xcode emits an
  unexpected compiler-output warning for that shape. Mini instead uses a small
  build phase to copy `Reference.h` and `Reference.m` into
  `ReferenceSamples/` inside the built app.
- If the runtime copy is missing, `MiniPreviewPreset` falls back to its minimal
  inline sample (`Sample.h` / `Sample`), which is not useful for ObjC alignment.

`SourceModelBridge.m` remains the better project-aware investigation fixture
because it is a real package source paired with
`Sources/SourceModelBridge/include/SourceModelBridge.h`. Use it when checking
whether Xcode's live editor is applying header/index-aware coloring.

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

swift run EditorSpecTool rendered-diff \
  --file Sources/SourceModelBridge/SourceModelBridge.m \
  --language objectiveC --pretty

swift test --filter SyntaxHighlighterEngine
```

## Known Limits

- Companion header symbols are out of scope for the runtime overlay.
  `Reference.m` can approximate Xcode only for symbols present in the current
  `.m` source text or captured by the local scanner.
- No full method/property resolution. The current member rule distinguishes
  `self.` local properties and dotted system members; it does not resolve
  receiver types or selector families.
- Current `DVTTextStorage` rendered snapshots are still shallow for project
  header/index semantics; live Xcode can color some `SourceModelBridge.m`
  identifiers after indexing that the standalone DVT route reports as ordinary
  identifiers.
- Preprocessor macro body token splitting is incomplete.
- `NS_ENUM`/`NS_OPTIONS` require grammar work or a small overlay if exact Xcode
  behavior is required.
