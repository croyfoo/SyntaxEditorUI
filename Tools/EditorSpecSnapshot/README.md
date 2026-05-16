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

## Generate package syntax vocabularies

```bash
python3 Tools/EditorSpecSnapshot/generate_highlight_definitions.py
```

This rewrites the `*Language+Generated.swift` files in each
`Sources/SyntaxEditorCore/Languages/<Language>/` directory from the local
`.xclangspec` files and refreshes generated word-list blocks in the bundled
`highlights.scm` resources. Package runtime code keeps only the
SyntaxEditorUI-supported vocabulary; theme fallback and Tree-sitter node
matching stay in handwritten source.

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

## Swift rule model target

`XclangSpecSyntax` is a package-internal Swift target for modeling
`.xclangspec` / `.xcsynspec` rule files. It parses plist documents, preserves
unknown rule fields, and builds rule-reference closures from `BasedOn`,
`Tokenizer`, `IncludeRules`, `Rules`, `Start`, `End`, `Until`, `AltUntil`,
`AltEnd`, `AltToken`, `EntityNameMap`, and `LanguageEmbeddings`. It also exposes
the installed `Syntax` metadata keys used by Xcode 26.5 specs, including
word scanners, regex matches, capture types, source scanner names, traversal
flags, and indentation/folding flags. Keep private-framework probes in this
tool directory; package runtime code should depend on generated data or the
`XclangSpecSyntax` model, not on Xcode frameworks.
