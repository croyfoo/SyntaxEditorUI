# Xcode Highlighting Oracle

This note defines the mechanical probes used when aligning SyntaxEditorUI
highlighting with Xcode. Screenshots are useful for spotting symptoms, but they
are not the oracle. The oracle should expose token ranges, syntax buckets, and
when possible the rendered color that Xcode actually applies.

## Probe Routes

### SourceModel

Command:

```sh
swift run EditorSpecTool source-model-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.m \
  --language objectiveC --pretty
```

Use this for xclangspec/rule investigation. It is close to the
`SourceModel.framework` language specification layer and exposes
`specificationIdentifier`, `tokenName`, and source ranges. The ObjC language
specification used for re-checks is:

```text
/Applications/Xcode.app/Contents/SharedFrameworks/SourceModel.framework/Versions/A/Resources/LanguageSpecifications/ObjectiveC.xclangspec
```

Limitations:

- It is a lexical/spec-layer view, not always the final editor UI view.
- For Swift, it is too shallow for late semantic coloring.
- For Objective-C, it emits structural buckets like `name.type`,
  `name.partial`, and `name.tree` that do not necessarily map to visible
  colored categories in Xcode's editor.

### DVTTextStorage Rendered Snapshot

Command:

```sh
swift run EditorSpecTool xcode-dvt-rendered-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.m \
  --language objectiveC --pretty

swift run EditorSpecTool rendered-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.m \
  --language objectiveC --pretty
```

Use this as a standalone DVT/theme probe. It creates `DVTTextStorage`, applies
the Xcode theme, asks it to color the range, then reads effective color and node
type.

Current behavior:

- It is useful for shallow lexical coloring and theme extraction.
- It can under-report Objective-C coloring that Xcode's live SourceEditor path
  applies after the editor has SourceModel/SymbolCache-backed classification.
- It logs duplicate language-registration messages and CoreText warnings in
  this environment. Those logs are noisy but not currently fatal.

Limitations:

- Rendered diffs still count color-space/color-value differences even when the
  syntax bucket is aligned. Treat the row content, not only the summary number,
  as the evidence.
- For Swift, this path has not been the useful semantic oracle so far.

### SourceEditor + SymbolCache

Command:

```sh
swift run EditorSpecTool xcode-classification-tokens \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool classification-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.swift \
  --language swift --pretty

swift run EditorSpecTool classification-diff \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.m \
  --language objectiveC --pretty
```

Use this for structured token classification in Xcode's SourceEditor path. The
tool-only target imports private Xcode modules and builds a
`SymbolCacheEditorLanguage` around the current file where the language supports
it.

Important constraints:

- This is tool/test-only. The runtime package must not depend on Xcode private
  frameworks.
- Current-file semantic depth can classify same-file declarations, attributes,
  and macros well enough for the current milestone.
- Objective-C classification currently exposes SourceEditor UIKind buckets such
  as `typeDeclaration` and `otherDeclaration`. This is closer to the live editor
  pipeline than standalone DVT snapshots, but it is still not a full project
  index replay.
- For Objective-C, current-file classification can under-report delayed live
  lexical-scope coloring. In particular, selector references and
  current-file or header-backed member chains may appear as `plain` in
  `classification-diff` even when the live Xcode editor colors them.
- Objective-C Apple macro identifiers are another current-file under-reporting
  case. `NS_ASSUME_NONNULL_*`, `NS_SWIFT_NAME`, `NS_ENUM`, and `NS_OPTIONS`
  can appear as `plain` in `classification-diff`, while the live editor colors
  the macro identifier as preprocessor and colors the `NS_ENUM`/`NS_OPTIONS`
  typedef name as a type declaration.
- Objective-C implementation files need one extra runtime assumption: a quoted
  `#import "Header.h"` is visible to Xcode's project index but not to
  `SyntaxHighlighterEngine`, which receives only source text. For those files,
  use xclangspec/live-editor evidence to preserve lexical member/type buckets
  without adding a full header parser.
- Runtime tables should stay fixture-backed. Objective-C currently keeps a small
  imported/runtime helper list for functions visible in the reference sample
  (`objc_msgSend`, `NSSelectorFromString`, `NSMakeRange`, etc.); do not add
  broad Swift-style tables such as `min`, `max`, `lowerBound`, or similar names
  from screenshots alone.

## Language Flag Notes

Use `objectiveC` for Objective-C `EditorSpecTool` commands. Do not use
`objective-c` with the tool command-line parser.

## Current Rule

When SourceModel and DVT disagree, choose the probe that matches the question:

- xclangspec/range investigation: SourceModel.
- standalone theme/color extraction: DVT rendered snapshot.
- live-editor bucket alignment for Swift: SourceEditor + SymbolCache
  classification, backed by live Xcode screenshots when the tool lacks
  project/index context.
- live-editor bucket alignment for Objective-C: SourceEditor + SymbolCache for
  declaration UIKind buckets, plus live Xcode and `ObjectiveC.xclangspec` /
  SourceModel range evidence for delayed lexical-scope colors.
