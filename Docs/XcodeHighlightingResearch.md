# Xcode Highlighting Research

This is a running research note for Xcode-aligned syntax highlighting in
SyntaxEditorUI. It is intentionally written as durable context for future
compaction and handoff, not as final user-facing documentation.

## Goal

Make Swift highlighting mechanically verifiable against Xcode.app behavior.
Screenshots are useful symptoms, but they are not the oracle. The useful oracle
needs to expose token classification, semantic scope, and rendered color as
structured data.

The current problem case is:

```swift
didSet { wrappedValue = min(max(wrappedValue, range.lowerBound), range.upperBound) }
self.wrappedValue = min(max(wrappedValue, range.lowerBound), range.upperBound)
```

In screenshots, `min`, `max`, `lowerBound`, and `upperBound` still do not look
fully aligned with Xcode. The existing mechanical probes do not currently see a
classification difference there, so the verification layer itself needs more
work.

## Current Tooling

`EditorSpecTool` lives under `Tools/EditorSpecSnapshot/EditorSpecTool`. It is a
SwiftPM executable and is intentionally not part of the public package runtime.

Current commands:

```sh
swift run EditorSpecTool editor-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool source-model-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool xcode-classification-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool xcode-rendered-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool xcode-dvt-rendered-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool classification-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool rendered-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty
```

As of 2026-05-18, for `Tools/Mini/Mini/ReferenceSamples/Reference.swift`:

- `classification-diff`: `differences: 0`
- `rendered-diff`: `differences: 0`
- Xcode-side `xcode-classification-tokens` reports `min`, `max`,
  `lowerBound`, and `upperBound` as `plain`
- Xcode-side `xcode-rendered-tokens` also routes those ranges through the same
  SourceEditor classification path for Swift, so it also reports them as
  `plain`
- `xcode-dvt-rendered-tokens` runs, but currently logs
  `Couldn't load language spec for 'Xcode.SourceCodeLanguage.Swift'` and emits
  broad `plain` line ranges for Swift. It is not a useful Swift oracle yet.

This means the current oracle matches SyntaxEditorUI, but may not match the
fully rendered Xcode UI after Xcode has loaded delayed semantic information.

## Xcode Framework Paths

Known installed Xcode paths:

```text
/Applications/Xcode.app/Contents/SharedFrameworks/SourceModel.framework
/Applications/Xcode.app/Contents/SharedFrameworks/SourceEditor.framework
/Applications/Xcode.app/Contents/SharedFrameworks/SymbolCache.framework
/Applications/Xcode.app/Contents/SharedFrameworks/SymbolCacheIndexing.framework
/Applications/Xcode.app/Contents/SharedFrameworks/SymbolCacheSupport.framework
/Applications/Xcode.app/Contents/SharedFrameworks/DVTSourceEditor.framework
/Applications/Xcode.app/Contents/SharedFrameworks/DVTKit.framework
/Applications/Xcode.app/Contents/SharedFrameworks/DVTFoundation.framework
/Applications/Xcode.app/Contents/SharedFrameworks/SourceKit.framework
```

Language specs are under:

```text
/Applications/Xcode.app/Contents/SharedFrameworks/SourceModel.framework/Versions/A/Resources/LanguageSpecifications
```

Swift theme files used by SourceEditor are under:

```text
/Applications/Xcode.app/Contents/SharedFrameworks/SourceEditor.framework/Versions/A/Resources/Default (Dark).xccolortheme
/Applications/Xcode.app/Contents/SharedFrameworks/SourceEditor.framework/Versions/A/Resources/Default (Light).xccolortheme
```

## Probe Routes

### 1. SourceModel Rule Probe

Implementation:

- `Sources/SourceModelBridge/SourceModelBridge.m`
- `SourceModelBridge.snapshot(...)`
- `EditorSpecTool source-model-tokens`

Mechanism:

1. Loads `SourceModel.framework`.
2. Resolves an `SMSourceCodeLanguage`.
3. Creates `SMSourceModel` with a lightweight buffer provider.
4. Calls `parse`.
5. Enumerates source model items with range, token, node type, token name, and
   specification identifier.

Use this for:

- xclangspec/rule investigation
- non-Swift source model behavior
- checking lexical/spec token boundaries

Do not treat this as the main Swift UI oracle. For Swift, SourceModel is lower
level than Xcode's SourceEditor/SymbolCache path and does not represent the
late semantic classification observed in the editor UI.

