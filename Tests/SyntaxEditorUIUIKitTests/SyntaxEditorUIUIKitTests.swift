#if canImport(UIKit)
import Testing
import SyntaxEditorUITestSupport
import UIKit
@testable import SyntaxEditorUIUIKit

@MainActor
struct SyntaxEditorUIUIKitTests {
    @Test("SyntaxEditorUIUIKit exposes the UIKit editor surface")
    func exposesUIKitEditorSurface() {
        let context = SyntaxEditorUITestContext(text: "let value = 1")
        let editorView = SyntaxEditorView(document: context.document, configuration: context.configuration)
        #expect(type(of: editorView).superclass() == UIScrollView.self)
        #expect(editorView.text == "let value = 1")
    }
}
#endif
