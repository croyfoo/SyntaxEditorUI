import Foundation

struct MiniLaunchConfiguration {
    static let uiTestEmptyDocumentArgument = "--uitest-empty-document"
    static let sampleText = """
    const answer = 42;
    function greet(name) {
        return `Hello, ${name}!`;
    }
    """
    static var current: MiniLaunchConfiguration {
        MiniLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }

    let initialText: String

    init(arguments: [String]) {
        if arguments.contains(Self.uiTestEmptyDocumentArgument) {
            initialText = ""
        } else {
            initialText = Self.sampleText
        }
    }
}
