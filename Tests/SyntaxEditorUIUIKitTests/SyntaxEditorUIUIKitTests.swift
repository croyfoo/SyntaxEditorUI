#if canImport(UIKit)
import Testing
import UIKit
@testable import SyntaxEditorUIUIKit

@MainActor
struct SyntaxEditorUIUIKitTests {
    @Test("SyntaxEditorUIUIKit exposes the UIKit editor surface")
    func exposesUIKitEditorSurface() {
        let editorView = SyntaxEditorView()
        #expect(type(of: editorView).superclass() == UIScrollView.self)
    }
}
#endif
