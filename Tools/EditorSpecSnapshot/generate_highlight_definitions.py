#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import xclangspec_snapshot


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = (
    REPOSITORY_ROOT
    / "Sources"
    / "SyntaxEditorCore"
    / "Highlighting"
    / "BuiltInEditorSourceSyntaxDefinitions+Generated.swift"
)
DEFAULT_QUERY_ROOT = REPOSITORY_ROOT / "Sources" / "SyntaxEditorCore" / "Resources"

LANGUAGE_CASES = {
    "Xcode.SourceCodeLanguage.CSS": "css",
    "Xcode.SourceCodeLanguage.HTML": "html",
    "Xcode.SourceCodeLanguage.JavaScript": "javascript",
    "Xcode.SourceCodeLanguage.JSON": "json",
    "Xcode.SourceCodeLanguage.Objective-C": "objectiveC",
    "Xcode.SourceCodeLanguage.Swift": "swift",
    "Xcode.SourceCodeLanguage.TOML_INI": "toml",
    "Xcode.SourceCodeLanguage.XML": "xml",
}

QUERY_DIRECTORY_NAMES = {
    "css": "CSSQueries",
    "html": "HTMLQueries",
    "javascript": "JavaScriptQueries",
    "json": "JSONQueries",
    "objectiveC": "ObjectiveCQueries",
    "swift": "SwiftQueries",
    "toml": "TOMLQueries",
    "xml": "XMLQueries",
}

GENERATED_BLOCK_BEGIN = "; BEGIN GENERATED EDITOR SYNTAX WORDS: {name}"
GENERATED_BLOCK_END = "; END GENERATED EDITOR SYNTAX WORDS: {name}"

CSS_STABLE_AT_RULE_WORDS = {
    "@keyframes",
    "@supports",
}

OBJECTIVEC_STABLE_ATTRIBUTE_WORDS = {
    "@autoreleasepool",
    "@catch",
    "@compatibility_alias",
    "@defs",
    "@dynamic",
    "@end",
    "@finally",
    "@implementation",
    "@interface",
    "@optional",
    "@property",
    "@protocol",
    "@required",
    "@selector",
    "@synchronized",
    "@synthesize",
    "@throw",
    "@try",
}

STYLE_KEY_FALLBACKS = {
    "plain": ["editor.syntax.plain"],
    "comment": ["editor.syntax.comment"],
    "comment.doc": ["editor.syntax.comment.doc", "editor.syntax.comment"],
    "comment.doc.keyword": ["editor.syntax.comment.doc.keyword", "editor.syntax.comment.doc", "editor.syntax.comment"],
    "mark": ["editor.syntax.mark", "editor.syntax.comment"],
    "string": ["editor.syntax.string", "editor.syntax.character"],
    "character": ["editor.syntax.character", "editor.syntax.string"],
    "number": ["editor.syntax.number"],
    "keyword": ["editor.syntax.keyword"],
    "preprocessor": ["editor.syntax.preprocessor", "editor.syntax.keyword"],
    "url": ["editor.syntax.url", "editor.syntax.number"],
    "attribute": ["editor.syntax.attribute", "editor.syntax.identifier.variable", "editor.syntax.plain"],
    "declaration.other": ["editor.syntax.declaration.other", "editor.syntax.identifier.function", "editor.syntax.plain"],
    "declaration.type": ["editor.syntax.declaration.type", "editor.syntax.identifier.type", "editor.syntax.plain"],
    "identifier.type": ["editor.syntax.identifier.type", "editor.syntax.declaration.type", "editor.syntax.plain"],
    "identifier.type.system": ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type", "editor.syntax.plain"],
    "identifier.class": ["editor.syntax.identifier.class", "editor.syntax.identifier.type", "editor.syntax.plain"],
    "identifier.class.system": ["editor.syntax.identifier.class.system", "editor.syntax.identifier.class", "editor.syntax.plain"],
    "identifier.function": ["editor.syntax.identifier.function", "editor.syntax.declaration.other", "editor.syntax.plain"],
    "identifier.function.system": ["editor.syntax.identifier.function.system", "editor.syntax.identifier.function", "editor.syntax.plain"],
    "identifier.macro": ["editor.syntax.identifier.macro", "editor.syntax.declaration.other", "editor.syntax.plain"],
    "identifier.macro.system": ["editor.syntax.identifier.macro.system", "editor.syntax.identifier.macro", "editor.syntax.plain"],
    "identifier.constant": ["editor.syntax.identifier.constant", "editor.syntax.plain"],
    "identifier.constant.system": ["editor.syntax.identifier.constant.system", "editor.syntax.identifier.constant", "editor.syntax.plain"],
    "identifier.variable": ["editor.syntax.identifier.variable", "editor.syntax.plain"],
    "identifier.variable.system": ["editor.syntax.identifier.variable.system", "editor.syntax.identifier.variable", "editor.syntax.plain"],
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate bundled editor source syntax definitions from local xclangspec files."
    )
    parser.add_argument(
        "--xcode",
        default=str(xclangspec_snapshot.DEFAULT_TOOLCHAIN_APP),
        help="Path to the local developer tool app bundle.",
    )
    parser.add_argument(
        "--output",
        default=str(DEFAULT_OUTPUT),
        help="Swift file to rewrite.",
    )
    parser.add_argument(
        "--query-root",
        default=str(DEFAULT_QUERY_ROOT),
        help="Root directory containing bundled query resources.",
    )
    parser.add_argument(
        "--skip-query-update",
        action="store_true",
        help="Only rewrite the generated Swift vocabulary file.",
    )
    return parser.parse_args()


