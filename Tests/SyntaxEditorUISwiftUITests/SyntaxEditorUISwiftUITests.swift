import SwiftUI
import Testing
@testable import SyntaxEditorUISwiftUI

@MainActor
struct SyntaxEditorUISwiftUITests {
    @Test("SyntaxEditorUISwiftUI exposes the SwiftUI wrapper")
    func exposesSwiftUIWrapper() {
        let editor = SyntaxEditor()
        #expect(String(describing: type(of: editor)) == "SyntaxEditor")
    }
}
