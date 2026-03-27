import Foundation
import SwiftTreeSitter

public protocol SyntaxLanguage: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    var treeSitterSupport: SyntaxTreeSitterSupport { get }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit?
    func isInsideLiteralOrComment(source: String, location: Int) -> Bool
}

public struct SyntaxLanguageEdit {
    public let text: String
    public let selectedRange: NSRange

    public init(text: String, selectedRange: NSRange) {
        self.text = text
        self.selectedRange = selectedRange
    }
}

public struct SyntaxTreeSitterSupport: Sendable {
    public let name: String
    public let bundleName: String
    public let queryDirectories: [URL]
    public let cacheKey: String
    private let makeLanguageBody: @Sendable () -> Language

    public init(
        name: String,
        bundleName: String,
        queryDirectories: [URL] = [],
        cacheKey: String? = nil,
        makeLanguage: @escaping @Sendable () -> Language
    ) {
        let standardizedQueryDirectories = queryDirectories.map {
            $0.standardizedFileURL
        }
        self.name = name
        self.bundleName = bundleName
        self.queryDirectories = standardizedQueryDirectories
        self.cacheKey = cacheKey ?? Self.defaultCacheKey(
            name: name,
            bundleName: bundleName,
            queryDirectories: standardizedQueryDirectories
        )
        self.makeLanguageBody = makeLanguage
    }

    public func makeLanguage() -> Language {
        makeLanguageBody()
    }

    private static func defaultCacheKey(
        name: String,
        bundleName: String,
        queryDirectories: [URL]
    ) -> String {
        let queryDirectoryList = queryDirectories
            .map(\.path)
            .joined(separator: "|")
        return "\(name)|\(bundleName)|\(queryDirectoryList)"
    }
}

extension SyntaxLanguage {
    var syntaxHighlightCacheKey: String {
        "\(identifier)|\(treeSitterSupport.cacheKey)"
    }
}

public enum BuiltinSyntaxLanguages {
    public static let css = CSSLanguage()
    public static let html = HTMLLanguage()
    public static let javascript = JavaScriptLanguage()
    public static let json = JSONLanguage()
    public static let swift = SwiftLanguage()
    public static let xml = XMLLanguage()

    public static var all: [any SyntaxLanguage] {
        [css, html, javascript, json, swift, xml]
    }

    public static func named(_ normalizedRawValue: String) -> (any SyntaxLanguage)? {
        let lowered = normalizedRawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch lowered {
        case "css":
            return css
        case "html", "htm":
            return html
        case "javascript", "js":
            return javascript
        case "json":
            return json
        case "swift":
            return swift
        case "xml":
            return xml
        default:
            return nil
        }
    }
}
