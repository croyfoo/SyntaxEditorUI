import SyntaxEditorUI
import Testing
@testable import Mini

struct MiniTests {
    @MainActor
    @Test("SyntaxEditorModel init uses the default sample text with JavaScript language")
    func defaultMiniModel() {
        let model = SyntaxEditorModel(configuration: MiniLaunchConfiguration(arguments: []))

        #expect(model.text.contains("const answer = 42;"))
        #expect(model.language.identifier == BuiltinSyntaxLanguages.javascript.identifier)
    }

    @MainActor
    @Test("SyntaxEditorModel init can start with an empty document for UI tests")
    func emptyDocumentMiniModel() {
        let model = SyntaxEditorModel(
            configuration: MiniLaunchConfiguration(arguments: [MiniLaunchConfiguration.uiTestEmptyDocumentArgument])
        )

        #expect(model.text.isEmpty)
        #expect(model.language.identifier == BuiltinSyntaxLanguages.javascript.identifier)
    }

    @Test("MiniLaunchConfiguration can start with an HTML preset")
    func htmlPresetLaunchConfiguration() {
        let configuration = MiniLaunchConfiguration(arguments: [MiniLaunchConfiguration.htmlDocumentArgument])

        #expect(configuration.initialText.contains("<script>"))
        #expect(configuration.initialText.contains("<style>"))
        #expect(configuration.language.identifier == BuiltinSyntaxLanguages.html.identifier)
    }
}
