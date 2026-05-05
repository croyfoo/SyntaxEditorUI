import Observation
import SyntaxEditorUI

@MainActor
@Observable
final class MiniContentViewModel {
    var editorModel: SyntaxEditorModel
    var selectedPresetID: MiniPreviewPreset.ID? {
        didSet {
            guard let selectedPresetID,
                  selectedPresetID != currentPresetID,
                  let preset = MiniPreviewPreset.preset(for: selectedPresetID)
            else {
                return
            }

            currentPresetID = selectedPresetID

            editorModel = SyntaxEditorModel(
                text: text(for: preset),
                language: preset.language,
                lineWrappingEnabled: false
            )
        }
    }

    private let initialPresetID: MiniPreviewPreset.ID
    private let initialPresetText: String
    private(set) var currentPresetID: MiniPreviewPreset.ID

    init(configuration: MiniLaunchConfiguration) {
        self.initialPresetID = configuration.initialPresetID
        self.initialPresetText = configuration.initialText
        self.currentPresetID = configuration.initialPresetID
        self.editorModel = SyntaxEditorModel(configuration: configuration)
        self.selectedPresetID = configuration.initialPresetID
    }

    var currentPreset: MiniPreviewPreset {
        MiniPreviewPreset.preset(for: currentPresetID) ?? .javascript
    }

    private func text(for preset: MiniPreviewPreset) -> String {
        if preset.id == initialPresetID {
            return initialPresetText
        }

        return preset.sampleText
    }
}
