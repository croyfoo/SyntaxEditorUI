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


def swift_rule_definition(rule: dict[str, Any], indent: str) -> list[str]:
    lines = [f"{indent}EditorLanguageRuleDefinition("]
    lines.append(f"{indent}    identifier: {swift_string(rule['identifier'])},")
    lines.append(f"{indent}    basedOn: {swift_array(rule['basedOn'], indent + '    ')},")
    lines.append(f"{indent}    syntaxTypes: {swift_array(rule['syntaxTypes'], indent + '    ')},")
    lines.append(f"{indent}    words: {swift_array(rule['words'], indent + '    ', max_inline=120)},")
    lines.append(f"{indent}    start: {swift_string(rule['start']) if rule['start'] is not None else 'nil'},")
    lines.append(f"{indent}    end: {swift_string(rule['end']) if rule['end'] is not None else 'nil'},")
    lines.append(f"{indent}    includeRules: {swift_array(rule['includeRules'], indent + '    ')},")
    lines.append(f"{indent}    tokenizer: {swift_string(rule['tokenizer']) if rule['tokenizer'] is not None else 'nil'}")
    lines.append(f"{indent})")
    return lines


def generate_swift(snapshot: dict[str, Any]) -> str:
    rule_index = snapshot["rulesByIdentifier"]
    languages = [
        language
        for language in snapshot["languages"]
        if language.get("identifier") in LANGUAGE_CASES
    ]
    languages.sort(key=language_sort_key)

    lines: list[str] = [
        "// Generated from local xclangspec/xcsynspec language definitions. Do not edit by hand.",
        "",
        "package struct EditorLanguageRuleDefinition: Sendable {",
        "    package let identifier: String",
        "    package let basedOn: [String]",
        "    package let syntaxTypes: [String]",
        "    package let words: [String]",
        "    package let start: String?",
        "    package let end: String?",
        "    package let includeRules: [String]",
        "    package let tokenizer: String?",
        "}",
        "",
        "package struct EditorLanguageSyntaxDefinition: Sendable {",
        "    package let fileExtensions: [String]",
        "    package let rootRuleIdentifier: String",
        "    package let syntaxTypes: [String]",
        "    package let rules: [EditorLanguageRuleDefinition]",
        "    package let keywordWords: Set<String>",
        "    package let attributeWords: Set<String>",
        "    package let preprocessorWords: Set<String>",
        "}",
        "",
        "package enum BuiltInEditorSourceSyntaxDefinitions {",
        "    package static let all: [SyntaxLanguage: EditorLanguageSyntaxDefinition] = [",
    ]

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
        root_rule = rule_suffix(str(language.get("languageSpecification", "")))

        lines.append(f"        .{case_name}: EditorLanguageSyntaxDefinition(")
        lines.append(f"            fileExtensions: {swift_array(sorted(map(str, language.get('fileExtensions', []))), '            ')},")
        lines.append(f"            rootRuleIdentifier: {swift_string(root_rule)},")
        lines.append(f"            syntaxTypes: {swift_array(syntax_types, '            ')},")
        lines.append("            rules: [")
        for rule in rule_definitions:
            rule_lines = swift_rule_definition(rule, "                ")
            lines.extend(rule_lines[:-1])
            lines.append(rule_lines[-1] + ",")
        lines.append("            ],")
        lines.append(f"            keywordWords: Set({swift_array(keyword_words, '            ')}),")
        lines.append(f"            attributeWords: Set({swift_array(attribute_words, '            ')}),")
        lines.append(f"            preprocessorWords: Set({swift_array(preprocessor_words, '            ')})")
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


if __name__ == "__main__":
    main()
