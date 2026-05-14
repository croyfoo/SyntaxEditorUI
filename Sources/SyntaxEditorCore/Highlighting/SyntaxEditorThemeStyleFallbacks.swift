package enum SyntaxEditorThemeStyleFallbacks {
    package static func styleKeys(
        for syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage? = nil
    ) -> [String]? {
        if let language,
           let languageFallbacks = styleKeyFallbacksByLanguage[language],
           let keys = languageFallbacks[syntaxID.rawValue]
        {
            return keys
        }
        if let keys = styleKeyFallbacks[syntaxID.rawValue] {
            return keys
        }
        if let keys = prefixStyleKeys(for: syntaxID.rawValue) {
            return keys
        }
        return styleKeyFallbacks[syntaxID.rawValue] ?? [syntaxID.styleKey, "editor.syntax.plain"]
    }

    package static func styleKeys(
        for sourceSyntaxID: String,
        language: SyntaxLanguage? = nil
    ) -> [String]? {
        styleKeys(for: EditorSourceSyntaxID(sourceSyntaxID), language: language)
    }

    private static let styleKeyFallbacks: [String: [String]] = [
        "attribute": ["editor.syntax.attribute", "editor.syntax.identifier.variable", "editor.syntax.plain"],
        "character": ["editor.syntax.character", "editor.syntax.string"],
        "comment": ["editor.syntax.comment"],
        "comment.doc": ["editor.syntax.comment.doc", "editor.syntax.comment"],
        "comment.doc.keyword": ["editor.syntax.comment.doc.keyword", "editor.syntax.comment.doc", "editor.syntax.comment"],
        "declaration.other": ["editor.syntax.declaration.other", "editor.syntax.identifier.function", "editor.syntax.plain"],
        "declaration.type": ["editor.syntax.declaration.type", "editor.syntax.identifier.type", "editor.syntax.plain"],
        "identifier.class": ["editor.syntax.identifier.class", "editor.syntax.identifier.type", "editor.syntax.plain"],
        "identifier.class.system": ["editor.syntax.identifier.class.system", "editor.syntax.identifier.class", "editor.syntax.plain"],
        "identifier.constant": ["editor.syntax.identifier.constant", "editor.syntax.plain"],
        "identifier.constant.system": [
            "editor.syntax.identifier.constant.system",
            "editor.syntax.identifier.constant",
            "editor.syntax.plain",
        ],
        "identifier.function": ["editor.syntax.identifier.function", "editor.syntax.declaration.other", "editor.syntax.plain"],
        "identifier.function.system": [
            "editor.syntax.identifier.function.system",
            "editor.syntax.identifier.function",
            "editor.syntax.plain",
        ],
        "identifier.macro": ["editor.syntax.identifier.macro", "editor.syntax.declaration.other", "editor.syntax.plain"],
        "identifier.macro.system": ["editor.syntax.identifier.macro.system", "editor.syntax.identifier.macro", "editor.syntax.plain"],
        "identifier.type": ["editor.syntax.identifier.type", "editor.syntax.declaration.type", "editor.syntax.plain"],
        "identifier.type.system": ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type", "editor.syntax.plain"],
        "identifier.variable": ["editor.syntax.identifier.variable", "editor.syntax.plain"],
        "identifier.variable.system": [
            "editor.syntax.identifier.variable.system",
            "editor.syntax.identifier.variable",
            "editor.syntax.plain",
        ],
        "keyword": ["editor.syntax.keyword"],
        "mark": ["editor.syntax.mark", "editor.syntax.comment"],
        "number": ["editor.syntax.number"],
        "plain": ["editor.syntax.plain"],
        "preprocessor": ["editor.syntax.preprocessor", "editor.syntax.keyword"],
        "string": ["editor.syntax.string", "editor.syntax.character"],
        "url": ["editor.syntax.url", "editor.syntax.number"],
    ]

    private static func prefixStyleKeys(for syntaxID: String) -> [String]? {
        if syntaxID == "plain" {
            return styleKeyFallbacks["plain"]
        }
        if syntaxID == "preprocessor" || syntaxID.hasPrefix("preprocessor.") {
            return styleKeyFallbacks["preprocessor"]
        }
        if syntaxID == "keyword" || syntaxID.hasPrefix("keyword.") {
            return styleKeyFallbacks["keyword"]
        }
        if syntaxID == "comment" || syntaxID.hasPrefix("comment.") {
            return styleKeyFallbacks["comment"]
        }
        if syntaxID == "string" || syntaxID.hasPrefix("string.") {
            return styleKeyFallbacks["string"]
        }
        if syntaxID == "character" || syntaxID.hasPrefix("character.") {
            return styleKeyFallbacks["character"]
        }
        if syntaxID == "number" || syntaxID.hasPrefix("number.") {
            return styleKeyFallbacks["number"]
        }
        if syntaxID == "url" || syntaxID.hasPrefix("url.") {
            return styleKeyFallbacks["url"]
        }
        if syntaxID == "attribute" || syntaxID.hasPrefix("attribute.") {
            return styleKeyFallbacks["attribute"]
        }
        if syntaxID.hasPrefix("declaration.type") || syntaxID.hasPrefix("declaration.precedencegroup") {
            return styleKeyFallbacks["declaration.type"]
        }
        if syntaxID.hasPrefix("declaration.") {
            return styleKeyFallbacks["declaration.other"]
        }
        if syntaxID.hasPrefix("definition.macro") {
            return styleKeyFallbacks["identifier.macro"]
        }
        if syntaxID.hasPrefix("definition.function") || syntaxID.hasPrefix("definition.method") {
            return styleKeyFallbacks["identifier.function"]
        }
        if syntaxID.hasPrefix("definition.property") {
            return styleKeyFallbacks["identifier.variable"]
        }
        if syntaxID.hasPrefix("definition.class")
            || syntaxID.hasPrefix("definition.type")
            || syntaxID.hasPrefix("definition.entity")
            || syntaxID.hasPrefix("definition.style")
            || syntaxID == "entity"
            || syntaxID.hasPrefix("entity.")
            || syntaxID == "section"
            || syntaxID.hasPrefix("section.")
        {
            return styleKeyFallbacks["identifier.type"]
        }
        if syntaxID.hasPrefix("identifier.type") {
            return styleKeyFallbacks["identifier.type"]
        }
        if syntaxID.hasPrefix("identifier.class") {
            return styleKeyFallbacks["identifier.class"]
        }
        if syntaxID.hasPrefix("identifier.function") || syntaxID.hasPrefix("identifier.method") {
            return styleKeyFallbacks["identifier.function"]
        }
        if syntaxID.hasPrefix("identifier.macro") {
            return styleKeyFallbacks["identifier.macro"]
        }
        if syntaxID.hasPrefix("identifier.constant") {
            return styleKeyFallbacks["identifier.constant"]
        }
        if syntaxID.hasPrefix("identifier.variable") {
            return styleKeyFallbacks["identifier.variable"]
        }
        return nil
    }

    private static let styleKeyFallbacksByLanguage: [SyntaxLanguage: [String: [String]]] = [:]
}
