import Foundation

protocol SyntaxLanguageSupport: Sendable {
    var language: SyntaxLanguage { get }
    var displayName: String { get }
    var aliases: Set<String> { get }
    var treeSitterSupport: SyntaxLanguage.TreeSitterSupport? { get }
    var supportsCodeEditingCommands: Bool { get }

    init()

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguage.EditResult?
    func isInsideLiteralOrComment(source: String, location: Int) -> Bool
}

extension SyntaxLanguageSupport {
    var aliases: Set<String> {
        [language.identifier]
    }

    var supportsCodeEditingCommands: Bool {
        true
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
