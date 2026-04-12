import Foundation
import SyntaxEditorUI

struct MiniLaunchConfiguration {
    static let uiTestEmptyDocumentArgument = "--uitest-empty-document"
    static let htmlDocumentArgument = "--html-document"
    static var current: MiniLaunchConfiguration {
        MiniLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }

    let initialPresetID: MiniPreviewPreset.ID
    let initialText: String

    init(arguments: [String]) {
        if arguments.contains(Self.uiTestEmptyDocumentArgument) {
            initialPresetID = .javascript
            initialText = ""
        } else if arguments.contains(Self.htmlDocumentArgument) {
            let preset = MiniPreviewPreset.html
            initialPresetID = preset.id
            initialText = preset.sampleText
        } else {
            let preset = MiniPreviewPreset.javascript
            initialPresetID = preset.id
            initialText = preset.sampleText
        }
    }

    var initialPreset: MiniPreviewPreset {
        return MiniPreviewPreset.preset(for: initialPresetID) ?? .javascript
    }
}

extension SyntaxEditorModel {
    @MainActor
    convenience init(configuration: MiniLaunchConfiguration) {
        self.init(
            text: configuration.initialText,
            language: configuration.initialPreset.language
        )
    }
}
