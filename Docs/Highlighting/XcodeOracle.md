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
`specificationIdentifier`, `tokenName`, and source ranges.

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

Use this for the actual rendered color path in DVT-backed languages. It creates
`DVTTextStorage`, applies the Xcode theme, asks it to color the range, then
reads effective color and node type.

Current behavior:

- This is the strongest visual oracle for Objective-C.
- It shows many Objective-C class names, Foundation types, method names, and
  property names as ordinary identifier-colored text, even when SourceModel has
  structural `name.*` tokens.
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
```

Use this for Swift structured token classification. The tool-only target imports
private Xcode Swift modules and builds a `SymbolCacheEditorLanguage` around the
current file.

Important constraints:

- This is tool/test-only. The runtime package must not depend on Xcode private
  frameworks.
- Current-file semantic depth can classify same-file declarations, attributes,
  macros, and local references well enough for the current milestone.
- SDK/stdlib symbols need stronger oracle data before runtime tables are added.
  Do not guess `min`, `max`, `lowerBound`, or similar members from screenshots
  alone.

## Language Flag Notes

Use `objectiveC` for Objective-C `EditorSpecTool` commands. Do not use
`objective-c` with the tool command-line parser.

## Current Rule

When SourceModel and DVT disagree, choose the probe that matches the question:

- xclangspec/range investigation: SourceModel.
- visible editor color: DVT rendered snapshot for Objective-C.
- Swift semantic buckets: SourceEditor + SymbolCache.

