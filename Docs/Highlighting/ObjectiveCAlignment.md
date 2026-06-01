# Objective-C Highlighting Alignment

Objective-C should be aligned against Xcode, but it should not simply reuse the
Swift semantic model. Current evidence points to Xcode's same staged
SourceEditor pipeline, with Objective-C buckets coming from SourceModel and
SourceEditor UIKind classification rather than Swift's symbol model.

## Current Runtime Shape

- Query file:
  `Sources/SyntaxEditorCore/Resources/ObjectiveCQueries/highlights.scm`
- Grammar dependency:
  `tree-sitter-grammars/tree-sitter-objc`
- Verification:
  - `EditorSpecTool diff` for SourceModel range/spec investigation.
  - `EditorSpecTool classification-diff` and `xcode-classification-tokens` for
    SourceEditor UIKind buckets.
  - `EditorSpecTool rendered-diff` for SourceEditor bucket colors.
  - `EditorSpecTool xcode-dvt-rendered-tokens` only for standalone DVT/theme
    checks.

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
- Current-file SourceEditor classification under-reports some live Objective-C
  lexical-scope coloring. In an open Xcode editor, method selector references
  and `self.<known property>` chains receive delayed lexical-scope colors even
  when the current-file probe reports `plain`.

The current runtime maps these xclangspec `name.*` roles onto existing
`EditorSourceSyntaxID` values because the generated theme table does not yet
ship exact `xcode.syntax.name.*` slots:

- class/interface/protocol declaration name -> `.declarationType`
- method/C function declaration name -> `.declarationOther`
- most type references in ObjC type positions -> `.identifierTypeSystem`.
  This is a lexical/import-aware approximation, not a resolved symbol table.
- same-file C function calls -> `.identifierFunction`
- known imported/system C calls used by the reference fixture, including
  `objc_msgSend` casts and Foundation/Objective-C runtime helpers ->
  `.identifierFunctionSystem`
- parameters, locals, and labels -> `.plain`
- file-scope constants and implementation ivars -> lexical variable buckets
  on references, while their declarations remain declaration-shaped or plain
  according to the surrounding syntax.
- message selector references -> `.identifierFunction`
- `self.<known property>` -> `.identifierVariable`
- member references chained from a known or header-backed `self` property ->
  `.identifierVariableSystem`
- member references in implementation files with quoted companion-header imports
  -> `.identifierVariableSystem`, because the runtime cannot load that header
  but Xcode's live editor sees the imported declarations.
- Objective-C dictionary literal `@`, `{`, and `}` -> `.number`
- Objective-C boxed expression delimiters in `@(value)` and boxed booleans
  `@YES` / `@NO` -> `.number`
- Apple macro identifiers such as `NS_ASSUME_NONNULL_*`, `NS_SWIFT_NAME`,
  `NS_ENUM`, and `NS_OPTIONS` -> `.preprocessor`; `NS_ENUM`/`NS_OPTIONS`
  typedef names -> `.declarationType`

This is a visual compatibility mapping, not a claim that Xcode's internal
syntax ID is identical.

### SourceEditor Classification Is Not the Whole Oracle

SourceModel often reports structural Objective-C buckets:

- `xcode.lang.objc.classname` -> `name.type`
- method punctuation -> `name.partial`
- category names and parentheses -> `name.partial`
- `NS_ENUM(...)` container -> `name.tree`

SourceEditor classification exposes useful UI buckets from the same staged
editor path. Current probes show Objective-C ranges classified as
`typeDeclaration` and `otherDeclaration` for class/interface, property, method,
and function declaration names.

The current-file probe is not deep enough for all live Objective-C lexical
scope. It still reports method selector references and `self.<property>` member
references as `plain`, while the live Xcode editor colors those ranges after its
delayed pass. For those cases, use live Xcode screenshots plus
`ObjectiveC.xclangspec`/SourceModel range shape as the evidence instead of
treating `classification-diff` as a zero-difference oracle.

