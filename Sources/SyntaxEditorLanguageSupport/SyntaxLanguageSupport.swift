import Foundation
import SwiftTreeSitter
import SyntaxEditorCoreTypes

package protocol SyntaxLanguageSupport: Sendable {
    var language: SyntaxLanguage { get }
    var displayName: String { get }
    var aliases: Set<String> { get }
    var treeSitterSupport: SyntaxLanguageTreeSitterSupport? { get }
    var supportsCodeEditingCommands: Bool { get }

    init()

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguage.EditResult?
    func isInsideLiteralOrComment(source: String, location: Int) -> Bool
}

extension SyntaxLanguageSupport {
    package var aliases: Set<String> {
        [language.identifier]
    }

    package var supportsCodeEditingCommands: Bool {
        true
    }
}

package struct SyntaxLanguageTreeSitterSupport: Sendable {
    package let name: String
    package let bundleName: String
    package let queryDirectories: [URL]
    private let makeLanguageBody: @Sendable () -> Language

    package init(
        name: String,
        bundleName: String,
        queryDirectories: [URL] = [],
        makeLanguage: @escaping @Sendable () -> Language
    ) {
        let standardizedQueryDirectories = queryDirectories.map {
            $0.standardizedFileURL
        }
        self.name = name
        self.bundleName = bundleName
        self.queryDirectories = standardizedQueryDirectories
        self.makeLanguageBody = makeLanguage
    }

    package func makeLanguage() -> Language {
        makeLanguageBody()
    }
}

package enum BundledLanguageQueryResources {
    package static func directories(in bundle: Bundle, named directoryName: String) -> [URL] {
        guard let resourceURL = bundle.resourceURL else {
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
