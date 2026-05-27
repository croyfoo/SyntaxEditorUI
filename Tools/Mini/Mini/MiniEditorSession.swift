import Observation
import SyntaxEditorUI

@MainActor
@Observable
final class MiniEditorSession {
    let editorDocument: SyntaxEditorDocument
    let editorConfiguration: SyntaxEditorConfiguration
    private(set) var selectedPresetID: MiniPreviewPreset.ID

    private let initialPresetID: MiniPreviewPreset.ID
    private let initialPresetText: String

    init(configuration: MiniLaunchConfiguration) {
        self.initialPresetID = configuration.initialPresetID
        self.initialPresetText = configuration.initialText
        self.selectedPresetID = configuration.initialPresetID
        self.editorDocument = SyntaxEditorDocument(text: configuration.initialText)
        self.editorConfiguration = SyntaxEditorConfiguration(
            language: configuration.initialPreset.language,
            lineWrappingEnabled: false
        )
    }

    var currentPreset: MiniPreviewPreset {
        MiniPreviewPreset.preset(for: selectedPresetID) ?? .javascript
    }

    var selectedThemePreset: SyntaxEditorColorTheme.Preset {
        get { editorConfiguration.colorTheme.preset ?? .default }
        set { editorConfiguration.colorTheme = .preset(newValue) }
    }

    func selectPreset(_ presetID: MiniPreviewPreset.ID) {
        guard selectedPresetID != presetID,
              let preset = MiniPreviewPreset.preset(for: presetID)
        else {
            return
        }

        selectedPresetID = presetID
        editorConfiguration.language = preset.language
        editorDocument.replaceText(text(for: preset))
    }

    private func text(for preset: MiniPreviewPreset) -> String {
        if preset.id == initialPresetID {
            return initialPresetText
        }

        return preset.sampleText
    }
}
