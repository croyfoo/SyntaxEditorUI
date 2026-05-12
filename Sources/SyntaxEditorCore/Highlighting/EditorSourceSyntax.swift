import Foundation

package struct EditorSourceSyntaxID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = Self.normalized(rawValue)
    }

    package init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    package init(_ value: String) {
        self.init(rawValue: value)
    }

    package var styleKey: String {
        "editor.syntax.\(rawValue)"
    }

    private static func normalized(_ value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.hasPrefix("editor.syntax.") {
            return String(lowered.dropFirst("editor.syntax.".count))
        }
        if lowered.hasPrefix("xcode.syntax.") {
            return String(lowered.dropFirst("xcode.syntax.".count))
        }
        return lowered
    }
}

package extension EditorSourceSyntaxID {
    static let plain: Self = "plain"
    static let comment: Self = "comment"
    static let documentationComment: Self = "comment.doc"
    static let documentationCommentKeyword: Self = "comment.doc.keyword"
    static let mark: Self = "mark"
    static let string: Self = "string"
    static let character: Self = "character"
    static let number: Self = "number"
    static let keyword: Self = "keyword"
    static let preprocessor: Self = "preprocessor"
    static let url: Self = "url"
    static let attribute: Self = "attribute"
    static let declarationOther: Self = "declaration.other"
    static let declarationType: Self = "declaration.type"
    static let identifierType: Self = "identifier.type"
    static let identifierTypeSystem: Self = "identifier.type.system"
    static let identifierClass: Self = "identifier.class"
    static let identifierClassSystem: Self = "identifier.class.system"
    static let identifierFunction: Self = "identifier.function"
    static let identifierFunctionSystem: Self = "identifier.function.system"
    static let identifierMacro: Self = "identifier.macro"
    static let identifierMacroSystem: Self = "identifier.macro.system"
    static let identifierConstant: Self = "identifier.constant"
    static let identifierConstantSystem: Self = "identifier.constant.system"
    static let identifierVariable: Self = "identifier.variable"
    static let identifierVariableSystem: Self = "identifier.variable.system"
}

package struct EditorSourceSyntaxClassification: Equatable, Sendable {
    package let syntaxID: EditorSourceSyntaxID
    package let language: SyntaxLanguage?

    package init(syntaxID: EditorSourceSyntaxID, language: SyntaxLanguage?) {
        self.syntaxID = syntaxID
        self.language = language
    }
}

package enum EditorSourceSyntaxCategory {
    case comment
    case string
    case keyword
    case number
    case function
    case type
    case constant
    case variable
    case punctuation

    package static func category(for syntaxID: EditorSourceSyntaxID) -> Self? {
        let value = syntaxID.rawValue
        if value == "comment" || value.hasPrefix("comment.") || value == "mark" {
            return .comment
        }
        if value == "string" || value == "character" || value.hasPrefix("markup.code") {
            return .string
        }
        if value == "keyword" || value == "preprocessor" {
            return .keyword
        }
        if value == "number" || value == "url" {
            return .number
        }
        if value.contains(".function") || value.contains(".method") || value == "identifier.macro" || value == "identifier.macro.system" {
            return .function
        }
        if value.contains(".type") || value.contains(".class") || value == "declaration.type" {
            return .type
        }
        if value.contains(".constant") {
            return .constant
        }
        if value == "declaration.other" {
            return .function
        }
        if value == "attribute" || value.contains(".variable") {
            return .variable
        }
        if value == "plain" {
            return nil
        }
        return .punctuation
    }
}