def swift_string(value: str) -> str:
    return (
        "\""
        + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        + "\""
    )


def swift_array(values: list[str], indent: str, max_inline: int = 96) -> str:
    if not values:
        return "[]"
    joined = ", ".join(swift_string(value) for value in values)
    if len(joined) <= max_inline:
        return f"[{joined}]"
    inner = ",\n".join(f"{indent}    {swift_string(value)}" for value in values)
    return f"[\n{inner},\n{indent}]"


def syntax_suffix(value: str) -> str:
    value = value.lower()
    if value.startswith("xcode.syntax."):
        return value[len("xcode.syntax.") :]
    if value.startswith("editor.syntax."):
        return value[len("editor.syntax.") :]
    return value


def rule_suffix(value: str) -> str:
    return value[len("xcode.lang.") :] if value.startswith("xcode.lang.") else value


def language_sort_key(language: dict[str, Any]) -> int:
    identifier = str(language.get("identifier", ""))
    keys = list(LANGUAGE_CASES)
    return keys.index(identifier) if identifier in keys else len(keys)


def rule_entry(rule_record: dict[str, Any]) -> dict[str, Any]:
    entry = rule_record.get("entry")
    return entry if isinstance(entry, dict) else rule_record


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def string_list(value: Any) -> list[str]:
    values: list[str] = []
    for item in as_list(value):
        if isinstance(item, str):
            values.append(item)
    return sorted(dict.fromkeys(values))


def rule_syntax_types(rule: dict[str, Any]) -> list[str]:
    entry = rule_entry(rule)
    syntax = entry.get("Syntax")
    if not isinstance(syntax, dict):
        return []
    values = []
    for key in ("Type", "AltType"):
        value = syntax.get(key)
        if isinstance(value, str) and value.startswith("xcode.syntax."):
            values.append(syntax_suffix(value))
    return sorted(dict.fromkeys(values))


def rule_definition(rule_identifier: str, rule: dict[str, Any]) -> dict[str, Any]:
    entry = rule_entry(rule)
    syntax = entry.get("Syntax")
    syntax = syntax if isinstance(syntax, dict) else {}
    return {
        "identifier": rule_suffix(rule_identifier),
        "basedOn": [rule_suffix(value) for value in string_list(entry.get("BasedOn"))],
        "syntaxTypes": rule_syntax_types(rule),
        "words": string_list(syntax.get("Words")),
        "start": syntax.get("Start") if isinstance(syntax.get("Start"), str) else None,
        "end": syntax.get("End") if isinstance(syntax.get("End"), str) else None,
        "includeRules": [rule_suffix(value) for value in string_list(syntax.get("IncludeRules"))],
        "tokenizer": rule_suffix(syntax["Tokenizer"]) if isinstance(syntax.get("Tokenizer"), str) else None,
    }


def language_words(rule_definitions: list[dict[str, Any]], syntax_filter: str | None = None) -> list[str]:
    words: set[str] = set()
    for rule in rule_definitions:
        syntax_types = set(rule["syntaxTypes"])
        if syntax_filter and syntax_filter not in syntax_types:
            continue
        words.update(rule["words"])
    return sorted(words)


