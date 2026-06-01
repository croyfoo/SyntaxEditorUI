import Foundation
import SwiftTreeSitter

public enum SyntaxLanguage: String, Sendable, CaseIterable, Identifiable {
    case plainText = "plain-text"
    case css
    case html
    case javascript
    case json
    case objectiveC = "objective-c"
    case swift
    case toml
    case xml

    public var id: String {
        identifier
    }

    public var identifier: String {
        rawValue
    }

    public var displayName: String {
        support.displayName
    }

    public static var all: [SyntaxLanguage] {
        allCases
    }

    public static func named(_ normalizedRawValue: String) -> SyntaxLanguage? {
        let lowered = normalizedRawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return allCases.first { $0.support.aliases.contains(lowered) }
    }
}

struct SyntaxLanguageEdit {
    let edits: [SyntaxEditorTextEdit]
    let selectedRange: NSRange

    init(edits: [SyntaxEditorTextEdit], selectedRange: NSRange) {
        self.edits = edits
        self.selectedRange = selectedRange
    }
}

struct SyntaxTreeSitterSupport: Sendable {
    let name: String
    let bundleName: String
    let queryDirectories: [URL]
    private let makeLanguageBody: @Sendable () -> Language

    init(
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

    func makeLanguage() -> Language {
        makeLanguageBody()
    }
}

extension SyntaxLanguage {
    var support: any SyntaxLanguageSupport {
        switch self {
        case .plainText:
            PlainTextLanguage()
        case .css:
            CSSLanguage()
        case .html:
            HTMLLanguage()
        case .javascript:
            JavaScriptLanguage()
        case .json:
            JSONLanguage()
        case .objectiveC:
            ObjectiveCLanguage()
        case .swift:
            SwiftLanguage()
        case .toml:
            TOMLLanguage()
        case .xml:
            XMLLanguage()
        }
    }

    package var syntaxHighlightCacheKey: String {
        identifier
    }

    package static var syntaxHighlightedCases: [SyntaxLanguage] {
        allCases.filter(\.supportsSyntaxHighlighting)
    }

    package var supportsSyntaxHighlighting: Bool {
        treeSitterSupport != nil
    }

    package var supportsCodeEditingCommands: Bool {
        support.supportsCodeEditingCommands
    }

    var treeSitterSupport: SyntaxTreeSitterSupport? {
        support.treeSitterSupport
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        support.toggleComment(source: source, selection: selection)
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        support.isInsideLiteralOrComment(source: source, location: location)
    }
}
