import Foundation

protocol SyntaxLanguageSupport: Sendable {
    var language: SyntaxLanguage { get }
    var displayName: String { get }
    var aliases: Set<String> { get }
    var treeSitterSupport: SyntaxTreeSitterSupport { get }

    init()

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit?
    func isInsideLiteralOrComment(source: String, location: Int) -> Bool
}

extension SyntaxLanguageSupport {
    var aliases: Set<String> {
        [language.identifier]
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
