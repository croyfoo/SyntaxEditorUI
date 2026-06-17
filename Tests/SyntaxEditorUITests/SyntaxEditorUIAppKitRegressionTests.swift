#if canImport(AppKit)
import Foundation
import Observation
import ObservationBridge
import SwiftUI
import Testing
import AppKit
@testable import SyntaxEditorUI
@testable import SyntaxEditorUIAppKit

extension SyntaxEditorUITests {
    @MainActor
    private func layoutMacEditorView(
        _ editorView: SyntaxEditorView,
        width: CGFloat = 220,
        height: CGFloat = 140
    ) {
        editorView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        editorView.needsLayout = true
        editorView.layoutSubtreeIfNeeded()
    }

    private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    @MainActor
    private func attachMacEditorWindow(_ editorView: SyntaxEditorView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = editorView
        window.makeKeyAndOrderFront(nil)
        editorView.frame = window.contentView?.bounds ?? .zero
        editorView.layoutSubtreeIfNeeded()
        editorView.textView.layoutVisibleViewport()
        return window
    }

    @MainActor
    private func macEditorWindowPoint(
        in window: NSWindow,
        textView: SyntaxEditorTextInputView,
        characterRange: NSRange,
        xOffset: CGFloat = 1
    ) -> NSPoint {
        let screenRect = textView.firstRect(forCharacterRange: characterRange, actualRange: nil)
        return window.convertPoint(
            fromScreen: NSPoint(
                x: screenRect.minX + xOffset,
                y: screenRect.midY
            )
        )
    }

