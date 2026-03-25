import SyntaxEditorUI
import Testing
@testable import Mini

struct MiniTests {
    @MainActor
    @Test("SyntaxEditorModel init uses the default sample text with JavaScript language")
    func defaultMiniModel() {
        let model = SyntaxEditorModel(text: MiniLaunchConfiguration(arguments: []).initialText)

        #expect(model.text.contains("const answer = 42;"))
        #expect(model.language.identifier == BuiltinSyntaxLanguages.javascript.identifier)
    }

    @MainActor
    @Test("SyntaxEditorModel init can start with an empty document for UI tests")
    func emptyDocumentMiniModel() {
        let model = SyntaxEditorModel(
            text: MiniLaunchConfiguration(arguments: [MiniLaunchConfiguration.uiTestEmptyDocumentArgument]).initialText
        )

        #expect(model.text.isEmpty)
        #expect(model.language.identifier == BuiltinSyntaxLanguages.javascript.identifier)
    }
}
