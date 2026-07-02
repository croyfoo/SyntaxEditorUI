import Foundation

package enum EditorSourceSyntax {
package struct ID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
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
}

package extension EditorSourceSyntax.ID {
    static let plain: Self = "plain"
    static let comment: Self = "comment"
    static let documentationComment: Self = "comment.doc"
    static let documentationCommentKeyword: Self = "comment.doc.keyword"
    static let mark: Self = "mark"
    static let string: Self = "string"
    static let character: Self = "character"
    static let pattern: Self = "pattern"
    static let number: Self = "number"
    static let keyword: Self = "keyword"
    static let preprocessor: Self = "preprocessor"
    static let url: Self = "url"
    static let attribute: Self = "attribute"
    static let identifier: Self = "identifier"
    static let name: Self = "name"
    static let nameOther: Self = "name.other"
    static let namePartial: Self = "name.partial"
    static let nameType: Self = "name.type"
    static let nameTree: Self = "name.tree"
    static let declarationOther: Self = "declaration.other"
    static let declarationType: Self = "declaration.type"
    static let declarationEnumCase: Self = "declaration.enum.case"
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

extension EditorSourceSyntax {
package struct Classification: Equatable, Sendable {
    package let syntaxID: EditorSourceSyntax.ID
    package let language: SyntaxLanguage?

    package init(syntaxID: EditorSourceSyntax.ID, language: SyntaxLanguage?) {
        self.syntaxID = syntaxID
        self.language = language
    }
}

package enum Capture {
    private static let canonicalPrefix = "editor.syntax."

    package static func parse(
        rawCaptureName: String,
        rootLanguage: SyntaxLanguage
    ) -> EditorSourceSyntax.Classification {
        let normalized = normalizedCaptureName(rawCaptureName)
        guard normalized.hasPrefix(canonicalPrefix) else {
            return EditorSourceSyntax.Classification(syntaxID: .plain, language: rootLanguage)
        }

        let payload = normalized.dropFirst(canonicalPrefix.count)
        guard let separator = payload.firstIndex(of: ".") else {
            return EditorSourceSyntax.Classification(syntaxID: .plain, language: rootLanguage)
        }

        let languageName = String(payload[..<separator])
        let syntaxID = String(payload[payload.index(after: separator)...])
        guard syntaxID.isEmpty == false,
              let language = SyntaxLanguage.editorSyntaxCaptureLanguage(named: languageName)
        else {
            return EditorSourceSyntax.Classification(syntaxID: .plain, language: rootLanguage)
        }

        return EditorSourceSyntax.Classification(
            syntaxID: EditorSourceSyntax.ID(syntaxID),
            language: language
        )
    }

    package static func rawCaptureName(
        syntaxID: EditorSourceSyntax.ID,
        language: SyntaxLanguage
    ) -> String {
        "\(canonicalPrefix)\(language.editorSyntaxCaptureIdentifier).\(syntaxID.rawValue)"
    }

    private static func normalizedCaptureName(_ rawCaptureName: String) -> String {
        var name = rawCaptureName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        return name
    }
}
}

private extension SyntaxLanguage {
    var editorSyntaxCaptureIdentifier: String {
        switch self {
        case .plainText:
            "plaintext"
        case .css:
            "css"
        case .html:
            "html"
        case .javascript:
            "javascript"
        case .json:
            "json"
        case .objectiveC:
            "objectivec"
        case .php:
            "php"
        case .swift:
            "swift"
        case .toml:
            "toml"
        case .xml:
            "xml"
        case .yaml:
            "yaml"
        case .shell:
            "shell"
        case .markdown:
            "markdown"
        case .markdownInline:
            "markdown-inline"
        }
    }

    static func editorSyntaxCaptureLanguage(named rawName: String) -> SyntaxLanguage? {
        switch rawName {
        case "plaintext", "plain-text", "plain", "text":
            .plainText
        case "css":
            .css
        case "html":
            .html
        case "javascript":
            .javascript
        case "json":
            .json
        case "objectivec":
            .objectiveC
        case "php":
            .php
        case "swift":
            .swift
        case "toml":
            .toml
        case "xml":
            .xml
        case "yaml", "yml":
            .yaml
        case "shell", "bash", "sh", "zsh":
            .shell
        case "markdown", "md", "mdown", "mkd":
            .markdown
        case "markdown-inline", "markdown_inline":
            .markdownInline
        default:
            nil
        }
    }
}

extension EditorSourceSyntax {
package enum Category {
    case comment
    case string
    case keyword
    case number
    case function
    case type
    case constant
    case variable
    case punctuation

    package static func category(for syntaxID: EditorSourceSyntax.ID) -> Self? {
        let value = syntaxID.rawValue
        if value == "comment" || value.hasPrefix("comment.") || value == "mark" {
            return .comment
        }
        if value == "string" || value == "character" || value == "pattern" || value.hasPrefix("markup.code") {
            return .string
        }
        if value == "keyword" || value.hasPrefix("keyword.") || value == "preprocessor" || value.hasPrefix("preprocessor.") {
            return .keyword
        }
        if value == "number" || value == "url" {
            return .number
        }
        if value == "name" || value == "name.other" || value.contains(".function") || value.contains(".method") || value == "identifier.macro" || value == "identifier.macro.system" {
            return .function
        }
        if value == "name.partial" || value == "name.tree" || value.contains(".type") || value.contains(".class") || value == "declaration.type" || value.hasPrefix("definition.") || value == "typedef" || value == "associatedtype" {
            return .type
        }
        if value.contains(".constant") {
            return .constant
        }
        if value == "declaration.other" || value == "declaration.enum.case" {
            return .function
        }
        if value == "attribute" || value.contains(".variable") {
            return .variable
        }
        if value == "plain" || value == "identifier" {
            return nil
        }
        if value == "punctuation" || value == "operator" {
            return .punctuation
        }
        return nil
    }
}
}
