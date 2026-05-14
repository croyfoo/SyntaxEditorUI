import Foundation

protocol SyntaxLanguageSupport: Sendable {
    var language: SyntaxLanguage { get }
    var displayName: String { get }
    var aliases: Set<String> { get }
    var treeSitterSupport: SyntaxTreeSitterSupport { get }
    var syntaxVocabulary: EditorLanguageSyntaxVocabulary { get }

    init()

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit?
    func isInsideLiteralOrComment(source: String, location: Int) -> Bool
}

extension SyntaxLanguageSupport {
    var aliases: Set<String> {
        [language.identifier]
    }
}

package struct EditorLanguageSyntaxVocabulary: Sendable {
    package let fileExtensions: [String]
    package let rootRuleIdentifier: String
    package let syntaxTypes: [String]
    package let keywordWords: Set<String>
    package let attributeWords: Set<String>
    package let preprocessorWords: Set<String>

    package init(
        fileExtensions: [String],
        rootRuleIdentifier: String,
        syntaxTypes: [String],
        keywordWords: Set<String>,
        attributeWords: Set<String>,
        preprocessorWords: Set<String>
    ) {
        self.fileExtensions = fileExtensions
        self.rootRuleIdentifier = rootRuleIdentifier
        self.syntaxTypes = syntaxTypes
        self.keywordWords = keywordWords
        self.attributeWords = attributeWords
        self.preprocessorWords = preprocessorWords
    }
}

enum BundledLanguageQueryResources {
    static func directories(named directoryName: String) -> [URL] {
        guard let resourceURL = Bundle.module.resourceURL else {
            return []
        }

        return [
            resourceURL.appendingPathComponent(
                directoryName,
                isDirectory: true
            ),
        ]
    }
}