    @Test("SyntaxEditorView reflects document text replacements on macOS")
    @MainActor
    func syntaxEditorViewMacTextObservation() async {
        let model = SyntaxEditorTestContext(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(testContext: model)
        guard let delivery = editorView.modelDeliveryForTesting else {
            Issue.record("Expected SyntaxEditorView to expose its production document delivery")
            return
        }
        let renderedText = await delivery.values {
            editorView.textView.string
        }

        #expect(await renderedText.waitUntilValue("const answer = 42;"))

        model.model.replaceText("{\"enabled\":true}")

        #expect(await renderedText.waitUntilValue("{\"enabled\":true}"))
    }

    @Test("SyntaxEditorView clamps macOS selection after whole-document replacement")
    @MainActor
    func syntaxEditorViewMacClampsSelectionAfterWholeDocumentReplacement() {
        let model = SyntaxEditorTestContext(text: "abcdef", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: SyntaxEditorUITestHighlighter())
        editorView.textView.setSelectedRange(NSRange(location: 6, length: 0))

        model.model.replaceText("a")
        editorView.synchronizeDocumentForTesting()

        #expect(editorView.textView.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView keeps macOS selection when setting unchanged text")
    @MainActor
    func syntaxEditorViewMacKeepsSelectionWhenSettingUnchangedText() {
        let source = "abcdef"
        let replacement = "abcdefghi"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: SyntaxEditorUITestHighlighter())

        model.model.replaceText(
            replacement,
            selectedRange: NSRange(location: replacement.utf16.count, length: 0)
        )
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.selectedRange() == NSRange(location: replacement.utf16.count, length: 0))

        editorView.selectedRange = NSRange(location: 2, length: 0)
        let revision = model.model.textRevision
        let latestTextChange = model.model.latestTextChange

        editorView.text = replacement

        #expect(model.model.textRevision == revision)
        #expect(model.model.latestTextChange == latestTextChange)
        #expect(model.model.selectedRange == NSRange(location: 2, length: 0))
        #expect(editorView.textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test("SyntaxEditorView enables macOS find bar by default")
    @MainActor
    func syntaxEditorViewMacEnablesFindBarByDefault() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "let value = 1"))

        #expect(editorView.isFindInteractionEnabled)
        #expect(editorView.textView.usesFindBar)
        #expect(editorView.textView.isIncrementalSearchingEnabled)
        #expect(!editorView.textView.usesFindPanel)

        let showFindItem = NSMenuItem()
        showFindItem.tag = NSTextFinder.Action.showFindInterface.rawValue
        editorView.textView.performTextFinderAction(showFindItem)
        #expect(editorView.isFindBarVisible)

        editorView.isFindInteractionEnabled = false
        #expect(!editorView.textView.usesFindBar)
        #expect(!editorView.textView.isIncrementalSearchingEnabled)
        #expect(!editorView.textView.usesFindPanel)
        #expect(!editorView.isFindBarVisible)

        editorView.isFindInteractionEnabled = true
        #expect(editorView.textView.usesFindBar)
        #expect(editorView.textView.isIncrementalSearchingEnabled)
        #expect(!editorView.textView.usesFindPanel)
    }

    @Test("SyntaxEditorView exposes AppKit text layout geometry to NSTextFinder")
    @MainActor
    func syntaxEditorViewExposesTextLayoutGeometryToTextFinder() {
        let source = "first line\nsecond line\nthird line"
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: source))
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        let contentView = editorView.textView.contentView(at: 0, effectiveCharacterRange: &effectiveRange)

        #expect(contentView === editorView.textView.textContentView)
        #expect(effectiveRange == NSRange(location: 0, length: (source as NSString).length))

        let secondLineRange = (source as NSString).range(of: "second")
        let rects = editorView.textView.rects(forCharacterRange: secondLineRange) ?? []

        #expect(!rects.isEmpty)
        #expect(rects.allSatisfy { !$0.rectValue.isEmpty })
    }

    @Test("SyntaxEditorView uses macOS NSTextFinder for match navigation")
    @MainActor
    func syntaxEditorViewMacUsesTextFinderForMatchNavigation() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "alpha beta alpha"))
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        editorView.selectedRange = NSRange(location: 0, length: 5)
        let setSearchStringItem = NSMenuItem()
        setSearchStringItem.tag = NSTextFinder.Action.setSearchString.rawValue
        editorView.textView.performTextFinderAction(setSearchStringItem)

        let nextMatchItem = NSMenuItem()
        nextMatchItem.tag = NSTextFinder.Action.nextMatch.rawValue
        editorView.textView.performTextFinderAction(nextMatchItem)

        #expect(editorView.selectedRange == NSRange(location: 11, length: 5))
    }

    @Test("SyntaxEditorView applies macOS NSTextFinder replacements through the editor pipeline")
    @MainActor
    func syntaxEditorViewMacAppliesTextFinderReplacementThroughEditorPipeline() {
        let model = SyntaxEditorTestContext(text: "alpha beta")
        let editorView = SyntaxEditorView(testContext: model)

        editorView.textView.replaceCharacters(in: NSRange(location: 0, length: 5), with: "omega")

        #expect(model.model.text == "omega beta")
        #expect(editorView.selectedRange == NSRange(location: 5, length: 0))
    }

    @Test("SyntaxEditorView keeps macOS find bar available while read-only")
    @MainActor
    func syntaxEditorViewMacKeepsFindBarAvailableWhileReadOnly() {
        let model = SyntaxEditorTestContext(text: "let value = 1", isEditable: false)
        let editorView = SyntaxEditorView(testContext: model)

        #expect(editorView.isFindInteractionEnabled)
        #expect(editorView.textView.usesFindBar)
        #expect(editorView.textView.isIncrementalSearchingEnabled)
        #expect(editorView.textView.isEditable == false)

        model.model.isEditable = true
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.usesFindBar)
        #expect(editorView.textView.isIncrementalSearchingEnabled)
        #expect(editorView.textView.isEditable)

        model.model.isEditable = false
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.usesFindBar)
        #expect(editorView.textView.isIncrementalSearchingEnabled)
        #expect(editorView.textView.isEditable == false)
    }

    @Test("SyntaxEditorView reflects custom macOS theme")
    @MainActor
    func syntaxEditorViewMacThemeObservation() async {
        let source = "let value = \"text\""
        let initialTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456)
        )
        let updatedTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter()
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: initialTheme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.model.theme = updatedTheme

        editorView.synchronizeDocumentForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
    }

    @Test("SyntaxEditorView refreshes macOS permanent base foreground after appearance changes")
    @MainActor
    func syntaxEditorViewMacRefreshesPermanentBaseForegroundAfterAppearanceChanges() throws {
        let model = SyntaxEditorTestContext(
            text: "plain text",
            language: SyntaxLanguage.swift,
            theme: .default
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: SyntaxEditorUITestHighlighter())

        editorView.appearance = NSAppearance(named: .aqua)
        editorView.viewDidChangeEffectiveAppearance()
        let lightForeground = try #require(macEditorPermanentForegroundColor(editorView, at: 0))

        editorView.appearance = NSAppearance(named: .darkAqua)
        editorView.viewDidChangeEffectiveAppearance()
        let darkBaseForeground = try #require(editorView.baseForegroundColorForTesting())

        #expect(syntaxEditorUITestColorsEqual(macEditorPermanentForegroundColor(editorView, at: 0), darkBaseForeground))
        #expect(!syntaxEditorUITestColorsEqual(lightForeground, darkBaseForeground))
    }

    @Test("SyntaxEditorView reflects macOS background drawing configuration")
    @MainActor
    func syntaxEditorViewMacDrawsBackgroundObservation() async {
        let background = syntaxEditorUITestColor(hex: 0x112233)
        let theme = syntaxEditorUITestTheme(background: background)
        let model = SyntaxEditorTestContext(
            text: "let value = 1",
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: SyntaxEditorUITestHighlighter())
        guard let delivery = editorView.modelConfigurationDeliveryForTesting else {
            Issue.record("Expected SyntaxEditorView to expose its production configuration delivery")
            return
        }
        let stopsDrawingBackground = await delivery.values {
            editorView.drawsBackground == false
                && editorView.textView.drawsBackground == false
                && syntaxEditorUITestColorsEqual(editorView.backgroundColor, background)
                && syntaxEditorUITestColorsEqual(editorView.textView.backgroundColor, background)
        }

        #expect(editorView.drawsBackground)
        #expect(!editorView.textView.drawsBackground)
        #expect(syntaxEditorUITestColorsEqual(editorView.backgroundColor, background))
        #expect(syntaxEditorUITestColorsEqual(editorView.textView.backgroundColor, background))

        model.model.drawsBackground = false

        #expect(await stopsDrawingBackground.waitUntilValue(true))
    }

    @Test("SyntaxEditorView resets nested empty-style macOS tokens to the base theme")
    @MainActor
    func syntaxEditorViewMacResetsNestedEmptyStyleTokensToBaseTheme() async {
        let source = "\"${value}\""
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.javascript.string"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 3, length: 5),
                    rawCaptureName: "editor.syntax.javascript.plain"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), theme.baseForeground))
    }

    @Test("SyntaxEditorView resets multi-level empty-style macOS tokens to the base theme")
    @MainActor
    func syntaxEditorViewMacResetsMultiLevelEmptyStyleTokensToBaseTheme() async {
        let source = "0123456789"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0x654321),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 10),
                    rawCaptureName: "editor.syntax.javascript.keyword"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 2, length: 6),
                    rawCaptureName: "editor.syntax.javascript.string"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 4, length: 2),
                    rawCaptureName: "editor.syntax.javascript.plain"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 2), theme.string))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 4), theme.baseForeground))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 6), theme.string))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 8), theme.keyword))
    }

    @Test("SyntaxEditorView reapplies macOS same-style tokens after empty-style splits")
    @MainActor
    func syntaxEditorViewMacReappliesSameStyleTokensAfterEmptyStyleSplits() async {
        let source = "\"${value}\""
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.javascript.string"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 3, length: 4),
                    rawCaptureName: "editor.syntax.javascript.plain"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 6, length: 4),
                    rawCaptureName: "editor.syntax.javascript.string"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), theme.baseForeground))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 6), theme.string))
    }

    @Test("SyntaxEditorView keeps macOS empty-style gaps between separated same-style runs")
    @MainActor
    func syntaxEditorViewMacKeepsEmptyStyleGapsBetweenSeparatedSameStyleRuns() async {
        let source = "\"${value}\""
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.javascript.string"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 4, length: 2),
                    rawCaptureName: "editor.syntax.javascript.plain"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 4, length: 1),
                    rawCaptureName: "editor.syntax.javascript.string"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 4), theme.string))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 5), theme.baseForeground))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 6), theme.string))
    }

    @Test("SyntaxEditorView reapplies cached macOS syntax colors without highlighting")
    @MainActor
    func syntaxEditorViewMacThemeReusesCachedHighlightTokens() async {
        let source = "let value = \"text\""
        let initialTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let updatedTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x654321),
            keyword: syntaxEditorUITestColor(hex: 0x876543)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: initialTheme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), initialTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.model.theme = updatedTheme

        editorView.synchronizeDocumentForTesting()
        #expect(
            syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.keyword)
                && syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground)
        )
        await editorView.waitForPendingHighlightForTesting()
        #expect(await highlighter.callCount() == initialCallCount)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
    }

    @Test("SyntaxEditorView refreshes macOS syntax colors when theme changes after incremental edits")
    @MainActor
    func syntaxEditorViewMacThemeRefreshesAfterIncrementalEditDropsCachedTokens() async {
        let source = "let value = \"text\""
        let initialTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let updatedTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x876543)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: initialTheme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), initialTheme.keyword))

        editorView.textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        editorView.textView.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        await editorView.waitForPendingHighlightForTesting()
        let editedCallCount = await highlighter.callCount()
        #expect(editedCallCount == initialCallCount + 1)

        model.model.theme = updatedTheme
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(await highlighter.callCount() == editedCallCount + 1)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
    }

    @Test("SyntaxEditorView preserves macOS syntax colors after editor state changes")
    @MainActor
    func syntaxEditorViewMacEditorStateDoesNotResetSyntaxColors() async {
        let source = "let value = \"text\""
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model)

        editorView.textView.textStorage?.addAttribute(
            .foregroundColor,
            value: theme.keyword,
            range: NSRange(location: 0, length: 3)
        )
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.model.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.hasHorizontalScroller == false)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.model.isEditable = false

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.isEditable == false)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView preserves cached macOS syntax colors after font size delta changes")
    @MainActor
    func syntaxEditorViewMacFontSizeDeltaPreservesCachedHighlightTokens() async throws {
        let source = "let value = \"text\""
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        let initialFont = try #require(macEditorFont(editorView, at: 0))

        model.model.fontSizeDelta = 4
        editorView.synchronizeDocumentForTesting()

        #expect(await highlighter.callCount() == initialCallCount)
        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        let plainFont = try #require(macEditorFont(editorView, at: 3))
        #expect(abs(highlightedFont.pointSize - (initialFont.pointSize + 4)) < 0.01)
        #expect(abs(plainFont.pointSize - highlightedFont.pointSize) < 0.01)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), theme.baseForeground))
    }

    @Test("SyntaxEditorView applies built-in macOS theme fonts after theme changes")
    @MainActor
    func syntaxEditorViewMacAppliesBuiltInThemeFontsAfterThemeChanges() async throws {
        let source = "let value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: .default
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()

        model.model.theme = .presentationLarge
        editorView.synchronizeDocumentForTesting()

        #expect(await highlighter.callCount() == initialCallCount)
        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        let plainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(highlightedFont.pointSize - 28) < 0.01)
        #expect(abs(plainFont.pointSize - 28) < 0.01)
    }

    @Test("SyntaxEditorView keeps macOS syntax fonts out of TextKit storage")
    @MainActor
    func syntaxEditorViewMacSyntaxFontsUseRenderingAttributes() async throws {
        let source = "/// doc"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.comment.doc"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: .civic
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        editorView.appearance = NSAppearance(named: .aqua)
        editorView.viewDidChangeEffectiveAppearance()

        await editorView.waitForPendingHighlightForTesting()

        let renderedFont = try #require(macEditorFont(editorView, at: 0))
        let highlightedStorageFont = try #require(
            editorView.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        let plainStorageFont = try #require(
            editorView.textView.textStorage?.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
        )
        #expect(!syntaxEditorUITestFontsEqual(renderedFont, highlightedStorageFont))
        #expect(syntaxEditorUITestFontsEqual(highlightedStorageFont, plainStorageFont))
    }

    @Test("SyntaxEditorView applies macOS theme fonts while selection delays highlight")
    @MainActor
    func syntaxEditorViewMacThemeFontUpdatesSelectedTextBeforeDelayedHighlight() async throws {
        let source = "let value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: .default
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 3))
        model.model.theme = .presentationLarge
        editorView.synchronizeDocumentForTesting()

        #expect(editorView.textView.selectedRange() == NSRange(location: 0, length: 3))
        #expect(await highlighter.callCount() == initialCallCount)
        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        let plainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(highlightedFont.pointSize - 28) < 0.01)
        #expect(abs(plainFont.pointSize - 28) < 0.01)

        editorView.textView.setSelectedRange(NSRange(location: 3, length: 0))
        editorView.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editorView.textView)
        )

        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorForegroundColor(editorView, at: 0),
                SyntaxEditorTheme.presentationLarge.keyword
            )
        )
    }

    @Test("SyntaxEditorView applies macOS token fonts while selection delays theme highlight")
    @MainActor
    func syntaxEditorViewMacThemeTokenFontUpdatesSelectedTextBeforeDelayedHighlight() async throws {
        let source = "let value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.comment.doc"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: "",
            language: SyntaxLanguage.swift,
            theme: .default
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        editorView.appearance = NSAppearance(named: .aqua)
        editorView.viewDidChangeEffectiveAppearance()
        model.model.replaceText(source)
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        let initialHighlightedFont = try #require(macEditorFont(editorView, at: 0))
        let initialPlainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(!syntaxEditorUITestFontsEqual(initialHighlightedFont, initialPlainFont))

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 3))
        model.model.theme = .civic
        editorView.synchronizeDocumentForTesting()

        #expect(editorView.textView.selectedRange() == NSRange(location: 0, length: 3))
        #expect(await highlighter.callCount() == initialCallCount)
        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        let plainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(syntaxEditorUITestFontsEqual(plainFont, initialPlainFont))
        #expect(!syntaxEditorUITestFontsEqual(highlightedFont, initialHighlightedFont))
        #expect(!syntaxEditorUITestFontsEqual(highlightedFont, plainFont))
    }

    @Test("SyntaxEditorView applies macOS font size delta while selection delays highlight")
    @MainActor
    func syntaxEditorViewMacFontSizeDeltaUpdatesSelectedTextBeforeDelayedHighlight() async throws {
        let source = "let value = \"text\""
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        let initialHighlightedFont = try #require(macEditorFont(editorView, at: 0))
        let initialPlainFont = try #require(macEditorFont(editorView, at: 3))

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 3))
        model.model.fontSizeDelta = 4
        editorView.synchronizeDocumentForTesting()

        #expect(editorView.textView.selectedRange() == NSRange(location: 0, length: 3))
        #expect(await highlighter.callCount() == initialCallCount)
        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        let plainFont = try #require(macEditorFont(editorView, at: 3))
        #expect(abs(highlightedFont.pointSize - (initialHighlightedFont.pointSize + 4)) < 0.01)
        #expect(abs(plainFont.pointSize - (initialPlainFont.pointSize + 4)) < 0.01)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), theme.baseForeground))
    }

    @Test("SyntaxEditorView applies macOS base attributes before delayed highlight")
    @MainActor
    func syntaxEditorViewMacAppliesBaseAttributesBeforeDelayedHighlight() async throws {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            resetGate: resetGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        let baseFont = try #require(editorView.textView.font)

        await resetGate.waitUntilSuspended()
        #expect(syntaxEditorUITestFontsEqual(macEditorFont(editorView, at: 0), baseFont))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))

        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView applies macOS fast pass highlight before final phase")
    @MainActor
    func syntaxEditorViewMacAppliesFastPassHighlightBeforeFinalPhase() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0xABCDEF),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let completeGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorPhasedTestHighlighter(
            fastTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            completeTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.string"
                ),
            ],
            completeGate: completeGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await completeGate.waitUntilSuspended()
        #expect(await syntaxEditorWaitForColor(
            { macEditorForegroundColor(editorView, at: 0) },
            equals: theme.keyword
        ))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 4), theme.baseForeground))
        #expect(await highlighter.callCount() == 1)

        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))

        let updatedTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x112233),
            string: syntaxEditorUITestColor(hex: 0x556677),
            keyword: syntaxEditorUITestColor(hex: 0x334455)
        )
        model.model.theme = updatedTheme
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(await highlighter.callCount() == 1)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.string))
    }

    @Test("SyntaxEditorView applies macOS incremental fast pass before any complete highlight")
    @MainActor
    func syntaxEditorViewMacAppliesIncrementalFastPassBeforeAnyCompleteHighlight() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0xABCDEF),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let updateRefreshRange = NSRange(location: 0, length: source.utf16.count + 1)
        let completeGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorPhasedTestHighlighter(
            fastTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateFastTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.string"
                ),
            ],
            completeTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            completeGate: completeGate,
            updateRefreshRange: updateRefreshRange
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await completeGate.waitUntilSuspended()
        #expect(await syntaxEditorWaitForColor(
            { macEditorForegroundColor(editorView, at: 0) },
            equals: theme.keyword
        ))

        let insertionRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(insertionRange)
        editorView.textView.insertText("x", replacementRange: insertionRange)

        #expect(await syntaxEditorWaitForColor(
            { macEditorForegroundColor(editorView, at: 0) },
            equals: theme.string
        ))
        #expect(editorView.textView.string == "\(source)x")

        await completeGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView keeps macOS complete incremental materialization inside refresh range")
    @MainActor
    func syntaxEditorViewMacKeepsCompleteIncrementalMaterializationInsideRefreshRange() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0xABCDEF),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let insertedRange = NSRange(location: source.utf16.count, length: 1)
        let completeGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorPhasedTestHighlighter(
            fastTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateFastTokens: [],
            completeTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateCompleteTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.string"
                ),
                SyntaxEditorHighlighting.Token(
                    range: insertedRange,
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            completeGate: completeGate,
            updateRefreshRange: insertedRange
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await completeGate.waitUntilSuspended()
        #expect(await syntaxEditorWaitForColor(
            { macEditorForegroundColor(editorView, at: 0) },
            equals: theme.keyword
        ))
        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        let insertionRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(insertionRange)
        let updateSuspensionCount = await completeGate.currentSuspensionCount()
        editorView.textView.insertText("x", replacementRange: insertionRange)
        await completeGate.waitUntilSuspended(after: updateSuspensionCount)

        await completeGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == "\(source)x")
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorForegroundColor(editorView, at: source.utf16.count),
                theme.keyword
            )
        )
    }

    @Test("SyntaxEditorView applies macOS incremental fast pass after empty complete highlight")
    @MainActor
    func syntaxEditorViewMacAppliesIncrementalFastPassAfterEmptyCompleteHighlight() async {
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let completeGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorPhasedTestHighlighter(
            fastTokens: [],
            updateFastTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 1),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            completeTokens: [],
            completeGate: completeGate
        )
        let model = SyntaxEditorTestContext(
            text: "",
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await completeGate.waitUntilSuspended()
        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editorView.textView.insertText("l", replacementRange: NSRange(location: 0, length: 0))

        #expect(await syntaxEditorWaitForColor(
            { macEditorForegroundColor(editorView, at: 0) },
            equals: theme.keyword
        ))
        #expect(editorView.textView.string == "l")

        await completeGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
    }

    @Test("SyntaxEditorView preserves macOS semantic highlight during incremental fast pass")
    @MainActor
    func syntaxEditorViewMacPreservesSemanticHighlightDuringIncrementalFastPass() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0xABCDEF),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let completeGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorPhasedTestHighlighter(
            fastTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            completeTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.string"
                ),
            ],
            completeGate: completeGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await completeGate.waitUntilSuspended()
        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))

        let insertionRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(insertionRange)
        editorView.textView.insertText("x", replacementRange: insertionRange)

        let skippedFastPass = await editorView.waitForSkippedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass)
        #expect(skippedFastPass)
        #expect(editorView.textView.string == "\(source)x")
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))

        await completeGate.resumeAll()
        if skippedFastPass {
            await editorView.waitForPendingHighlightForTesting()
            #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))
        }
    }

    @Test("SyntaxEditorView preserves macOS semantic highlight across rapid incremental fast passes")
    @MainActor
    func syntaxEditorViewMacPreservesSemanticHighlightAcrossRapidIncrementalFastPasses() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0xABCDEF),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let completeGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorPhasedTestHighlighter(
            fastTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            completeTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.string"
                ),
            ],
            completeGate: completeGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await completeGate.waitUntilSuspended()
        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))

        let firstSuspensionCount = await completeGate.currentSuspensionCount()
        let firstInsertionRange = NSRange(location: 0, length: 0)
        editorView.textView.setSelectedRange(firstInsertionRange)
        editorView.textView.insertText("x", replacementRange: firstInsertionRange)

        await completeGate.waitUntilSuspended(after: firstSuspensionCount)
        #expect(await editorView.waitForSkippedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(editorView.textView.string == "x\(source)")
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 1), theme.string))

        let secondSuspensionCount = await completeGate.currentSuspensionCount()
        let secondInsertionRange = NSRange(location: editorView.textView.string.utf16.count, length: 0)
        editorView.textView.setSelectedRange(secondInsertionRange)
        editorView.textView.insertText("y", replacementRange: secondInsertionRange)

        await completeGate.waitUntilSuspended(after: secondSuspensionCount)
        #expect(await editorView.waitForSkippedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(editorView.textView.string == "x\(source)y")
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 1), theme.string))

        await completeGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))
    }

    @Test("SyntaxEditorView resets macOS highlight state without repainting old text before document replacement")
    @MainActor
    func syntaxEditorViewMacResetsHighlightStateWithoutRepaintingOldTextBeforeDocumentReplacement() async {
        let source = "let value = 1"
        let replacement = "var pasted = 2\nprint(pasted)"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            resetGate: resetGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await resetGate.waitUntilSuspended()
        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(editorView.syntaxColorRunCountForTesting == 1)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        let suspensionCount = await resetGate.currentSuspensionCount()
        model.model.replaceText(replacement)
        editorView.synchronizeDocumentForTesting()

        await resetGate.waitUntilSuspended(after: suspensionCount)
        #expect(editorView.textView.string == replacement)
        #expect(editorView.syntaxColorRunCountForTesting == 0)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))

        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
    }

    @Test("SyntaxEditorView clears macOS syntax runs when switching to plain text")
    @MainActor
    func syntaxEditorViewMacClearsSyntaxRunsWhenSwitchingToPlainText() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(editorView.syntaxColorRunCountForTesting == 1)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.model.language = .plainText
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.syntaxColorRunCountForTesting == 0)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))
    }

    @Test("SyntaxEditorView applies built-in macOS theme base font to plain and highlighted text")
    @MainActor
    func syntaxEditorViewMacAppliesBuiltInThemeBaseFont() async throws {
        let source = "let value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: .presentationLarge
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()

        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        let plainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(highlightedFont.pointSize - plainFont.pointSize) < 0.01)
        #expect(abs(plainFont.pointSize - 28) < 0.01)
    }

    @Test("SyntaxEditorView applies macOS font size delta to built-in theme fonts")
    @MainActor
    func syntaxEditorViewMacAppliesFontSizeDeltaToBuiltInThemeFonts() async throws {
        let source = "let value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: .presentationLarge,
            fontSizeDelta: 3
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()

        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        let plainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(highlightedFont.pointSize - plainFont.pointSize) < 0.01)
        #expect(abs(plainFont.pointSize - 31) < 0.01)
    }

    @Test("SyntaxEditorView clamps macOS font size delta")
    @MainActor
    func syntaxEditorViewMacClampsFontSizeDelta() async throws {
        let source = "let value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: .presentationLarge,
            fontSizeDelta: 100
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let maximumHighlightedFont = try #require(macEditorFont(editorView, at: 0))
        let maximumPlainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(maximumHighlightedFont.pointSize - 64) < 0.01)
        #expect(abs(maximumPlainFont.pointSize - 64) < 0.01)

        model.model.fontSizeDelta = -100
        editorView.synchronizeDocumentForTesting()

        let minimumHighlightedFont = try #require(macEditorFont(editorView, at: 0))
        let minimumPlainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(minimumHighlightedFont.pointSize - 4) < 0.01)
        #expect(abs(minimumPlainFont.pointSize - 4) < 0.01)
    }

    @Test("SyntaxEditorView recomputes selected macOS font size after delta overshoot")
    @MainActor
    func syntaxEditorViewMacRecomputesSelectedFontSizeAfterDeltaOvershoot() async throws {
        let source = "let value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: .presentationLarge,
            fontSizeDelta: 100
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let maximumPlainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(maximumPlainFont.pointSize - 64) < 0.01)

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 3))
        model.model.decreaseFontSize()
        editorView.synchronizeDocumentForTesting()

        #expect(model.model.fontSizeDelta == 35)
        let decreasedHighlightedFont = try #require(macEditorFont(editorView, at: 0))
        let decreasedPlainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(decreasedHighlightedFont.pointSize - 63) < 0.01)
        #expect(abs(decreasedPlainFont.pointSize - 63) < 0.01)

        model.model.resetFontSize()
        editorView.synchronizeDocumentForTesting()

        #expect(model.model.fontSizeDelta == 0)
        let resetHighlightedFont = try #require(macEditorFont(editorView, at: 0))
        let resetPlainFont = try #require(macEditorFont(editorView, at: 4))
        #expect(abs(resetHighlightedFont.pointSize - 28) < 0.01)
        #expect(abs(resetPlainFont.pointSize - 28) < 0.01)
    }

    @Test("SyntaxEditorView applies macOS base attributes to inserted text before delayed update highlight")
    @MainActor
    func syntaxEditorViewMacAppliesBaseAttributesToInsertedTextBeforeDelayedUpdateHighlight() async throws {
        let source = "let value = 1"
        let insertedPrefix = "// "
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let updateGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateTokens: [],
            updateGate: updateGate,
            updateRefreshRange: NSRange(location: 0, length: source.utf16.count + insertedPrefix.utf16.count)
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        let baseFont = try #require(editorView.textView.font)
        await editorView.waitForPendingHighlightForTesting()

        let previousSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.textView.insertText(insertedPrefix, replacementRange: NSRange(location: 0, length: 0))

        await updateGate.waitUntilSuspended(after: previousSuspensionCount)
        #expect(editorView.textView.string == insertedPrefix + source)
        #expect(syntaxEditorUITestFontsEqual(macEditorFont(editorView, at: 0), baseFont))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))

        await updateGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
    }

    @Test("SyntaxEditorView restores macOS base font when syntax font tokens are removed")
    @MainActor
    func syntaxEditorViewMacRestoresBaseFontWhenSyntaxFontTokensAreRemoved() async throws {
        let source = "let value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.comment.doc"
                ),
            ],
            updateTokens: [],
            updateRefreshRange: NSRange(location: 0, length: 3)
        )
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        let baseFont = try #require(editorView.textView.font)

        await editorView.waitForPendingHighlightForTesting()
        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        #expect(!syntaxEditorUITestFontsEqual(highlightedFont, baseFont))

        editorView.textView.insertText("var", replacementRange: NSRange(location: 0, length: 3))
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == "var value = 1")
        #expect(syntaxEditorUITestFontsEqual(macEditorFont(editorView, at: 0), baseFont))
    }

    @Test("SyntaxEditorView restores shifted macOS syntax font after prefix edits")
    @MainActor
    func syntaxEditorViewMacRestoresShiftedSyntaxFontAfterPrefixEdits() async throws {
        let source = "let value = 1"
        let insertedPrefix = "// "
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.comment.doc"
                ),
            ],
            updateTokens: [],
            updateRefreshRange: NSRange(location: 0, length: source.utf16.count + insertedPrefix.utf16.count)
        )
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        let baseFont = try #require(editorView.textView.font)

        await editorView.waitForPendingHighlightForTesting()
        let highlightedFont = try #require(macEditorFont(editorView, at: 0))
        #expect(!syntaxEditorUITestFontsEqual(highlightedFont, baseFont))

        editorView.textView.insertText(insertedPrefix, replacementRange: NSRange(location: 0, length: 0))
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == insertedPrefix + source)
        #expect(syntaxEditorUITestFontsEqual(macEditorFont(editorView, at: insertedPrefix.utf16.count), baseFont))
    }

    @Test("SyntaxEditorView applies dense macOS highlight tokens across the document")
    @MainActor
    func syntaxEditorViewMacAppliesDenseHighlightTokensAcrossDocument() async {
        let fixture = syntaxEditorDenseHighlightFixture()
        let theme = syntaxEditorUITestTheme(
            comment: syntaxEditorUITestColor(hex: 0x305070),
            string: syntaxEditorUITestColor(hex: 0x507030),
            keyword: syntaxEditorUITestColor(hex: 0x703050)
        )
        let highlighter = SyntaxEditorUITestHighlighter(tokens: fixture.tokens)
        let model = SyntaxEditorTestContext(
            text: fixture.source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()

        let middleLocation = fixture.source.utf16.count / 2
        let lastLocation = fixture.source.utf16.count - 1
        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorForegroundColor(editorView, at: 0),
                syntaxEditorDenseHighlightColor(in: theme, at: 0)
            )
        )
        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorForegroundColor(editorView, at: middleLocation),
                syntaxEditorDenseHighlightColor(in: theme, at: middleLocation)
            )
        )
        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorForegroundColor(editorView, at: lastLocation),
                syntaxEditorDenseHighlightColor(in: theme, at: lastLocation)
            )
        )
        #expect(macEditorFont(editorView, at: middleLocation) != nil)
    }

    @Test("SyntaxEditorView applies macOS syntax colors outside draw")
    @MainActor
    func syntaxEditorViewMacAppliesSyntaxColorsOutsideDraw() async {
        let fixture = syntaxEditorDenseHighlightFixture(tokenCount: 1_500)
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x102030),
            comment: syntaxEditorUITestColor(hex: 0x305070),
            string: syntaxEditorUITestColor(hex: 0x507030),
            keyword: syntaxEditorUITestColor(hex: 0x703050)
        )
        let highlighter = SyntaxEditorUITestHighlighter(tokens: fixture.tokens)
        let model = SyntaxEditorTestContext(
            text: fixture.source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        let deferredLocation = 1_000

        await editorView.waitForPendingHighlightForTesting()

        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorForegroundColor(editorView, at: deferredLocation),
                syntaxEditorDenseHighlightColor(in: theme, at: deferredLocation)
            )
        )
        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorPermanentForegroundColor(editorView, at: deferredLocation),
                theme.baseForeground
            )
        )
    }

    @Test("SyntaxEditorView draws macOS syntax foregrounds through TextKit fragments")
    @MainActor
    func syntaxEditorViewMacDrawsSyntaxForegroundsThroughTextKitFragments() async throws {
        let source = "let let let let let let let"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x0000FF),
            keyword: syntaxEditorUITestColor(hex: 0xFF0000),
            background: syntaxEditorUITestColor(hex: 0x000000)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme,
            fontSizeDelta: 8
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        layoutMacEditorView(editorView, width: 320, height: 140)

        await editorView.waitForPendingHighlightForTesting()
        let fragmentView = try #require(macEditorVisibleFragmentViews(editorView).first)
        let styleEpoch = editorView.syntaxForegroundMaterializationCountForTesting

        let renderedKeywordColor = macEditorRenderedFragmentContainsDominantColor(
            fragmentView,
            targetColor: theme.keyword,
            backgroundColor: theme.background
        )

        #expect(editorView.syntaxForegroundMaterializationCountForTesting == styleEpoch)
        #expect(renderedKeywordColor)
        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorPermanentForegroundColor(editorView, at: 0),
                theme.baseForeground
            )
        )
    }

    @Test("SyntaxEditorView clips macOS TextKit fragment drawing to dirty lines")
    @MainActor
    func syntaxEditorViewMacClipsTextKitFragmentDrawingToDirtyLines() async throws {
        let source = Array(repeating: "let wrappedValue = wrappedValue", count: 12).joined(separator: " ")
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x0000FF),
            keyword: syntaxEditorUITestColor(hex: 0xFF0000),
            background: syntaxEditorUITestColor(hex: 0x000000)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true,
            theme: theme,
            fontSizeDelta: 4
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        layoutMacEditorView(editorView, width: 180, height: 160)

        await editorView.waitForPendingHighlightForTesting()
        let fragmentView = try #require(macEditorVisibleFragmentViews(editorView).first)
        let layoutFragment = try #require(fragmentView.layoutFragment as? SyntaxEditorTextLayoutFragment)
        #expect(layoutFragment.textLineFragments.count > 3)

        let initialDrawCount = layoutFragment.lineFragmentDrawCountForTesting
        macEditorDrawFragment(
            fragmentView,
            dirtyRect: NSRect(x: 0, y: 0, width: fragmentView.bounds.width, height: 4),
            backgroundColor: theme.background
        )
        let drawnLineCount = layoutFragment.lineFragmentDrawCountForTesting - initialDrawCount

        #expect(drawnLineCount > 0)
        #expect(drawnLineCount < layoutFragment.textLineFragments.count)
    }

    @Test("SyntaxEditorView keeps macOS rendering attribute validation local during jump scrolls")
    @MainActor
    func syntaxEditorViewMacKeepsRenderingAttributeValidationLocalDuringJumpScrolls() async throws {
        let repeatedToken = "let wrappedValue = wrappedValue "
        let repeatCount = 1_600
        let source = String(repeating: repeatedToken, count: repeatCount)
        let tokenStride = repeatedToken.utf16.count
        let tokens = (0..<repeatCount).map { index in
            SyntaxEditorHighlighting.Token(
                range: NSRange(location: index * tokenStride, length: 3),
                rawCaptureName: "editor.syntax.swift.keyword"
            )
        }
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x0000FF),
            keyword: syntaxEditorUITestColor(hex: 0xFF0000),
            background: syntaxEditorUITestColor(hex: 0x000000)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(tokens: tokens, resetGate: resetGate)
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        layoutMacEditorView(editorView, width: 180, height: 140)

        await resetGate.waitUntilSuspended()
        let initialFragmentView = try #require(macEditorVisibleFragmentViews(editorView).first)
        let initialFragmentRange = editorView.textView.textRange(for: initialFragmentView.layoutFragment)
        #expect(initialFragmentRange.length > source.utf16.count / 2)

        editorView.textView.resetSyntaxRenderingAttributeCountersForTesting()
        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()

        let initialValidatedLength = editorView.textView.syntaxRenderingAttributeUTF16LengthForTesting
        let initialValidatedColorRuns = editorView.textView.syntaxRenderingAttributeColorRunCountForTesting
        #expect(initialValidatedLength > 0)
        #expect(initialValidatedLength < source.utf16.count / 4)
        #expect(initialValidatedColorRuns > 0)
        #expect(initialValidatedColorRuns < tokens.count / 4)

        editorView.contentView.scroll(to: NSPoint(x: 0, y: 8_000))
        editorView.reflectScrolledClipView(editorView.contentView)
        editorView.textView.layoutVisibleViewport()

        let scrolledFragmentView = try #require(
            macEditorVisibleFragmentViews(editorView)
                .first { $0.frame.intersects(editorView.textView.visibleRect) }
        )
        let scrolledFragmentRange = editorView.textView.textRange(for: scrolledFragmentView.layoutFragment)
        let scrolledTargetRanges = editorView.textView.syntaxRenderingAttributeTargetRangesForTesting(
            in: scrolledFragmentView.layoutFragment
        )
        let scrolledTargetLength = scrolledTargetRanges.reduce(0) { $0 + $1.length }
        #expect(!scrolledTargetRanges.isEmpty)
        #expect(scrolledFragmentRange.length > source.utf16.count / 2)
        #expect(scrolledTargetLength < scrolledFragmentRange.length / 4)

        let scrolledDirtyRect = editorView.textView.visibleRect
            .offsetBy(dx: -scrolledFragmentView.frame.minX, dy: -scrolledFragmentView.frame.minY)
            .intersection(scrolledFragmentView.bounds)
        editorView.textView.resetSyntaxRenderingAttributeCountersForTesting()
        macEditorDrawFragment(
            scrolledFragmentView,
            dirtyRect: scrolledDirtyRect,
            backgroundColor: theme.background
        )
        #expect(editorView.textView.syntaxRenderingAttributeUTF16LengthForTesting > 0)
        #expect(editorView.textView.syntaxRenderingAttributeUTF16LengthForTesting < source.utf16.count / 4)
        #expect(editorView.textView.syntaxRenderingAttributeColorRunCountForTesting < tokens.count / 4)

        editorView.textView.resetSyntaxRenderingAttributeCountersForTesting()
        editorView.textView.invalidateSyntaxRenderingAttributes(
            for: [NSRange(location: 0, length: source.utf16.count)]
        )
        #expect(editorView.textView.syntaxRenderingAttributeUTF16LengthForTesting > 0)
        #expect(editorView.textView.syntaxRenderingAttributeUTF16LengthForTesting < source.utf16.count / 4)
        #expect(editorView.textView.syntaxRenderingAttributeColorRunCountForTesting < tokens.count / 4)
    }

    @Test("SyntaxEditorView replaces stale macOS syntax colors after new highlight epochs")
    @MainActor
    func syntaxEditorViewMacReplacesStaleSyntaxColorsAfterNewEpochs() async {
        let source = "let"
        let initialTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x102030),
            keyword: syntaxEditorUITestColor(hex: 0x305070)
        )
        let updatedTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x102030),
            keyword: syntaxEditorUITestColor(hex: 0x703050)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: initialTheme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), initialTheme.keyword))

        model.model.theme = updatedTheme
        editorView.synchronizeDocumentForTesting()

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorPermanentForegroundColor(editorView, at: 0),
                updatedTheme.baseForeground
            )
        )
    }

    @Test("SyntaxEditorView keeps macOS syntax colors while typing awaits highlight")
    @MainActor
    func syntaxEditorViewMacKeepsMaterializedSyntaxColorsDuringPendingTypingHighlight() async {
        let source = "let\nvalue"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x102030),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let updateGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateGate: updateGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        let previousSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.textView.insertText("!", replacementRange: NSRange(location: source.utf16.count, length: 0))
        await updateGate.waitUntilSuspended(after: previousSuspensionCount)

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        await updateGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView keeps same-line macOS syntax colors while typing awaits highlight")
    @MainActor
    func syntaxEditorViewMacKeepsSameLineSyntaxColorsDuringPendingTypingHighlight() async {
        let source = "extension "
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x102030),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let updateGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 9),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateGate: updateGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        let previousSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.textView.insertText("S", replacementRange: NSRange(location: source.utf16.count, length: 0))
        await updateGate.waitUntilSuspended(after: previousSuspensionCount)

        #expect(editorView.textView.string == "extension S")
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        await updateGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView keeps shifted stale macOS syntax colors while typing awaits highlight")
    @MainActor
    func syntaxEditorViewMacMaterializesShiftedStaleSyntaxColorsDuringPendingTypingHighlight() async {
        let source = "let\nlet"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x102030),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let updateGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 4, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 5, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateGate: updateGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 4), theme.keyword))

        let previousSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        await updateGate.waitUntilSuspended(after: previousSuspensionCount)

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 5), theme.keyword))

        await updateGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 5), theme.keyword))
    }

    @Test("SyntaxEditorView avoids full macOS display invalidation after language resets")
    @MainActor
    func syntaxEditorViewMacAvoidsFullDisplayInvalidationAfterLanguageResets() async {
        let source = "let"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0x345678),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorLanguageAwareTestHighlighter(
            swiftTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            jsonTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.json.string"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let invalidationCount = editorView.fullTextDisplayInvalidationCountForTesting

        model.model.language = SyntaxLanguage.json
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.fullTextDisplayInvalidationCountForTesting == invalidationCount)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))
    }

    @Test("SyntaxEditorView redraws visible macOS text fragments after language resets")
    @MainActor
    func syntaxEditorViewMacRedrawsVisibleTextFragmentsAfterLanguageResets() async {
        let source = (0..<12)
            .map { "let value\($0) = \"text\"" }
            .joined(separator: "\n")
        var lineStart = 0
        let swiftTokens = source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            defer {
                lineStart += line.utf16.count + 1
            }
            return SyntaxEditorHighlighting.Token(
                range: NSRange(location: lineStart, length: 3),
                rawCaptureName: "editor.syntax.swift.keyword"
            )
        }
        let highlighter = SyntaxEditorLanguageAwareTestHighlighter(
            swiftTokens: swiftTokens,
            jsonTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.json.string"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        editorView.frame = NSRect(x: 0, y: 0, width: 640, height: 260)
        editorView.layoutSubtreeIfNeeded()

        await editorView.waitForPendingHighlightForTesting()
        let initialFragments = macEditorVisibleFragmentViews(editorView)
        #expect(!initialFragments.isEmpty)
        let fragmentInvalidationCount = editorView.fragmentDisplayInvalidationCountForTesting

        model.model.language = SyntaxLanguage.json
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.fragmentDisplayInvalidationCountForTesting > fragmentInvalidationCount)
    }

    @Test("SyntaxEditorView preserves macOS non-syntax attributes while applying delayed highlight")
    @MainActor
    func syntaxEditorViewMacDelayedHighlightPreservesNonSyntaxAttributes() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            resetGate: resetGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        editorView.textView.textStorage?.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 4, length: 5)
        )

        await resetGate.waitUntilSuspended()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))
        #expect(macEditorUnderlineStyle(editorView, at: 4) == NSUnderlineStyle.single.rawValue)

        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 4), theme.baseForeground))
        #expect(macEditorUnderlineStyle(editorView, at: 4) == NSUnderlineStyle.single.rawValue)
    }

    @Test("SyntaxEditorView keeps macOS bracket highlight only for caret selections")
    @MainActor
    func syntaxEditorViewAppKitBracketHighlightSkipsNonemptySelection() async {
        let source = "{}"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: SyntaxEditorUITestHighlighter())
        await editorView.waitForPendingHighlightForTesting()

        let visibleInvalidationCount = editorView.visibleTextDisplayInvalidationCountForTesting
        editorView.textView.setSelectedRange(NSRange(location: 1, length: 0))
        editorView.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editorView.textView)
        )

        #expect(editorView.bracketHighlightRangesForTesting == [
            NSRange(location: 0, length: 1),
            NSRange(location: 1, length: 1),
        ])
        #expect(macEditorHasBackgroundAttribute(editorView, at: 0))
        #expect(macEditorHasBackgroundAttribute(editorView, at: 1))
        #expect(macEditorTextStorageBackgroundColor(editorView, at: 0) == nil)
        #expect(macEditorTextStorageBackgroundColor(editorView, at: 1) == nil)
        #expect(editorView.visibleTextDisplayInvalidationCountForTesting == visibleInvalidationCount)

        editorView.textView.setSelectedRange(NSRange(location: 0, length: source.utf16.count))
        editorView.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editorView.textView)
        )

        #expect(editorView.bracketHighlightRangesForTesting.isEmpty)
        #expect(!macEditorHasBackgroundAttribute(editorView, at: 0))
        #expect(!macEditorHasBackgroundAttribute(editorView, at: 1))
        #expect(editorView.visibleTextDisplayInvalidationCountForTesting == visibleInvalidationCount)
    }

    @Test("SyntaxEditorView keeps macOS text painting owned by the scroll view")
    @MainActor
    func syntaxEditorViewMacUsesScrollViewBackedTextPainting() {
        let model = SyntaxEditorTestContext(text: "let value = 1", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: SyntaxEditorUITestHighlighter())

        #expect(editorView.drawsBackground)
        #expect(!editorView.textView.drawsBackground)
        #expect(!editorView.textView.textContentView.wantsLayer)
        #expect(!(editorView.textView.textContentView.layer is CATiledLayer))
        #expect(!type(of: editorView.textView).isCompatibleWithResponsiveScrolling)
    }

    @Test("SyntaxEditorView defers macOS syntax colors while preserving active selection drawing")
    @MainActor
    func syntaxEditorViewMacDefersHighlightApplicationDuringSelection() async {
        let source = "{}\nlet value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 3, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            resetGate: resetGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        await resetGate.waitUntilSuspended()

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 2))
        editorView.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editorView.textView)
        )
        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.bracketHighlightRangesForTesting.isEmpty)
        #expect(!macEditorHasBackgroundAttribute(editorView, at: 0))
        #expect(!macEditorHasBackgroundAttribute(editorView, at: 1))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), theme.baseForeground))

        editorView.textView.setSelectedRange(NSRange(location: 2, length: 0))
        editorView.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editorView.textView)
        )

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), theme.keyword))
        #expect(editorView.bracketHighlightRangesForTesting == [
            NSRange(location: 0, length: 1),
            NSRange(location: 1, length: 1),
        ])
    }

    @Test("SyntaxEditorView drops deferred macOS syntax colors after language changes")
    @MainActor
    func syntaxEditorViewMacDropsDeferredHighlightAfterLanguageChange() async {
        let source = "let"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorLanguageAwareTestHighlighter(
            swiftTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            jsonTokens: [],
            resetGate: resetGate
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        await resetGate.waitUntilSuspended()

        editorView.textView.setSelectedRange(NSRange(location: 0, length: source.utf16.count))
        editorView.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editorView.textView)
        )
        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))

        let previousSuspensionCount = await resetGate.currentSuspensionCount()
        model.model.language = SyntaxLanguage.json
        editorView.synchronizeDocumentForTesting()
        await resetGate.waitUntilSuspended(after: previousSuspensionCount)
        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editorView.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editorView.textView)
        )
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))

        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))
    }

    @Test("SyntaxEditorView applies latest macOS highlight after model replacement")
    @MainActor
    func syntaxEditorViewMacAppliesLatestHighlightAfterModelReplacement() async {
        let initialSource = "let"
        let replacementSource = "\"x\""
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            string: syntaxEditorUITestColor(hex: 0x345678),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorLanguageAwareTestHighlighter(
            swiftTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: initialSource.utf16.count),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            jsonTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: replacementSource.utf16.count),
                    rawCaptureName: "editor.syntax.json.string"
                ),
            ],
            resetGate: resetGate
        )
        let initialModel = SyntaxEditorTestContext(
            text: initialSource,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let replacementModel = SyntaxEditorModel(
            text: replacementSource,
            language: SyntaxLanguage.json,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: initialModel, highlighter: highlighter)
        await resetGate.waitUntilSuspended()
        let previousSuspensionCount = await resetGate.currentSuspensionCount()

        editorView.update(model: replacementModel)
        await resetGate.waitUntilSuspended(after: previousSuspensionCount)
        await resetGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.model === replacementModel)
        #expect(editorView.textView.string == replacementSource)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.string))
    }

    @Test("SyntaxEditorView fully repaints macOS syntax colors after dropping deferred highlights")
    @MainActor
    func syntaxEditorViewMacFullRepaintsAfterDroppingDeferredHighlight() async {
        let source = "let\nlet"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let updateGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 4, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            resetGate: resetGate,
            updateGate: updateGate,
            updateRefreshRange: NSRange(location: 0, length: source.utf16.count),
            updateTokenPayload: .fullSnapshot
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        await resetGate.waitUntilSuspended()

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 3))
        editorView.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editorView.textView)
        )
        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 4), theme.baseForeground))

        let previousSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.textView.insertText("var", replacementRange: NSRange(location: 0, length: 3))
        await updateGate.waitUntilSuspended(after: previousSuspensionCount)
        await updateGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == "var\nlet")
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 4), theme.keyword))
    }

    @Test("SyntaxEditorView preserves macOS syntax colors outside command edit ranges")
    @MainActor
    func syntaxEditorViewMacCommandEditsPreserveSyntaxColorsOutsideRefreshRange() async {
        let source = "let value = "
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            updateRefreshRange: NSRange(location: source.utf16.count, length: 2)
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        let insertionRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(insertionRange)
        editorView.textView.insertText("\"", replacementRange: insertionRange)
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == "\(source)\"\"")
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView sends macOS text change notifications for command edits")
    @MainActor
    func syntaxEditorViewMacCommandEditsSendTextChangeNotifications() async {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let recorder = SyntaxEditorNotificationRecorder()
        NotificationCenter.default.addObserver(
            recorder,
            selector: #selector(SyntaxEditorNotificationRecorder.record(_:)),
            name: NSText.didChangeNotification,
            object: editorView.textView
        )
        defer {
            NotificationCenter.default.removeObserver(recorder)
        }

        let insertionRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(insertionRange)
        editorView.textView.insertText("\"", replacementRange: insertionRange)
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == "\(source)\"\"")
        #expect(recorder.count == 1)
    }

    @Test("SyntaxEditorView syncs macOS multi-range replacements from the final text")
    @MainActor
    func syntaxEditorViewMacMultiRangeReplacementSyncsFinalText() async {
        let source = "abcde"
        let expectedSource = "aXcYe"
        let completeGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorPhasedTestHighlighter(
            fastTokens: [],
            completeTokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 1),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            completeGate: completeGate
        )
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await completeGate.waitUntilSuspended()
        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(editorView.syntaxColorRunCountForTesting == 1)

        let didAccept = editorView.textView.shouldReplaceCharacters(
            inRanges: [
                NSValue(range: NSRange(location: 1, length: 1)),
                NSValue(range: NSRange(location: 3, length: 1)),
            ],
            with: ["X", "Y"]
        )
        #expect(didAccept)

        let suspensionCount = await completeGate.currentSuspensionCount()
        editorView.textView.string = expectedSource
        #expect(editorView.syntaxColorRunCountForTesting == 0)
        await completeGate.waitUntilSuspended(after: suspensionCount)

        #expect(editorView.textView.string == expectedSource)
        #expect(model.model.text == expectedSource)
        #expect(editorView.syntaxColorRunCountForTesting == 0)

        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
    }

    @Test("SyntaxEditorView keeps macOS marked range unchanged when marked text is handled as command input")
    @MainActor
    func syntaxEditorViewMacRejectedMarkedCommandDoesNotInstallMarkedRange() async {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let insertionRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(insertionRange)

        editorView.textView.setMarkedText(
            "\"",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        await editorView.waitForPendingHighlightForTesting()

        let expectedSource = source + "\"\""
        #expect(!editorView.textView.hasMarkedText())
        #expect(editorView.textView.markedRange().location == NSNotFound)
        #expect(editorView.textView.string == expectedSource)
        #expect(model.model.text == expectedSource)
    }

    @Test("SyntaxEditorView replaces macOS marked text when IME commits through insertText")
    @MainActor
    func syntaxEditorViewMacReplacesMarkedTextWhenIMECommitsThroughInsertText() async {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let insertionRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(insertionRange)

        editorView.textView.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editorView.textView.insertText("仮名", replacementRange: NSRange(location: NSNotFound, length: 0))
        await editorView.waitForPendingHighlightForTesting()

        let expectedSource = source + "仮名"
        #expect(!editorView.textView.hasMarkedText())
        #expect(editorView.textView.markedRange().location == NSNotFound)
        #expect(editorView.textView.string == expectedSource)
        #expect(model.model.text == expectedSource)
        #expect(editorView.textView.selectedRange() == NSRange(location: expectedSource.utf16.count, length: 0))
    }

    @Test("SyntaxEditorView clears macOS marked-text highlight suppression after IME commit")
    @MainActor
    func syntaxEditorViewMacClearsMarkedTextHighlightSuppressionAfterIMECommit() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        layoutMacEditorView(editorView)
        let originalMarkedTextHook = editorView.textView.didChangeMarkedTextRange
        var markedTextHookCallCount = 0
        editorView.textView.didChangeMarkedTextRange = {
            markedTextHookCallCount += 1
            originalMarkedTextHook?()
        }

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 3))
        editorView.textView.setMarkedText(
            "let",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))
        #expect(markedTextHookCallCount == 1)

        editorView.textView.insertText("let", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(editorView.textView.markedRange().location == NSNotFound)
        #expect(markedTextHookCallCount == 2)
    }

    @Test("SyntaxEditorView preserves macOS attributed marked text attributes")
    @MainActor
    func syntaxEditorViewMacPreservesAttributedMarkedTextAttributes() async throws {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let insertionRange = NSRange(location: source.utf16.count, length: 0)
        let markedForeground = syntaxEditorUITestColor(hex: 0x1A7F37)
        let markedUnderline = syntaxEditorUITestColor(hex: 0x0969DA)
        let markedText = NSMutableAttributedString(string: "かな")
        let markedTextRange = NSRange(location: 0, length: markedText.length)
        markedText.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: markedTextRange
        )
        markedText.addAttribute(.underlineColor, value: markedUnderline, range: markedTextRange)
        markedText.addAttribute(.foregroundColor, value: markedForeground, range: markedTextRange)
        editorView.textView.setSelectedRange(insertionRange)
        layoutMacEditorView(editorView)

        editorView.textView.setMarkedText(
            markedText,
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        await editorView.waitForPendingHighlightForTesting()

        let installedRange = NSRange(location: insertionRange.location, length: markedText.length)
        #expect(editorView.textView.markedRange() == installedRange)
        #expect(macEditorUnderlineStyle(editorView, at: installedRange.location) == NSUnderlineStyle.single.rawValue)
        #expect(
            syntaxEditorUITestColorsEqual(
                editorView.textView.textStorage?.attribute(
                    .underlineColor,
                    at: installedRange.location,
                    effectiveRange: nil
                ) as? NSColor,
                markedUnderline
            )
        )
        #expect(syntaxEditorUITestColorsEqual(
            macEditorPermanentForegroundColor(editorView, at: installedRange.location),
            markedForeground
        ))

        let installedTextRange = try #require(editorView.textView.textRange(forUTF16Range: installedRange))
        var renderingForeground: NSColor?
        editorView.textView.textLayoutManager.enumerateRenderingAttributes(
            from: installedTextRange.location,
            reverse: false
        ) { _, attributes, range in
            let utf16Range = editorView.textView.utf16Range(for: range)
            guard NSIntersectionRange(utf16Range, installedRange).length > 0 else {
                return true
            }
            renderingForeground = attributes[.foregroundColor] as? NSColor
            return false
        }
        #expect(renderingForeground == nil)
    }

    @Test("SyntaxEditorView clears macOS marked-text highlight suppression after unmarking")
    @MainActor
    func syntaxEditorViewMacClearsMarkedTextHighlightSuppressionAfterUnmarking() async {
        let source = "let value = 1"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        layoutMacEditorView(editorView)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        let markedRange = NSRange(location: 0, length: 3)
        editorView.textView.markedTextRangeStorage = markedRange
        editorView.textView.markedTextAttributedStringStorage = NSAttributedString(
            string: "let",
            attributes: editorView.textView.typingAttributes
        )
        editorView.textView.applyMarkedTextAttributes()
        editorView.textView.didChangeMarkedTextRange?()

        #expect(editorView.textView.markedRange() == markedRange)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))

        editorView.textView.unmarkText()

        #expect(editorView.textView.markedRange().location == NSNotFound)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView preserves macOS highlights for observed document edits")
    @MainActor
    func syntaxEditorViewMacObservedDocumentEditsPreserveExistingHighlights() async {
        let source = "let first = 1\nlet second = 2"
        let appendedText = "\nlet third = 3"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(range: NSRange(location: 0, length: 3), rawCaptureName: "editor.syntax.swift.keyword"),
            ],
            updateRefreshRange: NSRange(location: source.utf16.count, length: appendedText.utf16.count)
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        _ = model.model.commitTextReplacements(
            [
                SyntaxEditorTextChange.Replacement(
                    range: NSRange(location: source.utf16.count, length: 0),
                    replacement: appendedText
                ),
            ],
            selectedRange: NSRange(location: source.utf16.count + appendedText.utf16.count, length: 0)
        )
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == source + appendedText)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView fully applies macOS highlight when skipped revisions precede an incremental result")
    @MainActor
    func syntaxEditorViewMacFullyAppliesHighlightAfterSkippedIncrementalRevisions() async {
        let firstPaste = "let first = 1\n"
        let secondPaste = "let second = 2\n"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let resetGate = ManualSyntaxHighlightGate()
        let updateGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: firstPaste.utf16.count, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ],
            resetGate: resetGate,
            updateGate: updateGate,
            updateRefreshRange: NSRange(
                location: 0,
                length: firstPaste.utf16.count + secondPaste.utf16.count
            ),
            updateTokenPayload: .fullSnapshot
        )
        let model = SyntaxEditorTestContext(
            text: "",
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        await resetGate.waitUntilSuspended()

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let firstSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.textView.insertText(firstPaste, replacementRange: NSRange(location: 0, length: 0))
        await updateGate.waitUntilSuspended(after: firstSuspensionCount)
        editorView.textView.setSelectedRange(NSRange(location: firstPaste.utf16.count, length: 0))
        let secondSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.textView.insertText(
            secondPaste,
            replacementRange: NSRange(location: firstPaste.utf16.count, length: 0)
        )
        await updateGate.waitUntilSuspended(after: secondSuspensionCount)

        await resetGate.resumeAll()
        await updateGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == firstPaste + secondPaste)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(
            syntaxEditorUITestColorsEqual(
                macEditorForegroundColor(editorView, at: firstPaste.utf16.count),
                theme.keyword
            )
        )
    }

    @Test("SyntaxEditorView renders macOS pasted text before async highlight completes")
    @MainActor
    func syntaxEditorViewMacRendersPastedTextBeforeAsyncHighlightCompletes() async {
        let source = "let start = 0\n"
        let pastedText = String(repeating: "let value = 1\n", count: 500)
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let updateGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(updateGate: updateGate)
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        layoutMacEditorView(editorView)
        await editorView.waitForPendingHighlightForTesting()
        let initialDocumentHeight = editorView.textView.frame.height

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editorView.textView.insertText(pastedText, replacementRange: NSRange(location: 0, length: 0))
        await updateGate.waitUntilSuspended()
        layoutMacEditorView(editorView)
        let pastedDocumentHeight = editorView.textView.frame.height

        #expect(editorView.textView.string == pastedText + source)
        #expect(model.model.text == pastedText + source)
        #expect(pastedDocumentHeight > initialDocumentHeight + 1_000)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.baseForeground))

        let previousSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.textView.replaceCharacters(
            in: NSRange(location: 0, length: pastedText.utf16.count),
            with: ""
        )
        await updateGate.waitUntilSuspended(after: previousSuspensionCount)
        layoutMacEditorView(editorView)

        #expect(editorView.textView.string == source)
        #expect(model.model.text == source)
        #expect(editorView.textView.frame.height < pastedDocumentHeight - 1_000)

        await updateGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
    }

    @Test("SyntaxEditorView schedules macOS paste highlight while attribute highlight is applying")
    @MainActor
    func syntaxEditorViewMacSchedulesPasteHighlightWhileAttributeHighlightIsApplying() async {
        let source = "let value = 1\n"
        let pastedText = "let pasted = 2\n"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 3),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editorView.setApplyingHighlightForTesting(true)
        editorView.textView.insertText(pastedText, replacementRange: NSRange(location: 0, length: 0))
        editorView.setApplyingHighlightForTesting(false)
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.textView.string == pastedText + source)
        #expect(model.model.text == pastedText + source)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewMacEditorStateObservation() async {
        let model = SyntaxEditorTestContext(text: "body {}", language: SyntaxLanguage.css)
        let editorView = SyntaxEditorView(testContext: model)

        model.model.isEditable = false
        model.model.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(
            editorView.textView.isEditable == false
                && editorView.hasHorizontalScroller == false
        )

        model.model.lineWrappingEnabled = false

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.hasHorizontalScroller == true)
    }

    @Test("SyntaxEditorView redraws macOS text after enabling wrapping from a horizontal scroll")
    @MainActor
    func syntaxEditorViewMacWrappingResetsHorizontalClipOrigin() async {
        let model = SyntaxEditorTestContext(
            text: String(repeating: "let horizontalScrollNeedsWrapping = true; ", count: 32),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutMacEditorView(editorView)

        editorView.textView.frame.size.width = 1_600
        editorView.contentView.scroll(to: NSPoint(x: 600, y: editorView.contentView.bounds.origin.y))
        editorView.reflectScrolledClipView(editorView.contentView)
        #expect(editorView.contentView.bounds.origin.x > 0)

        model.model.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect({
            guard let textContainer = editorView.textView.textContainer else {
                return false
            }

            return editorView.hasHorizontalScroller == false
                && editorView.contentView.bounds.origin.x <= 0.5
                && editorView.textView.visibleRect.origin.x <= 0.5
                && editorView.textView.isHorizontallyResizable == false
                && textContainer.widthTracksTextView == true
                && textContainer.lineBreakMode == .byWordWrapping
                && approximatelyEqual(textContainer.containerSize.width, editorView.contentSize.width)
                && approximatelyEqual(editorView.textView.frame.width, editorView.contentSize.width)
        }())
    }

    @Test("SyntaxEditorView recalculates macOS document height after wrapping toggles")
    @MainActor
    func syntaxEditorViewMacWrappingToggleRecalculatesDocumentHeight() async {
        let source = String(repeating: "let wrappingHeightMustTrackVisualLines = true; ", count: 48)
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutMacEditorView(editorView, width: 240, height: 120)
        let unwrappedHeight = editorView.textView.frame.height

        model.model.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        layoutMacEditorView(editorView, width: 240, height: 120)
        let wrappedHeight = editorView.textView.frame.height

        #expect(wrappedHeight > unwrappedHeight + 400)

        model.model.lineWrappingEnabled = false

        editorView.synchronizeDocumentForTesting()
        layoutMacEditorView(editorView, width: 240, height: 120)

        #expect(editorView.textView.frame.height < wrappedHeight - 400)
        #expect(approximatelyEqual(editorView.textView.frame.height, unwrappedHeight))
    }

    @Test("SyntaxEditorView does not repaint all macOS text fragments while scrolling")
    @MainActor
    func syntaxEditorViewMacScrollDoesNotInvalidateVisibleFragments() async {
        let model = SyntaxEditorTestContext(
            text: String(repeating: "let value = 1\n", count: 400),
            language: SyntaxLanguage.swift
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutMacEditorView(editorView)

        let visibleInvalidationCount = editorView.visibleTextDisplayInvalidationCountForTesting
        editorView.contentView.scroll(to: NSPoint(x: 0, y: 400))
        editorView.reflectScrolledClipView(editorView.contentView)

        #expect(editorView.visibleTextDisplayInvalidationCountForTesting == visibleInvalidationCount)
    }

    @Test("SyntaxEditorView does not query offscreen macOS caret geometry while scrolling")
    @MainActor
    func syntaxEditorViewMacScrollDoesNotQueryOffscreenCaretGeometry() {
        let model = SyntaxEditorTestContext(
            text: String(repeating: "let value = 1\n", count: 1_200),
            language: SyntaxLanguage.swift
        )
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        #expect(window.makeFirstResponder(editorView.textView))
        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let initialQueryCount = editorView.textView.caretGeometryQueryCountForTesting

        editorView.contentView.scroll(to: NSPoint(x: 0, y: 2_000))
        editorView.reflectScrolledClipView(editorView.contentView)

        #expect(editorView.textView.caretGeometryQueryCountForTesting == initialQueryCount)
        #expect(editorView.textView.insertionIndicatorDisplayModeForTesting == .hidden)
        #expect(editorView.textView.insertionIndicatorIsHiddenForTesting)
    }

    @Test("SyntaxEditorView does not fan out macOS content invalidation to every text fragment")
    @MainActor
    func syntaxEditorViewMacContentInvalidationDoesNotInvalidateAllFragments() async {
        let model = SyntaxEditorTestContext(
            text: String(repeating: "let value = 1\n", count: 400),
            language: SyntaxLanguage.swift
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutMacEditorView(editorView)

        let fragmentInvalidationCount = editorView.fragmentDisplayInvalidationCountForTesting
        editorView.textView.textContentView.setNeedsDisplay(editorView.textView.bounds)

        #expect(editorView.fragmentDisplayInvalidationCountForTesting == fragmentInvalidationCount)
    }

    @Test("SyntaxEditorView wraps to unobscured macOS content width")
    @MainActor
    func syntaxEditorViewMacWrappingAccountsForContentInsets() async {
        let model = SyntaxEditorTestContext(
            text: String(repeating: "let insetAwareWrappingWidth = true; ", count: 16),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)
        editorView.contentInsets = NSEdgeInsets(top: 12, left: 80, bottom: 0, right: 24)
        layoutMacEditorView(editorView, width: 360, height: 160)

        #expect({
            guard let textContainer = editorView.textView.textContainer else {
                return false
            }

            let contentInsets = editorView.contentView.contentInsets
            let expectedWidth = editorView.contentSize.width - contentInsets.left - contentInsets.right
            let expectedHeight = editorView.contentSize.height - contentInsets.bottom
            let expectedClipOriginX = -contentInsets.left
            return editorView.hasHorizontalScroller == false
                && approximatelyEqual(editorView.contentView.bounds.origin.x, expectedClipOriginX)
                && textContainer.widthTracksTextView == true
                && approximatelyEqual(textContainer.containerSize.width, expectedWidth)
                && approximatelyEqual(editorView.textView.frame.width, expectedWidth)
                && approximatelyEqual(editorView.textView.minSize.height, expectedHeight)
        }())
    }

    @Test("SyntaxEditorView updates macOS wrapping geometry after resize")
    @MainActor
    func syntaxEditorViewMacWrappingTracksResizedContentWidth() async {
        let model = SyntaxEditorTestContext(
            text: String(repeating: "let resizedWrappingWidth = true; ", count: 16),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutMacEditorView(editorView, width: 520, height: 180)

        #expect({
            guard let textContainer = editorView.textView.textContainer else {
                return false
            }

            return approximatelyEqual(textContainer.containerSize.width, editorView.contentSize.width)
                && approximatelyEqual(editorView.textView.frame.width, editorView.contentSize.width)
        }())

        layoutMacEditorView(editorView, width: 240, height: 180)

        #expect({
            guard let textContainer = editorView.textView.textContainer else {
                return false
            }

            return editorView.contentView.bounds.origin.x <= 0.5
                && approximatelyEqual(textContainer.containerSize.width, editorView.contentSize.width)
                && approximatelyEqual(editorView.textView.frame.width, editorView.contentSize.width)
        }())
    }

    @Test("SyntaxEditorView does not rebuild macOS line metrics during resize")
    @MainActor
    func syntaxEditorViewMacResizeDoesNotRebuildLineMetrics() async {
        let longLine = String(
            repeating: "let extremelyLongIdentifierName = syntaxEditorHorizontalScrollValue; ",
            count: 4
        )
        let source = (0..<2_000)
            .map { index in
                index == 1_500 ? longLine : "let value\(index) = \(index)"
            }
            .joined(separator: "\n")
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutMacEditorView(editorView, width: 720, height: 300)

        let rebuildCount = editorView.lineMetricsFullRebuildCountForTesting
        layoutMacEditorView(editorView, width: 360, height: 300)
        layoutMacEditorView(editorView, width: 640, height: 300)

        #expect(editorView.lineMetricsFullRebuildCountForTesting == rebuildCount)
        #expect(approximatelyEqual(editorView.textView.frame.width, editorView.contentSize.width))
    }

    @Test("SyntaxEditorView keeps inset macOS wrapping geometry after resize")
    @MainActor
    func syntaxEditorViewMacWrappingTracksInsetContentWidthAfterResize() async {
        let model = SyntaxEditorTestContext(
            text: String(repeating: "let insetResizeWrappingWidth = true; ", count: 16),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)
        editorView.contentInsets = NSEdgeInsets(top: 0, left: 96, bottom: 0, right: 44)
        layoutMacEditorView(editorView, width: 560, height: 180)

        #expect({
            guard let textContainer = editorView.textView.textContainer else {
                return false
            }

            let contentInsets = editorView.contentView.contentInsets
            let expectedWidth = editorView.contentSize.width - contentInsets.left - contentInsets.right
            let expectedClipOriginX = -contentInsets.left
            return approximatelyEqual(editorView.contentView.bounds.origin.x, expectedClipOriginX)
                && approximatelyEqual(textContainer.containerSize.width, expectedWidth)
                && approximatelyEqual(editorView.textView.frame.width, expectedWidth)
        }())

        layoutMacEditorView(editorView, width: 320, height: 180)

        #expect({
            guard let textContainer = editorView.textView.textContainer else {
                return false
            }

            let contentInsets = editorView.contentView.contentInsets
            let expectedWidth = editorView.contentSize.width - contentInsets.left - contentInsets.right
            let expectedClipOriginX = -contentInsets.left
            return approximatelyEqual(editorView.contentView.bounds.origin.x, expectedClipOriginX)
                && approximatelyEqual(textContainer.containerSize.width, expectedWidth)
                && approximatelyEqual(editorView.textView.frame.width, expectedWidth)
        }())
    }

    @Test("SyntaxEditorView keeps synchronizing after language changes on macOS")
    @MainActor
    func syntaxEditorViewMacLanguageChangeKeepsObservationAlive() async {
        let model = SyntaxEditorTestContext(text: "let answer = 42", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)

        model.model.language = SyntaxLanguage.json
        model.model.isEditable = false

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.isEditable == false)

        model.model.replaceText("{\"answer\":42}")

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.string == "{\"answer\":42}")
    }

    @Test("SyntaxEditorMenu builds AppKit Editor menu item commands")
    @MainActor
    func syntaxEditorMenuBuildsAppKitEditorMenuItemCommands() throws {
        let menuItem = SyntaxEditorMenu.makeEditorMenuItem()
        #expect(menuItem.title == "Editor")
        let menu = try #require(menuItem.submenu)

        let structureMenu = try #require(syntaxEditorSubmenu(menu, title: "Structure"))
        let shiftRight = structureMenu.item(withTitle: "Shift Right")
        #expect(shiftRight?.action == NSSelectorFromString("syntaxEditorShiftRight:"))
        #expect(shiftRight?.target == nil)
        #expect(shiftRight?.keyEquivalent == "]")
        #expect(shiftRight?.keyEquivalentModifierMask.intersection(syntaxEditorMenuItemModifierMask) == [.command])

        let shiftLeft = structureMenu.item(withTitle: "Shift Left")
        #expect(shiftLeft?.action == NSSelectorFromString("syntaxEditorShiftLeft:"))
        #expect(shiftLeft?.target == nil)
        #expect(shiftLeft?.keyEquivalent == "[")
        #expect(shiftLeft?.keyEquivalentModifierMask.intersection(syntaxEditorMenuItemModifierMask) == [.command])

        let commentSelection = structureMenu.item(withTitle: "Comment Selection")
        #expect(structureMenu.items.firstIndex(where: { $0.isSeparatorItem }) == 2)
        #expect(commentSelection?.action == NSSelectorFromString("syntaxEditorCommentSelection:"))
        #expect(commentSelection?.target == nil)
        #expect(commentSelection?.keyEquivalent == "/")
        #expect(commentSelection?.keyEquivalentModifierMask.intersection(syntaxEditorMenuItemModifierMask) == [.command])

        let fontSizeMenu = try #require(syntaxEditorSubmenu(menu, title: "Font Size"))
        let increase = fontSizeMenu.item(withTitle: "Increase")
        #expect(increase?.action == NSSelectorFromString("syntaxEditorIncreaseFontSize:"))
        #expect(increase?.target == nil)
        #expect(increase?.keyEquivalent == "+")
        #expect(increase?.keyEquivalentModifierMask.intersection(syntaxEditorMenuItemModifierMask) == [.command])

        let decrease = fontSizeMenu.item(withTitle: "Decrease")
        #expect(decrease?.action == NSSelectorFromString("syntaxEditorDecreaseFontSize:"))
        #expect(decrease?.target == nil)
        #expect(decrease?.keyEquivalent == "-")
        #expect(decrease?.keyEquivalentModifierMask.intersection(syntaxEditorMenuItemModifierMask) == [.command])

        let reset = fontSizeMenu.item(withTitle: "Reset")
        #expect(fontSizeMenu.items.firstIndex(where: { $0.isSeparatorItem }) == 2)
        #expect(reset?.action == NSSelectorFromString("syntaxEditorResetFontSize:"))
        #expect(reset?.target == nil)
        #expect(reset?.keyEquivalent == "0")
        #expect(reset?.keyEquivalentModifierMask.intersection(syntaxEditorMenuItemModifierMask) == [.control, .command])

        let wrapLines = menu.item(withTitle: "Wrap Lines")
        #expect(wrapLines?.action == NSSelectorFromString("syntaxEditorToggleLineWrapping:"))
        #expect(wrapLines?.target == nil)
        #expect(wrapLines?.keyEquivalent == "l")
        #expect(wrapLines?.keyEquivalentModifierMask.intersection(syntaxEditorMenuItemModifierMask) == [.control, .shift, .command])
    }

    @Test("SyntaxEditorView validates and handles AppKit Editor menu actions")
    @MainActor
    func syntaxEditorViewMacValidatesAndHandlesEditorMenuActions() throws {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        let menu = try #require(SyntaxEditorMenu.makeEditorMenuItem().submenu)
        let structureMenu = try #require(syntaxEditorSubmenu(menu, title: "Structure"))
        let shiftRight = try #require(structureMenu.item(withTitle: "Shift Right"))
        let wrapLines = try #require(menu.item(withTitle: "Wrap Lines"))

        #expect(!editorView.textView.validateUserInterfaceItem(shiftRight))
        #expect(editorView.textView.validateUserInterfaceItem(wrapLines))
        #expect(wrapLines.state == .off)
        model.model.lineWrappingEnabled = true
        #expect(editorView.textView.validateUserInterfaceItem(wrapLines))
        #expect(wrapLines.state == .on)

        model.model.lineWrappingEnabled = false
        model.model.isEditable = true
        editorView.synchronizeDocumentForTesting()
        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = editorView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView.textView)
        defer { window.orderOut(nil) }

        #expect(NSApplication.shared.sendAction(
            NSSelectorFromString("syntaxEditorShiftRight:"),
            to: editorView.textView,
            from: shiftRight
        ))
        #expect(model.model.text == "    \(source)")
        #expect(editorView.textView.string == "    \(source)")

        #expect(NSApplication.shared.sendAction(
            NSSelectorFromString("syntaxEditorToggleLineWrapping:"),
            to: editorView.textView,
            from: wrapLines
        ))
        #expect(model.model.lineWrappingEnabled)
    }

    @Test("SyntaxEditorView handles AppKit standard edit key equivalents")
    @MainActor
    func syntaxEditorViewMacHandlesStandardEditKeyEquivalents() throws {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = editorView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView.textView)
        defer { window.orderOut(nil) }

        let pasteboard = NSPasteboard.general
        let previousPasteboardString = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousPasteboardString {
                pasteboard.setString(previousPasteboardString, forType: .string)
            }
        }

        let copyEvent = try #require(makeMacCommandKeyEvent("c"))
        let pasteEvent = try #require(makeMacCommandKeyEvent("v"))
        let cutEvent = try #require(makeMacCommandKeyEvent("x"))
        let selectAllEvent = try #require(makeMacCommandKeyEvent("a"))
        let copyItem = NSMenuItem(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        let cutItem = NSMenuItem(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: "x")
        let pasteItem = NSMenuItem(title: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: "v")

        editorView.textView.setSelectedRange(NSRange(location: 4, length: 6))

        #expect(editorView.textView.validateUserInterfaceItem(copyItem))
        #expect(editorView.textView.performKeyEquivalent(with: copyEvent))
        #expect(pasteboard.string(forType: .string) == "answer")

        pasteboard.clearContents()
        pasteboard.setString("value", forType: .string)
        #expect(editorView.textView.validateUserInterfaceItem(pasteItem))
        #expect(editorView.textView.performKeyEquivalent(with: pasteEvent))
        #expect(model.model.text == "let value = 42")
        #expect(editorView.textView.string == "let value = 42")
        #expect(editorView.textView.selectedRange() == NSRange(location: 9, length: 0))

        editorView.textView.setSelectedRange(NSRange(location: 4, length: 5))
        #expect(editorView.textView.validateUserInterfaceItem(cutItem))
        #expect(editorView.textView.performKeyEquivalent(with: cutEvent))
        #expect(pasteboard.string(forType: .string) == "value")
        #expect(model.model.text == "let  = 42")
        #expect(editorView.textView.string == "let  = 42")
        #expect(editorView.textView.selectedRange() == NSRange(location: 4, length: 0))

        #expect(editorView.textView.performKeyEquivalent(with: selectAllEvent))
        #expect(editorView.textView.selectedRange() == NSRange(location: 0, length: editorView.textView.string.utf16.count))

        model.model.isEditable = false
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.validateUserInterfaceItem(copyItem))
        #expect(!editorView.textView.validateUserInterfaceItem(cutItem))
        #expect(!editorView.textView.validateUserInterfaceItem(pasteItem))
    }

    @Test("SyntaxEditorView provides AppKit contextual edit menu")
    @MainActor
    func syntaxEditorViewMacProvidesContextualEditMenu() throws {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        let pasteboard = NSPasteboard.general
        let previousPasteboardString = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousPasteboardString {
                pasteboard.setString(previousPasteboardString, forType: .string)
            }
        }

        editorView.textView.setSelectedRange(NSRange(location: 4, length: 6))
        let previousSelection = editorView.textView.selectedRange()
        pasteboard.clearContents()
        pasteboard.setString("value", forType: .string)

        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 12, y: 12),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        let menu = try #require(editorView.textView.menu(for: event))

        #expect(window.firstResponder === editorView.textView)
        #expect(editorView.textView.selectedRange() == previousSelection)
        #expect(menu.items.count == 3)
        #expect(menu.items[0].title == "Cut")
        #expect(menu.items[0].action == #selector(NSText.cut(_:)))
        #expect(menu.items[0].keyEquivalent == "")
        #expect(menu.items[0].target === editorView.textView)
        #expect(menu.items[1].title == "Copy")
        #expect(menu.items[1].action == #selector(NSText.copy(_:)))
        #expect(menu.items[1].keyEquivalent == "")
        #expect(menu.items[1].target === editorView.textView)
        #expect(menu.items[2].title == "Paste")
        #expect(menu.items[2].action == #selector(NSText.paste(_:)))
        #expect(menu.items[2].keyEquivalent == "")
        #expect(menu.items[2].target === editorView.textView)

        menu.update()
        #expect(menu.items[0].isEnabled)
        #expect(menu.items[1].isEnabled)
        #expect(menu.items[2].isEnabled)

        pasteboard.clearContents()
        model.model.isEditable = false
        editorView.synchronizeDocumentForTesting()

        menu.update()
        #expect(!menu.items[0].isEnabled)
        #expect(menu.items[1].isEnabled)
        #expect(!menu.items[2].isEnabled)

        editorView.textView.isSelectable = false
        #expect(editorView.textView.menu(for: event) == nil)
    }

    @Test("SyntaxEditorView leaves AppKit paste key equivalents to the active search field")
    @MainActor
    func syntaxEditorViewMacLeavesPasteKeyEquivalentToActiveSearchField() throws {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let searchField = NSSearchField(frame: NSRect(x: 0, y: 200, width: 220, height: 24))
        editorView.frame = NSRect(x: 0, y: 0, width: 320, height: 190)
        container.addSubview(editorView)
        container.addSubview(searchField)
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
        defer { window.orderOut(nil) }

        let pasteboard = NSPasteboard.general
        let previousPasteboardString = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousPasteboardString {
                pasteboard.setString(previousPasteboardString, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("pasted", forType: .string)

        let pasteEvent = try #require(makeMacCommandKeyEvent("v"))
        #expect(window.firstResponder !== editorView.textView)
        #expect(!editorView.textView.performKeyEquivalent(with: pasteEvent))
        #expect(model.model.text == source)
        #expect(editorView.textView.string == source)
    }

    @Test("SyntaxEditorView read-only delegate commands do not mutate text on macOS")
    @MainActor
    func syntaxEditorViewMacReadOnlyDelegateCommandsDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        editorView.textView.setSelectedRange(NSRange(location: 0, length: source.utf16.count))

        #expect(!editorView.textView(
            editorView.textView,
            shouldChangeTextIn: NSRange(location: 0, length: 0),
            replacementString: "\t"
        ))

        let commandSelectors = [
            #selector(NSResponder.insertTab(_:)),
            #selector(NSResponder.insertBacktab(_:)),
            #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.deleteBackward(_:)),
        ]

        for commandSelector in commandSelectors {
            #expect(!editorView.textView(editorView.textView, doCommandBy: commandSelector))
            #expect(model.model.text == source)
            #expect(editorView.textView.string == source)
        }
    }

    @Test("SyntaxEditorView inserts macOS tab spaces at the caret")
    @MainActor
    func syntaxEditorViewMacInsertTabAtCaret() {
        let source = "abcde"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.textView.setSelectedRange(NSRange(location: 2, length: 0))

        #expect(editorView.textView(
            editorView.textView,
            doCommandBy: #selector(NSResponder.insertTab(_:))
        ))

        #expect(model.model.text == "ab  cde")
        #expect(editorView.textView.string == "ab  cde")
        #expect(editorView.textView.selectedRange() == NSRange(location: 4, length: 0))
    }

    @Test("SyntaxEditorView inserts raw macOS tab in plain text")
    @MainActor
    func syntaxEditorViewMacInsertPlainTextTabAtCaret() {
        let source = "abcde"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.plainText)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.textView.setSelectedRange(NSRange(location: 2, length: 0))

        #expect(editorView.textView(
            editorView.textView,
            doCommandBy: #selector(NSResponder.insertTab(_:))
        ))

        #expect(model.model.text == "ab\tcde")
        #expect(editorView.textView.string == "ab\tcde")
        #expect(editorView.textView.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test("SyntaxEditorView accepts macOS first responder keyboard input")
    @MainActor
    func syntaxEditorViewMacAcceptsFirstResponderKeyboardInput() {
        let source = "let"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = editorView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        #expect(window.makeFirstResponder(editorView))
        #expect(window.firstResponder === editorView.textView)

        editorView.textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        guard let event = makeMacKeyEvent("x") else {
            Issue.record("Failed to create macOS key event")
            return
        }

        editorView.textView.keyDown(with: event)

        #expect(model.model.text == "letx")
        #expect(editorView.textView.string == "letx")
        #expect(editorView.textView.selectedRange() == NSRange(location: 4, length: 0))
    }

    @Test("SyntaxEditorView focuses macOS text input through rendered fragments")
    @MainActor
    func syntaxEditorViewMacFocusesTextInputThroughRenderedFragments() {
        let model = SyntaxEditorTestContext(text: "let value = 1", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        let clickPoint = NSPoint(x: 12, y: 12)
        #expect(editorView.textView.hitTest(clickPoint) === editorView.textView)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: editorView.textView.convert(clickPoint, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            Issue.record("Failed to create macOS mouse event")
            return
        }

        editorView.textView.mouseDown(with: event)

        #expect(window.firstResponder === editorView.textView)
    }

    @Test("SyntaxEditorView shows the macOS insertion indicator for caret selections")
    @MainActor
    func syntaxEditorViewMacShowsInsertionIndicatorForCaretSelections() {
        let source = "let value = 1"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        #expect(window.makeFirstResponder(editorView.textView))
        editorView.textView.setSelectedRange(NSRange(location: 4, length: 0))

        #expect(editorView.textView.insertionIndicatorDisplayModeForTesting == .automatic)
        #expect(!editorView.textView.insertionIndicatorIsHiddenForTesting)
        #expect(!editorView.textView.insertionIndicatorFrameForTesting.isEmpty)
    }

    @Test("SyntaxEditorView draws macOS selection overlay in rendered fragments")
    @MainActor
    func syntaxEditorViewMacDrawsSelectionOverlayInRenderedFragments() {
        let source = "let value = 1"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        #expect(window.makeFirstResponder(editorView.textView))
        editorView.textView.setSelectedRange((source as NSString).range(of: "value"))

        #expect(!editorView.textView.selectionHighlightRectsForTesting.isEmpty)
        #expect(editorView.textView.insertionIndicatorDisplayModeForTesting == .hidden)
        #expect(editorView.textView.insertionIndicatorIsHiddenForTesting)
    }

    @Test("SyntaxEditorView draws macOS incremental find candidates in rendered fragments")
    @MainActor
    func syntaxEditorViewMacDrawsIncrementalFindCandidatesInRenderedFragments() {
        let source = "m m m"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        editorView.textView.setFindHighlightRangesForTesting([
            NSRange(location: 0, length: 1),
            NSRange(location: 2, length: 1),
            NSRange(location: 4, length: 1),
        ])

        #expect(editorView.textView.findHighlightRectsForTesting.count >= 3)
        #expect(!editorView.textView.findCandidateHighlightFillColorForTesting.isEqual(NSColor.yellow))
        #expect(editorView.textView.findCandidateHighlightCornerRadiusForTesting > 0)

        let invalidationCount = editorView.fragmentDisplayInvalidationCountForTesting
        editorView.textView.setNeedsDisplayForVisibleTextFragments()
        #expect(editorView.fragmentDisplayInvalidationCountForTesting > invalidationCount)
    }

    @Test("SyntaxEditorView limits macOS incremental find candidates to visible fragments")
    @MainActor
    func syntaxEditorViewMacFindHighlightsIgnoreOffscreenRanges() {
        let source = (0..<500)
            .map { "match \($0)" }
            .joined(separator: "\n")
        let nsSource = source as NSString
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        let offscreenRanges = (250..<500).map { nsSource.range(of: "match \($0)") }
        editorView.textView.setFindHighlightRangesForTesting(offscreenRanges)
        #expect(editorView.textView.findHighlightRectsForTesting.isEmpty)

        let visibleRange = nsSource.range(of: "match 0")
        editorView.textView.setFindHighlightRangesForTesting(offscreenRanges + [visibleRange])
        #expect(editorView.textView.findHighlightRectsForTesting.count == 1)
    }

    @Test("SyntaxEditorView excludes the current macOS find match from candidate highlights")
    @MainActor
    func syntaxEditorViewMacFindHighlightsExcludeCurrentMatch() {
        let source = "m m m"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        editorView.textView.setSelectedRange(NSRange(location: 2, length: 1))
        #expect(editorView.textView.selectedRange() == NSRange(location: 2, length: 1))
        editorView.textView.setFindHighlightRangesForTesting([
            NSRange(location: 0, length: 1),
            NSRange(location: 4, length: 1),
        ])
        let nonCurrentMatchRectCount = editorView.textView.findHighlightRectsForTesting.count
        #expect(nonCurrentMatchRectCount > 0)

        editorView.textView.setFindHighlightRangesForTesting([
            NSRange(location: 0, length: 1),
            NSRange(location: 2, length: 1),
            NSRange(location: 4, length: 1),
        ])

        #expect(editorView.textView.findHighlightRectsForTesting.count == nonCurrentMatchRectCount)
    }

    @Test("SyntaxEditorView clears macOS find candidate highlights")
    @MainActor
    func syntaxEditorViewMacClearsFindCandidateHighlights() {
        let source = "m m m"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        editorView.textView.setFindHighlightRangesForTesting([
            NSRange(location: 0, length: 1),
            NSRange(location: 2, length: 1),
        ])
        #expect(!editorView.textView.findHighlightRectsForTesting.isEmpty)

        editorView.textView.setFindHighlightRangesForTesting([])
        #expect(editorView.textView.findHighlightRectsForTesting.isEmpty)

        editorView.textView.setFindHighlightRangesForTesting([
            NSRange(location: 4, length: 1),
        ])
        #expect(!editorView.textView.findHighlightRectsForTesting.isEmpty)

        editorView.textView.setFindHighlightRangesForTesting(nil)
        #expect(editorView.textView.findHighlightRectsForTesting.isEmpty)
    }

    @Test("SyntaxEditorView resolves macOS text input character indexes from screen points")
    @MainActor
    func syntaxEditorViewMacResolvesCharacterIndexFromScreenPoint() {
        let source = "let value = 1"
        let valueRange = (source as NSString).range(of: "value")
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        let screenRect = editorView.textView.firstRect(forCharacterRange: valueRange, actualRange: nil)
        let screenPoint = NSPoint(x: screenRect.minX + 1, y: screenRect.midY)

        #expect(editorView.textView.characterIndex(for: screenPoint) == valueRange.location)
    }

    @Test("SyntaxEditorView updates macOS mouse drag selections")
    @MainActor
    func syntaxEditorViewMacUpdatesMouseDragSelections() {
        let source = "let value = 1"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = attachMacEditorWindow(editorView)
        defer { window.orderOut(nil) }

        let startPoint = macEditorWindowPoint(
            in: window,
            textView: editorView.textView,
            characterRange: NSRange(location: 0, length: 1)
        )
        let endPoint = macEditorWindowPoint(
            in: window,
            textView: editorView.textView,
            characterRange: NSRange(location: 8, length: 1)
        )
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: startPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ),
            let mouseDragged = NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: endPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        else {
            Issue.record("Failed to create macOS mouse events")
            return
        }

        editorView.textView.mouseDown(with: mouseDown)
        editorView.textView.mouseDragged(with: mouseDragged)

        #expect(editorView.textView.selectedRange().location == 0)
        #expect(editorView.textView.selectedRange().length > 0)
    }

    @Test("SyntaxEditorView uses TextKit navigation for macOS movement commands")
    @MainActor
    func syntaxEditorViewMacUsesTextKitNavigationForMovementCommands() {
        let source = "abc def\nghi"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))

        editorView.textView.doCommand(by: #selector(NSResponder.moveWordRight(_:)))
        #expect(editorView.textView.selectedRange().location > 0)

        editorView.textView.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
        #expect(editorView.textView.selectedRange() == NSRange(location: 7, length: 0))

        editorView.textView.doCommand(by: #selector(NSResponder.moveToEndOfDocument(_:)))
        #expect(editorView.textView.selectedRange() == NSRange(location: source.utf16.count, length: 0))

        editorView.textView.doCommand(by: #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)))
        #expect(editorView.textView.selectedRange().location == 0)
        #expect(editorView.textView.selectedRange().length == source.utf16.count)
    }

    @Test("SyntaxEditorView read-only key equivalents do not mutate text on macOS")
    @MainActor
    func syntaxEditorViewMacReadOnlyKeyEquivalentsDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        editorView.textView.setSelectedRange(NSRange(location: 0, length: source.utf16.count))

        guard let lineWrappingEvent = makeMacCommandKeyEvent(
            "l",
            modifierFlags: [.control, .shift, .command]
        ) else {
            Issue.record("Failed to create line wrapping key event")
            return
        }

        #expect(editorView.textView.performKeyEquivalent(with: lineWrappingEvent))
        #expect(model.model.lineWrappingEnabled)
        #expect(editorView.textView.string == source)

        for (character, modifiers) in [
            ("+", NSEvent.ModifierFlags.command),
            ("-", NSEvent.ModifierFlags.command),
            ("0", NSEvent.ModifierFlags([.control, .command])),
        ] {
            guard let event = makeMacCommandKeyEvent(character, modifierFlags: modifiers) else {
                Issue.record("Failed to create font size key event for \(character)")
                continue
            }

            #expect(editorView.textView.performKeyEquivalent(with: event))
            #expect(model.model.text == source)
            #expect(editorView.textView.string == source)
        }

        for character in ["/", "]", "["] {
            guard let event = makeMacCommandKeyEvent(character) else {
                Issue.record("Failed to create command key event for \(character)")
                continue
            }

            _ = editorView.textView.performKeyEquivalent(with: event)
            #expect(model.model.text == source)
            #expect(editorView.textView.string == source)
        }
    }

    @Test("SyntaxEditorView toggles macOS line wrapping key equivalent")
    @MainActor
    func syntaxEditorViewMacToggleLineWrappingKeyEquivalent() {
        let model = SyntaxEditorTestContext(
            text: String(repeating: "let macHorizontalScrollNeedsWrapping = true; ", count: 8),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)

        guard let event = makeMacCommandKeyEvent(
            "l",
            modifierFlags: [.control, .shift, .command]
        ) else {
            Issue.record("Failed to create line wrapping key event")
            return
        }

        #expect(editorView.textView.performKeyEquivalent(with: event))
        #expect(model.model.lineWrappingEnabled)
        editorView.synchronizeDocumentForTesting()
        #expect(!editorView.hasHorizontalScroller)

        #expect(editorView.textView.performKeyEquivalent(with: event))
        #expect(!model.model.lineWrappingEnabled)
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.hasHorizontalScroller)
    }

    @Test("SyntaxEditorView applies macOS font size key equivalents")
    @MainActor
    func syntaxEditorViewMacFontSizeKeyEquivalents() {
        let model = SyntaxEditorTestContext(text: "let answer = 42", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)

        guard let increaseEvent = makeMacCommandKeyEvent("+"),
              let decreaseEvent = makeMacCommandKeyEvent("-"),
              let resetEvent = makeMacCommandKeyEvent("0", modifierFlags: [.control, .command])
        else {
            Issue.record("Failed to create font size key events")
            return
        }

        #expect(editorView.textView.performKeyEquivalent(with: increaseEvent))
        #expect(model.model.fontSizeDelta == 1)

        #expect(editorView.textView.performKeyEquivalent(with: decreaseEvent))
        #expect(model.model.fontSizeDelta == 0)

        model.model.fontSizeDelta = 5
        #expect(editorView.textView.performKeyEquivalent(with: resetEvent))
        #expect(model.model.fontSizeDelta == 0)
    }

    @Test("SyntaxEditorView uses native macOS undo stack for text input")
    @MainActor
    func syntaxEditorViewMacNativeTextInputUndoRedo() async {
        let source = "let answer = 42"
        let editedSource = "\(source)!"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = editorView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView.textView)
        defer { window.orderOut(nil) }

        guard let undoManager = editorView.textView.undoManager else {
            Issue.record("SyntaxEditorView text view has no undo manager")
            return
        }

        let editRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(editRange)
        editorView.textView.insertText("!", replacementRange: editRange)
        editorView.textView.breakUndoCoalescing()

        #expect(model.model.text == editedSource)
        #expect(editorView.textView.string == editedSource)

        let undoSelector = NSSelectorFromString("undo:")
        let redoSelector = NSSelectorFromString("redo:")
        let undoItem = NSMenuItem(title: "Undo", action: undoSelector, keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: redoSelector, keyEquivalent: "Z")

        #expect(undoManager.canUndo)
        #expect(editorView.textView.validateUserInterfaceItem(undoItem))

        model.model.isEditable = false
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.isEditable == false)
        #expect(!undoManager.canUndo)
        #expect(!editorView.textView.validateUserInterfaceItem(undoItem))

        #expect(NSApplication.shared.sendAction(undoSelector, to: editorView.textView, from: undoItem))
        #expect(model.model.text == editedSource)
        #expect(editorView.textView.string == editedSource)

        model.model.isEditable = true
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.isEditable == true)

        #expect(undoManager.canUndo)
        #expect(NSApplication.shared.sendAction(undoSelector, to: editorView.textView, from: undoItem))

        #expect(model.model.text == source)
        #expect(editorView.textView.string == source)
        #expect(undoManager.canRedo)
        #expect(editorView.textView.validateUserInterfaceItem(redoItem))
        #expect(NSApplication.shared.sendAction(redoSelector, to: editorView.textView, from: redoItem))

        #expect(model.model.text == editedSource)
        #expect(editorView.textView.string == editedSource)
    }

    @Test("SyntaxEditorView preserves undo history when undo manager runs while read-only on macOS")
    @MainActor
    func syntaxEditorViewMacReadOnlyUndoManagerPreservesHistory() async {
        let source = "let answer = 42"
        let onceIndentedSource = "    \(source)"
        let twiceIndentedSource = "        \(source)"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = editorView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView.textView)
        defer { window.orderOut(nil) }

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))

        guard let undoManager = editorView.textView.undoManager else {
            Issue.record("SyntaxEditorView text view has no undo manager")
            return
        }
        undoManager.groupsByEvent = false

        func runUndoGroupedCommand(_ action: () -> Bool) {
            undoManager.beginUndoGrouping()
            let handled = action()
            undoManager.endUndoGrouping()
            #expect(handled)
        }

        runUndoGroupedCommand {
            editorView.textView(
                editorView.textView,
                doCommandBy: #selector(NSResponder.insertTab(_:))
            )
        }
        runUndoGroupedCommand {
            editorView.textView(
                editorView.textView,
                doCommandBy: #selector(NSResponder.insertTab(_:))
            )
        }
        #expect(model.model.text == twiceIndentedSource)

        model.model.isEditable = false
        undoManager.undo()
        undoManager.undo()

        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)
        #expect(model.model.text == twiceIndentedSource)
        #expect(editorView.textView.string == twiceIndentedSource)

        model.model.isEditable = true

        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.model.text == onceIndentedSource)
        #expect(editorView.textView.string == onceIndentedSource)
        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.model.text == source)
        #expect(editorView.textView.string == source)
        #expect(undoManager.canRedo)

        model.model.isEditable = false
        undoManager.redo()
        undoManager.redo()

        #expect(model.model.text == source)
        #expect(editorView.textView.string == source)
        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)

        model.model.isEditable = true

        #expect(undoManager.canRedo)
        undoManager.redo()
        undoManager.redo()

        #expect(model.model.text == twiceIndentedSource)
        #expect(editorView.textView.string == twiceIndentedSource)
    }

    @Test("SyntaxEditorViewController enables undo support on macOS")
    @MainActor
    func syntaxEditorViewControllerMacUndo() {
        let model = SyntaxEditorTestContext(text: "{}", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()

        let textView = controller.textView
        #expect(textView.allowsUndo == true)
    }

    @Test("SyntaxEditorViewController renders source-of-truth state on macOS")
    @MainActor
    func syntaxEditorViewControllerMacRendersSourceOfTruthState() async {
        let model = SyntaxEditorTestContext(text: "{}", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()

        #expect(controller.model === model.model)
        #expect(controller.model === model.model)
        #expect(
            controller.textView(
                controller.textView,
                shouldChangeTextIn: NSRange(location: 0, length: 0),
                replacementString: "a"
            )
        )

        guard let delivery = controller.editorView.modelDeliveryForTesting else {
            Issue.record("Expected SyntaxEditorViewController to expose its production document delivery")
            return
        }
        let renderedText = await delivery.values {
            controller.textView.string
        }

        #expect(await renderedText.waitUntilValue("{}"))

        model.model.replaceText("{\"enabled\":true}")

        #expect(await renderedText.waitUntilValue("{\"enabled\":true}"))
    }

    @Test("SyntaxEditorViewController reflects document text replacements on macOS")
    @MainActor
    func syntaxEditorViewControllerMacTextObservation() async {
        let model = SyntaxEditorTestContext(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()
        guard let delivery = controller.editorView.modelDeliveryForTesting else {
            Issue.record("Expected SyntaxEditorViewController to expose its production document delivery")
            return
        }
        let renderedText = await delivery.values {
            controller.textView.string
        }

        #expect(await renderedText.waitUntilValue("const answer = 42;"))

        model.model.replaceText("{\"enabled\":true}")

        #expect(await renderedText.waitUntilValue("{\"enabled\":true}"))
    }

    @Test("SyntaxEditorViewController does not rerun macOS configuration observation for document changes")
    @MainActor
    func syntaxEditorViewControllerMacConfigurationObservationIgnoresDocumentChanges() async {
        let model = SyntaxEditorTestContext(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()
        guard let configurationDelivery = controller.editorView.modelConfigurationDeliveryForTesting,
              let documentDelivery = controller.editorView.modelDeliveryForTesting
        else {
            Issue.record("Expected SyntaxEditorViewController to expose its production deliveries")
            return
        }
        let configurationPassCounter = SyntaxEditorObservationPassCounter()
        let configurationPasses = await configurationDelivery.values {
            configurationPassCounter.next()
        }
        let renderedText = await documentDelivery.values {
            controller.textView.string
        }

        #expect(await configurationPasses.waitUntilValue(1))

        model.model.language = SyntaxLanguage.json

        #expect(await configurationPasses.waitUntilValue(2))

        model.model.replaceText("{\"enabled\":true}")

        #expect(await renderedText.waitUntilValue("{\"enabled\":true}"))
        await syntaxEditorDrainMainActorObservationDelivery(recording: configurationPasses)
        #expect(configurationPasses.snapshot() == [1, 2])
    }

    @Test("SyntaxEditorViewController reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacEditorStateObservation() async {
        let model = SyntaxEditorTestContext(text: "body {}", language: SyntaxLanguage.css)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()
        guard let delivery = controller.editorView.modelConfigurationDeliveryForTesting else {
            Issue.record("Expected SyntaxEditorViewController to expose its production configuration delivery")
            return
        }
        let renderedState = await delivery.values {
            SyntaxEditorRenderedEditorState(
                isEditable: controller.textView.isEditable,
                wrapsLines: controller.scrollView.hasHorizontalScroller == false
            )
        }

        model.model.isEditable = false
        model.model.lineWrappingEnabled = true

        #expect(
            await renderedState.waitUntilValue(
                SyntaxEditorRenderedEditorState(isEditable: false, wrapsLines: true)
            )
        )

        model.model.lineWrappingEnabled = false

        #expect(
            await renderedState.waitUntilValue(
                SyntaxEditorRenderedEditorState(isEditable: false, wrapsLines: false)
            )
        )
    }

    @Test("SyntaxEditorViewController keeps synchronizing after language changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacLanguageChangeKeepsObservationAlive() async {
        let model = SyntaxEditorTestContext(text: "let answer = 42", language: SyntaxLanguage.swift)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()

        model.model.language = SyntaxLanguage.json
        model.model.isEditable = false

        controller.synchronizeDocumentForTesting()
        #expect(controller.textView.isEditable == false)

        model.model.replaceText("{\"answer\":42}")

        controller.synchronizeDocumentForTesting()
        #expect(controller.textView.string == "{\"answer\":42}")
    }
}
#endif
