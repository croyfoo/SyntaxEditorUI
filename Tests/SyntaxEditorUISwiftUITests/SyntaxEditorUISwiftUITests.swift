import SwiftUI
import Testing
import SyntaxEditorUITestSupport
@testable import SyntaxEditorUISwiftUI

@MainActor
struct SyntaxEditorUISwiftUITests {
    @Test("SyntaxEditorUISwiftUI exposes the SwiftUI wrapper")
    func exposesSwiftUIWrapper() {
        let context = SyntaxEditorUITestContext(text: "let value = 1")
        let editor = SyntaxEditor(document: context.document, configuration: context.configuration)
        #expect(String(describing: type(of: editor)) == "SyntaxEditor")
    }
}