### 2. DVTTextStorage Render Probe

Implementation:

- `Sources/SourceModelBridge/SourceModelBridge.m`
- `SourceModelBridge.renderedSnapshot(...)`
- Non-Swift `EditorSpecTool xcode-rendered-tokens`

Mechanism:

1. Loads `DVTFoundation.framework`, `SourceModel.framework`, and
   `DVTKit.framework`.
2. Initializes `DVTDeveloperPaths`.
3. Scans DVT plugins.
4. Registers DVT source specifications.
5. Creates `DVTTextStorage`.
6. Applies `DVTFontAndColorTheme`.
7. Sets language and enables syntax coloring.
8. Calls `fixSyntaxColoringInRange:`.
9. Reads `colorAtCharacterIndex:effectiveRange:context:` and
   `nodeTypeAtCharacterIndex:effectiveRange:context:`.

Use this for:

- rendered color inspection
- languages where SourceEditor/SymbolCache Swift semantic path is not used
- theme/color regressions

Open issue:

- For Swift, `EditorSpecTool` currently avoids this path and uses
  SourceEditor/SymbolCache classification instead. If Xcode UI visual behavior
  differs from SourceEditor token classification, we need to test whether the
  DVTTextStorage path captures the UI's later coloring pass for Swift.

### 3. SourceEditor + SymbolCache Probe

Implementation:

- `Tools/EditorSpecSnapshot/EditorSpecTool/main.swift`
- `EditorSpecTool xcode-classification-tokens`
- `EditorSpecTool xcode-rendered-tokens`
- `EditorSpecTool classification-diff`
- `EditorSpecTool rendered-diff`

Mechanism:

1. Imports private Swift modules:
   - `SourceEditor`
   - `SymbolCache`
   - `SymbolCacheIndexing`
   - `SymbolCacheSupport`
2. Builds a `GenericLanguage` named `Swift`, backed by
   `SymbolCacheLanguageService`.
3. Wraps it in `SymbolCacheEditorLanguage`.
4. Creates a `FileParsingSymbolCache` with `makeDefaultSymbolCache`.
5. Parses the current file only.
6. Wraps the snapshot in a `SymbolCacheComposite`.
7. Creates `BasicSymbolCacheDocumentSettings`.
8. Creates `SourceEditorDataSource`.
9. Sets `SymbolCacheLanguageService.symbolCacheComposite`.
10. Calls `documentSettingsChanged(filePath)`.
11. Enumerates syntax tokens line by line.
12. For each token range, asks:

```swift
syntaxTypeAtPosition(position, includingSemanticsAndDocumentation: true)
```

Useful interface facts:

```swift
public protocol SourceEditorSyntaxTokenProvider {
    func syntaxTypeAtPosition(_:) -> (SourceEditorTokenType?, Range<SourceEditorPosition>)?
    func syntaxTypeAtPosition(
        _: SourceEditorPosition,
        includingSemanticsAndDocumentation: Bool
    ) -> (SourceEditorTokenType?, Range<SourceEditorPosition>)?
    func enumerateSyntaxTokensOnLine(_: Int, handler: (SourceEditorTokenType, Range<Int>) -> ())
}
```

`SourceEditorTokenType.UIKind` exposes the semantic color buckets we currently
map into `EditorSourceSyntaxID`:

```swift
case className(Scope)
case typeName(Scope)
case functionMethodName(Scope)
case constant(Scope)
case instanceGlobalVariable(Scope)
case preprocessorMacro(Scope)
case attribute
case keyword
case comment
case documentationComment
case mark
...

enum Scope {
    case external
    case project
}
```

This is the strongest structured oracle currently wired into the repo, but it
does not fully explain the screenshot mismatch for `min`, `max`, `lowerBound`,
or `upperBound`.

## What the Binary Symbols Suggest

`SymbolCacheSupport.framework` exposes more behavior than the thin generated
Swift interface currently used by `EditorSpecTool`.

Observed exported/demangled names include:

