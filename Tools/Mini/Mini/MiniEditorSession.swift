import Observation
import SyntaxEditorUI

@MainActor
@Observable
final class MiniEditorSession {
    let editorModel: SyntaxEditorModel
    private(set) var selectedPresetID: MiniPreviewPreset.ID

    private let initialPresetID: MiniPreviewPreset.ID
    private let initialPresetText: String

    init(configuration: MiniLaunchConfiguration) {
        self.initialPresetID = configuration.initialPresetID
        self.initialPresetText = configuration.initialText
        self.selectedPresetID = configuration.initialPresetID
        self.editorModel = SyntaxEditorModel(
            text: configuration.initialText,
            language: configuration.initialPreset.language,
            lineWrappingEnabled: false
        )
    }

    var currentPreset: MiniPreviewPreset {
        MiniPreviewPreset.preset(for: selectedPresetID) ?? .javascript
    }

    var selectedThemePreset: SyntaxEditorTheme.Preset {
        get { editorModel.theme.preset ?? .default }
        set { editorModel.theme = .preset(newValue) }
    }

    func selectPreset(_ presetID: MiniPreviewPreset.ID) {
        guard selectedPresetID != presetID,
              let preset = MiniPreviewPreset.preset(for: presetID)
        else {
            return
        }

        selectedPresetID = presetID
        editorModel.language = preset.language
        editorModel.replaceText(text(for: preset))
    }

    private func text(for preset: MiniPreviewPreset) -> String {
        if preset.id == initialPresetID {
            return initialPresetText
        }

        return preset.sampleText
    }
}
