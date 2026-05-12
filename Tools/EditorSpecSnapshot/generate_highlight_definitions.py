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
    / "BuiltInEditorLanguageSyntaxDefinitions+Generated.swift"
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

LANGUAGE_STYLE_KEY_OVERRIDES = {
    "toml": {
        "identifier": ["editor.syntax.attribute", "editor.syntax.plain"],
        "name": ["editor.syntax.plain"],
        "section": ["editor.syntax.plain"],
    },
}

TREE_SITTER_CAPTURE_SYNTAX_TYPE_SUFFIXES = {
    "css": {
        "attribute.css.name": "identifier",
        "function.css.name": "identifier",
        "function.css.name.keyword": "keyword",
        "keyword.css.atrule": "keyword",
        "keyword.css.important": "keyword",
        "keyword.css.keyframe": "keyword",
        "number.css": "number",
        "operator.css": "plain",
        "property.css.feature": "keyword",
        "property.css.feature.supports": "identifier",
        "property.css.name": "keyword",
        "punctuation": "plain",
        "punctuation.delimiter": "plain",
        "selector.css": "definition.style",
        "string.css": "string",
        "string.css.color": "number",
        "type.css.unit": "keyword",
        "variable.css.customproperty": "identifier",
    },
    "html": {
        "attribute.html.name": "identifier",
        "constant.html.doctype": "keyword",
        "punctuation.html.bracket": "keyword",
        "string.html.attributevalue": "string",
        "tag.html": "keyword",
    },
    "javascript": {
        "constant": "identifier",
        "constant.builtin": "keyword",
        "constructor": "definition.class",
        "embedded": "plain",
        "function": "definition.function",
        "function.builtin": "definition.function",
        "function.method": "definition.method",
        "keyword": "keyword",
        "operator": "plain",
        "property": "identifier",
        "punctuation": "plain",
        "punctuation.bracket": "plain",
        "punctuation.delimiter": "plain",
        "punctuation.special": "plain",
        "string.special": "string",
        "variable": "identifier",
        "variable.builtin": "identifier",
    },
    "json": {
        "constant.builtin": "keyword",
        "escape": "string",
        "string.special.key": "string",
    },
    "objectiveC": {
        "attribute": "keyword",
        "constant": "identifier",
        "constant.macro": "preprocessor",
        "constructor": "definition.method",
        "delimiter": "plain",
        "exception": "keyword",
        "function": "definition.function",
        "function.builtin": "definition.function",
        "function.macro": "definition.macro",
        "function.macro.builtin": "definition.macro",
        "function.special": "definition.function",
        "include": "preprocessor.include",
        "keyword": "keyword",
        "keyword.coroutine": "keyword",
        "keyword.function": "keyword",
        "keyword.operator": "keyword",
        "label": "plain",
        "method": "definition.method",
        "method.call": "definition.method",
        "namespace": "name.type",
        "operator": "plain",
        "parameter": "name.parameter",
        "parameter.builtin": "name.parameter",
        "preproc": "preprocessor",
        "property": "definition.property",
        "punctuation": "plain",
        "punctuation.bracket": "plain",
        "punctuation.special": "plain",
        "storageclass": "keyword",
        "string.special": "string",
        "text.uri": "url",
        "type": "name.type",
        "type.builtin": "name.type",
        "type.qualifier": "keyword",
        "variable": "identifier",
        "variable.builtin": "identifier",
    },
    "swift": {
        "attribute.swift.name": "identifier",
        "attribute.swift.punctuation": "identifier",
        "boolean": "keyword",
        "character.special": "character",
        "comment.documentation": "comment.doc",
        "constant.builtin": "keyword",
        "constant.macro": "preprocessor",
        "constructor": "keyword",
        "declaration.swift.constant": "declaration.variable",
        "declaration.swift.function": "declaration.function",
        "declaration.swift.macro": "definition.macro",
        "declaration.swift.other": "declaration.variable",
        "declaration.swift.property": "declaration.property",
        "declaration.swift.type": "declaration.struct",
        "delimiter": "plain",
        "function.swift.call": "definition.function",
        "function.swift.macro": "definition.macro",
        "identifier.swift.argument.label": "plain",
        "identifier.swift.import.name": "plain",
        "identifier.swift.local": "plain",
        "identifier.swift.other.constant": "identifier",
        "identifier.swift.other.function": "definition.function",
        "identifier.swift.other.macro": "definition.macro",
        "identifier.swift.other.property": "identifier",
        "identifier.swift.other.type": "name.type",
        "identifier.swift.project.constant": "identifier",
        "identifier.swift.project.function": "definition.function",
        "identifier.swift.project.macro": "definition.macro",
        "identifier.swift.project.property": "identifier",
        "identifier.swift.project.type": "name.type",
        "keyword": "keyword",
        "keyword.directive": "preprocessor",
        "keyword.directive.condition.swift": "preprocessor",
        "keyword.function": "keyword",
        "keyword.modifier": "keyword",
        "keyword.swift.attribute.builtin": "keyword",
        "keyword.swift.availability": "keyword",
        "keyword.swift.availability.punctuation": "keyword",
        "keyword.swift.modifier.contextual": "keyword",
        "keyword.swift.statement.reserved": "keyword",
        "keyword.swift.type.builtin": "keyword",
        "keyword.type": "keyword",
        "label": "plain",
        "operator": "plain",
        "punctuation": "plain",
        "punctuation.bracket": "plain",
        "punctuation.delimiter": "plain",
        "punctuation.special": "plain",
        "string.escape": "string",
        "string.regexp": "string",
        "text.uri": "url",
        "type.swift.reference": "name.type",
        "variable": "plain",
        "variable.member": "identifier",
        "variable.parameter": "plain",
    },
    "toml": {
        "boolean": "keyword",
        "operator": "plain",
        "property": "identifier",
        "punctuation": "plain",
        "punctuation.bracket": "plain",
        "punctuation.delimiter": "plain",
        "string.special": "string",
        "type": "name",
    },
    "xml": {
        "attribute": "identifier",
        "character": "character",
        "constant": "keyword",
        "constant.builtin": "keyword",
        "embedded": "plain",
        "entity": "keyword",
        "error": "plain",
        "escape": "character",
        "function": "definition.function",
        "keyword": "keyword",
        "label": "plain",
        "markup": "plain",
        "markup.heading": "keyword",
        "markup.link": "url",
        "markup.raw": "string",
        "operator": "plain",
        "property": "identifier",
        "punctuation": "plain",
        "punctuation.bracket": "plain",
        "punctuation.delimiter": "plain",
        "string.special.symbol": "string",
        "string.special.key": "string",
        "tag": "keyword",
        "tag.error": "keyword",
        "type": "name.type",
        "type.builtin": "name.type",
        "variable": "identifier",
    },
}

