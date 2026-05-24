# Xcode Highlighting Research

This is a running research note for Xcode-aligned syntax highlighting in
SyntaxEditorUI. It is intentionally written as durable context for future
compaction and handoff, not as final user-facing documentation.

## Current Documentation Map

The active, organized notes are split by concern:

- [Highlighting/XcodeOracle.md](Highlighting/XcodeOracle.md): the shared Xcode
  oracle routes, what each route can prove, and the commands used to compare
  SyntaxEditorUI with Xcode.
- [Highlighting/SwiftAlignment.md](Highlighting/SwiftAlignment.md): Swift
  grammar/query/semantic-overlay findings and the known limits of the current
  SourceEditor + SymbolCache probe.
- [Highlighting/ObjectiveCAlignment.md](Highlighting/ObjectiveCAlignment.md):
  Objective-C xclangspec/DVT findings, current query policy, and grammar
  limitations.

This file remains the longer chronological research log. When new findings are
stable enough to guide implementation, copy the distilled result into the
language-specific files above.

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

swift run EditorSpecTool xcode-dvt-language-diagnostics \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool xcode-source-editor-view-diagnostics \
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

Diagnostic command:

```sh
swift run EditorSpecTool xcode-dvt-language-diagnostics \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty
```

Observed diagnostic result on 2026-05-18:

- `DVTPlugInManager.scanForPlugIns:` succeeds.
- `swiftSourceCodeLanguage`, `sourceCodeLanguageWithIdentifier:`,
  `sourceCodeLanguageForLanguageSpecificationIdentifier:`, and
  `sourceCodeLanguageForLanguageName:` all resolve Swift.
- Before explicit SourceModel spec registration, Swift's
  `languageSpecification` is a `MISSING` proxy for `xcode.lang.swift`.
- After explicitly registering SourceModel's `LanguageSpecifications`
  directory through
  `DVTSourceSpecification.registerSpecificationProxiesFromPropertyListsInDirectory:recursively:inBundle:`,
  Swift's `languageSpecification` becomes a real `DVTLanguageSpecification`
  named `Swift`, with `xcode.lang.simpleColoring` as its super specification.
- `DVTSourceSpecification.specificationForIdentifier:@"xcode.lang.swift"`
  still returns a `DVTSourceSpecification` missing proxy, while the language
  object itself returns a real `DVTLanguageSpecification`; these are related but
  not the same runtime class.
- Calling `_sourceCodeLanguageForExtension:` with a plain string is unsafe. The
  selector expects an internal object that responds to `identifier`, despite
  the selector name. `SourceModelBridge` therefore avoids this selector for
  file-extension fallback and maps known extensions to safe language class
  methods instead.
- Applying the explicit SourceModel spec registration to `DVTTextStorage`
  rendering makes this standalone process terminate during Swift coloring, so
  `xcode-dvt-rendered-tokens` currently leaves that registration disabled.

Current interpretation: DVT language resolution itself is now understood well
enough to diagnose. The remaining gap is not "Swift language cannot be found";
it is that the standalone `DVTTextStorage` coloring path either needs more of
Xcode's editor process initialization, or it is the wrong layer for the delayed
semantic state seen in the live editor UI.

The diagnostic command reports:

- `DVTSourceCodeLanguage.identifier`
- `DVTSourceCodeLanguage.languageName`
- `DVTSourceCodeLanguage.languageSpecification`
- `languageSpecification.identifier`
- the result of resolving Swift by:
  - `swiftSourceCodeLanguage`
  - `sourceCodeLanguageForLanguageSpecificationIdentifier:@"xcode.lang.swift"`
  - `sourceCodeLanguageForLanguageName:@"Swift"`
  - `sourceCodeLanguageWithIdentifier:@"Xcode.SourceCodeLanguage.Swift"`

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

Observed result on 2026-05-18:

- `SourceEditorView` is present in `SourceEditor.framework` as
  `_TtC12SourceEditor16SourceEditorView`.
- `nm | swift-demangle` shows a direct method symbol for
  `SourceEditor.SourceEditorView.syntaxType(location:effectiveRange:)`.
- The current generated `SourceEditor.swiftinterface` does not include
  `SourceEditorView`.
- A minimal manual interface declaration compiles far enough to type-check, but
  Swift resolves the method call through a dispatch thunk:
  `dispatch thunk of SourceEditor.SourceEditorView.syntaxType(...)`.
- That dispatch thunk is not exported, so the tool fails to link. Do not keep a
  half-working `xcode-source-editor-view-*` command in tree.

Runtime diagnostic command:

