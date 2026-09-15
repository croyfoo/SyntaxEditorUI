import SyntaxEditorCoreTypes
import SyntaxEditorLanguageSupport

extension SyntaxEditorHighlighting {
    /// Prepares shared highlighting resources for a language before first use.
    ///
    /// Preparation is optional and does not highlight or change a document.
    /// Repeated and concurrent calls reuse the same setup. Passing
    /// `SyntaxLanguage.plainText` requires no highlighting resources.
    ///
    /// - Parameter language: The language an editor is expected to display.
    public static func prepare(_ language: SyntaxLanguage) async {
        _ = await LanguageConfigurationRegistry.shared.highlightingSetup(for: language)
    }

    /// Prepares shared highlighting resources for a collection of languages.
    ///
    /// Duplicate languages are prepared once per call. This method returns
    /// after preparation has finished for every distinct language in the
    /// sequence. It does not change any editor's selected language or text.
    ///
    /// - Parameter languages: The language modes your app expects to display.
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