TREE_SITTER_CAPTURE_STYLE_KEYS = {
    "css": {
        "keyword.css.keyframes": ["editor.syntax.declaration.other", "editor.syntax.preprocessor", "editor.syntax.keyword"],
        "keyword.css.supports": ["editor.syntax.declaration.other", "editor.syntax.preprocessor", "editor.syntax.keyword"],
        "selector.css": ["editor.syntax.declaration.other", "editor.syntax.identifier.type", "editor.syntax.plain"],
    },
    "html": {
        "attribute.html.name": ["editor.syntax.attribute", "editor.syntax.identifier.variable", "editor.syntax.plain"],
        "constant.html.doctype": ["editor.syntax.keyword"],
        "punctuation.html.bracket": ["editor.syntax.keyword", "editor.syntax.plain"],
        "tag.html": ["editor.syntax.keyword", "editor.syntax.plain"],
        "variable": ["editor.syntax.plain"],
        "variable.builtin": ["editor.syntax.plain"],
    },
    "javascript": {
        "property": ["editor.syntax.plain"],
        "variable": ["editor.syntax.plain"],
        "variable.builtin": ["editor.syntax.plain"],
    },
    "objectiveC": {
        "function.builtin": ["editor.syntax.identifier.function.system", "editor.syntax.identifier.function"],
        "method.call": ["editor.syntax.identifier.function.system", "editor.syntax.identifier.function"],
        "namespace": ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type"],
        "property": ["editor.syntax.plain"],
        "type": ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type"],
        "type.builtin": ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type"],
        "variable": ["editor.syntax.plain"],
        "variable.builtin": ["editor.syntax.plain"],
    },
    "swift": {
        "attribute.swift.name": ["editor.syntax.attribute", "editor.syntax.identifier.type.system"],
        "attribute.swift.punctuation": ["editor.syntax.identifier.type.system", "editor.syntax.attribute"],
        "boolean": ["editor.syntax.keyword", "editor.syntax.identifier.constant"],
        "comment.documentation.keyword": ["editor.syntax.comment.doc.keyword", "editor.syntax.comment.doc", "editor.syntax.comment"],
        "comment.doc.keyword": ["editor.syntax.comment.doc.keyword", "editor.syntax.comment.doc", "editor.syntax.comment"],
        "comment.mark": ["editor.syntax.mark", "editor.syntax.comment"],
        "constant.builtin": ["editor.syntax.keyword", "editor.syntax.identifier.constant"],
        "constant.macro": ["editor.syntax.identifier.macro.system", "editor.syntax.identifier.macro", "editor.syntax.preprocessor"],
        "constructor": ["editor.syntax.keyword"],
        "declaration.swift.type.name": ["editor.syntax.declaration.type", "editor.syntax.identifier.type"],
        "declaration.swift": ["editor.syntax.declaration.other", "editor.syntax.identifier.function"],
        "function.swift.call": ["editor.syntax.identifier.function.system", "editor.syntax.identifier.function"],
        "function.swift.macro": ["editor.syntax.identifier.macro.system", "editor.syntax.identifier.macro"],
        "identifier.swift.argument.label": ["editor.syntax.plain"],
        "identifier.swift.import.name": ["editor.syntax.plain"],
        "identifier.swift.local": ["editor.syntax.plain"],
        "identifier.swift.other.constant": ["editor.syntax.identifier.constant.system", "editor.syntax.identifier.constant"],
        "identifier.swift.other.function": ["editor.syntax.identifier.function.system", "editor.syntax.identifier.function"],
        "identifier.swift.other.macro": ["editor.syntax.identifier.macro.system", "editor.syntax.identifier.macro"],
        "identifier.swift.other.property": ["editor.syntax.identifier.variable.system", "editor.syntax.identifier.variable", "editor.syntax.plain"],
        "identifier.swift.other.type": ["editor.syntax.identifier.type.system", "editor.syntax.identifier.class.system", "editor.syntax.identifier.type"],
        "identifier.swift.project.constant": ["editor.syntax.identifier.constant", "editor.syntax.identifier.variable"],
        "identifier.swift.project.function": ["editor.syntax.identifier.function", "editor.syntax.declaration.other"],
        "identifier.swift.project.macro": ["editor.syntax.identifier.macro", "editor.syntax.identifier.function"],
        "identifier.swift.project.property": ["editor.syntax.identifier.variable", "editor.syntax.plain"],
        "identifier.swift.project.type": ["editor.syntax.identifier.type", "editor.syntax.identifier.class", "editor.syntax.declaration.type"],
        "keyword.directive": ["editor.syntax.preprocessor", "editor.syntax.keyword"],
        "keyword.swift.type.builtin": ["editor.syntax.keyword", "editor.syntax.identifier.type.system"],
        "operator": ["editor.syntax.plain"],
        "punctuation": ["editor.syntax.plain"],
        "punctuation.bracket": ["editor.syntax.plain"],
        "punctuation.delimiter": ["editor.syntax.plain"],
        "punctuation.special": ["editor.syntax.plain"],
        "type.swift.reference": ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type"],
        "variable": ["editor.syntax.plain"],
        "variable.parameter": ["editor.syntax.plain"],
    },
    "toml": {
        "property": ["editor.syntax.attribute", "editor.syntax.plain"],
        "type": ["editor.syntax.plain"],
    },
}

