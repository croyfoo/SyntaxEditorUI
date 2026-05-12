import Foundation

// Normalizes Tree-sitter capture names into editor source syntax IDs.
// Generated source syntax definitions own the vocabulary; this adapter owns
// capture-shape and language-context decisions such as HTML injections.
package enum TreeSitterCaptureClassifier {
    package static func classify(
        rawCaptureName: String,
        tokenText: String,
        rootLanguage: SyntaxLanguage
    ) -> EditorSourceSyntaxClassification {
        let raw = rawCaptureName.lowercased()
        if rootLanguage == .html {
            if raw.hasSuffix(".css") || raw.contains(".css.") || raw.hasPrefix("selector.css") {
                return classifyCSS(rawCaptureName: raw, tokenText: tokenText, language: .css)
            }
            if isJavaScriptCapture(raw) {
                return classifyJavaScript(rawCaptureName: raw, tokenText: tokenText, language: .javascript)
            }
        }

        switch rootLanguage {
        case .css:
            return classifyCSS(rawCaptureName: raw, tokenText: tokenText, language: .css)
        case .html:
            return classifyHTML(rawCaptureName: raw, tokenText: tokenText)
        case .javascript:
            return classifyJavaScript(rawCaptureName: raw, tokenText: tokenText, language: .javascript)
        case .json:
            return classifyJSON(rawCaptureName: raw, tokenText: tokenText)
        case .objectiveC:
            return classifyObjectiveC(rawCaptureName: raw, tokenText: tokenText)
        case .swift:
            return classifySwift(rawCaptureName: raw, tokenText: tokenText)
        case .toml:
            return classifyTOML(rawCaptureName: raw, tokenText: tokenText)
        case .xml:
            return classifyXML(rawCaptureName: raw, tokenText: tokenText)
        }
    }
}

private extension TreeSitterCaptureClassifier {
    static func classifyCSS(
        rawCaptureName raw: String,
        tokenText: String,
        language: SyntaxLanguage
    ) -> EditorSourceSyntaxClassification {
        let syntaxID: EditorSourceSyntaxID
        if raw.hasPrefix("comment") {
            syntaxID = .comment
        } else if raw == "keyword.css.atrule" {
            syntaxID = .keyword
        } else if raw.contains("atrule") || raw == "keyword.css.supports" || raw == "keyword.css.keyframes" {
            syntaxID = .declarationOther
        } else if raw.hasPrefix("keyword") {
            syntaxID = .keyword
        } else if raw.hasPrefix("selector") || raw == "tag_name" {
            syntaxID = .declarationOther
        } else if raw == "property.css.name" || raw == "property.css.feature" {
            syntaxID = .keyword
        } else if raw == "property.css.feature.supports" {
            syntaxID = .plain
        } else if raw.hasPrefix("variable.css.customproperty") {
            syntaxID = .plain
        } else if raw.hasPrefix("function.css.name.keyword") {
            syntaxID = .keyword
        } else if raw.hasPrefix("function.css.name") {
            syntaxID = .plain
        } else if raw.hasPrefix("string.css.color") || raw.hasPrefix("number.css") {
            syntaxID = .number
        } else if raw.hasPrefix("string") {
            syntaxID = .string
        } else if raw.hasPrefix("type.css.unit") {
            syntaxID = .keyword
        } else if raw.hasPrefix("attribute.css") {
            syntaxID = .plain
        } else {
            syntaxID = classifyCommon(raw) ?? .plain
        }
        return EditorSourceSyntaxClassification(syntaxID: syntaxID, language: language)
    }

    static func classifyHTML(rawCaptureName raw: String, tokenText: String) -> EditorSourceSyntaxClassification {
        let syntaxID: EditorSourceSyntaxID
        if raw == "constant.html.doctype" {
            syntaxID = .keyword
        } else if raw.hasPrefix("tag.html") || raw == "punctuation.html.bracket" {
            syntaxID = .keyword
        } else if raw.hasPrefix("attribute.html.name") {
            syntaxID = .attribute
        } else if raw.hasPrefix("string.html.attributevalue") {
            syntaxID = .string
        } else if raw.hasPrefix("entity") || raw.hasPrefix("character") {
            syntaxID = .character
        } else {
            syntaxID = classifyCommon(raw) ?? .plain
        }
        return EditorSourceSyntaxClassification(syntaxID: syntaxID, language: .html)
    }

