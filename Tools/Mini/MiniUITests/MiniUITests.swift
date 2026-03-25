import XCTest

final class MiniUITests: XCTestCase {
    private enum LaunchArgument {
        static let emptyDocument = "--uitest-empty-document"
    }

    private var app: XCUIApplication!

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append(LaunchArgument.emptyDocument)
        app.launch()
    }

    @MainActor
    func testEditorAppearsOnLaunch() throws {
        let editor = editorElement()
        let value = editor.value as? String

        XCTAssertTrue(value == nil || value?.isEmpty == true, "Expected an empty editor but found \(String(describing: value))")
    }

    @MainActor
    func testAutoPairsOpeningBrace() throws {
        let editor = editorElement()

        editor.tap()
        editor.typeText("{")

        XCTAssertEqual(editorText(editor), "{}")
    }

    @MainActor
    func testSmartNewlineInsideBraceBlock() throws {
        let editor = editorElement()

        editor.tap()
        editor.typeText("{")
        editor.typeText("\n")

        XCTAssertEqual(editorText(editor), "{\n    \n}")
    }

    private func editorElement() -> XCUIElement {
        let editor = app.textViews["mini.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        return editor
    }

    private func editorText(_ editor: XCUIElement) -> String? {
        editor.value as? String
    }
}
