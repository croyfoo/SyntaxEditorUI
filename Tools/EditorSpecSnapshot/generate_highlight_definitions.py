#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import xclangspec_snapshot


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_QUERY_ROOT = REPOSITORY_ROOT / "Sources"

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

QUERY_DIRECTORY_PATHS = {
    "css": Path("SyntaxEditorLanguageCSS/Resources/CSSQueries"),
    "html": Path("SyntaxEditorLanguageHTML/Resources/HTMLQueries"),
    "javascript": Path("SyntaxEditorLanguageJavaScript/Resources/JavaScriptQueries"),
    "json": Path("SyntaxEditorLanguageJSON/Resources/JSONQueries"),
    "objectiveC": Path("SyntaxEditorLanguageObjectiveC/Resources/ObjectiveCQueries"),
    "swift": Path("SyntaxEditorLanguageSwift/Resources/SwiftQueries"),
    "toml": Path("SyntaxEditorLanguageTOML/Resources/TOMLQueries"),
    "xml": Path("SyntaxEditorLanguageXML/Resources/XMLQueries"),
}

GENERATED_BLOCK_BEGIN = "; BEGIN GENERATED EDITOR SYNTAX WORDS: {name}"
GENERATED_BLOCK_END = "; END GENERATED EDITOR SYNTAX WORDS: {name}"
CSS_KEYWORD_PREDICATE_CHUNK_SIZE = 128
CSS_ANONYMOUS_KEYWORD_AT_RULES = {
    "@charset",
    "@import",
    "@media",
}

OBJECTIVEC_STABLE_ATTRIBUTE_WORDS = [
    "@autoreleasepool",
    "@catch",
    "@compatibility_alias",
    "@defs",
    "@dynamic",
    "@end",
    "@encode",
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
]

OBJECTIVEC_STABLE_PREPROCESSOR_WORDS = {
    "define",
    "elif",
    "else",
    "endif",
    "if",
    "ifdef",
    "ifndef",
    "undef",
}

def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate bundled editor syntax query blocks from local xclangspec files."
    )
    parser.add_argument(
        "--xcode",
        default=str(xclangspec_snapshot.DEFAULT_TOOLCHAIN_APP),
        help="Path to the local developer tool app bundle.",
    )
    parser.add_argument(
        "--query-root",
        default=str(DEFAULT_QUERY_ROOT),
        help=(
            "Root directory containing language target sources. A flat root "
            "containing *Queries directories is also accepted."
        ),
    )
    return parser.parse_args()


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
    for value in as_list(syntax.get("CaptureTypes")):
        if isinstance(value, str) and value.startswith("xcode.syntax."):
            values.append(syntax_suffix(value))
    return sorted(dict.fromkeys(values))


def rule_word_list(rule_identifier: str, rule: dict[str, Any]) -> dict[str, Any]:
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


def language_words(rule_word_lists: list[dict[str, Any]], syntax_filter: str | None = None) -> list[str]:
    words: set[str] = set()
    for rule in rule_word_lists:
        syntax_types = set(rule["syntaxTypes"])
        if syntax_filter:
            if syntax_filter == "preprocessor":
                if not any(value == "preprocessor" or value.startswith("preprocessor.") for value in syntax_types):
                    continue
            elif syntax_filter not in syntax_types:
                continue
        words.update(rule["words"])
    return sorted(words)


def supported_language_word_lists(snapshot: dict[str, Any]) -> list[dict[str, Any]]:
    rule_index = snapshot["rulesByIdentifier"]
    languages = [
        language
        for language in snapshot["languages"]
        if language.get("identifier") in LANGUAGE_CASES
    ]
    languages.sort(key=language_sort_key)

    word_lists: list[dict[str, Any]] = []
    for language in languages:
        case_name = LANGUAGE_CASES[str(language["identifier"])]
        rule_word_lists = [
            rule_word_list(rule_identifier, rule_index[rule_identifier])
            for rule_identifier in language.get("ruleIdentifiers", [])
            if rule_identifier in rule_index
        ]
        keyword_words = language_words(rule_word_lists, "keyword")
        preprocessor_words = language_words(rule_word_lists, "preprocessor")
        attribute_words = [
            word
            for word in keyword_words
            if word.startswith("@") or word.startswith("#")
        ]
        word_lists.append({
            "caseName": case_name,
            "keywordWords": keyword_words,
            "attributeWords": attribute_words,
            "preprocessorWords": preprocessor_words,
        })
    return word_lists