    static func classifyJavaScript(
        rawCaptureName raw: String,
        tokenText: String,
        language: SyntaxLanguage
    ) -> EditorSourceSyntaxClassification {
        let syntaxID: EditorSourceSyntaxID
        if raw.hasPrefix("constructor") {
            syntaxID = .identifierTypeSystem
        } else if raw.hasPrefix("function") {
            syntaxID = .identifierFunctionSystem
        } else if raw.hasPrefix("property") || raw.hasPrefix("variable") {
            syntaxID = .plain
        } else if raw.hasPrefix("constant.builtin") {
            syntaxID = .keyword
        } else {
            syntaxID = classifyCommon(raw) ?? .plain
        }
        return EditorSourceSyntaxClassification(syntaxID: syntaxID, language: language)
    }

    static func classifyJSON(rawCaptureName raw: String, tokenText: String) -> EditorSourceSyntaxClassification {
        let syntaxID: EditorSourceSyntaxID
        if raw == "string.special.key" {
            syntaxID = .string
        } else if raw.hasPrefix("constant.builtin") {
            syntaxID = .keyword
        } else {
            syntaxID = classifyCommon(raw) ?? .plain
        }
        return EditorSourceSyntaxClassification(syntaxID: syntaxID, language: .json)
    }

    static func classifyObjectiveC(rawCaptureName raw: String, tokenText: String) -> EditorSourceSyntaxClassification {
        let syntaxID: EditorSourceSyntaxID
        if raw.hasPrefix("include") || raw.hasPrefix("preproc") || raw.hasPrefix("constant.macro") {
            syntaxID = .preprocessor
        } else if raw.hasPrefix("type.qualifier") {
            syntaxID = .keyword
        } else if raw.hasPrefix("type") || raw.hasPrefix("namespace") {
            syntaxID = .identifierTypeSystem
        } else if raw.hasPrefix("method") || raw.hasPrefix("function") || raw.hasPrefix("constructor") {
            syntaxID = .identifierFunctionSystem
        } else if raw.hasPrefix("exception") {
            syntaxID = .keyword
        } else if raw.hasPrefix("property") {
            syntaxID = .plain
        } else if raw.hasPrefix("variable") {
            syntaxID = .plain
        } else if raw.hasPrefix("attribute") || raw.hasPrefix("storageclass") {
            syntaxID = .keyword
        } else {
            syntaxID = classifyCommon(raw) ?? .plain
        }
        return EditorSourceSyntaxClassification(syntaxID: syntaxID, language: .objectiveC)
    }

    static func classifySwift(rawCaptureName raw: String, tokenText: String) -> EditorSourceSyntaxClassification {
        let syntaxID: EditorSourceSyntaxID
        if raw.hasPrefix("comment.documentation.keyword") || raw == "comment.doc.keyword" {
            syntaxID = .documentationCommentKeyword
        } else if raw.hasPrefix("comment.documentation") || raw.hasPrefix("comment.doc") {
            syntaxID = .documentationComment
        } else if raw == "comment.mark" {
            syntaxID = .mark
        } else if raw.hasPrefix("keyword.directive.condition.swift") {
            syntaxID = .preprocessor
        } else if raw == "keyword.directive" {
            syntaxID = .preprocessor
        } else if raw.hasPrefix("keyword.swift.availability") || raw.hasPrefix("keyword.swift.attribute.builtin") {
            syntaxID = .keyword
        } else if raw == "attribute.swift.punctuation" || raw == "attribute.swift.name" {
            syntaxID = .identifierTypeSystem
        } else if raw.hasPrefix("declaration.swift.type") {
            syntaxID = .declarationType
        } else if raw.hasPrefix("declaration.swift.macro") {
            syntaxID = .identifierMacro
        } else if raw.hasPrefix("declaration.swift") {
            syntaxID = .declarationOther
        } else if raw == "type.swift.reference" || raw.hasPrefix("identifier.swift.other.type") || raw.hasPrefix("identifier.swift.project.type") {
            syntaxID = .identifierTypeSystem
        } else if raw.hasPrefix("identifier.swift.import.name")
                    || raw.hasPrefix("identifier.swift.argument.label")
                    || raw.hasPrefix("identifier.swift.local")
        {
            syntaxID = .plain
        } else if raw.hasPrefix("identifier.swift.other.function") || raw.hasPrefix("identifier.swift.project.function") || raw == "function.swift.call" {
            syntaxID = .identifierFunctionSystem
        } else if raw.hasPrefix("identifier.swift.other.macro")
                    || raw.hasPrefix("identifier.swift.project.macro")
                    || raw == "function.swift.macro"
                    || raw == "constant.macro"
        {
            syntaxID = .identifierMacroSystem
        } else if raw.hasPrefix("identifier.swift.other.constant") || raw.hasPrefix("identifier.swift.project.constant") {
            syntaxID = .identifierConstantSystem
        } else if raw.hasPrefix("identifier.swift.other.property") || raw.hasPrefix("identifier.swift.project.property") || raw == "variable.member" {
            syntaxID = .identifierVariableSystem
        } else if raw == "constructor" {
            syntaxID = .keyword
        } else if raw == "constant.builtin" || raw == "boolean" || raw.hasPrefix("keyword.swift.type.builtin") {
            syntaxID = .keyword
        } else if raw == "text.uri" {
            syntaxID = .url
        } else if raw.hasPrefix("operator") || raw.hasPrefix("punctuation") || raw == "delimiter" || raw == "variable" || raw == "variable.parameter" {
            syntaxID = .plain
        } else {
            syntaxID = classifyCommon(raw) ?? .plain
        }
        return EditorSourceSyntaxClassification(syntaxID: syntaxID, language: .swift)
    }

