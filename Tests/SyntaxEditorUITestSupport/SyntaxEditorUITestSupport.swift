import Foundation
import SyntaxEditorCore
import SyntaxEditorUI

@MainActor
public struct SyntaxEditorUITestContext {
    public let document: SyntaxEditorDocument
    public let configuration: SyntaxEditorConfiguration

    public init(
        text: String = "",
        language: SyntaxLanguage = .javascript,
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false,
        colorTheme: SyntaxEditorColorTheme = .default,
        drawsBackground: Bool = true,
        fontSizeDelta: Int = 0
    ) {
        self.document = SyntaxEditorDocument(text: text)
        self.configuration = SyntaxEditorConfiguration(
            language: language,
            isEditable: isEditable,
            lineWrappingEnabled: lineWrappingEnabled,
            colorTheme: colorTheme,
            drawsBackground: drawsBackground,
            fontSizeDelta: fontSizeDelta
        )
    }
}
