import Observation

@MainActor
@Observable
public final class SyntaxEditorModel {
    public var text: String
    public var language: SyntaxLanguage
    public var isEditable: Bool
    public var lineWrappingEnabled: Bool
    public var colorTheme: SyntaxEditorColorTheme

    public init(
        text: String = "",
        language: SyntaxLanguage = .javascript,
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false,
        colorTheme: SyntaxEditorColorTheme = .xcode
    ) {
        self.text = text
        self.language = language
        self.isEditable = isEditable
        self.lineWrappingEnabled = lineWrappingEnabled
        self.colorTheme = colorTheme
    }
}
