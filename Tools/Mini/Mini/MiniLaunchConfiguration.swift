import Foundation
import SyntaxEditorUI

struct MiniLaunchConfiguration {
    static let uiTestEmptyDocumentArgument = "--uitest-empty-document"
    static let htmlDocumentArgument = "--html-document"
    static let sampleText = """
    const answer = 42;
    function greet(name) {
        return `Hello, ${name}!`;
    }
    """
    static let htmlSampleText = """
    <!DOCTYPE html>
    <html>
    <head>
        <style>
        body { color: red; }
        </style>
    </head>
    <body>
        <!-- greeting -->
        <script>
        const answer = 42;
        </script>
        <div class="message">Hello</div>
    </body>
    </html>
    """
    static var current: MiniLaunchConfiguration {
        MiniLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }

    let initialText: String
    let language: any SyntaxLanguage

    init(arguments: [String]) {
        if arguments.contains(Self.uiTestEmptyDocumentArgument) {
            initialText = ""
            language = BuiltinSyntaxLanguages.javascript
        } else if arguments.contains(Self.htmlDocumentArgument) {
            initialText = Self.htmlSampleText
            language = BuiltinSyntaxLanguages.html
        } else {
            initialText = Self.sampleText
            language = BuiltinSyntaxLanguages.javascript
        }
    }
}

extension SyntaxEditorModel {
    @MainActor
    convenience init(configuration: MiniLaunchConfiguration) {
        self.init(
            text: configuration.initialText,
            language: configuration.language
        )
    }
}
