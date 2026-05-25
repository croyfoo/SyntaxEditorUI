import Observation
import SyntaxEditorUI

@MainActor
@Observable
final class MiniContentViewModel {
    let editorDocument: SyntaxEditorDocument
    let editorConfiguration: SyntaxEditorConfiguration
    var selectedPresetID: MiniPreviewPreset.ID? {
        didSet {
            guard let selectedPresetID,
                  selectedPresetID != currentPresetID,
                  let preset = MiniPreviewPreset.preset(for: selectedPresetID)
            else {
                return
            }

            editorConfiguration.language = preset.language
            editorDocument.replaceText(text(for: preset))
            currentPresetID = selectedPresetID
        }
    }

    private let initialPresetID: MiniPreviewPreset.ID
    private let initialPresetText: String
    private(set) var currentPresetID: MiniPreviewPreset.ID

    init(configuration: MiniLaunchConfiguration) {
        self.initialPresetID = configuration.initialPresetID
        self.initialPresetText = configuration.initialText
        self.currentPresetID = configuration.initialPresetID
        self.editorDocument = SyntaxEditorDocument(text: configuration.initialText)
        self.editorConfiguration = SyntaxEditorConfiguration(
            language: configuration.initialPreset.language,
            lineWrappingEnabled: false
        )
        self.selectedPresetID = configuration.initialPresetID
    }

    var currentPreset: MiniPreviewPreset {
        MiniPreviewPreset.preset(for: currentPresetID) ?? .javascript
    }

    var selectedThemePreset: SyntaxEditorColorTheme.Preset {
        get { editorConfiguration.colorTheme.preset ?? .default }
        set { editorConfiguration.colorTheme = .preset(newValue) }
    }

    private func text(for preset: MiniPreviewPreset) -> String {
        if preset.id == initialPresetID {
            return initialPresetText
        }

        return preset.sampleText
    }
}
