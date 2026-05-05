import Foundation
import SyntaxEditorUI

struct MiniLaunchConfiguration {
    static let uiTestEmptyDocumentArgument = "--uitest-empty-document"
    static let uiTestHorizontalScrollDocumentArgument = "--uitest-horizontal-scroll-document"
    static let htmlDocumentArgument = "--html-document"
    static var current: MiniLaunchConfiguration {
        MiniLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }

    let initialPresetID: MiniPreviewPreset.ID
    let initialText: String
    let appliesHorizontalScrollOffset: Bool

    init(arguments: [String]) {
        if arguments.contains(Self.uiTestEmptyDocumentArgument) {
            initialPresetID = .javascript
            initialText = ""
            appliesHorizontalScrollOffset = false
        } else if arguments.contains(Self.uiTestHorizontalScrollDocumentArgument) {
            initialPresetID = .html
            initialText = Self.horizontalScrollDocument
            appliesHorizontalScrollOffset = true
        } else if arguments.contains(Self.htmlDocumentArgument) {
            let preset = MiniPreviewPreset.html
            initialPresetID = preset.id
            initialText = preset.sampleText
            appliesHorizontalScrollOffset = false
        } else {
            let preset = MiniPreviewPreset.javascript
            initialPresetID = preset.id
            initialText = preset.sampleText
            appliesHorizontalScrollOffset = false
        }
    }

    var initialPreset: MiniPreviewPreset {
        return MiniPreviewPreset.preset(for: initialPresetID) ?? .javascript
    }

    private static let horizontalScrollDocument =
        "<!DOCTYPE html>\n<html><body><div class=\"message\">"
        + "horizontal_scroll_proof_start_"
        + String(repeating: "0123456789", count: 24)
        + "_rendered_after_scroll_"
        + String(repeating: "abcdefghij", count: 24)
        + "_horizontal_scroll_proof_end"
        + "</div></body></html>"
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