def supported_language_definitions(snapshot: dict[str, Any]) -> list[dict[str, Any]]:
    rule_index = snapshot["rulesByIdentifier"]
    languages = [
        language
        for language in snapshot["languages"]
        if language.get("identifier") in LANGUAGE_CASES
    ]
    languages.sort(key=language_sort_key)

    definitions: list[dict[str, Any]] = []
    for language in languages:
        case_name = LANGUAGE_CASES[str(language["identifier"])]
        rule_definitions = [
            rule_definition(rule_identifier, rule_index[rule_identifier])
            for rule_identifier in language.get("ruleIdentifiers", [])
            if rule_identifier in rule_index
        ]
        syntax_types = sorted({
            syntax_suffix(str(value))
            for value in language.get("syntaxTypes", [])
            if str(value).startswith("xcode.syntax.")
        })
        keyword_words = language_words(rule_definitions, "keyword")
        preprocessor_words = language_words(rule_definitions, "preprocessor")
        attribute_words = [
            word
            for word in keyword_words
            if word.startswith("@") or word.startswith("#")
        ]
        definitions.append({
            "caseName": case_name,
            "fileExtensions": sorted(map(str, language.get("fileExtensions", []))),
            "rootRuleIdentifier": rule_suffix(str(language.get("languageSpecification", ""))),
            "syntaxTypes": syntax_types,
            "keywordWords": keyword_words,
            "attributeWords": attribute_words,
            "preprocessorWords": preprocessor_words,
        })
    return definitions