- `SymbolCacheLanguageService.semanticServiceHelper`
- `SymbolCacheLanguageService.registerServiceHelper(...)`
- `SymbolCacheLanguageService.clearSemanticCache()`
- `SymbolCacheLanguageService.typedSwiftTree()`
- `SymbolCacheLanguageService.asyncSwiftTreeContext(...)`
- `SymbolCacheLanguageService.singleUseAsyncSwiftTreeContext(...)`
- `SymbolCacheLanguageService.isPropertyOrMethodReference(at:)`
- `SymbolCacheLanguageService.isDeclarationIdentifier(at:)`
- `SymbolCacheLanguageService.rangeForUSR(_:)`
- `SymbolCacheLanguageService.referencesToSymbolAtPosition(...)`
- `SymbolCacheLanguageService.navigationToSymbolAtPosition(...)`
- `SymbolCacheLanguageService.sourceModel`
- `SwiftTypeResolver`
- `SwiftSymbolTable`
- `SwiftTreeContext`
- `SwiftSourceModelToSymbolCacheElementTranslator`
- `SymbolReferenceGraphReporter`
- `DataSourceObservingSymbolCache`
- `SingleFileSymbolCacheComposite`
- `SwiftProjectFilesSideTable`

`SymbolCacheIndexing.framework` exposes SDK/module import machinery:

- `SDKModulesSymbolCache`
- `SDKSymbolCache`
- `SwiftImportedSDKSymbolCache`
- `SymbolCacheSDKLoader`
- `SymbolCacheSDKImporter`
- `SymbolicSwiftInterfacesIndex`
- `SwiftModuleImporter`
- `SwiftSourceModelToSymbolCacheElementTranslator`
- `SourceModelSymbolCacheLanguageParser`

This suggests Xcode's full editor can potentially combine:

- current file parsing
- project/module symbol cache
- SDK symbol cache
- Swift typed tree / type resolver
- optional semantic service helper

The current `EditorSpecTool` only builds a very small single-file cache and
does not load SDK symbol caches.

## Current Mismatch Hypothesis

The Xcode UI likely has at least two observable phases:

1. A fast syntactic/source-model pass.
2. A later semantic pass backed by SymbolCache/SourceKit/index data.

The current `SourceEditor + SymbolCache` probe asks for semantics, but it only
feeds a current-file `FileParsingSymbolCache` into a minimal composite. That is
enough for some same-file/project-ish identifiers, but not necessarily enough
for standard library globals or typed member resolution.

For the concrete case:

- `min` / `max` require knowing that an unresolved call callee is a standard
  library function, or at least applying a conservative external-call heuristic.
- `lowerBound` / `upperBound` require knowing that `range` has type
  `ClosedRange<Value>` and that those names are members of that type.

Tree-sitter grammar and `highlights.scm` cannot correctly infer that. A correct
Xcode-like result needs either:

- Xcode's semantic service/index/cache path, or
- a SyntaxEditorUI-owned semantic approximation with local type inference and
  a standard-library member table.

The first option is preferred for verification. The second option is only an
implementation fallback after we know what Xcode's structured oracle says.

## Why Current Diff Can Be Zero While Screenshot Looks Wrong

Current Swift rendered diff does not sample the real Xcode editor view. It maps
SourceEditor token classification through Xcode's `Default (Dark/Light)` theme.

Therefore:

- If `SourceEditorTokenType` says `plain`, rendered diff also expects plain.
- If the live Xcode UI later recolors the same range through a path not exposed
  by our current `SymbolCacheLanguageService` setup, current diff will stay at
  zero.
- Screenshot mismatch is then not a theme/color-space problem; it is an oracle
  coverage problem.

## Practical Verification Gaps

Known gaps:

- We do not instantiate a real `SourceEditorView`.
- We do not inspect `SourceEditorView.syntaxType(location:effectiveRange:)`.
- We do not inspect line layers / attributed storage after layout.
- We do not attach a real Xcode project/workspace symbol cache.
- We do not load SDK symbol caches through `SymbolCacheIndexing`.
- We do not wire a `SemanticServiceHelper`.
- The generated private Swift interfaces under
  `Tools/EditorSpecSnapshot/PrivateInterfaces` are intentionally minimal and do
  not include many symbols visible through `nm`.

## Candidate Next Probes

### Probe A: DVTTextStorage Swift Render Snapshot

Goal: check whether `DVTTextStorage` captures the color seen in Xcode's editor
for Swift better than the current SourceEditor token route.

Work:

- Add a Swift-specific command to force `SourceModelBridge.renderedSnapshot`.
- Compare `min`, `max`, `lowerBound`, and `upperBound`.
- If this sees the screenshot behavior, use it as the rendered UI oracle.

