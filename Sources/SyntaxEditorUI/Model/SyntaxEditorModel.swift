import Observation

@MainActor
@Observable
public final class SyntaxEditorModel {
    public var text: String
    public var language: any SyntaxLanguage
    public var isEditable: Bool
    public var lineWrappingEnabled: Bool

    public init(
        text: String = "",
        language: any SyntaxLanguage,
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false
    ) {
        self.text = text
        self.language = language
        self.isEditable = isEditable
        self.lineWrappingEnabled = lineWrappingEnabled
    }

    public convenience init(
        text: String = "",
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false
    ) {
        self.init(
            text: text,
            language: BuiltinSyntaxLanguages.javascript,
            isEditable: isEditable,
            lineWrappingEnabled: lineWrappingEnabled
        )
    }
}
