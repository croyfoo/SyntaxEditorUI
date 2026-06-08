import Foundation
import SyntaxEditorCore
import SyntaxEditorUI

@MainActor
public struct SyntaxEditorUITestContext {
    public let model: SyntaxEditorModel

    public init(
        text: String = "",
        language: SyntaxLanguage = .javascript,
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false,
        theme: SyntaxEditorTheme = .default,
        drawsBackground: Bool = true,
        fontSizeDelta: Int = 0
    ) {
        self.model = SyntaxEditorModel(
            text: text,
            language: language,
            isEditable: isEditable,
            lineWrappingEnabled: lineWrappingEnabled,
            theme: theme,
            drawsBackground: drawsBackground,
            fontSizeDelta: fontSizeDelta
        )
    }
}
