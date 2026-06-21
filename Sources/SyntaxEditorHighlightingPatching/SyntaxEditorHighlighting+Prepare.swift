import SyntaxEditorCoreTypes
import SyntaxEditorHighlightingTypes

extension SyntaxEditorHighlighting {
    public static func prepare(_ language: SyntaxLanguage) async {
        _ = await LanguageConfigurationRegistry.shared.highlightingSetup(for: language)
    }

    public static func prepare<S: Sequence>(_ languages: S) async where S.Element == SyntaxLanguage {
        let registry = LanguageConfigurationRegistry.shared
        for language in uniqueLanguages(languages) {
            _ = await registry.highlightingSetup(for: language)
        }
    }

    private static func uniqueLanguages<S: Sequence>(_ languages: S) -> [SyntaxLanguage]
        where S.Element == SyntaxLanguage
    {
        var seen = Set<SyntaxLanguage>()
        var result: [SyntaxLanguage] = []

        for language in languages where seen.insert(language).inserted {
            result.append(language)
        }

        return result
    }
}
