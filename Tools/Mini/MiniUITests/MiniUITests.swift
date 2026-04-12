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
    func testEditorWorkflowAndPresetSwitching() throws {
        let editor = editorElement()
        let value = editor.value as? String

        XCTAssertTrue(value == nil || value?.isEmpty == true, "Expected an empty editor but found \(String(describing: value))")

        editor.tap()
        editor.typeText("{")

        XCTAssertEqual(editorText(editor), "{}")
        editor.typeText("\n")

        XCTAssertEqual(editorText(editor), "{\n    \n}")
        openLanguagesSidebar()

        let htmlRow = languageElement("html")
        XCTAssertTrue(htmlRow.waitForExistence(timeout: 5))
        htmlRow.tap()

        let htmlEditor = editorElement()
        XCTAssertTrue(waitForEditorText(htmlEditor, toContain: "<script>"))
    }

    private func editorElement() -> XCUIElement {
        let editor = app.textViews["mini.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        return editor
    }

    private func languageElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)["mini.language.\(identifier)"]
    }

    private func openLanguagesSidebar() {
        if languageElement("html").exists {
            return
        }

        let backButton = app.navigationBars.buttons["Languages"]
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
            return
        }

        let firstButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(firstButton.waitForExistence(timeout: 5))
        firstButton.tap()
    }

    private func editorText(_ editor: XCUIElement) -> String? {
        editor.value as? String
    }

    private func waitForEditorText(_ editor: XCUIElement, toContain expectedSubstring: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)

        while Date() < deadline {
            if editorText(editor)?.contains(expectedSubstring) == true {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return false
    }
}