COMMON_TREE_SITTER_CAPTURE_SYNTAX_TYPE_SUFFIXES = {
    "boolean": "keyword",
    "comment": "comment",
    "comment.doc": "comment.doc",
    "comment.documentation": "comment.doc",
    "constant.builtin": "keyword",
    "keyword": "keyword",
    "number": "number",
    "operator": "plain",
    "punctuation": "plain",
    "punctuation.bracket": "plain",
    "punctuation.delimiter": "plain",
    "punctuation.special": "plain",
    "string": "string",
    "string.escape": "string",
    "string.special": "string",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate SyntaxEditorUI Swift highlight definitions from local xclangspec files."
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
    escaped = (
        value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
    )
    return f"\"{escaped}\""


def swift_array(values: list[str], indent: str) -> str:
    if not values:
        return "[]"
    joined = ", ".join(swift_string(value) for value in values)
    if len(joined) <= 96:
        return f"[{joined}]"
    inner = ",\n".join(f"{indent}    {swift_string(value)}" for value in values)
    return f"[\n{inner},\n{indent}]"


def strip_known_prefix(value: str, prefixes: tuple[str, ...]) -> str:
    for prefix in prefixes:
        if value.startswith(prefix):
            return value[len(prefix):]
    return value


def syntax_type_suffix(value: str) -> str:
    return strip_known_prefix(value, ("xcode.syntax.",))


def rule_identifier_suffix(value: str) -> str:
    return strip_known_prefix(value, ("xcode.lang.",))


def language_record_sort_key(language: dict[str, Any]) -> int:
    identifier = str(language.get("identifier", ""))
    cases = list(LANGUAGE_CASES)
    return cases.index(identifier) if identifier in LANGUAGE_CASES else len(cases)


def rule_syntax_type_suffixes(rule: dict[str, Any]) -> list[str]:
    entry = xclangspec_snapshot.rule_entry(rule)
    syntax = entry.get("Syntax")
    if not isinstance(syntax, dict):
        return []

    values: list[str] = []
    for key in ("Type", "AltType"):
        value = syntax.get(key)
        if isinstance(value, str) and value.startswith("xcode.syntax."):
            suffix = syntax_type_suffix(value)
            if suffix not in values:
                values.append(suffix)
    return values


def generic_style_keys_for_syntax_suffix(suffix: str) -> list[str]:
    if suffix == "plain":
        return ["editor.syntax.plain"]
    if suffix == "comment":
        return ["editor.syntax.comment"]
    if suffix == "comment.doc":
        return ["editor.syntax.comment.doc", "editor.syntax.comment"]
    if suffix == "mark":
        return ["editor.syntax.mark", "editor.syntax.comment"]
    if suffix == "character":
        return ["editor.syntax.character", "editor.syntax.string"]
    if suffix == "string":
        return ["editor.syntax.string", "editor.syntax.character"]
    if suffix == "number":
        return ["editor.syntax.number"]
    if suffix in {"url", "url.mail"}:
        return ["editor.syntax.url", "editor.syntax.number"]
    if suffix == "keyword":
        return ["editor.syntax.keyword"]
    if suffix.startswith("preprocessor"):
        return ["editor.syntax.preprocessor", "editor.syntax.keyword"]
    if suffix in {
        "declaration.actor",
        "declaration.enum",
        "declaration.objc.interface",
        "declaration.precedencegroup",
        "declaration.protocol",
        "declaration.struct",
        "declaration.union",
        "definition.class",
        "definition.extension",
        "definition.objc.implementation",
        "name.type",
        "typedef",
        "associatedtype",
    }:
        return ["editor.syntax.declaration.type", "editor.syntax.identifier.type"]
    if suffix in {
        "declaration.enum.case",
        "declaration.function",
        "declaration.method",
        "declaration.operator",
        "declaration.property",
        "declaration.variable",
        "definition.deinitializer",
        "definition.function",
        "definition.method",
        "definition.method.class",
        "definition.subscript",
        "method.declarator",
    }:
        return ["editor.syntax.declaration.other", "editor.syntax.identifier.function"]
    if suffix == "definition.macro":
        return ["editor.syntax.identifier.macro", "editor.syntax.declaration.other"]
    if suffix in {"definition.entity", "definition.style", "entity", "entity.start", "section"}:
        return ["editor.syntax.identifier.type", "editor.syntax.declaration.type"]
    if suffix == "definition.property":
        return ["editor.syntax.identifier.variable", "editor.syntax.declaration.other"]
    if suffix == "definition.method":
        return ["editor.syntax.identifier.function", "editor.syntax.declaration.other"]
    if suffix.startswith("name.") or suffix in {"name", "identifier", "pattern", "assignment"}:
        return ["editor.syntax.plain"]
    if suffix in {"module.import", "objc.import"}:
        return ["editor.syntax.plain"]
    if suffix == "completionplaceholder":
        return ["editor.syntax.plain"]

    return [f"editor.syntax.{suffix}", "editor.syntax.plain"]


def style_keys_for_syntax_suffix(suffix: str, language_case: str | None = None) -> list[str]:
    if language_case:
        overrides = LANGUAGE_STYLE_KEY_OVERRIDES.get(language_case, {})
        if suffix in overrides:
            return overrides[suffix]
    return generic_style_keys_for_syntax_suffix(suffix)


def source_syntax_style_key_table(languages: list[dict[str, Any]]) -> dict[str, list[str]]:
    suffixes: set[str] = set()
    for language in languages:
        suffixes.update(str(value) for value in language.get("syntaxTypes", []))

    normalized_suffixes = {
        syntax_type_suffix(value) for value in suffixes if value.startswith("xcode.syntax.")
    }
    return {
        suffix: generic_style_keys_for_syntax_suffix(suffix)
        for suffix in sorted(normalized_suffixes)
    }


def capture_syntax_suffixes_for_language(language_case: str) -> dict[str, str]:
    suffixes = dict(COMMON_TREE_SITTER_CAPTURE_SYNTAX_TYPE_SUFFIXES)
    if language_case == "html":
        suffixes.update(TREE_SITTER_CAPTURE_SYNTAX_TYPE_SUFFIXES.get("css", {}))
        suffixes.update(TREE_SITTER_CAPTURE_SYNTAX_TYPE_SUFFIXES.get("javascript", {}))
    suffixes.update(TREE_SITTER_CAPTURE_SYNTAX_TYPE_SUFFIXES.get(language_case, {}))
    return suffixes


def capture_style_keys_for_language(language_case: str) -> dict[str, list[str]]:
    entries: dict[str, list[str]] = {}
    for capture_name, suffix in capture_syntax_suffixes_for_language(language_case).items():
        entries[capture_name.lower()] = style_keys_for_syntax_suffix(suffix, language_case)

    if language_case == "html":
        for capture_name, style_keys in TREE_SITTER_CAPTURE_STYLE_KEYS.get("css", {}).items():
            entries[capture_name.lower()] = style_keys
        for capture_name, style_keys in TREE_SITTER_CAPTURE_STYLE_KEYS.get("javascript", {}).items():
            entries[capture_name.lower()] = style_keys

    for capture_name, style_keys in TREE_SITTER_CAPTURE_STYLE_KEYS.get(language_case, {}).items():
        entries[capture_name.lower()] = style_keys
    return entries


def generate_swift(snapshot: dict[str, Any]) -> str:
    rule_index = snapshot["rulesByIdentifier"]
    languages = [
        language
        for language in snapshot["languages"]
        if language.get("identifier") in LANGUAGE_CASES
    ]
    languages.sort(key=language_record_sort_key)
    style_key_table = source_syntax_style_key_table(languages)

    lines: list[str] = [
        "// Generated from local xclangspec language definitions. Do not edit by hand.",
        "",
        "package struct BuiltInEditorLanguageSyntaxDefinition: Sendable {",
        "    package let fileExtensions: [String]",
        "    package let syntaxTypeSuffixes: [String]",
        "    package let ruleSyntaxTypeSuffixes: [String: [String]]",
        "",
        "    package func styleKeys(forSourceSyntaxType sourceSyntaxType: String) -> [String]? {",
        "        BuiltInEditorSourceSyntaxStyleKeyResolver.styleKeys(for: sourceSyntaxType)",
        "    }",
        "}",
        "",
        "package struct BuiltInEditorTreeSitterCaptureStyleKeyEntry: Sendable {",
        "    package let capturePrefix: String",
        "    package let styleKeys: [String]",
        "}",
        "",
        "package enum BuiltInEditorLanguageSyntaxDefinitions {",
        "    package static let all: [SyntaxLanguage: BuiltInEditorLanguageSyntaxDefinition] = [",
    ]

    for language in languages:
        case_name = LANGUAGE_CASES[str(language["identifier"])]
        file_extensions = sorted(str(value) for value in language.get("fileExtensions", []))
        syntax_suffixes = sorted(
            syntax_type_suffix(str(value))
            for value in language.get("syntaxTypes", [])
            if str(value).startswith("xcode.syntax.")
        )
        rule_entries: list[tuple[str, list[str]]] = []
        for rule_identifier in language.get("ruleIdentifiers", []):
            rule = rule_index.get(rule_identifier)
            if not isinstance(rule, dict):
                continue
            suffixes = rule_syntax_type_suffixes(rule)
            if suffixes:
                rule_entries.append((rule_identifier_suffix(rule_identifier), suffixes))

        lines.append(f"        .{case_name}: BuiltInEditorLanguageSyntaxDefinition(")
        lines.append(f"            fileExtensions: {swift_array(file_extensions, '            ')},")
        lines.append(f"            syntaxTypeSuffixes: {swift_array(syntax_suffixes, '            ')},")
        lines.append("            ruleSyntaxTypeSuffixes: [")
        for rule_identifier, suffixes in sorted(rule_entries):
            lines.append(
                f"                {swift_string(rule_identifier)}: {swift_array(suffixes, '                ')},"
            )
        lines.append("            ]")
        lines.append("        ),")

    lines.extend([
        "    ]",
        "}",
        "",
        "package enum BuiltInEditorSourceSyntaxStyleKeyResolver {",
        "    package static func styleKeys(for sourceSyntaxType: String, language: SyntaxLanguage? = nil) -> [String]? {",
        "        let suffix = normalizedSuffix(for: sourceSyntaxType)",
        "        if let language,",
        "           let styleKeys = styleKeyOverridesByLanguage[language]?[suffix] {",
        "            return styleKeys",
        "        }",
        "        return styleKeysBySyntaxTypeSuffix[suffix]",
        "    }",
        "",
        "    private static func normalizedSuffix(for sourceSyntaxType: String) -> String {",
        "        let lowered = sourceSyntaxType.lowercased()",
        "        if lowered.hasPrefix(\"xcode.syntax.\") {",
        "            return String(lowered.dropFirst(\"xcode.syntax.\".count))",
        "        }",
        "        if lowered.hasPrefix(\"editor.syntax.\") {",
        "            return String(lowered.dropFirst(\"editor.syntax.\".count))",
        "        }",
        "        return lowered",
        "    }",
        "",
        "    private static let styleKeysBySyntaxTypeSuffix: [String: [String]] = [",
    ])

    for suffix, style_keys in style_key_table.items():
        lines.append(f"        {swift_string(suffix)}: {swift_array(style_keys, '        ')},")

    lines.extend([
        "    ]",
        "",
        "    private static let styleKeyOverridesByLanguage: [SyntaxLanguage: [String: [String]]] = [",
    ])

    for case_name, overrides in sorted(LANGUAGE_STYLE_KEY_OVERRIDES.items()):
        lines.append(f"        .{case_name}: [")
        for suffix, style_keys in sorted(overrides.items()):
            lines.append(f"            {swift_string(suffix)}: {swift_array(style_keys, '            ')},")
        lines.append("        ],")

    lines.extend([
        "    ]",
        "}",
        "",
        "package enum BuiltInEditorTreeSitterCaptureStyleKeyResolver {",
        "    package static func styleKeys(for captureName: String, language: SyntaxLanguage?) -> [String]? {",
        "        guard let language,",
        "              let exactStyleKeys = exactStyleKeysByLanguage[language] else {",
        "            return nil",
        "        }",
        "",
        "        let name = captureName.lowercased()",
        "        if let styleKeys = exactStyleKeys[name] {",
        "            return styleKeys",
        "        }",
        "",
        "        for entry in prefixStyleKeysByLanguage[language] ?? [] where name.hasPrefix(entry.capturePrefix + \".\") {",
        "            return entry.styleKeys",
        "        }",
        "",
        "        return nil",
        "    }",
        "",
        "    private static let exactStyleKeysByLanguage: [SyntaxLanguage: [String: [String]]] = [",
    ])

    for case_name in sorted(LANGUAGE_CASES.values()):
        entries = capture_style_keys_for_language(case_name)
        lines.append(f"        .{case_name}: [")
        for capture_name, style_keys in sorted(entries.items()):
            lines.append(f"            {swift_string(capture_name)}: {swift_array(style_keys, '            ')},")
        lines.append("        ],")

    lines.extend([
        "    ]",
        "",
        "    private static let prefixStyleKeysByLanguage: [SyntaxLanguage: [BuiltInEditorTreeSitterCaptureStyleKeyEntry]] = [",
    ])

    for case_name in sorted(LANGUAGE_CASES.values()):
        entries = capture_style_keys_for_language(case_name)
        prefix_entries = sorted(entries.items(), key=lambda item: (-len(item[0]), item[0]))
        lines.append(f"        .{case_name}: [")
        for capture_name, style_keys in prefix_entries:
            lines.append(
                "            BuiltInEditorTreeSitterCaptureStyleKeyEntry("
                f"capturePrefix: {swift_string(capture_name)}, "
                f"styleKeys: {swift_array(style_keys, '            ')}"
                "),"
            )
        lines.append("        ],")

    lines.extend([
        "    ]",
        "}",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    args = parse_arguments()
    snapshot_args = argparse.Namespace(
        xcode=args.xcode,
        spec_dir=None,
        metadata_dir=None,
        language=[],
        all_languages=False,
        pretty=False,
    )
    snapshot = xclangspec_snapshot.build_snapshot(snapshot_args)
    output_path = Path(args.output).expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(generate_swift(snapshot), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