def generate_swift(snapshot: dict[str, Any]) -> str:
    languages = supported_language_definitions(snapshot)

    lines: list[str] = [
        "// Generated from local xclangspec/xcsynspec language vocabulary. Do not edit by hand.",
        "",
        "package struct EditorLanguageSyntaxDefinition: Sendable {",
        "    package let fileExtensions: [String]",
        "    package let rootRuleIdentifier: String",
        "    package let syntaxTypes: [String]",
        "    package let keywordWords: Set<String>",
        "    package let attributeWords: Set<String>",
        "    package let preprocessorWords: Set<String>",
        "}",
        "",
        "package enum BuiltInEditorSourceSyntaxDefinitions {",
        "    package static let all: [SyntaxLanguage: EditorLanguageSyntaxDefinition] = [",
    ]

    for language in languages:
        case_name = language["caseName"]
        lines.append(f"        .{case_name}: EditorLanguageSyntaxDefinition(")
        lines.append(f"            fileExtensions: {swift_array(language['fileExtensions'], '            ')},")
        lines.append(f"            rootRuleIdentifier: {swift_string(language['rootRuleIdentifier'])},")
        lines.append(f"            syntaxTypes: {swift_array(language['syntaxTypes'], '            ')},")
        lines.append(f"            keywordWords: Set({swift_array(language['keywordWords'], '            ')}),")
        lines.append(f"            attributeWords: Set({swift_array(language['attributeWords'], '            ')}),")
        lines.append(f"            preprocessorWords: Set({swift_array(language['preprocessorWords'], '            ')})")
        lines.append("        ),")

    lines.extend(
        [
            "    ]",
            "",
            "    package static func definition(for language: SyntaxLanguage) -> EditorLanguageSyntaxDefinition? {",
            "        all[language]",
            "    }",
            "}",
            "",
            "package enum BuiltInEditorSourceSyntaxStyleKeyResolver {",
            "    package static func styleKeys(",
            "        for syntaxID: EditorSourceSyntaxID,",
            "        language: SyntaxLanguage? = nil",
            "    ) -> [String]? {",
            "        if let language,",
            "           let languageFallbacks = styleKeyFallbacksByLanguage[language],",
            "           let keys = languageFallbacks[syntaxID.rawValue] {",
            "            return keys",
            "        }",
            "        if let keys = styleKeyFallbacks[syntaxID.rawValue] {",
            "            return keys",
            "        }",
            "        if let keys = prefixStyleKeys(for: syntaxID.rawValue) {",
            "            return keys",
            "        }",
            "        return styleKeyFallbacks[syntaxID.rawValue] ?? [syntaxID.styleKey, \"editor.syntax.plain\"]",
            "    }",
            "",
            "    package static func styleKeys(",
            "        for sourceSyntaxID: String,",
            "        language: SyntaxLanguage? = nil",
            "    ) -> [String]? {",
            "        styleKeys(for: EditorSourceSyntaxID(sourceSyntaxID), language: language)",
            "    }",
            "",
            "    private static let styleKeyFallbacks: [String: [String]] = [",
        ]
    )

    for syntax_id, style_keys in sorted(STYLE_KEY_FALLBACKS.items()):
        lines.append(f"        {swift_string(syntax_id)}: {swift_array(style_keys, '        ')},")

    lines.extend(
        [
            "    ]",
            "",
            "    private static func prefixStyleKeys(for syntaxID: String) -> [String]? {",
            "        if syntaxID == \"plain\" {",
            "            return styleKeyFallbacks[\"plain\"]",
            "        }",
            "        if syntaxID == \"preprocessor\" || syntaxID.hasPrefix(\"preprocessor.\") {",
            "            return styleKeyFallbacks[\"preprocessor\"]",
            "        }",
            "        if syntaxID == \"keyword\" || syntaxID.hasPrefix(\"keyword.\") {",
            "            return styleKeyFallbacks[\"keyword\"]",
            "        }",
            "        if syntaxID == \"comment\" || syntaxID.hasPrefix(\"comment.\") {",
            "            return styleKeyFallbacks[\"comment\"]",
            "        }",
            "        if syntaxID == \"string\" || syntaxID.hasPrefix(\"string.\") {",
            "            return styleKeyFallbacks[\"string\"]",
            "        }",
            "        if syntaxID == \"character\" || syntaxID.hasPrefix(\"character.\") {",
            "            return styleKeyFallbacks[\"character\"]",
            "        }",
            "        if syntaxID == \"number\" || syntaxID.hasPrefix(\"number.\") {",
            "            return styleKeyFallbacks[\"number\"]",
            "        }",
            "        if syntaxID == \"url\" || syntaxID.hasPrefix(\"url.\") {",
            "            return styleKeyFallbacks[\"url\"]",
            "        }",
            "        if syntaxID == \"attribute\" || syntaxID.hasPrefix(\"attribute.\") {",
            "            return styleKeyFallbacks[\"attribute\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"declaration.type\") || syntaxID.hasPrefix(\"declaration.precedencegroup\") {",
            "            return styleKeyFallbacks[\"declaration.type\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"declaration.\") {",
            "            return styleKeyFallbacks[\"declaration.other\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"definition.macro\") {",
            "            return styleKeyFallbacks[\"identifier.macro\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"definition.function\") || syntaxID.hasPrefix(\"definition.method\") {",
            "            return styleKeyFallbacks[\"identifier.function\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"definition.property\") {",
            "            return styleKeyFallbacks[\"identifier.variable\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"definition.class\")",
            "            || syntaxID.hasPrefix(\"definition.type\")",
            "            || syntaxID.hasPrefix(\"definition.entity\")",
            "            || syntaxID.hasPrefix(\"definition.style\")",
            "            || syntaxID == \"entity\"",
            "            || syntaxID.hasPrefix(\"entity.\")",
            "            || syntaxID == \"section\"",
            "            || syntaxID.hasPrefix(\"section.\")",
            "        {",
            "            return styleKeyFallbacks[\"identifier.type\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"identifier.type\") {",
            "            return styleKeyFallbacks[\"identifier.type\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"identifier.class\") {",
            "            return styleKeyFallbacks[\"identifier.class\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"identifier.function\") || syntaxID.hasPrefix(\"identifier.method\") {",
            "            return styleKeyFallbacks[\"identifier.function\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"identifier.macro\") {",
            "            return styleKeyFallbacks[\"identifier.macro\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"identifier.constant\") {",
            "            return styleKeyFallbacks[\"identifier.constant\"]",
            "        }",
            "        if syntaxID.hasPrefix(\"identifier.variable\") {",
            "            return styleKeyFallbacks[\"identifier.variable\"]",
            "        }",
            "        return nil",
            "    }",
            "",
            "    private static let styleKeyFallbacksByLanguage: [SyntaxLanguage: [String: [String]]] = [:]",
            "}",
            "",
        ]
    )
    return "\n".join(lines)


def scm_string(value: str) -> str:
    return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""


def scm_string_lines(values: list[str], indent: str) -> list[str]:
    return [f"{indent}{scm_string(value)}" for value in values]


