import SyntaxEditorUI

struct MiniLaunchConfiguration {
    static var current: MiniLaunchConfiguration {
        MiniLaunchConfiguration(initialPreset: .javascript)
    }

    let initialPresetID: MiniPreviewPreset.ID
    let initialText: String

    init(initialPreset: MiniPreviewPreset) {
        initialPresetID = initialPreset.id
        initialText = initialPreset.sampleText
    }

    var initialPreset: MiniPreviewPreset {
        MiniPreviewPreset.preset(for: initialPresetID) ?? .javascript
    }
}

extension SyntaxEditorModel {
    @MainActor
    convenience init(configuration: MiniLaunchConfiguration) {
        self.init(
            text: configuration.initialText,
            language: configuration.initialPreset.language,
            lineWrappingEnabled: false
        )
    }
}
