// Generated from local xclangspec/xcsynspec language vocabulary. Do not edit by hand.

extension JSONLanguage {
    var syntaxVocabulary: EditorLanguageSyntaxVocabulary {
        Self.generatedSyntaxVocabulary
    }

    private static let generatedSyntaxVocabulary = EditorLanguageSyntaxVocabulary(
        fileExtensions: ["mtlp-json", "ndjson"],
        rootRuleIdentifier: "json",
        syntaxTypes: ["comment", "identifier", "keyword", "mark", "number", "plain", "string", "url", "url.mail"],
        keywordWords: Set(["false", "null", "true"]),
        attributeWords: Set([]),
        preprocessorWords: Set([])
    )
}