Current command:

```sh
swift run EditorSpecTool xcode-dvt-rendered-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty
```

Observed result on 2026-05-18:

- Command exits successfully.
- STDERR repeatedly logs `Couldn't load language spec for
  'Xcode.SourceCodeLanguage.Swift'`.
- Output chunks are broad line ranges with `nodeType: 0` and `syntaxID: plain`.
- The `min/max/lowerBound/upperBound` lines are emitted as whole plain lines,
  so this probe does not yet capture the Xcode UI state.

Additional observations:

- `Swift.xclangspec` exists under SourceModel resources and its first rule
  identifiers are `xcode.lang.swift.identifier`,
  `xcode.lang.swift.identifier.attribute`,
  `xcode.lang.swift.preprocessor.keyword`, and related Swift rule names.
- `DVTSourceCodeLanguage` exposes `swiftSourceCodeLanguage`,
  `sourceCodeLanguageForLanguageSpecificationIdentifier:`,
  `sourceCodeLanguageForFileDataTypeIdentifier:`, and
  `sourceCodeLanguageForLanguageName:` according to Xcode framework strings.
- `DVTSourceSpecification` exposes
  `searchForAndRegisterAllAvailableSpecifications`.
- `DVTTextStorage` exposes `sourceLanguageServiceContext` and
  `fixSyntaxColoringInRange:`.
- `~/PrivateHeaderKit/generated-headers` did not have generated headers for
  `DVTSourceCodeLanguage` or `DVTSourceSpecification` in the current local
  header snapshot, so this path still needs runtime probing rather than header-
  guided implementation.

Current interpretation: the DVT text-storage route is not yet initialized the
same way Xcode initializes its editor process. The file-level language
identifier resolves far enough to produce a Swift `DVTSourceCodeLanguage`, but
that object cannot load its language spec in this standalone tool process.
Before treating DVT output as a failed oracle, try a dedicated DVT language
diagnostic command that reports:

- `DVTSourceCodeLanguage.identifier`
- `DVTSourceCodeLanguage.languageName`
- `DVTSourceCodeLanguage.languageSpecification`
- `languageSpecification.identifier`
- the result of resolving Swift by:
  - `swiftSourceCodeLanguage`
  - `sourceCodeLanguageForLanguageSpecificationIdentifier:@"xcode.lang.swift"`
  - `sourceCodeLanguageForLanguageName:@"Swift"`
  - `_sourceCodeLanguageForExtension:@"swift"`

Risk:

- DVTTextStorage may still only provide the fast syntax-color pass without
  delayed semantic symbol colors.

### Probe B: SourceEditorView-Based Snapshot

Goal: instantiate the same `SourceEditorView` stack that Xcode uses and read
the view/dataSource token or attributed-color state after layout.

Work:

- Create a tool-only macOS probe.
- Build `SourceEditorDataSource` and `SourceEditorView`.
- Attach color/font themes.
- Let layout finish.
- Read either:
  - `SourceEditorView.syntaxType(location:effectiveRange:)`, or
  - line layer attributed data if accessible.

Risk:

- UI classes may require more Xcode IDE initialization than the CLI tool
  currently performs.
- A view snapshot may still not produce full semantics unless project/index
  services are attached.

### Probe C: Rich SymbolCache Composite

Goal: feed SourceEditor the same kinds of symbol caches Xcode has available.

Work:

- Investigate `SymbolCacheIndexing.SymbolCacheSDKLoader`.
- Load standard library / SDK modules into `SDKModulesSymbolCache`.
- Provide those providers through `SymbolCacheProviderTokenStore`.
- Re-run `syntaxTypeAtPosition(... includingSemanticsAndDocumentation: true)`.

Risk:

- The API surface is mostly not in the current generated Swift interface.
- This may need regenerated private interfaces with MachOSwiftSection, or
  Objective-C/runtime calls where possible.

### Probe D: SourceKit/IndexStore Semantic Tokens

Goal: ask the compiler/sourcekit layer for semantic classification directly.

Work:

- Investigate `SourceKit.framework`, `SourceKitSupport.framework`, and
  `IndexStoreDB_*` frameworks.
- Determine whether Xcode exposes semantic-token-like data for editor coloring.

Risk:

- This may reproduce SourceKit-LSP style semantic tokens, not Xcode editor
  colors.
- It may over-classify relative to Xcode's UI taxonomy.

