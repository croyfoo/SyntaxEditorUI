// Generated from local xclangspec/xcsynspec language vocabulary. Do not edit by hand.

extension TOMLLanguage {
    var syntaxVocabulary: EditorLanguageSyntaxVocabulary {
        Self.generatedSyntaxVocabulary
    }

    private static let generatedSyntaxVocabulary = EditorLanguageSyntaxVocabulary(
        fileExtensions: ["cfg", "config", "ini", "toml"],
        rootRuleIdentifier: "toml",
        syntaxTypes: [
            "comment",
            "identifier",
            "keyword",
            "mark",
            "name",
            "number",
            "plain",
            "section",
            "string",
            "url",
            "url.mail",
        ],
        keywordWords: Set(["false", "true"]),
        attributeWords: Set([]),
        preprocessorWords: Set([])
    )
}