    static func classifyTOML(rawCaptureName raw: String, tokenText: String) -> EditorSourceSyntaxClassification {
        let syntaxID: EditorSourceSyntaxID
        if raw == "property" {
            syntaxID = .attribute
        } else if raw == "type" || raw.hasPrefix("operator") || raw.hasPrefix("punctuation") {
            syntaxID = .plain
        } else if raw == "boolean" {
            syntaxID = .keyword
        } else {
            syntaxID = classifyCommon(raw) ?? .plain
        }
        return EditorSourceSyntaxClassification(syntaxID: syntaxID, language: .toml)
    }

    static func classifyXML(rawCaptureName raw: String, tokenText: String) -> EditorSourceSyntaxClassification {
        let syntaxID: EditorSourceSyntaxID
        if raw.hasPrefix("tag") || raw.hasPrefix("keyword") || raw.hasPrefix("constant") || raw.hasPrefix("entity") {
            syntaxID = .keyword
        } else if raw.hasPrefix("attribute") || raw.hasPrefix("property") {
            syntaxID = .attribute
        } else if raw.hasPrefix("type") {
            syntaxID = .identifierTypeSystem
        } else if raw.hasPrefix("character") || raw.hasPrefix("escape") {
            syntaxID = .character
        } else if raw.hasPrefix("markup.raw") {
            syntaxID = .string
        } else if raw.hasPrefix("markup.heading") {
            syntaxID = .keyword
        } else if raw.hasPrefix("markup.link") {
            syntaxID = .url
        } else {
            syntaxID = classifyCommon(raw) ?? .plain
        }
        return EditorSourceSyntaxClassification(syntaxID: syntaxID, language: .xml)
    }

    static func classifyCommon(_ raw: String) -> EditorSourceSyntaxID? {
        if raw.hasPrefix("comment.documentation.keyword") || raw == "comment.doc.keyword" {
            return .documentationCommentKeyword
        }
        if raw.hasPrefix("comment.documentation") || raw.hasPrefix("comment.doc") {
            return .documentationComment
        }
        if raw.hasPrefix("comment") {
            return .comment
        }
        if raw.hasPrefix("character") || raw.hasPrefix("escape") {
            return .character
        }
        if raw.hasPrefix("string") || raw.contains("regex") {
            return .string
        }
        if raw.hasPrefix("number") {
            return .number
        }
        if raw.hasPrefix("keyword") {
            return .keyword
        }
        if raw.hasPrefix("preproc") || raw.hasPrefix("include") {
            return .preprocessor
        }
        if raw.hasPrefix("operator") || raw.hasPrefix("punctuation") || raw.hasPrefix("delimiter") {
            return .plain
        }
        if raw == "boolean" {
            return .keyword
        }
        if raw.hasPrefix("constant") {
            return .identifierConstant
        }
        if raw.hasPrefix("function") || raw.hasPrefix("method") {
            return .identifierFunction
        }
        if raw.hasPrefix("type") {
            return .identifierType
        }
        if raw.hasPrefix("attribute") || raw.hasPrefix("property") || raw.hasPrefix("variable") {
            return .identifierVariable
        }
        if raw == "text.uri" {
            return .url
        }
        return nil
    }

    static func isJavaScriptCapture(_ raw: String) -> Bool {
        guard raw.contains(".html") == false,
              raw.contains(".css") == false
        else {
            return false
        }

        return raw == "keyword"
            || raw.hasPrefix("variable")
            || raw.hasPrefix("property")
            || raw == "constant.builtin"
            || raw.hasPrefix("function")
            || raw.hasPrefix("constructor")
            || raw.hasPrefix("string.special")
            || raw.hasPrefix("punctuation")
            || raw.hasPrefix("operator")
    }
}