The same SourceEditor current-file probe can leave common Apple macro forms such
as `NS_ASSUME_NONNULL_BEGIN`, `NS_ASSUME_NONNULL_END`, `NS_SWIFT_NAME`,
`NS_ENUM`, and `NS_OPTIONS` plain in the reference header. In a live Xcode
editor, those macro identifiers use the preprocessor color. That behavior also
matches `ObjectiveC.xclangspec`'s identifier rule shape: Objective-C identifiers
enable `CheckPreprocessorKnownMacros`, so known macro identifiers can be colored
by the editor's macro knowledge even when a current-file probe reports only
`plain`.

Runtime implication:

- Do not force Objective-C identifiers into `.identifierTypeSystem` or
  `.identifierFunctionSystem` just because SourceModel uses `name.*`.
- Keep most non-declaration identifiers as `.plain` or their base lexical
  bucket.
- Preserve the delayed fast-pass behavior: the lexical pass can appear first,
  and the Objective-C overlay is expected to arrive in the complete phase.

Standalone `DVTTextStorage` snapshots are not enough for project-aware ObjC
semantics. In current probes, `xcode-dvt-rendered-tokens` reports many
SourceEditor-classified ranges as ordinary identifiers because it does not have
the same staged SourceEditor classification path as an open Xcode editor.

The useful split is:

- `ObjectiveC.xclangspec`: reliable for lexical rule shape and role names.
- `xcode-classification-tokens` / `classification-diff`: best current tool
  probe for declaration UIKind buckets and broad app-path behavior.
- live Xcode editor in a real project: required for Objective-C lexical-scope
  colors such as selector references and `self` property/member chains.
- standalone DVT rendered probes: useful for theme/color extraction and shallow
  lexical checks only.

### Runtime Overlay Shape

Objective-C now has a small internal overlay, separate from the Swift overlay.
It intentionally stays file-local and conservative:

- It builds a per-source symbol index from the current `.m`/`.h` text and the
  base query tokens.
- It records local type declarations from `@interface`, `@implementation`,
  `@protocol`, `@class`, block typedefs, and ordinary typedef forms that the
  SourceEditor current-file oracle classifies as declarations.
- It records local C function and method declaration names.
- It records local properties from `@property` declarations and zero-argument
  getter methods.
- It strips broad ObjC semantic captures before applying overlay tokens, so
  stale incremental tokens do not accumulate.

Current overlay behavior:

- declaration class/interface/protocol names become `.declarationType`.
- superclass names in `@interface ... : Superclass` become
  `.identifierTypeSystem` in the live-editor approximation, even though the
  current-file SourceEditor probe may classify that position as a declaration.
- type references in ObjC type positions become `.identifierTypeSystem`.
- same-file C calls, external C calls, bare parameters, locals, and labels
  are split: same-file calls receive `.identifierFunction`, a small set of
  imported/runtime helpers receive `.identifierFunctionSystem`, and bare
  parameters, locals, and labels remain `.plain` or their base lexical
  classification.
- message selector references become `.identifierFunction`, matching live Xcode
  lexical-scope coloring.
- references to properties declared in the current source as `self.property`
  become `.identifierVariable`.
- members chained from a known or quoted-header-backed `self` property, such as
  `self.text.length`, become `.identifierVariableSystem`; direct
  macro-shaped names that are not known properties stay plain.
- unrelated member names in `.m` files with quoted companion-header imports are
  colored `.identifierVariableSystem` as a header-backed lexical fallback.
- function-like macro invocations declared in the current file, such as
  `ReferenceLog(...)`, use the preprocessor color.
- file-scope constant references and implementation ivar references receive
  lexical variable colors because Xcode's live editor colors those after the
  delayed pass; local variables and parameters stay plain.
- property declarations become `.declarationOther` only where the app-path
  oracle classifies the property name as `otherDeclaration`; macro-suffixed
  declarations that SourceEditor leaves plain stay plain.
