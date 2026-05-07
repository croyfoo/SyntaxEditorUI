import Foundation
import SwiftTreeSitter

public enum SyntaxLanguage: String, Sendable, CaseIterable, Identifiable {
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
        switch self {
        case .css:
            "CSS"
        case .html:
            "HTML"
        case .javascript:
            "JavaScript"
        case .json:
            "JSON"
        case .objectiveC:
            "Objective-C"
        case .swift:
            "Swift"
        case .toml:
            "TOML"
        case .xml:
            "XML"
        }
    }

    public static var all: [SyntaxLanguage] {
        allCases
    }

    public static func named(_ normalizedRawValue: String) -> SyntaxLanguage? {
        let lowered = normalizedRawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch lowered {
        case "css":
            return .css
        case "html", "htm":
            return .html
        case "javascript", "js":
            return .javascript
        case "json":
            return .json
        case "objective-c", "objectivec", "objc":
            return .objectiveC
        case "swift":
            return .swift
        case "toml":
            return .toml
        case "xml":
            return .xml
        default:
            return nil
        }
    }
}

struct SyntaxLanguageEdit {
    let text: String
    let selectedRange: NSRange

    init(text: String, selectedRange: NSRange) {
        self.text = text
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
    package var syntaxHighlightCacheKey: String {
        identifier
    }

    var treeSitterSupport: SyntaxTreeSitterSupport {
        switch self {
        case .css:
            CSSLanguage().treeSitterSupport
        case .html:
            HTMLLanguage().treeSitterSupport
        case .javascript:
            JavaScriptLanguage().treeSitterSupport
        case .json:
            JSONLanguage().treeSitterSupport
        case .objectiveC:
            ObjectiveCLanguage().treeSitterSupport
        case .swift:
            SwiftLanguage().treeSitterSupport
        case .toml:
            TOMLLanguage().treeSitterSupport
        case .xml:
            XMLLanguage().treeSitterSupport
        }
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        switch self {
        case .css:
            CSSLanguage().toggleComment(source: source, selection: selection)
        case .html:
            HTMLLanguage().toggleComment(source: source, selection: selection)
        case .javascript:
            JavaScriptLanguage().toggleComment(source: source, selection: selection)
        case .json:
            JSONLanguage().toggleComment(source: source, selection: selection)
        case .objectiveC:
            ObjectiveCLanguage().toggleComment(source: source, selection: selection)
        case .swift:
            SwiftLanguage().toggleComment(source: source, selection: selection)
        case .toml:
            TOMLLanguage().toggleComment(source: source, selection: selection)
        case .xml:
            XMLLanguage().toggleComment(source: source, selection: selection)
        }
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        switch self {
        case .css:
            CSSLanguage().isInsideLiteralOrComment(source: source, location: location)
        case .html:
            HTMLLanguage().isInsideLiteralOrComment(source: source, location: location)
        case .javascript:
            JavaScriptLanguage().isInsideLiteralOrComment(source: source, location: location)
        case .json:
            JSONLanguage().isInsideLiteralOrComment(source: source, location: location)
        case .objectiveC:
            ObjectiveCLanguage().isInsideLiteralOrComment(source: source, location: location)
        case .swift:
            SwiftLanguage().isInsideLiteralOrComment(source: source, location: location)
        case .toml:
            TOMLLanguage().isInsideLiteralOrComment(source: source, location: location)
        case .xml:
            XMLLanguage().isInsideLiteralOrComment(source: source, location: location)
        }
    }
}
