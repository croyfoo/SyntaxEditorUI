# EditorSpecSnapshot

Local tools for deriving reference syntax-coloring expectations from the
developer toolchain installed on this Mac.

These tools are intentionally outside the package products. They are for
fixture generation and investigation only; the package runtime must not depend
on private frameworks or local developer-tool installation details.

## Extract supported language specifications

```bash
python3 Tools/EditorSpecSnapshot/xclangspec_snapshot.py --pretty \
  > /tmp/editor-spec-snapshot.json
```

The snapshot includes every `.xclangspec` and `.xcsynspec` entry under
`SourceModel.framework`, every source language metadata plist needed by the
currently supported SyntaxEditorUI languages, and a derived rule closure for
each supported source language. The derived closure follows
`BasedOn`, `Tokenizer`, `IncludeRules`, `Rules`, `Start`, `End`, `AltEnd`,
`AltToken`, and `EntityNameMap` references when they point at known rule
identifiers.

To inspect a single language while still resolving from the full rule index:

```bash
python3 Tools/EditorSpecSnapshot/xclangspec_snapshot.py \
  --language Xcode.SourceCodeLanguage.HTML --pretty
```

Use `--all-languages` only when investigating unsupported languages.

## Generate package highlight definitions

```bash
python3 Tools/EditorSpecSnapshot/generate_highlight_definitions.py
```

This rewrites
`Sources/SyntaxEditorCore/Highlighting/BuiltInEditorSourceSyntaxDefinitions+Generated.swift`
from the local `.xclangspec` files. It keeps only the SyntaxEditorUI-supported
languages in package code.

## Extract SourceModel parse items

Build the private-framework probe:

```bash
clang -fobjc-arc -framework Foundation \
  Tools/EditorSpecSnapshot/source_model_snapshot.m \
  -o /tmp/source_model_snapshot
```

Run it against a sample file:

```bash
/tmp/source_model_snapshot \
  --language html \
  --file Tools/Mini/Mini/ReferenceSamples/Reference.html \
  --pretty
```

The output is a JSON list of flattened source model items with source ranges,
matched rule identifiers, token names, and `xcode.syntax.*` node type names.
It uses private framework APIs and is not suitable for app or package runtime.
