import Testing
@testable import SyntaxEditorUICommon

@MainActor
struct SyntaxEditorUICommonTests {
    @Test("SyntaxEditorUICommon exposes TextKit 2 render storage")
    func exposesTextKit2RenderStorage() {
        let store = SyntaxEditorTextKit2RenderStore()
        #expect(store.hasForegroundRuns == false)
    }
}
