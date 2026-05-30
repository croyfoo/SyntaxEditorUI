#if canImport(AppKit)
import AppKit
import Testing
@testable import SyntaxEditorUIAppKit

@MainActor
struct SyntaxEditorUIAppKitTests {
    @Test("SyntaxEditorUIAppKit exposes the AppKit editor surface")
    func exposesAppKitEditorSurface() {
        let editorView = SyntaxEditorView()
        #expect(type(of: editorView).superclass() == NSScrollView.self)
    }
}
#endif