def scm_string(value: str) -> str:
    return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""


def scm_string_lines(values: list[str], indent: str) -> list[str]:
    return [f"{indent}{scm_string(value)}" for value in values]


def chunks(values: list[str], size: int) -> list[list[str]]:
    return [
        values[index:index + size]
        for index in range(0, len(values), size)
    ]


def generated_css_keyword_pattern(pattern_lines: list[str], values: list[str]) -> list[str]:
    return [
        *pattern_lines,
        "  (#any-of? @editor.syntax.css.keyword",
        *scm_string_lines(values, "    "),
        "  ))",
    ]


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
        attribute_words = set(languages["objectiveC"]["attributeWords"])
        values = [
            word
            for word in OBJECTIVEC_STABLE_ATTRIBUTE_WORDS
            if word in attribute_words
        ]
        lines = [
            "[",
            *scm_string_lines(values, "  "),
            "] @editor.syntax.objectivec.keyword",
        ]
        return "\n".join(lines)

    if name == "objectivec-preprocessor-keywords":
        values = sorted({
            f"#{word}"
            for word in languages["objectiveC"]["preprocessorWords"]
            if word in OBJECTIVEC_STABLE_PREPROCESSOR_WORDS
        })
        lines = [
            "[",
            *scm_string_lines(values, "  "),
            "] @editor.syntax.objectivec.preprocessor",
        ]
        return "\n".join(lines)

    if name == "css-keywords":
        values = languages["css"]["keywordWords"]
        literal_values = sorted(set(values).intersection(CSS_ANONYMOUS_KEYWORD_AT_RULES))
        patterns = [
            [
                "([",
                "  (property_name)",
                "  (feature_name)",
                "  (function_name)",
                "  (keyframes_name)",
                "  (unit)",
                "  (at_keyword)",
                "  (tag_name)",
                "  (keyword_query)",
                "] @editor.syntax.css.keyword",
            ],
            ["((pseudo_class_selector (class_name) @editor.syntax.css.keyword)"],
            ["((pseudo_element_selector (tag_name) @editor.syntax.css.keyword)"],
            ["((declaration (plain_value) @editor.syntax.css.keyword)"],
            ["((arguments (plain_value) @editor.syntax.css.keyword)"],
        ]
        literal_lines = [
            "[",
            *scm_string_lines(literal_values, "  "),
            "] @editor.syntax.css.keyword",
        ] if literal_values else []
        predicate_lines = [
            "\n".join(generated_css_keyword_pattern(pattern, chunk))
            for pattern in patterns
            for chunk in chunks(values, CSS_KEYWORD_PREDICATE_CHUNK_SIZE)
        ]
        return "\n\n".join([
            *([] if not literal_lines else ["\n".join(literal_lines)]),
            *predicate_lines,
        ])

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


def query_directory_path(query_root: Path, language_case: str) -> Path:
    target_relative_path = QUERY_DIRECTORY_PATHS[language_case]
    candidates = [
        query_root / target_relative_path,
        query_root / target_relative_path.name,
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def rewrite_query_block(
    query_root: Path,
    language_case: str,
    block_name: str,
    languages: dict[str, dict[str, Any]],
) -> None:
    query_path = query_directory_path(query_root, language_case) / "highlights.scm"
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
        for language in supported_language_word_lists(snapshot)
    }
    for language_case, block_name in [
        ("swift", "swift-attributes"),
        ("objectiveC", "objectivec-attributes"),
        ("objectiveC", "objectivec-preprocessor-keywords"),
        ("css", "css-keywords"),
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
    update_query_blocks(snapshot, Path(args.query_root).expanduser())


if __name__ == "__main__":
    main()