## Implementation Boundary

Runtime package code must not depend on Xcode private frameworks.

Allowed:

- tool-only probes
- fixture generation
- generated vocabulary/query data
- generated expected snapshots
- private Swift interfaces under `Tools/EditorSpecSnapshot/PrivateInterfaces`

Not allowed:

- shipping Xcode private framework linkage in `SyntaxEditorUI`
- exposing private framework concepts through public package API

## Current Architecture Split

Keep the current responsibility split unless evidence changes it:

- `highlights.scm`: query-expressible lexical/syntactic classification
- `dependencies/tree-sitter-swift`: parse-tree boundary fixes
- `SwiftSyntaxOverlayTokenProvider`: semantic-ish overlay that cannot be cleanly
  expressed in query
- `SwiftFileSymbolIndex`: file-local project/external approximation
- `EditorSpecTool`: Xcode oracle and diff generation

If a mismatch needs type resolution (`range.lowerBound`) it does not belong in
the grammar or query.

## Open Questions

- Does `DVTTextStorage` for Swift report the live UI colors for
  `min/max/lowerBound/upperBound`, or only the fast syntactic colors?
- Can a standalone `SourceEditorView` be initialized enough to expose the
  delayed semantic color state?
- What concrete object provides `SemanticServiceHelper` in Xcode?
- Does `BasicSymbolCacheDocumentSettings.shouldUseSemanticServiceHelper` return
  true, and if so, why does the current minimal tool still miss the screenshot
  behavior?
- What providers does Xcode put into its real `SymbolCacheComposite` for open
  Swift files?
- Can `SymbolCacheSDKLoader` load enough standard library/SDK symbols for a CLI
  oracle?
- Do `min/max` and `ClosedRange.lowerBound/upperBound` become typed/system
  tokens if the SDK/module symbol caches are present?

## Useful Commands

Inspect current Xcode framework Swift symbols:

```sh
xcrun nm -gU /Applications/Xcode.app/Contents/SharedFrameworks/SymbolCacheSupport.framework/Versions/A/SymbolCacheSupport \
  | xcrun swift-demangle \
  | rg "SymbolCacheLanguageService|SwiftTypeResolver|SwiftSymbolTable|Semantic|syntaxType"

xcrun nm -gU /Applications/Xcode.app/Contents/SharedFrameworks/SourceEditor.framework/Versions/A/SourceEditor \
  | xcrun swift-demangle \
  | rg "SourceEditorSyntaxTokenProvider|SourceEditorView|SourceEditorTokenType|SemanticServiceHelper"

xcrun nm -gU /Applications/Xcode.app/Contents/SharedFrameworks/SymbolCacheIndexing.framework/Versions/A/SymbolCacheIndexing \
  | xcrun swift-demangle \
  | rg "SymbolCacheSDK|SwiftSourceModel|SwiftModule|SDKModulesSymbolCache"
```

Inspect Xcode spec files:

```sh
plutil -p /Applications/Xcode.app/Contents/SharedFrameworks/SourceModel.framework/Versions/A/Resources/LanguageSpecifications/Swift.xclangspec
plutil -p "/Applications/Xcode.app/Contents/SharedFrameworks/SourceModel.framework/Versions/A/Resources/LanguageSpecifications/Built-in Syntax Types.xcsynspec"
```

Run current Swift oracle:

```sh
swift run EditorSpecTool classification-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool rendered-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty
```

Focused inspection for the current mismatch:

```sh
swift run EditorSpecTool xcode-classification-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty \
  | rg -n -C 5 '"text" : "(min|max|lowerBound|upperBound|range|wrappedValue)"'

swift run EditorSpecTool xcode-dvt-rendered-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty \
  | rg -n -C 5 '"text" : "(min|max|lowerBound|upperBound|range|wrappedValue)"'

swift run EditorSpecTool editor-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty \
  | rg -n -C 5 '"text" : "(min|max|lowerBound|upperBound|range|wrappedValue)"'
```

## Immediate Recommendation

Do not change SyntaxEditorUI's semantic overlay for `min/max/lowerBound` yet.
The current structured oracle says they are plain, while the screenshot suggests
the oracle is incomplete. First add a new tool-only verification route that can
observe the Xcode.app framework path closer to the real editor UI.

Start with Probe A because it is the smallest change. If DVTTextStorage does not
show the mismatch, move to Probe B or C.