```sh
swift run EditorSpecTool xcode-source-editor-view-diagnostics \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty
```

Observed diagnostic result on 2026-05-18:

- `SourceEditor.SourceEditorView`,
  `_TtC12SourceEditor16SourceEditorView`, and
  `_TtC12SourceEditor24SnapshotSourceEditorView` all resolve as runtime
  classes.
- A zero-sized `SourceEditorView` can be instantiated in the standalone tool.
- `contentView`, `scrollView`, `replaceScrollViewWith:`, and
  `attributedSubstringForProposedRange:actualRange:` are Objective-C-visible
  selectors.
- `dataSource` / `setDataSource:` are not Objective-C selectors; they are
  Swift-only property accessors.
- `dlsym` can resolve the direct Swift symbols for:
  - `SourceEditorView.syntaxType(location:effectiveRange:)`
  - `SourceEditorView.dataSource` getter / setter dispatch thunks
  - `SourceEditorView.init(frame:)`

Current interpretation: Probe B is still viable, but it needs a lower-level
entry point than a normal Swift interface call. The likely options are:

- regenerate a fuller private Swift interface and confirm whether the method
  dispatch form changes;
- call the direct mangled symbols through `dlsym` / `unsafeBitCast`, starting
  with the `dataSource` setter and only then `syntaxType`;
- use Objective-C runtime only for selectors that are actually exposed, not for
  `dataSource` or `syntaxType`.

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

Observed result on 2026-05-18:

- The generated private interface currently checked in at
  `Tools/EditorSpecSnapshot/PrivateInterfaces/SymbolCacheIndexing.swiftmodule/arm64-apple-macos.swiftinterface`
  only exposes:

```swift
extension SymbolCache.FileParsingSymbolCache {
    public static func makeDefaultSymbolCache(
        name: Swift.String?,
        basePath: Swift.String?
    ) -> Self
}
```

- The framework binary exports substantially more SDK/module loading surface
  than that interface exposes. `nm | swift-demangle` shows:
  - `SDKModulesSymbolCache : SymbolCacheProvider`
  - `SDKSymbolCache : ModuleNameSymbolCacheProvider`
  - `SDKSymbolCache : LanguageSpecificSymbolCacheProvider`
  - `SDKSymbolCache.moduleName`
  - `SDKSymbolCache.isSwiftModule`
  - `SDKSymbolCache.visibleDependencies`
  - `SwiftImportedSDKSymbolCache`
  - `SymbolCacheSDKStorage.init(ioManager:)`
  - `SymbolCacheSDKIOManager.init(baseURL:onlySerializeSwift:)`
  - `SymbolCacheFrameworksIndex.init()`
  - `SymbolCacheFrameworksIndex.modulesSymbolCache`
  - `SymbolCacheFrameworksIndex.swiftCrossImportsIndex`
  - `SymbolCacheFrameworksIndex.addFrameworkSearchPath(_:)`
  - `SymbolCacheSystemIncludeIndex.init(url:modulesSymbolCache:)`
  - `SymbolCacheSDKImporter.init(sdkURL:toolchainModulesURL:storage:frameworksIndex:systemIncludeIndex:onlyLoadFromCache:useRelativePaths:)`
  - `SymbolCacheSDKImporter.implicitlyLoadedSwiftModules`
  - `SymbolCacheSDKLoadType.module(String)`
  - `SymbolCacheSDKLoadType.systemHeader(String)`
  - `SymbolCacheSDKLoadType.stdLib`
  - `SymbolCacheSDKLoader.init(sdkURL:toolchainModulesURL:variantName:storage:onlyLoadFromCache:useRelativePaths:)`
  - `SymbolCacheSDKLoader.modulesSymbolCache`
  - `SymbolCacheSDKLoader.frameworkTypes`
  - `SymbolCacheSDKRequestHandler.init(sdkLoader:frameworksToAlwaysLoad:)`
  - `SymbolCacheSDKRequestHandler.setModulesToLoad(_:addSDKSymbolCacheCallback:completionHandler:)`
  - `SymbolCacheSDKRequestHandler.setSdkFrameworksToLoad(_:addSDKSymbolCacheCallback:completionHandler:)`

- `SymbolCache.framework` also exports the provider plumbing needed to attach
  those caches:
  - `SymbolCacheProviderTokenStore.init(providers:)`
  - `SymbolCacheProviderTokenStore.addProvider(_:)`
  - `SymbolCacheProviderTokenStore.tokens`
  - `SymbolCacheComposite.providers`
  - `SymbolCacheComposite.symbolCaches`
  - `FileParsingSymbolCache.importsInFile(_:)`
  - `ProjectModulesSymbolCache`
  - `ModuleNameSymbolCacheProvider`
  - `LanguageSpecificSymbolCacheProvider`

