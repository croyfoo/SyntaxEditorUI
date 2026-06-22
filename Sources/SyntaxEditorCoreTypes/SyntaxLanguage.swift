import Foundation

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
        switch self {
        case .plainText:
            "Plain Text"
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

    public init?(identifier rawIdentifier: String) {
        let lowered = rawIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let language = Self.allCases.first(where: { $0.identifiers.contains(lowered) }) else {
            return nil
        }

        self = language
    }
}

extension SyntaxLanguage {
    package struct EditResult {
        package let edits: [SyntaxEditorTextChange.Replacement]
        package let selectedRange: NSRange

        package init(edits: [SyntaxEditorTextChange.Replacement], selectedRange: NSRange) {
            self.edits = edits
            self.selectedRange = selectedRange
        }
    }

    package var syntaxHighlightCacheKey: String {
        identifier
    }

    package static var syntaxHighlightedCases: [SyntaxLanguage] {
        allCases.filter(\.supportsSyntaxHighlighting)
    }

    public var supportsSyntaxHighlighting: Bool {
        switch self {
        case .plainText:
            false
        default:
            true
        }
    }

    public var supportsCodeEditingCommands: Bool {
        self != .plainText
    }

    package var identifiers: Set<String> {
        switch self {
        case .plainText:
            ["plain-text", "plain", "plaintext", "text", "txt", "text/plain"]
        case .css:
            ["css"]
        case .html:
            ["html", "htm"]
        case .javascript:
            ["javascript", "js"]
        case .json:
            ["json"]
        case .objectiveC:
            ["objective-c", "objectivec", "objc"]
        case .swift:
            ["swift"]
        case .toml:
            ["toml"]
        case .xml:
            ["xml"]
        }
    }
}
