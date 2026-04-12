import SyntaxEditorUI
import Testing
@testable import Mini

struct MiniTests {
    @Test("MiniLaunchConfiguration uses the JavaScript preset by default")
    func defaultLaunchConfiguration() {
        let configuration = MiniLaunchConfiguration(arguments: [])

        #expect(configuration.initialPresetID == .javascript)
        #expect(configuration.initialText == MiniPreviewPreset.javascript.sampleText)
    }

    @Test("MiniLaunchConfiguration can start with an empty JavaScript document for UI tests")
    func emptyDocumentLaunchConfiguration() {
        let configuration = MiniLaunchConfiguration(arguments: [MiniLaunchConfiguration.uiTestEmptyDocumentArgument])

        #expect(configuration.initialPresetID == .javascript)
        #expect(configuration.initialText.isEmpty)
    }

    @Test("MiniLaunchConfiguration can start with an HTML preset")
    func htmlPresetLaunchConfiguration() {
        let configuration = MiniLaunchConfiguration(arguments: [MiniLaunchConfiguration.htmlDocumentArgument])

        #expect(configuration.initialPresetID == .html)
        #expect(configuration.initialText == MiniPreviewPreset.html.sampleText)
    }

    @MainActor
    @Test("SyntaxEditorModel init uses the launch configuration preset language")
    func syntaxEditorModelUsesLaunchConfigurationPresetLanguage() {
        let model = SyntaxEditorModel(configuration: MiniLaunchConfiguration(arguments: [MiniLaunchConfiguration.htmlDocumentArgument]))

        #expect(model.language.identifier == BuiltinSyntaxLanguages.html.identifier)
        #expect(model.text == MiniPreviewPreset.html.sampleText)
    }

    @MainActor
    @Test("MiniContentViewModel updates the editor model when selecting a preset")
    func miniContentViewModelSelectPreset() {
        let model = MiniContentViewModel(configuration: MiniLaunchConfiguration(arguments: []))
        let previousEditorModel = model.editorModel

        model.selectedPresetID = .toml

        #expect(model.selectedPresetID == .toml)
        #expect(ObjectIdentifier(model.editorModel) != ObjectIdentifier(previousEditorModel))
        #expect(model.editorModel.language.identifier == BuiltinSyntaxLanguages.toml.identifier)
        #expect(model.editorModel.text == MiniPreviewPreset.toml.sampleText)
    }

    @MainActor
    @Test("MiniContentViewModel preserves the empty launch document while the initial preset selection is restored")
    func miniContentViewModelPreservesEmptyLaunchDocument() {
        let model = MiniContentViewModel(
            configuration: MiniLaunchConfiguration(arguments: [MiniLaunchConfiguration.uiTestEmptyDocumentArgument])
        )
        let previousEditorModel = model.editorModel

        model.selectedPresetID = nil
        model.selectedPresetID = .javascript

        #expect(model.editorModel.text.isEmpty)
        #expect(model.editorModel.language.identifier == BuiltinSyntaxLanguages.javascript.identifier)
        #expect(ObjectIdentifier(model.editorModel) == ObjectIdentifier(previousEditorModel))
    }

    @MainActor
    @Test("MiniContentViewModel keeps the edited document when the current selection is restored")
    func miniContentViewModelPreservesEditedDocumentWhenSelectionReturns() {
        let model = MiniContentViewModel(configuration: MiniLaunchConfiguration(arguments: []))
        model.editorModel.text = "const edited = true;\n"
        let previousEditorModel = model.editorModel

        model.selectedPresetID = nil
        model.selectedPresetID = .javascript

        #expect(model.editorModel.text == "const edited = true;\n")
        #expect(model.editorModel.language.identifier == BuiltinSyntaxLanguages.javascript.identifier)
        #expect(ObjectIdentifier(model.editorModel) == ObjectIdentifier(previousEditorModel))
    }

    @MainActor
    @Test("MiniContentViewModel restores the launch text when returning to the initial preset")
    func miniContentViewModelRestoresLaunchTextForInitialPreset() {
        let model = MiniContentViewModel(
            configuration: MiniLaunchConfiguration(arguments: [MiniLaunchConfiguration.uiTestEmptyDocumentArgument])
        )

        model.selectedPresetID = .html
        model.selectedPresetID = .javascript

        #expect(model.editorModel.text.isEmpty)
        #expect(model.editorModel.language.identifier == BuiltinSyntaxLanguages.javascript.identifier)
    }
}