- boxed expression delimiters in `@(value)` are `.number`.
- boxed boolean literals `@YES` / `@NO` are `.number`.
- quoted strings inside broad preprocessor macro bodies are split back to
  `.string`.

This intentionally does not parse arbitrary companion headers. A `.m` file only
receives its displayed source text in the runtime highlighter, so a quoted
`#import "Header.h"` cannot be resolved the way Xcode resolves it through the
project index. Objective-C compensates with a lexical fallback: when an
implementation imports a quoted header, header-backed member names are colored
like Xcode's delayed lexical-scope pass, while macro-shaped false positives stay
plain.

### Objective-C Keyword Set Is Mostly xclangspec-Driven

The current query treats language keywords and common Objective-C pseudo-keyword
identifiers as keywords, including:

- `self`, `super`, `_cmd`
- `id`, `instancetype`, `SEL`, `IMP`, `BOOL`; `Class` is plain in current
  SourceEditor classification
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

Current mitigation:

- Xcode can identify macro-body identifiers and strings more precisely.
- The overlay splits common quoted string literals inside broad preprocessor
  ranges, matching the visible `@"..."` macro-body case where Xcode keeps `@`
  in the preprocessor color and colors the quoted string.
- Macro-body identifiers remain broader preprocessor tokens unless there is
  stronger evidence for a narrower app-path bucket.

### Apple Macro Typedefs Need Live-Editor Compensation

`tree-sitter-objc` currently parses `typedef NS_ENUM(NSInteger, Name) { ... }`
poorly in the reference header. In observed parses it can become a bogus
`function_definition` with an `ERROR`, which also affects following declarations.
Separately, the SourceEditor current-file classification probe may leave the
macro name and enum/options typedef name plain in the header fixture. Live Xcode
does not: the macro identifiers are preprocessor-colored and the typedef name is
colored like a type declaration.

Runtime policy:

- Query-level special cases keep `typedef` keyword-colored.
- Force `NS_ENUM`, `NS_OPTIONS`, `NS_SWIFT_NAME`, and
  `NS_ASSUME_NONNULL_*` into the preprocessor bucket outside comments and
  strings.
- Use a small overlay scanner for `NS_ENUM`/`NS_OPTIONS` typedef names so the
  declaration color survives tree-sitter recovery failures.
- Keep macro arguments such as `NSInteger`/`NSUInteger` plain when Xcode leaves
  them plain in the macro argument position.

Possible future work:

- Fork/fix `tree-sitter-objc` grammar for `NS_ENUM`/`NS_OPTIONS`; the runtime
  scanner is a compatibility layer, not a parser replacement.
- Re-check live Xcode on a real indexed project when changing the known macro
  set, because the current-file SourceEditor probe is too shallow here.

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

swift run EditorSpecTool xcode-classification-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.m \
  --language objectiveC --pretty

swift run EditorSpecTool classification-diff \
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

- Full companion-header parsing is out of scope for the runtime overlay.
  `Reference.m` approximates Xcode with current-source symbols plus the
  quoted-header lexical fallback; it does not build a project symbol index.
- Method selector and member lexical-scope coloring is still not full
  Objective-C name resolution. Quoted header imports enable the fallback, but
  the runtime does not read or validate the imported header contents.
- Current SourceEditor probes are current-file oriented and miss some delayed
  live-editor lexical-scope ranges. A non-zero `classification-diff` caused by
  selector references or `self` property/member chains can be expected.
- Standalone `DVTTextStorage` rendered snapshots are shallow for SourceEditor
  delayed classification and project header/index semantics.
- Preprocessor macro body token splitting is still incomplete outside common
  quoted string literals and function-like macro invocations whose names are
  declared in the current file.
- `NS_ENUM`/`NS_OPTIONS` grammar recovery is still weak. The runtime compensates
  only for the macro identifiers and typedef names observed in the reference
  header; it does not attempt to parse enum case semantics.