def generated_block_body(name: str, languages: dict[str, dict[str, Any]]) -> str:
    if name == "swift-attributes":
        values = sorted({
            word[1:]
            for word in languages["swift"]["attributeWords"]
            if word.startswith("@") and len(word) > 1
        })
        predicate_values = ["@", *values]
        lines = [
            "((modifiers",
            "  (attribute",
            "    \"@\" @editor.syntax.swift.keyword",
            "    (user_type",
            "      (type_identifier) @editor.syntax.swift.keyword)))",
            "  (#any-of? @editor.syntax.swift.keyword",
            *scm_string_lines(predicate_values, "    "),
            "  ))",
            "",
            "((attribute",
            "  \"@\" @editor.syntax.swift.keyword",
            "  (user_type",
            "    (type_identifier) @editor.syntax.swift.keyword))",
            "  (#any-of? @editor.syntax.swift.keyword",
            *scm_string_lines(predicate_values, "    "),
            "  ))",
        ]
        return "\n".join(lines)

    if name == "objectivec-attributes":
        values = sorted({
            word
            for word in languages["objectiveC"]["attributeWords"]
            if word in OBJECTIVEC_STABLE_ATTRIBUTE_WORDS
        })
        lines = [
            "[",
            *scm_string_lines(values, "  "),
            "] @editor.syntax.objectivec.keyword",
        ]
        return "\n".join(lines)

    if name == "css-at-rules":
        css_words = set(languages["css"]["attributeWords"]) | {"@keyframes", "@supports"}
        values = sorted(css_words.intersection(CSS_STABLE_AT_RULE_WORDS))
        lines = [
            "[",
            *scm_string_lines(values, "  "),
            "] @editor.syntax.css.declaration.other",
        ]
        return "\n".join(lines)

    if name == "json-literals":
        values = sorted(languages["json"]["keywordWords"])
        lines = [
            "[",
            *[f"  ({value})" for value in values],
            "] @editor.syntax.json.keyword",
        ]
        return "\n".join(lines)

    if name == "toml-literals":
        return "(boolean) @editor.syntax.toml.keyword"

    raise KeyError(f"Unknown generated query block: {name}")


def replace_generated_block(source: str, name: str, body: str) -> str:
    begin = GENERATED_BLOCK_BEGIN.format(name=name)
    end = GENERATED_BLOCK_END.format(name=name)
    begin_index = source.find(begin)
    if begin_index == -1:
        raise ValueError(f"Missing generated block begin marker: {begin}")
    content_start = source.find("\n", begin_index)
    if content_start == -1:
        raise ValueError(f"Malformed generated block begin marker: {begin}")
    content_start += 1
    end_index = source.find(end, content_start)
    if end_index == -1:
        raise ValueError(f"Missing generated block end marker: {end}")
    return source[:content_start] + body.rstrip() + "\n" + source[end_index:]


def rewrite_query_block(
    query_root: Path,
    language_case: str,
    block_name: str,
    languages: dict[str, dict[str, Any]],
) -> None:
    query_path = query_root / QUERY_DIRECTORY_NAMES[language_case] / "highlights.scm"
    source = query_path.read_text(encoding="utf-8")
    updated = replace_generated_block(
        source,
        block_name,
        generated_block_body(block_name, languages),
    )
    query_path.write_text(updated, encoding="utf-8")


def update_query_blocks(snapshot: dict[str, Any], query_root: Path) -> None:
    languages = {
        language["caseName"]: language
        for language in supported_language_definitions(snapshot)
    }
    for language_case, block_name in [
        ("swift", "swift-attributes"),
        ("objectiveC", "objectivec-attributes"),
        ("css", "css-at-rules"),
        ("json", "json-literals"),
        ("toml", "toml-literals"),
    ]:
        rewrite_query_block(query_root, language_case, block_name, languages)


def main() -> None:
    args = parse_arguments()
    snapshot = xclangspec_snapshot.build_snapshot(
        argparse.Namespace(
            xcode=args.xcode,
            spec_dir=None,
            metadata_dir=None,
            language=[],
            all_languages=False,
            pretty=False,
        )
    )
    output = Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(generate_swift(snapshot), encoding="utf-8")
    if not args.skip_query_update:
        update_query_blocks(snapshot, Path(args.query_root).expanduser())


if __name__ == "__main__":
    main()