- `SymbolCacheSupport.framework` confirms that the current path has the right
  high-level service object, but is likely underfed:
  - `SymbolCacheLanguageService.semanticServiceHelper`
  - `SymbolCacheLanguageService.typedSwiftTree()`
  - `SymbolCacheLanguageService.sourceModel`
  - `SymbolCacheDocumentSettings.shouldUseSemanticServiceHelper`
  - `SwiftTypeResolver.init(symbolCacheComposite:filePath:)`
  - `SwiftTypeResolver.resolve(scopedType:)`
  - `SwiftTypeResolver.scopeID(name:fileElement:lineHint:)`
  - `DataSourceObservingSymbolCache.startObserving(...)`

Current interpretation: Probe C is now the most likely next verification route
for `min`, `max`, `lowerBound`, and `upperBound`. The existing
`xcode-classification-tokens` command feeds `SourceEditor` only a current-file
`FileParsingSymbolCache.snapshot()`. It does not attach stdlib, SDK, imported
module, or project module providers. If Xcode's live editor has a delayed pass
that colors those names through standard-library or SDK providers, the current
CLI oracle cannot observe it.

Concrete next step:

1. Extend the tool-only generated Swift interfaces just enough to expose
   `SymbolCacheSDKLoader`, `SymbolCacheSDKRequestHandler`,
   `SymbolCacheSDKLoadType`, `SDKSymbolCache`, `SDKModulesSymbolCache`,
   `SymbolCacheFrameworksIndex`, `SymbolCacheSystemIncludeIndex`,
   `SymbolCacheSDKStorage`, and `SymbolCacheSDKIOManager`.
2. Locate the active macOS SDK URL and Swift toolchain module URL from Xcode.
3. Create an SDK loader with `.stdLib` and imported modules from
   `FileParsingSymbolCache.importsInFile(_:)`.
4. Add returned `SDKSymbolCache` providers, plus `modulesSymbolCache`, into
   the same `SymbolCacheProviderTokenStore` used by
   `ToolSymbolCacheComposite`.
5. Re-run `xcode-classification-tokens` and focused inspection for
   `min/max/lowerBound/upperBound`.

Do this before pursuing the lower-level `SourceEditorView` ABI call. The
`SourceEditorView` path may still be necessary later, but it will remain
underfed if the `SymbolCacheComposite` does not contain SDK/module providers.

Risk:

- The API surface is mostly not in the current generated Swift interface.
- This may need regenerated private interfaces with MachOSwiftSection, or
  Objective-C/runtime calls where possible.
- Loading SDK caches may be slow or may require Xcode-specific storage paths.
- Some member coloring may still require a semantic service helper or typed
  Swift tree, even after SDK providers are present.

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
- What exact URL does Xcode use for Swift toolchain modules when constructing
  `SymbolCacheSDKLoader`?
- Which providers are present in Xcode's live `SymbolCacheProviderTokenStore`
  after the delayed semantic pass?

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
  | rg "SDKModulesSymbolCache|SwiftImportedSDKSymbolCache|SDKSymbolCache|SymbolCacheSDK(Importer|LoadType|IOManager|LoaderManager|RequestHandler|Storage)|SymbolCacheFrameworksIndex"

xcrun nm -gU /Applications/Xcode.app/Contents/SharedFrameworks/SymbolCache.framework/Versions/A/SymbolCache \
  | xcrun swift-demangle \
  | rg "ModuleNameSymbolCacheProvider|LanguageSpecificSymbolCacheProvider|SymbolCacheProviderTokenStore|FileParsingSymbolCache.importsInFile|ProjectModulesSymbolCache|SymbolCacheComposite"
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

swift run EditorSpecTool xcode-dvt-language-diagnostics \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool xcode-source-editor-view-diagnostics \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

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

Probe A has now shown that DVT language resolution can be diagnosed, but the
standalone DVT coloring path is still not a useful Swift oracle. Probe B has a
runtime entry point, but needs unsafe direct Swift ABI calls and still depends
on having a rich symbol cache.

The next implementation step should therefore be Probe C: enrich the
`SourceEditor + SymbolCache` oracle with stdlib/SDK/imported-module providers
from `SymbolCacheIndexing`, then re-check the current mismatch terms. Only move
to direct `SourceEditorView.syntaxType` calls if the enriched composite still
does not expose the live Xcode behavior.
