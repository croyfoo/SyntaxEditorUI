import Foundation
import Observation
import Testing
@testable import SyntaxEditorUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

private func requireObservable<T: Observable>(_ value: T) {}

private func syntaxEditorUITestColor(hex: UInt32) -> SyntaxEditorColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255.0
    let green = CGFloat((hex >> 8) & 0xFF) / 255.0
    let blue = CGFloat(hex & 0xFF) / 255.0

#if canImport(UIKit)
    return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
#elseif canImport(AppKit)
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
#endif
}

private func syntaxEditorUITestColorTheme(
    baseForeground: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x101112),
    bracketBackground: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x202122),
    comment: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x303132),
    string: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x404142),
    keyword: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x505152),
    number: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x606162),
    function: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x707172),
    type: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x808182),
    constant: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0x909192),
    variable: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0xA0A1A2),
    punctuation: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0xB0B1B2)
) -> SyntaxEditorColorTheme {
    SyntaxEditorColorTheme(
        baseForeground: baseForeground,
        bracketBackground: bracketBackground,
        comment: comment,
        string: string,
        keyword: keyword,
        number: number,
        function: function,
        type: type,
        constant: constant,
        variable: variable,
        punctuation: punctuation
    )
}

private func syntaxEditorUITestColorsEqual(_ lhs: SyntaxEditorColor?, _ rhs: SyntaxEditorColor) -> Bool {
    guard let lhs else { return false }

#if canImport(UIKit)
    var lhsRed: CGFloat = 0
    var lhsGreen: CGFloat = 0
    var lhsBlue: CGFloat = 0
    var lhsAlpha: CGFloat = 0
    var rhsRed: CGFloat = 0
    var rhsGreen: CGFloat = 0
    var rhsBlue: CGFloat = 0
    var rhsAlpha: CGFloat = 0

    guard lhs.getRed(&lhsRed, green: &lhsGreen, blue: &lhsBlue, alpha: &lhsAlpha),
          rhs.getRed(&rhsRed, green: &rhsGreen, blue: &rhsBlue, alpha: &rhsAlpha)
    else {
        return lhs.isEqual(rhs)
    }
#elseif canImport(AppKit)
    guard let lhs = lhs.usingColorSpace(.genericRGB),
          let rhs = rhs.usingColorSpace(.genericRGB)
    else {
        return lhs.isEqual(rhs)
    }

    let lhsRed = lhs.redComponent
    let lhsGreen = lhs.greenComponent
    let lhsBlue = lhs.blueComponent
    let lhsAlpha = lhs.alphaComponent
    let rhsRed = rhs.redComponent
    let rhsGreen = rhs.greenComponent
    let rhsBlue = rhs.blueComponent
    let rhsAlpha = rhs.alphaComponent
#endif

    return abs(lhsRed - rhsRed) < 0.002
        && abs(lhsGreen - rhsGreen) < 0.002
        && abs(lhsBlue - rhsBlue) < 0.002
        && abs(lhsAlpha - rhsAlpha) < 0.002
}

private actor SyntaxEditorUITestHighlighter: SyntaxHighlighting {
    private let tokens: [SyntaxHighlightToken]
    private let delayNanoseconds: UInt64
    private var resetCount = 0
    private var updateCount = 0

    init(tokens: [SyntaxHighlightToken] = [], delayNanoseconds: UInt64 = 0) {
        self.tokens = tokens
        self.delayNanoseconds = delayNanoseconds
    }

    func reset(source: String, language: SyntaxLanguage) async -> SyntaxHighlightResult {
        resetCount += 1
        await delayIfNeeded()
        return result(source: source, language: language)
    }

    func update(
        previousSource: String,
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation
    ) async -> SyntaxHighlightResult {
        updateCount += 1
        await delayIfNeeded()
        return result(source: source, language: language)
    }

    func callCount() -> Int {
        resetCount + updateCount
    }

    private func delayIfNeeded() async {
        guard delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }

    private func result(source: String, language: SyntaxLanguage) -> SyntaxHighlightResult {
        SyntaxHighlightResult(
            tokens: tokens,
            source: source,
            language: language,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }
}

#if canImport(UIKit)
private let syntaxEditorKeyCommandModifierMask: UIKeyModifierFlags = [
    .command,
    .control,
    .alternate,
    .shift,
]

@MainActor
private func hasSyntaxEditorKeyCommand(
    _ commands: [UIKeyCommand]?,
    input: String,
    modifierFlags: UIKeyModifierFlags
) -> Bool {
    commands?.contains { command in
        command.input == input
            && command.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == modifierFlags
    } ?? false
}

@MainActor
@discardableResult
private func performSyntaxEditorSelector(_ selectorName: String, on view: SyntaxEditorView) -> Bool {
    let selector = NSSelectorFromString(selectorName)
    guard view.responds(to: selector) else {
        Issue.record("SyntaxEditorView does not respond to \(selectorName)")
        return false
    }

    _ = view.perform(selector)
    return true
}

private let longIOSSyntaxEditorLine = String(
    repeating: "let extremelyLongIdentifierName = syntaxEditorHorizontalScrollValue; ",
    count: 4
)

private let longIOSSyntaxEditorMultilineText = """
const answer = 42;
function greet(name) {
    \(String(repeating: "return HelloName; ", count: 10))
}
"""

private let visibleMidIOSSyntaxEditorLocation = 20

private final class SyntaxEditorUITestInputDelegate: NSObject, UITextInputDelegate {
    var textWillChangeCount = 0
    var textDidChangeCount = 0
    var selectionWillChangeCount = 0
    var selectionDidChangeCount = 0
    var textDidChangeHandler: (((any UITextInput)?) -> Void)?

    func textWillChange(_ textInput: (any UITextInput)?) {
        textWillChangeCount += 1
    }

    func textDidChange(_ textInput: (any UITextInput)?) {
        textDidChangeCount += 1
        textDidChangeHandler?(textInput)
    }

    func selectionWillChange(_ textInput: (any UITextInput)?) {
        selectionWillChangeCount += 1
    }

    func selectionDidChange(_ textInput: (any UITextInput)?) {
        selectionDidChangeCount += 1
    }

    @available(iOS 18.4, *)
    func conversationContext(_ context: UIConversationContext?, didChange textInput: (any UITextInput)?) {}
}

private final class SyntaxEditorUITestForeignTextPosition: UITextPosition {}

private let offscreenWideIOSSyntaxEditorText: String = {
    let leadingShortLines = (0..<20).map { "let short\($0) = true;" }
    let wideLine = [String(repeating: "let offscreenHorizontalScrollRange = value; ", count: 24)]
    let trailingShortLines = (20..<60).map { "let short\($0) = false;" }
    return (leadingShortLines + wideLine + trailingShortLines).joined(separator: "\n")
}()

private let offscreenWideUnicodeIOSSyntaxEditorLine = String(repeating: "漢字🙂", count: 80)

private let offscreenWideUnicodeIOSSyntaxEditorText: String = {
    let leadingShortLines = (0..<20).map { "let short\($0) = true;" }
    let trailingShortLines = (20..<60).map { "let short\($0) = false;" }
    return (leadingShortLines + [offscreenWideUnicodeIOSSyntaxEditorLine] + trailingShortLines)
        .joined(separator: "\n")
}()

@MainActor
private func layoutIOSEditorView(
    _ editorView: SyntaxEditorView,
    width: CGFloat = 160,
    height: CGFloat = 120
) {
    editorView.frame = CGRect(x: 0, y: 0, width: width, height: height)
    editorView.setNeedsLayout()
    editorView.layoutIfNeeded()
}

@MainActor
private func iOSEditorHasHorizontalOverflow(_ editorView: SyntaxEditorView) -> Bool {
    layoutIOSEditorView(editorView)
    return !editorView.textContainer.widthTracksTextView
        && editorView.contentSize.width > editorView.bounds.width + 1
        && editorView.textContainer.size.width > editorView.bounds.width
}

@MainActor
private func iOSEditorHorizontalOverflowDiagnostics(_ editorView: SyntaxEditorView) -> String {
    layoutIOSEditorView(editorView)
    return "widthTracksTextView=\(editorView.textContainer.widthTracksTextView) "
        + "contentSize=\(editorView.contentSize) "
        + "bounds=\(editorView.bounds) "
        + "textContainer.size=\(editorView.textContainer.size) "
        + "lineBreakMode=\(String(describing: iOSEditorLineBreakMode(editorView)))"
}

@MainActor
private func iOSEditorRenderedContentFrame(_ editorView: SyntaxEditorView) -> CGRect? {
    let frame = editorView.renderedTextContentFrameForTesting
    guard frame.width > 0 else { return nil }

    return frame
}

@MainActor
private func iOSEditorTextUsageHeight(_ editorView: SyntaxEditorView) -> CGFloat {
    (editorView.textLayoutManager?.usageBoundsForTextContainer.maxY ?? 0)
        + editorView.textContainerInset.top
        + editorView.textContainerInset.bottom
}

@MainActor
private func iOSEditorVisibleTextContainerRect(_ editorView: SyntaxEditorView) -> CGRect {
    CGRect(
        x: max(0, editorView.contentOffset.x - editorView.textContainerInset.left),
        y: max(0, editorView.contentOffset.y - editorView.textContainerInset.top),
        width: min(
            editorView.textContainer.size.width,
            editorView.bounds.width + editorView.textContainerInset.left + editorView.textContainerInset.right
        ),
        height: editorView.bounds.height
            + editorView.textContainerInset.top
            + editorView.textContainerInset.bottom
    )
}

@MainActor
private func iOSEditorTextKit2UsageBoundsCoverVisibleHorizontalViewport(_ editorView: SyntaxEditorView) -> Bool {
    guard let textLayoutManager = editorView.textLayoutManager else {
        return false
    }

    let visibleRect = iOSEditorVisibleTextContainerRect(editorView)
    textLayoutManager.ensureLayout(for: visibleRect)

    return textLayoutManager.usageBoundsForTextContainer.maxX >= visibleRect.maxX - 1
}

@MainActor
private func iOSEditorTextKit2Diagnostics(_ editorView: SyntaxEditorView) -> String {
    let visibleRect = iOSEditorVisibleTextContainerRect(editorView)
    let usageBounds = editorView.textLayoutManager?.usageBoundsForTextContainer ?? .null
    return "textLayoutManager=\(String(describing: editorView.textLayoutManager)) "
        + "offset=\(editorView.contentOffset) "
        + "bounds=\(editorView.bounds) "
        + "contentSize=\(editorView.contentSize) "
        + "textContainer.size=\(editorView.textContainer.size) "
        + "visibleTextContainerRect=\(visibleRect) "
        + "usageBounds=\(usageBounds)"
}

@MainActor
private func iOSEditorHasBackgroundAttribute(_ editorView: SyntaxEditorView, at location: Int) -> Bool {
    editorView.bracketHighlightRangesForTesting.contains { NSLocationInRange(location, $0) }
}

@MainActor
private func iOSEditorForegroundColor(_ editorView: SyntaxEditorView, at location: Int) -> UIColor? {
    guard let attributedText = editorView.attributedText,
          location >= 0,
          location < attributedText.length
    else {
        return nil
    }

    return attributedText.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor
}

@MainActor
private func iOSEditorLineBreakMode(_ editorView: SyntaxEditorView, at location: Int = 0) -> NSLineBreakMode? {
    guard let attributedText = editorView.attributedText,
          location >= 0,
          location < attributedText.length
    else {
        return nil
    }

    return (attributedText.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?
        .lineBreakMode
}

@MainActor
private func iOSEditorUnderlineStyle(_ editorView: SyntaxEditorView, at location: Int) -> Int? {
    guard let attributedText = editorView.attributedText,
          location >= 0,
          location < attributedText.length
    else {
        return nil
    }

    let value = attributedText.attribute(.underlineStyle, at: location, effectiveRange: nil)
    if let number = value as? NSNumber {
        return number.intValue
    }
    return value as? Int
}

@MainActor
private func iOSEditorUnderlineColor(_ editorView: SyntaxEditorView, at location: Int) -> UIColor? {
    guard let attributedText = editorView.attributedText,
          location >= 0,
          location < attributedText.length
    else {
        return nil
    }

    return attributedText.attribute(.underlineColor, at: location, effectiveRange: nil) as? UIColor
}

#endif

#if canImport(AppKit)
private func requireNSTextViewDelegate(_ value: any NSTextViewDelegate) {}

@MainActor
private func macEditorForegroundColor(_ editorView: SyntaxEditorView, at location: Int) -> NSColor? {
    guard let textStorage = editorView.textView.textStorage else {
        return nil
    }
    guard location >= 0,
          location < textStorage.length
    else {
        return nil
    }

    return textStorage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
}

private func makeMacCommandKeyEvent(_ character: String) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: character,
        charactersIgnoringModifiers: character,
        isARepeat: false,
        keyCode: 0
    )
}
#endif

@Suite("SyntaxEditorUI")
struct SyntaxEditorUITests {
#if canImport(UIKit)
    @Test("SyntaxEditorViewController preserves Observable conformance on iOS")
    @MainActor
    func syntaxEditorViewControllerIOSObservableCompatibility() {
        let model = SyntaxEditorModel(text: "{}", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(model: model)

        requireObservable(controller)
        #expect(controller.model === model)
        #expect(controller.editorView.model === model)
    }

    @Test("SyntaxEditorView is the iOS custom scroll text input surface")
    @MainActor
    func syntaxEditorViewIOSUsesCustomScrollTextInputSurface() {
        let editorView = SyntaxEditorView(model: SyntaxEditorModel(text: "let value = 1"))
        let scrollSurface: UIScrollView = editorView
        let textInputSurface: any UITextInput = editorView

        #expect(scrollSurface === editorView)
        #expect(textInputSurface.textInputView === editorView)
    }

    @Test("SyntaxEditorView receives iOS text interaction hit tests through the rendering view")
    @MainActor
    func syntaxEditorViewIOSReceivesTextInteractionHitTestsThroughRenderingView() {
        let editorView = SyntaxEditorView(model: SyntaxEditorModel(text: "let value = 1"))
        layoutIOSEditorView(editorView)

        let hitView = editorView.hitTest(CGPoint(x: 24, y: 24), with: nil)

        #expect(hitView === editorView)
    }

    @Test("SyntaxEditorView applies transformed iOS text input to the model")
    @MainActor
    func syntaxEditorViewIOSAppliesTransformedTextInputToModel() {
        let model = SyntaxEditorModel(text: "", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.insertText("{")
        #expect(editorView.text == "{}")
        #expect(model.text == "{}")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))

        editorView.insertText("\n")
        #expect(editorView.text == "{\n    \n}")
        #expect(model.text == "{\n    \n}")
        #expect(editorView.selectedRange == NSRange(location: 6, length: 0))
    }

    @Test("SyntaxEditorView notifies the iOS input delegate for transformed text input")
    @MainActor
    func syntaxEditorViewIOSNotifiesInputDelegateForTransformedTextInput() {
        let model = SyntaxEditorModel(text: "", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(model: model)
        let inputDelegate = SyntaxEditorUITestInputDelegate()
        editorView.inputDelegate = inputDelegate
        layoutIOSEditorView(editorView)

        editorView.insertText("{")

        #expect(inputDelegate.textWillChangeCount == 1)
        #expect(inputDelegate.textDidChangeCount == 1)
        #expect(inputDelegate.selectionWillChangeCount == 1)
        #expect(inputDelegate.selectionDidChangeCount == 1)
    }

    @Test("SyntaxEditorView handles iOS candidate alternative text input")
    @MainActor
    func syntaxEditorViewIOSHandlesCandidateAlternativeTextInput() {
        let source = "let value ="
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        #expect(editorView.responds(to: NSSelectorFromString("insertText:alternatives:style:")))
        editorView.insertText(" ", alternatives: [], style: .none)

        #expect(editorView.text == source + " ")
        #expect(model.text == source + " ")
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("SyntaxEditorView underlines active iOS marked text")
    @MainActor
    func syntaxEditorViewIOSUnderlinesActiveMarkedText() {
        let model = SyntaxEditorModel(text: "let value = ", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        let markedTextColor = syntaxEditorUITestColor(hex: 0xFF8800)
        editorView.tintColor = markedTextColor
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: model.text.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))

        let markedLocation = "let value = ".utf16.count
        #expect(editorView.markedTextRange != nil)
        #expect(iOSEditorUnderlineStyle(editorView, at: markedLocation) == NSUnderlineStyle.single.rawValue)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorUnderlineColor(editorView, at: markedLocation), markedTextColor))

        editorView.unmarkText()

        #expect(editorView.markedTextRange == nil)
        #expect(iOSEditorUnderlineStyle(editorView, at: markedLocation) == nil)
    }

    @Test("SyntaxEditorView scrolls iOS marked text using the final IME selection")
    @MainActor
    func syntaxEditorViewIOSScrollsMarkedTextUsingFinalIMESelection() {
        let source = "let value = "
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 160, height: 120)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        let stableOffsetX = editorView.contentOffset.x
        editorView.setMarkedText(
            String(repeating: "かな", count: 80),
            selectedRange: NSRange(location: 0, length: 2)
        )
        layoutIOSEditorView(editorView, width: 160, height: 120)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count, length: 2))
    }

    @Test("SyntaxEditorView registers iOS undo for committed marked text")
    @MainActor
    func syntaxEditorViewIOSRegistersUndoForCommittedMarkedText() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        editorView.unmarkText()

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(editorView.text == source)
        #expect(model.text == source)
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count, length: 0))
    }

    @Test("SyntaxEditorView registers iOS undo for empty marked text replacement")
    @MainActor
    func syntaxEditorViewIOSRegistersUndoForEmptyMarkedTextReplacement() {
        let source = "let value = 42"
        let selectedRange = (source as NSString).range(of: "value")
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = selectedRange

        editorView.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(editorView.text == "let  = 42")
        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(editorView.text == source)
        #expect(model.text == source)
        #expect(editorView.selectedRange == selectedRange)
    }

    @Test("SyntaxEditorView replaces iOS marked text when IME commits through insertText")
    @MainActor
    func syntaxEditorViewIOSReplacesMarkedTextWhenIMECommitsThroughInsertText() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("あいうえお", selectedRange: NSRange(location: 5, length: 0))
        editorView.insertText("作成")

        let committedSource = source + "作成"
        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == committedSource)
        #expect(model.text == committedSource)
        #expect(editorView.selectedRange == NSRange(location: committedSource.utf16.count, length: 0))

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(editorView.text == source)
        #expect(model.text == source)
    }

    @Test("SyntaxEditorView clears iOS marked text before normal insertion after IME commit")
    @MainActor
    func syntaxEditorViewIOSClearsMarkedTextBeforeNormalInsertionAfterIMECommit() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("あいうえお", selectedRange: NSRange(location: 5, length: 0))
        editorView.insertText("作成")
        editorView.insertText("!")

        let expectedSource = source + "作成!"
        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == expectedSource)
        #expect(model.text == expectedSource)
        #expect(editorView.selectedRange == NSRange(location: expectedSource.utf16.count, length: 0))
    }

    @Test("SyntaxEditorView preserves iOS marked text when nil unmarks composition")
    @MainActor
    func syntaxEditorViewIOSPreservesMarkedTextWhenNilUnmarksComposition() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        editorView.setMarkedText(nil, selectedRange: NSRange(location: 0, length: 0))

        let expectedText = source + "かな"
        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == expectedText)
        #expect(model.text == expectedText)
        #expect(editorView.selectedRange == NSRange(location: expectedText.utf16.count, length: 0))
    }

    @Test("SyntaxEditorView clears iOS marked text when selection leaves composition")
    @MainActor
    func syntaxEditorViewIOSClearsMarkedTextWhenSelectionLeavesComposition() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        editorView.selectedTextRange = editorView.textRange(
            from: editorView.beginningOfDocument,
            to: editorView.beginningOfDocument
        )
        editorView.insertText("X")

        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == "X" + source + "かな")
        #expect(model.text == "X" + source + "かな")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView clears iOS marked text when selectedRange leaves composition")
    @MainActor
    func syntaxEditorViewIOSClearsMarkedTextWhenSelectedRangeLeavesComposition() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        editorView.selectedRange = NSRange(location: 0, length: 0)
        editorView.insertText("X")

        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == "X" + source + "かな")
        #expect(model.text == "X" + source + "かな")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView does not commit iOS marked text while read-only")
    @MainActor
    func syntaxEditorViewIOSDoesNotCommitMarkedTextWhileReadOnly() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        model.isEditable = false
        editorView.synchronizeModelForTesting()
        editorView.insertText("作成")

        #expect(editorView.text == source + "かな")
        #expect(model.text == source + "かな")
        #expect(editorView.markedTextRange != nil)
    }

    @Test("SyntaxEditorView coalesces repeated iOS marked text updates into one undo")
    @MainActor
    func syntaxEditorViewIOSCoalescesRepeatedMarkedTextUpdatesIntoOneUndo() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0))
        editorView.setMarkedText("あい", selectedRange: NSRange(location: 2, length: 0))
        editorView.setMarkedText("あいう", selectedRange: NSRange(location: 3, length: 0))
        editorView.unmarkText()

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(editorView.text == source + "あいう")
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(editorView.text == source)
        #expect(!undoManager.canUndo)
    }

    @Test("SyntaxEditorView clears stale iOS marked text undo anchors after normal edits")
    @MainActor
    func syntaxEditorViewIOSClearsStaleMarkedTextUndoAnchorsAfterNormalEdits() {
        let source = "let value = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        editorView.deleteBackward()

        let textAfterInterruptedComposition = editorView.text
        let selectionAfterInterruptedComposition = editorView.selectedRange
        #expect(textAfterInterruptedComposition == source + "か")
        #expect(editorView.markedTextRange == nil)
        editorView.undoManager?.removeAllActions()

        editorView.setMarkedText("字", selectedRange: NSRange(location: 1, length: 0))
        editorView.unmarkText()

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(editorView.text == source + "か字")
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(editorView.text == textAfterInterruptedComposition)
        #expect(editorView.selectedRange == selectionAfterInterruptedComposition)
    }

    @Test("SyntaxEditorView deletes a complete iOS composed character backward")
    @MainActor
    func syntaxEditorViewIOSDeletesCompleteComposedCharacterBackward() {
        let source = "a🙂b"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: ("a🙂" as NSString).length, length: 0)

        editorView.deleteBackward()

        #expect(editorView.text == "ab")
        #expect(model.text == "ab")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView preserves iOS UTF-16 position round trips")
    @MainActor
    func syntaxEditorViewIOSPreservesUTF16PositionRoundTrips() {
        let source = "🙂"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        guard let endPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: source.utf16.count
        )
        else {
            Issue.record("SyntaxEditorView could not move to the UTF-16 end offset")
            return
        }

        #expect(editorView.offset(from: editorView.beginningOfDocument, to: endPosition) == source.utf16.count)
        #expect(editorView.position(from: editorView.beginningOfDocument, offset: 1) == nil)
    }

    @Test("SyntaxEditorView returns iOS composed character ranges")
    @MainActor
    func syntaxEditorViewIOSReturnsComposedCharacterRanges() {
        let source = "a🙂e\u{301}b"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        let afterAOffset = ("a" as NSString).length
        let afterEmojiOffset = ("a🙂" as NSString).length
        let beforeCombiningCharacterOffset = afterEmojiOffset
        guard let afterA = editorView.position(from: editorView.beginningOfDocument, offset: afterAOffset),
              let afterEmoji = editorView.position(from: editorView.beginningOfDocument, offset: afterEmojiOffset),
              let emojiRange = editorView.characterRange(byExtending: afterA, in: .right),
              let previousEmojiRange = editorView.characterRange(byExtending: afterEmoji, in: .left),
              let combiningRange = editorView.characterRange(
                  byExtending: SyntaxEditorTextPosition(offset: beforeCombiningCharacterOffset),
                  in: .right
              )
        else {
            Issue.record("SyntaxEditorView could not build composed character ranges")
            return
        }

        #expect(editorView.text(in: emojiRange) == "🙂")
        #expect(editorView.text(in: previousEmojiRange) == "🙂")
        #expect(editorView.text(in: combiningRange) == "e\u{301}")
    }

    @Test("SyntaxEditorView preserves iOS command state through delayed selection callbacks")
    @MainActor
    func syntaxEditorViewIOSPreservesCommandStateThroughDelayedSelectionCallbacks() {
        let source = "description = "
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.toml)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.insertText("\"")
        #expect(editorView.text == source + "\"\"")
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))

        editorView.insertText("\"")
        #expect(editorView.text == source + "\"\"")
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count + 2, length: 0))

        editorView.insertText("\"")

        #expect(editorView.text == source + "\"\"\"")
        #expect(model.text == source + "\"\"\"")
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count + 3, length: 0))
    }

    @Test("SyntaxEditorView reflects model text mutations on iOS")
    @MainActor
    func syntaxEditorViewIOSTextObservation() async {
        let model = SyntaxEditorModel(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(model: model)

        model.text = "{\"enabled\":true}"

        editorView.synchronizeModelForTesting()
        #expect(editorView.text == "{\"enabled\":true}")
    }

    @Test("SyntaxEditorView reflects custom iOS color theme")
    @MainActor
    func syntaxEditorViewIOSColorThemeObservation() async {
        let source = "let value = \"text\""
        let initialTheme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456)
        )
        let updatedTheme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter()
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let editorView = SyntaxEditorView(model: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.colorTheme = updatedTheme

        editorView.synchronizeModelForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
    }

    @Test("SyntaxEditorView reapplies cached iOS syntax colors without highlighting")
    @MainActor
    func syntaxEditorViewIOSColorThemeReusesCachedHighlightTokens() async {
        let source = "let value = \"text\""
        let initialTheme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let updatedTheme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x654321),
            keyword: syntaxEditorUITestColor(hex: 0x876543)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxHighlightToken(
                    range: NSRange(location: 0, length: 3),
                    captureName: "keyword"
                ),
            ]
        )
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let editorView = SyntaxEditorView(model: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), initialTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.colorTheme = updatedTheme

        editorView.synchronizeModelForTesting()
        #expect(
            syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), updatedTheme.keyword)
                && syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground)
        )
        await editorView.waitForPendingHighlightForTesting()
        #expect(await highlighter.callCount() == initialCallCount)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
    }

    @Test("SyntaxEditorView preserves cached iOS syntax colors after font changes")
    @MainActor
    func syntaxEditorViewIOSFontChangePreservesCachedHighlightTokens() async {
        let source = "let value = \"text\""
        let theme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxHighlightToken(
                    range: NSRange(location: 0, length: 3),
                    captureName: "keyword"
                ),
            ]
        )
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(model: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()

        editorView.font = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)

        #expect(await highlighter.callCount() == initialCallCount)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), theme.baseForeground))
    }

    @Test("SyntaxEditorView reflects editable and wrapping changes on iOS")
    @MainActor
    func syntaxEditorViewIOSEditorStateObservation() async {
        let model = SyntaxEditorModel(text: longIOSSyntaxEditorLine, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        model.isEditable = false
        model.lineWrappingEnabled = true

        editorView.synchronizeModelForTesting()
        #expect(
            editorView.isEditable == false
                && editorView.textContainer.widthTracksTextView
        )
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(editorView.contentSize.height > editorView.bounds.height + 1)
        #expect(iOSEditorLineBreakMode(editorView) == .byCharWrapping)

        model.lineWrappingEnabled = false

        editorView.synchronizeModelForTesting()
        #expect(!editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)
        #expect(editorView.textContainer.size.width > editorView.bounds.width)
        #expect(iOSEditorLineBreakMode(editorView) == .byClipping)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        model.lineWrappingEnabled = true

        editorView.synchronizeModelForTesting()
        #expect(editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
    }

    @Test("SyntaxEditorView keeps empty no-wrap iOS content width tied to bounds")
    @MainActor
    func syntaxEditorViewIOSEmptyNoWrapContentWidthTracksBounds() {
        let model = SyntaxEditorModel(
            text: "",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)

        layoutIOSEditorView(editorView, width: 600, height: 240)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        layoutIOSEditorView(editorView, width: 240, height: 240)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
    }

    @Test("SyntaxEditorView preserves iOS syntax colors after editor state changes")
    @MainActor
    func syntaxEditorViewIOSEditorStateDoesNotResetSyntaxColors() async {
        let source = "let value = \"text\""
        let theme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        await editorView.waitForPendingHighlightForTesting()

        editorView.textStorage.addAttribute(
            .foregroundColor,
            value: theme.keyword,
            range: NSRange(location: 0, length: 3)
        )
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.lineWrappingEnabled = true

        editorView.synchronizeModelForTesting()
        #expect(editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.isEditable = false

        editorView.synchronizeModelForTesting()
        #expect(editorView.isEditable == false)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView enables horizontal scrolling for initial long iOS line")
    @MainActor
    func syntaxEditorViewIOSInitialLongLineScrollsHorizontally() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)

        layoutIOSEditorView(editorView)
        #expect(iOSEditorHasHorizontalOverflow(editorView))
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)
    }

    @Test("SyntaxEditorView includes offscreen iOS lines in initial horizontal scroll range")
    @MainActor
    func syntaxEditorViewIOSInitialOffscreenLongLineSetsHorizontalScrollRange() {
        let model = SyntaxEditorModel(
            text: offscreenWideIOSSyntaxEditorText,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)

        layoutIOSEditorView(editorView, width: 160, height: 120)
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)

        let maxOffsetX = max(0, editorView.contentSize.width - editorView.bounds.width)
        #expect(maxOffsetX > 0)

        editorView.setContentOffset(CGPoint(x: maxOffsetX, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 160, height: 120)
        #expect(editorView.contentOffset.x > 0)
    }

    @Test("SyntaxEditorView accounts for offscreen wide unicode iOS lines in horizontal scroll range")
    @MainActor
    func syntaxEditorViewIOSInitialOffscreenWideUnicodeLineSetsHorizontalScrollRange() {
        let model = SyntaxEditorModel(
            text: offscreenWideUnicodeIOSSyntaxEditorText,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)

        layoutIOSEditorView(editorView, width: 160, height: 120)
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)

        let measuredLineWidth = (offscreenWideUnicodeIOSSyntaxEditorLine as NSString).size(
            withAttributes: [.font: editorView.font]
        ).width
        #expect(editorView.contentSize.width >= measuredLineWidth)

        editorView.setContentOffset(
            CGPoint(x: max(0, editorView.contentSize.width - editorView.bounds.width), y: 0),
            animated: false
        )
        layoutIOSEditorView(editorView, width: 160, height: 120)
        #expect(editorView.contentOffset.x > 0)
    }

    @Test("SyntaxEditorView keeps TextKit 2 layout covering iOS horizontal scroll")
    @MainActor
    func syntaxEditorViewIOSTextKit2LayoutCoversHorizontalScrollViewport() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.contentSize.width > editorView.bounds.width + 1)
        #expect(editorView.textLayoutManager != nil)

        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let visibleRightEdge = editorView.contentOffset.x + editorView.bounds.width
        guard let renderedContentFrame = iOSEditorRenderedContentFrame(editorView) else {
            Issue.record("SyntaxEditorView does not expose a rendered content frame")
            return
        }

        #expect(renderedContentFrame.width >= editorView.contentSize.width - 1)
        #expect(renderedContentFrame.maxX >= visibleRightEdge - 1)
        #expect(
            iOSEditorTextKit2UsageBoundsCoverVisibleHorizontalViewport(editorView),
            Comment(rawValue: iOSEditorTextKit2Diagnostics(editorView))
        )
    }

    @Test("SyntaxEditorView keeps TextKit 2 layout covering iOS horizontal scroll after wrapping toggle")
    @MainActor
    func syntaxEditorViewIOSTextKit2LayoutCoversHorizontalScrollAfterWrappingToggle() async {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 504, height: 1104)

        #expect(editorView.textContainer.widthTracksTextView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(iOSEditorLineBreakMode(editorView) == .byCharWrapping)

        model.lineWrappingEnabled = false

        editorView.synchronizeModelForTesting()
        #expect(!editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView, width: 504, height: 1104)
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)
        #expect(editorView.textLayoutManager != nil)
        #expect(iOSEditorLineBreakMode(editorView) == .byClipping)

        let maxOffsetX = max(0, editorView.contentSize.width - editorView.bounds.width)
        for fraction in [0.25, 0.5, 0.75] {
            editorView.setContentOffset(CGPoint(x: maxOffsetX * fraction, y: 0), animated: false)
            layoutIOSEditorView(editorView, width: 504, height: 1104)

            guard let renderedContentFrame = iOSEditorRenderedContentFrame(editorView) else {
                Issue.record("SyntaxEditorView does not expose a rendered content frame")
                return
            }
            let visibleRightEdge = editorView.contentOffset.x + editorView.bounds.width

            #expect(editorView.contentOffset.x > 0)
            #expect(renderedContentFrame.width >= editorView.contentSize.width - 1)
            #expect(renderedContentFrame.maxX >= visibleRightEdge - 1)
            #expect(
                iOSEditorTextKit2UsageBoundsCoverVisibleHorizontalViewport(editorView),
                Comment(rawValue: iOSEditorTextKit2Diagnostics(editorView))
            )
        }
    }

    @Test("SyntaxEditorView keeps long iOS lines unwrapped while horizontally scrollable")
    @MainActor
    func syntaxEditorViewIOSNoWrapKeepsLongLinesUnwrapped() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.contentSize.width > editorView.bounds.width + 1)
        #expect(iOSEditorTextUsageHeight(editorView) <= 120)

        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.contentOffset.x > 0)
        #expect(iOSEditorTextUsageHeight(editorView) <= 120)
        #expect(editorView.textLayoutManager != nil)
        #expect(
            iOSEditorTextKit2UsageBoundsCoverVisibleHorizontalViewport(editorView),
            Comment(rawValue: iOSEditorTextKit2Diagnostics(editorView))
        )
    }

    @Test("SyntaxEditorView does not jump to the iOS line end when a visible long range is selected")
    @MainActor
    func syntaxEditorViewIOSVisibleLongRangeSelectionDoesNotJumpToLineEnd() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let stableOffsetX: CGFloat = 240
        editorView.setContentOffset(CGPoint(x: stableOffsetX, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let position = editorView.closestPosition(to: CGPoint(x: editorView.bounds.midX, y: 54)) else {
            Issue.record("SyntaxEditorView could not resolve a visible iOS text-input point")
            return
        }
        let location = editorView.offset(from: editorView.beginningOfDocument, to: position)
        editorView.selectedRange = NSRange(location: location, length: 0)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
        #expect(editorView.textLayoutManager != nil)
        #expect(
            iOSEditorTextKit2UsageBoundsCoverVisibleHorizontalViewport(editorView),
            Comment(rawValue: iOSEditorTextKit2Diagnostics(editorView))
        )
    }

    @Test("SyntaxEditorView snaps iOS trailing line whitespace taps to that line end")
    @MainActor
    func syntaxEditorViewIOSSnapsTrailingLineWhitespaceTapToLineEnd() {
        let source = "const answer = 42;\nfunction greet(name) {}"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = (source as NSString).range(of: "\n").location
        guard let lineEndPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: firstLineEnd
        ) else {
            Issue.record("SyntaxEditorView could not resolve the first line end")
            return
        }

        let lineEndRect = editorView.caretRect(for: lineEndPosition)
        guard let snappedPosition = editorView.closestPosition(
            to: CGPoint(x: lineEndRect.maxX + 96, y: lineEndRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve trailing line whitespace")
            return
        }

        #expect(editorView.offset(from: editorView.beginningOfDocument, to: snappedPosition) == firstLineEnd)
    }

    @Test("SyntaxEditorView keeps iOS drag hit testing on the touched visual line")
    @MainActor
    func syntaxEditorViewIOSKeepsDragHitTestingOnTouchedVisualLine() {
        let longLine = "    return "
            + String(repeating: "\"Hello, ${name}! \", ", count: 36)
        let source = [
            "const answer = 42;",
            "function greet(name) {",
            longLine,
            "}",
            "const again = 42;",
        ].joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let touchedLineStart = (source as NSString).range(of: longLine).location
        let touchedLineEnd = touchedLineStart + longLine.utf16.count
        guard let lineStartPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: touchedLineStart
        ) else {
            Issue.record("SyntaxEditorView could not resolve touched line start")
            return
        }

        let lineStartRect = editorView.caretRect(for: lineStartPosition)
        guard let hitPosition = editorView.closestPosition(
            to: CGPoint(x: lineStartRect.minX + 260, y: lineStartRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve touched line point")
            return
        }

        let hitOffset = editorView.offset(from: editorView.beginningOfDocument, to: hitPosition)
        #expect(hitOffset >= touchedLineStart)
        #expect(hitOffset <= touchedLineEnd)
        #expect(hitOffset < source.utf16.count - 1)
    }

    @Test("SyntaxEditorView constrains iOS drag hit testing to the requested text range")
    @MainActor
    func syntaxEditorViewIOSConstrainsDragHitTestingToRequestedRange() {
        let source = [
            "const answer = 42;",
            "function greet(name) {",
            "    return " + String(repeating: "\"Hello\", ", count: 28),
            "}",
            "const finalAnswer = 42;",
        ].joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let constrainedLine = "function greet(name) {"
        let constrainedStart = (source as NSString).range(of: constrainedLine).location
        let constrainedEnd = constrainedStart + constrainedLine.utf16.count
        guard let startPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: constrainedStart
        ),
              let endPosition = editorView.position(
                from: editorView.beginningOfDocument,
                offset: constrainedEnd
              ),
              let constrainedRange = editorView.textRange(from: startPosition, to: endPosition)
        else {
            Issue.record("SyntaxEditorView could not resolve constrained drag range")
            return
        }

        let farDocumentEndPoint = CGPoint(x: editorView.bounds.maxX - 12, y: editorView.bounds.maxY - 12)
        guard let constrainedPosition = editorView.closestPosition(
            to: farDocumentEndPoint,
            within: constrainedRange
        ) else {
            Issue.record("SyntaxEditorView could not resolve constrained drag point")
            return
        }

        let constrainedOffset = editorView.offset(
            from: editorView.beginningOfDocument,
            to: constrainedPosition
        )
        #expect(constrainedOffset >= constrainedStart)
        #expect(constrainedOffset <= constrainedEnd)
    }

    @Test("SyntaxEditorView keeps collapsed iOS drag constraints at anchor")
    @MainActor
    func syntaxEditorViewIOSKeepsCollapsedDragConstraintsAtAnchor() {
        let line = "const answer = 42;"
        let source = [
            "<script>",
            line,
            "</script>",
            "<script>",
            line,
            "</script>",
        ].joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.html,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let lineStart = (source as NSString).range(of: line).location
        let lineEnd = lineStart + line.utf16.count
        let targetOffset = lineStart + "const ".utf16.count
        guard let lineEndPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: lineEnd
        ),
              let targetPosition = editorView.position(
                from: editorView.beginningOfDocument,
                offset: targetOffset
              ),
              let collapsedRange = editorView.textRange(from: lineEndPosition, to: lineEndPosition)
        else {
            Issue.record("SyntaxEditorView could not resolve collapsed drag positions")
            return
        }

        let targetRect = editorView.caretRect(for: targetPosition)
        guard let resolvedPosition = editorView.closestPosition(
            to: CGPoint(x: targetRect.midX, y: targetRect.midY),
            within: collapsedRange
        ) else {
            Issue.record("SyntaxEditorView could not resolve collapsed constrained drag point")
            return
        }

        let resolvedOffset = editorView.offset(from: editorView.beginningOfDocument, to: resolvedPosition)
        #expect(resolvedOffset == lineEnd)
    }

    @Test("SyntaxEditorView resolves iOS clicks to the touched whitespace column")
    @MainActor
    func syntaxEditorViewIOSResolvesClicksToTouchedWhitespaceColumn() {
        let sourceLines = [
            "let prefix = 1;",
            "value          = 42;",
            "let suffix = 2;",
        ]
        let source = sourceLines.joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let whitespaceLineStart = (source as NSString).range(of: sourceLines[1]).location
        let whitespaceOffset = whitespaceLineStart + "value     ".utf16.count
        guard let whitespacePosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: whitespaceOffset
        ) else {
            Issue.record("SyntaxEditorView could not resolve whitespace position")
            return
        }

        let whitespaceRect = editorView.caretRect(for: whitespacePosition)
        guard let resolvedPosition = editorView.closestPosition(
            to: CGPoint(x: whitespaceRect.midX, y: whitespaceRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve whitespace click")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: resolvedPosition)
                == whitespaceOffset
        )
    }

    @Test("SyntaxEditorView resolves iOS clicks right of short lines to the line end")
    @MainActor
    func syntaxEditorViewIOSResolvesClicksRightOfShortLinesToLineEnd() {
        let sourceLines = [
            "let short = 1;",
            "let next = 2;",
        ]
        let source = sourceLines.joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = sourceLines[0].utf16.count
        guard let lineEndPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: firstLineEnd
        ) else {
            Issue.record("SyntaxEditorView could not resolve line end position")
            return
        }

        let lineEndRect = editorView.caretRect(for: lineEndPosition)
        guard let resolvedPosition = editorView.closestPosition(
            to: CGPoint(x: lineEndRect.maxX + 120, y: lineEndRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve right-of-line click")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: resolvedPosition)
                == firstLineEnd
        )
    }

    @Test("SyntaxEditorView resolves iOS clicks right of CRLF lines before the terminator")
    @MainActor
    func syntaxEditorViewIOSResolvesClicksRightOfCRLFLinesBeforeTerminator() {
        let firstLine = "let short = 1;"
        let source = "\(firstLine)\r\nlet next = 2;"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = firstLine.utf16.count
        guard let lineEndPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: firstLineEnd
        ) else {
            Issue.record("SyntaxEditorView could not resolve CRLF line end position")
            return
        }

        let lineEndRect = editorView.caretRect(for: lineEndPosition)
        guard let resolvedPosition = editorView.closestPosition(
            to: CGPoint(x: lineEndRect.maxX + 120, y: lineEndRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve right-of-CRLF-line click")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: resolvedPosition)
                == firstLineEnd
        )
    }

    @Test("SyntaxEditorView moves iOS caret vertically between visual lines")
    @MainActor
    func syntaxEditorViewIOSMovesCaretVerticallyBetweenVisualLines() {
        let sourceLines = [
            "let first = 0;",
            "01234567890123456789",
            "abcdefghijABCDEFGHIJ",
            "klmnopqrstKLMNOPQRST",
        ]
        let source = sourceLines.joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let secondLineStart = (source as NSString).range(of: sourceLines[1]).location
        let thirdLineStart = (source as NSString).range(of: sourceLines[2]).location
        let fourthLineStart = (source as NSString).range(of: sourceLines[3]).location
        let visualColumn = 10
        guard let currentPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: thirdLineStart + visualColumn
        ),
              let upPosition = editorView.position(from: currentPosition, in: .up, offset: 1),
              let downPosition = editorView.position(from: currentPosition, in: .down, offset: 1)
        else {
            Issue.record("SyntaxEditorView could not resolve vertical caret movement")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: upPosition)
                == secondLineStart + visualColumn
        )
        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: downPosition)
                == fourthLineStart + visualColumn
        )

        let currentRect = editorView.caretRect(for: currentPosition)
        let upRect = editorView.caretRect(for: upPosition)
        let downRect = editorView.caretRect(for: downPosition)
        #expect(upRect.midY < currentRect.midY)
        #expect(downRect.midY > currentRect.midY)
        #expect(abs(upRect.midX - currentRect.midX) <= 1)
        #expect(abs(downRect.midX - currentRect.midX) <= 1)
    }

    @Test("SyntaxEditorView keeps iOS caret column moving vertically from short visual lines")
    @MainActor
    func syntaxEditorViewIOSKeepsCaretColumnMovingVerticallyFromShortVisualLines() {
        let sourceLines = [
            "01234567890123456789",
            "abcde",
            "ABCDEFGHIJABCDEFGHIJ",
        ]
        let source = sourceLines.joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let secondLineStart = (source as NSString).range(of: sourceLines[1]).location
        let thirdLineStart = (source as NSString).range(of: sourceLines[2]).location
        let visualColumn = 4
        guard let shortLinePosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: secondLineStart + visualColumn
        ),
              let downPosition = editorView.position(from: shortLinePosition, in: .down, offset: 1)
        else {
            Issue.record("SyntaxEditorView could not resolve vertical caret movement from a short line")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: downPosition)
                == thirdLineStart + visualColumn
        )

        let shortLineRect = editorView.caretRect(for: shortLinePosition)
        let downRect = editorView.caretRect(for: downPosition)
        #expect(downRect.midY > shortLineRect.midY)
        #expect(abs(downRect.midX - shortLineRect.midX) <= 1)
    }

    @Test("SyntaxEditorView uses displayed iOS line break affinity for vertical caret movement")
    @MainActor
    func syntaxEditorViewIOSUsesDisplayedLineBreakAffinityForVerticalCaretMovement() {
        let sourceLines = [
            "abcde",
            "01234567890123456789",
            "ABCDEFGHIJABCDEFGHIJ",
        ]
        let source = sourceLines.joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = sourceLines[0].utf16.count
        let secondLineStart = (source as NSString).range(of: sourceLines[1]).location
        guard let downFromDocumentStart = editorView.position(
            from: editorView.beginningOfDocument,
            in: .down,
            offset: 1
        ) else {
            Issue.record("SyntaxEditorView could not resolve vertical caret movement from document start")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: downFromDocumentStart)
                == secondLineStart
        )

        guard let lineEndPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: firstLineEnd
        ),
              let downPosition = editorView.position(from: lineEndPosition, in: .down, offset: 1)
        else {
            Issue.record("SyntaxEditorView could not resolve vertical caret movement at a line break")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: downPosition)
                == secondLineStart + firstLineEnd
        )

        let lineEndRect = editorView.caretRect(for: lineEndPosition)
        let downRect = editorView.caretRect(for: downPosition)
        #expect(downRect.midY > lineEndRect.midY)
        #expect(abs(downRect.midX - lineEndRect.midX) <= 1)
    }

    @Test("SyntaxEditorView syncs iOS line-end selections with upstream affinity")
    @MainActor
    func syntaxEditorViewIOSSyncsLineEndSelectionsWithUpstreamAffinity() {
        let source = "abcde\n01234"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = (source as NSString).range(of: "\n").location
        editorView.selectedRange = NSRange(location: firstLineEnd, length: 0)

        #expect(editorView.textLayoutManager?.textSelections.first?.affinity == .upstream)
    }

    @Test("SyntaxEditorView keeps iOS caret on the edited whitespace line after text input")
    @MainActor
    func syntaxEditorViewIOSKeepsCaretOnEditedWhitespaceLineAfterTextInput() {
        let editedLine = "    body { color          : red; }"
        let source = [
            "<style>",
            editedLine,
            "</style>",
            "</head>",
        ].joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.html,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let editedLineStart = (source as NSString).range(of: editedLine).location
        let insertionOffset = editedLineStart + "    body { color".utf16.count
        guard let lineStartPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: editedLineStart
        ) else {
            Issue.record("SyntaxEditorView could not resolve the edited line start")
            return
        }
        let lineStartRect = editorView.caretRect(for: lineStartPosition)

        editorView.selectedRange = NSRange(location: insertionOffset, length: 0)
        editorView.insertText(".")
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let caretPosition = editorView.selectedTextRange?.start else {
            Issue.record("SyntaxEditorView did not expose a selected text range after whitespace-line input")
            return
        }
        let caretRect = editorView.caretRect(for: caretPosition)

        #expect(editorView.selectedRange == NSRange(location: insertionOffset + 1, length: 0))
        #expect(abs(caretRect.midY - lineStartRect.midY) <= 1)
        #expect(caretRect.midX > lineStartRect.midX)
    }

    @Test("SyntaxEditorView keeps iOS caret on the edited line after inserting before a line break")
    @MainActor
    func syntaxEditorViewIOSKeepsCaretOnEditedLineAfterInsertingBeforeLineBreak() {
        let editedLine = "    </style>"
        let source = [
            editedLine,
            "</head>",
            "<body>",
        ].joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.html,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let editedLineEnd = editedLine.utf16.count
        guard let lineStartPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: 0
        ) else {
            Issue.record("SyntaxEditorView could not resolve the edited line start")
            return
        }
        let lineStartRect = editorView.caretRect(for: lineStartPosition)

        editorView.selectedRange = NSRange(location: editedLineEnd, length: 0)
        editorView.insertText(".")
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let caretPosition = editorView.selectedTextRange?.start else {
            Issue.record("SyntaxEditorView did not expose a selected text range after line-break input")
            return
        }
        let caretRect = editorView.caretRect(for: caretPosition)

        #expect(editorView.text == "    </style>.\n</head>\n<body>")
        #expect(editorView.selectedRange == NSRange(location: editedLineEnd + 1, length: 0))
        #expect(abs(caretRect.midY - lineStartRect.midY) <= 1)
    }

    @Test("SyntaxEditorView keeps iOS EOF caret on the final visual line")
    @MainActor
    func syntaxEditorViewIOSKeepsEOFCaretOnFinalVisualLine() {
        let sourceLines = [
            "const answer = 42;",
            "function greet(name) {",
            "    return \"Hello\";",
            "}.",
        ]
        let source = sourceLines.joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let finalLineStart = (source as NSString).range(of: sourceLines[3]).location
        guard let finalLinePosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: finalLineStart
        ),
              let endPosition = editorView.position(
                from: editorView.beginningOfDocument,
                offset: source.utf16.count
              )
        else {
            Issue.record("SyntaxEditorView could not resolve the final line or EOF position")
            return
        }

        let finalLineRect = editorView.caretRect(for: finalLinePosition)
        let endRect = editorView.caretRect(for: endPosition)

        #expect(abs(endRect.midY - finalLineRect.midY) <= 1)

        guard let tappedPosition = editorView.closestPosition(
            to: CGPoint(x: endRect.midX + 120, y: endRect.maxY + 100)
        ) else {
            Issue.record("SyntaxEditorView could not resolve an empty-space tap below text")
            return
        }
        editorView.selectedTextRange = editorView.textRange(from: tappedPosition, to: tappedPosition)

        guard let selectedPosition = editorView.selectedTextRange?.start else {
            Issue.record("SyntaxEditorView did not expose a selected text range after empty-space tap")
            return
        }
        let tappedCaretRect = editorView.caretRect(for: selectedPosition)

        #expect(editorView.offset(from: editorView.beginningOfDocument, to: selectedPosition) == source.utf16.count)
        #expect(abs(tappedCaretRect.midY - finalLineRect.midY) <= 1)
    }

    @Test("SyntaxEditorView keeps iOS caret stable while repeatedly inserting spaces")
    @MainActor
    func syntaxEditorViewIOSKeepsCaretStableWhileRepeatedlyInsertingSpaces() async {
        let sourceLines = [
            "const answer = 42;",
            "function greet(name) {",
            "    return \"Hello\";",
            "}",
        ]
        let source = sourceLines.joined(separator: "\n")
        let highlighter = SyntaxEditorUITestHighlighter(delayNanoseconds: 1_000_000)
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model, highlighter: highlighter)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        await editorView.waitForPendingHighlightForTesting()

        let editedLineStart = (source as NSString).range(of: sourceLines[2]).location
        let insertionOffset = editedLineStart + sourceLines[2].utf16.count
        guard let editedLinePosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: editedLineStart
        ) else {
            Issue.record("SyntaxEditorView could not resolve the edited line start")
            return
        }
        let editedLineRect = editorView.caretRect(for: editedLinePosition)
        editorView.selectedRange = NSRange(location: insertionOffset, length: 0)

        var previousCaretX = editorView.caretRect(for: SyntaxEditorTextPosition(offset: insertionOffset)).midX
        for insertedSpaceCount in 1...12 {
            editorView.insertText(" ")
            layoutIOSEditorView(editorView, width: 393, height: 658)
            await Task.yield()

            guard let caretPosition = editorView.selectedTextRange?.start else {
                Issue.record("SyntaxEditorView did not expose a selected text range after space input")
                return
            }
            let caretRect = editorView.caretRect(for: caretPosition)
            #expect(editorView.selectedRange == NSRange(location: insertionOffset + insertedSpaceCount, length: 0))
            #expect(abs(caretRect.midY - editedLineRect.midY) <= 1)
            #expect(caretRect.midX >= previousCaretX)
            previousCaretX = caretRect.midX
        }

        await editorView.waitForPendingHighlightForTesting()
        guard let finalCaretPosition = editorView.selectedTextRange?.start else {
            Issue.record("SyntaxEditorView did not expose a selected text range after highlighting")
            return
        }
        let finalCaretRect = editorView.caretRect(for: finalCaretPosition)
        #expect(abs(finalCaretRect.midY - editedLineRect.midY) <= 1)
        #expect(editorView.selectedRange == NSRange(location: insertionOffset + 12, length: 0))
    }

    @Test("SyntaxEditorView places iOS caret on the immediate next line after newline input")
    @MainActor
    func syntaxEditorViewIOSPlacesCaretOnImmediateNextLineAfterNewlineInput() {
        let source = "abcde\n01234"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        editorView.selectedRange = NSRange(location: "abcde".utf16.count, length: 0)

        let firstLineRect = editorView.caretRect(for: editorView.beginningOfDocument)
        guard let originalSecondLinePosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: "abcde\n".utf16.count
        ) else {
            Issue.record("SyntaxEditorView could not resolve original second line")
            return
        }
        let originalSecondLineRect = editorView.caretRect(for: originalSecondLinePosition)

        editorView.insertText("\n")
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let caretPosition = editorView.selectedTextRange?.start else {
            Issue.record("SyntaxEditorView did not expose a selected text range after newline insertion")
            return
        }
        let caretRect = editorView.caretRect(for: caretPosition)

        #expect(editorView.text == "abcde\n\n01234")
        #expect(editorView.selectedRange == NSRange(location: "abcde\n".utf16.count, length: 0))
        #expect(caretRect.midY > firstLineRect.midY)
        #expect(abs(caretRect.midY - originalSecondLineRect.midY) <= 1)
    }

    @Test("SyntaxEditorView places iOS caret on the next line after appending newline")
    @MainActor
    func syntaxEditorViewIOSPlacesCaretOnNextLineAfterAppendingNewline() {
        let source = "abcde"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        let firstLineRect = editorView.caretRect(for: editorView.beginningOfDocument)

        editorView.insertText("\n")
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let caretPosition = editorView.selectedTextRange?.start else {
            Issue.record("SyntaxEditorView did not expose a selected text range after appending newline")
            return
        }
        let caretRect = editorView.caretRect(for: caretPosition)

        #expect(editorView.text == "abcde\n")
        #expect(editorView.selectedRange == NSRange(location: "abcde\n".utf16.count, length: 0))
        #expect(caretRect.midY > firstLineRect.midY + editorView.font.lineHeight * 0.5)
        #expect(caretRect.midY < firstLineRect.midY + editorView.font.lineHeight * 1.5)
    }

    @Test("SyntaxEditorView reports updated iOS caret geometry during transformed newline input")
    @MainActor
    func syntaxEditorViewIOSReportsUpdatedCaretGeometryDuringTransformedNewlineInput() {
        let model = SyntaxEditorModel(
            text: "{}",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        let inputDelegate = SyntaxEditorUITestInputDelegate()
        var observedCaretRect: CGRect?
        inputDelegate.textDidChangeHandler = { textInput in
            guard let editorView = textInput as? SyntaxEditorView,
                  let caretPosition = editorView.selectedTextRange?.start
            else {
                return
            }
            observedCaretRect = editorView.caretRect(for: caretPosition)
        }
        editorView.inputDelegate = inputDelegate
        layoutIOSEditorView(editorView, width: 393, height: 658)
        editorView.selectedRange = NSRange(location: 1, length: 0)

        editorView.insertText("\n")
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let caretPosition = editorView.selectedTextRange?.start,
              let lineStartPosition = editorView.position(
                  from: editorView.beginningOfDocument,
                  offset: "{\n".utf16.count
              ),
              let observedCaretRect
        else {
            Issue.record("SyntaxEditorView did not report caret geometry during transformed newline input")
            return
        }

        let caretRect = editorView.caretRect(for: caretPosition)
        let secondLineRect = editorView.caretRect(for: lineStartPosition)

        #expect(editorView.text == "{\n    \n}")
        #expect(editorView.selectedRange == NSRange(location: "{\n    ".utf16.count, length: 0))
        #expect(abs(observedCaretRect.midY - secondLineRect.midY) <= 1)
        #expect(abs(caretRect.midY - secondLineRect.midY) <= 1)
    }

    @Test("SyntaxEditorView keeps iOS caret on the edited line after inserting at line start")
    @MainActor
    func syntaxEditorViewIOSKeepsCaretOnEditedLineAfterInsertingAtLineStart() {
        let sourceLines = [
            "let first = 1;",
            "let second = 2;",
        ]
        let source = sourceLines.joined(separator: "\n")
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let secondLineStart = (source as NSString).range(of: sourceLines[1]).location
        editorView.selectedRange = NSRange(location: secondLineStart, length: 0)
        let firstLineRect = editorView.caretRect(for: editorView.beginningOfDocument)

        editorView.insertText("x")
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let editedPosition = editorView.selectedTextRange?.start
        guard let editedPosition else {
            Issue.record("SyntaxEditorView did not expose a selected text range after insertion")
            return
        }
        let editedRect = editorView.caretRect(for: editedPosition)

        #expect(editorView.selectedRange.location == secondLineStart + 1)
        #expect(editedRect.midY > firstLineRect.midY)
    }

    @Test("SyntaxEditorView rejects foreign iOS text positions for nonzero directional movement")
    @MainActor
    func syntaxEditorViewIOSRejectsForeignTextPositionsForNonzeroDirectionalMovement() {
        let model = SyntaxEditorModel(text: "abc", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        let foreignPosition = SyntaxEditorUITestForeignTextPosition()

        #expect(editorView.position(from: foreignPosition, in: .down, offset: 1) == nil)
        #expect(editorView.position(from: foreignPosition, in: .down, offset: 0) === foreignPosition)
    }

    @Test("SyntaxEditorView does not let iOS gesture selection changes own horizontal scrolling")
    @MainActor
    func syntaxEditorViewIOSGestureSelectionDoesNotOwnHorizontalScrolling() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let offscreenStartRange = editorView.textRange(
            from: editorView.beginningOfDocument,
            to: editorView.beginningOfDocument
        ) else {
            Issue.record("SyntaxEditorView could not resolve the document start range")
            return
        }

        let stableOffsetX = editorView.contentOffset.x
        editorView.selectedTextRange = offscreenStartRange
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
    }

    @Test("SyntaxEditorView blocks iOS text interaction auto-scroll during gesture selection")
    @MainActor
    func syntaxEditorViewIOSBlocksTextInteractionAutoScrollDuringGestureSelection() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let visiblePosition = editorView.closestPosition(to: CGPoint(x: 240, y: 54)),
              let visibleRange = editorView.textRange(from: visiblePosition, to: visiblePosition)
        else {
            Issue.record("SyntaxEditorView could not resolve a visible gesture selection range")
            return
        }

        let stableOffsetX = editorView.contentOffset.x
        editorView.selectedTextRange = visibleRange
        editorView.setContentOffset(CGPoint(x: editorView.contentSize.width - editorView.bounds.width, y: 0), animated: false)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
    }

    @Test("SyntaxEditorView maps trailing first-line iOS tap to first line end")
    @MainActor
    func syntaxEditorViewIOSTrailingFirstLineTapMapsToFirstLineEnd() {
        let source = "const answer = 42;\nfunction greet(name) {\n    return name\n}"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = (source as NSString).range(of: "\n").location
        let pointPastFirstLineText = CGPoint(
            x: editorView.bounds.minX + 260,
            y: editorView.textContainerInset.top + editorView.font.lineHeight * 0.5
        )

        guard let position = editorView.closestPosition(to: pointPastFirstLineText) else {
            Issue.record("SyntaxEditorView could not resolve a first-line trailing tap")
            return
        }

        let offset = editorView.offset(from: editorView.beginningOfDocument, to: position)
        #expect(offset == firstLineEnd)
    }

    @Test("SyntaxEditorView allows explicit iOS scrollRectToVisible to move horizontally")
    @MainActor
    func syntaxEditorViewIOSAllowsExplicitScrollRectToVisibleToMoveHorizontally() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let initialOffsetX = editorView.contentOffset.x
        let explicitTargetRect = CGRect(
            x: editorView.contentSize.width - 4,
            y: editorView.textContainerInset.top,
            width: 2,
            height: editorView.font.lineHeight
        )
        editorView.scrollRectToVisible(explicitTargetRect, animated: false)

        #expect(editorView.contentOffset.x > initialOffsetX)
    }

    @Test("SyntaxEditorView preserves horizontal offset for text interaction iOS scrollRectToVisible")
    @MainActor
    func syntaxEditorViewIOSPreservesHorizontalOffsetForTextInteractionScrollRectToVisible() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let textInteractionCaretRect = editorView.caretRect(for: editorView.beginningOfDocument)
        #expect(!textInteractionCaretRect.isEmpty)
        let textInteractionTargetRect = CGRect(
            x: editorView.contentSize.width - 4,
            y: editorView.textContainerInset.top,
            width: 2,
            height: editorView.font.lineHeight
        )
        editorView.scrollRectToVisible(textInteractionTargetRect, animated: false)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
    }

    @Test("SyntaxEditorView reports iOS visible content rect after horizontal scroll")
    @MainActor
    func syntaxEditorViewIOSVisibleContentRectTracksHorizontalScroll() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let visibleRect = CGRect(origin: editorView.contentOffset, size: editorView.bounds.size)
        #expect(abs(visibleRect.minX - editorView.contentOffset.x) <= 1)
        #expect(abs(visibleRect.minY - editorView.contentOffset.y) <= 1)
        #expect(abs(visibleRect.width - editorView.bounds.width) <= 1)
        #expect(abs(visibleRect.height - editorView.bounds.height) <= 1)

        let visibleMidPoint = CGPoint(x: editorView.bounds.midX, y: editorView.bounds.minY + 54)
        guard let position = editorView.closestPosition(to: visibleMidPoint) else {
            Issue.record("SyntaxEditorView could not resolve a scrolled visible text-input point")
            return
        }

        let location = editorView.offset(from: editorView.beginningOfDocument, to: position)
        #expect(location > 0)
        #expect(location < longIOSSyntaxEditorMultilineText.utf16.count)
    }

    @Test("SyntaxEditorView grows horizontal content size after observed iOS text update")
    @MainActor
    func syntaxEditorViewIOSObservedLongTextUpdateGrowsHorizontalContentSize() async {
        let model = SyntaxEditorModel(
            text: "let short = true",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        model.text = longIOSSyntaxEditorLine

        editorView.synchronizeModelForTesting()
        #expect(editorView.text == longIOSSyntaxEditorLine)
        layoutIOSEditorView(editorView)
        #expect(iOSEditorHasHorizontalOverflow(editorView))
    }

    @Test("SyntaxEditorView grows horizontal content size after direct iOS text assignment")
    @MainActor
    func syntaxEditorViewIOSDirectTextAssignmentGrowsHorizontalContentSize() {
        let model = SyntaxEditorModel(
            text: "let short = true",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        editorView.text = longIOSSyntaxEditorLine

        #expect(model.text == longIOSSyntaxEditorLine)
        layoutIOSEditorView(editorView)
        #expect(iOSEditorHasHorizontalOverflow(editorView))
    }

    @Test("SyntaxEditorView keeps iOS scroll position while editing")
    @MainActor
    func syntaxEditorViewIOSKeepsScrollPositionWhileEditing() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        let insertionLocation = visibleMidIOSSyntaxEditorLocation
        #expect(insertionLocation > 0)
        #expect(insertionLocation < longIOSSyntaxEditorLine.utf16.count)

        editorView.selectedRange = NSRange(location: insertionLocation, length: 0)
        layoutIOSEditorView(editorView)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        editorView.insertText("x")
        layoutIOSEditorView(editorView)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
    }

    @Test("SyntaxEditorView keeps iOS scroll position while moving cursor")
    @MainActor
    func syntaxEditorViewIOSKeepsScrollPositionWhileMovingCursor() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let targetLocation = visibleMidIOSSyntaxEditorLocation
        #expect(targetLocation > 0)
        #expect(targetLocation < longIOSSyntaxEditorLine.utf16.count)

        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        layoutIOSEditorView(editorView)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
    }

    @Test("SyntaxEditorView keeps native iOS bounce enabled")
    @MainActor
    func syntaxEditorViewIOSKeepsNativeBounceEnabled() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        #expect(editorView.bounces)
        #expect(editorView.alwaysBounceVertical)
    }

    @Test("SyntaxEditorView scrolls iOS ranges through the single text view")
    @MainActor
    func syntaxEditorViewIOSScrollsRangesThroughSingleTextView() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let targetLocation = max(0, longIOSSyntaxEditorLine.utf16.count - 1)
        #expect(editorView.position(
            from: editorView.beginningOfDocument,
            offset: targetLocation
        ) != nil)

        let scrollRangeToVisible: (NSRange) -> Void = editorView.scrollRangeToVisible
        scrollRangeToVisible(NSRange(location: targetLocation, length: 0))
        layoutIOSEditorView(editorView)

        #expect(editorView.contentOffset.x > stableOffsetX)
    }

    @Test("SyntaxEditorView scrolls iOS ranges outside adjusted right inset")
    @MainActor
    func syntaxEditorViewIOSScrollsRangesOutsideAdjustedRightInset() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        editorView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 44)
        layoutIOSEditorView(editorView)

        let targetLocation = max(0, longIOSSyntaxEditorLine.utf16.count - 1)
        guard let position = editorView.position(
            from: editorView.beginningOfDocument,
            offset: targetLocation
        ) else {
            Issue.record("SyntaxEditorView could not resolve the inset scroll target")
            return
        }

        let targetRect = editorView.caretRect(for: position)
        editorView.scrollRangeToVisible(NSRange(location: targetLocation, length: 0))
        layoutIOSEditorView(editorView)

        let insets = editorView.adjustedContentInset
        let visibleWidth = editorView.bounds.width - insets.left - insets.right
        let visibleMaxX = editorView.contentOffset.x + insets.left + visibleWidth
        #expect(insets.right >= 44)
        #expect(editorView.contentOffset.x > 0)
        #expect(targetRect.maxX <= visibleMaxX + 1)
    }

    @Test("SyntaxEditorView keeps iOS horizontal offset after visible cursor click")
    @MainActor
    func syntaxEditorViewIOSKeepsHorizontalOffsetAfterVisibleCursorClick() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let targetLocation = visibleMidIOSSyntaxEditorLocation
        #expect(targetLocation > 0)
        #expect(targetLocation < longIOSSyntaxEditorLine.utf16.count)
        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        layoutIOSEditorView(editorView)

        let stableOffsetX = editorView.contentOffset.x
        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        layoutIOSEditorView(editorView)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
    }

    @Test("SyntaxEditorView does not horizontally scroll after repeated visible iOS selection updates")
    @MainActor
    func syntaxEditorViewIOSDoesNotScrollHorizontallyAfterRepeatedVisibleSelectionUpdates() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let targetLocation = visibleMidIOSSyntaxEditorLocation
        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        layoutIOSEditorView(editorView)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
    }

    @Test("SyntaxEditorView keeps iOS horizontal offset after native content-space tap selection")
    @MainActor
    func syntaxEditorViewIOSKeepsHorizontalOffsetAfterNativeContentSpaceTapSelection() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.contentSize.width > editorView.bounds.width + 1)

        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let tapPoint = CGPoint(x: stableOffsetX + 200, y: 54)
        guard let position = editorView.closestPosition(to: tapPoint),
              let textRange = editorView.textRange(from: position, to: position)
        else {
            Issue.record("SyntaxEditorView could not resolve a native tap point")
            return
        }

        editorView.selectedTextRange = textRange
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
        guard let renderedContentFrame = iOSEditorRenderedContentFrame(editorView) else {
            Issue.record("SyntaxEditorView does not expose a rendered content frame")
            return
        }
        #expect(renderedContentFrame.width >= editorView.contentSize.width - 1)
        #expect(renderedContentFrame.maxX >= editorView.contentOffset.x + editorView.bounds.width - 1)
        #expect(
            iOSEditorTextKit2UsageBoundsCoverVisibleHorizontalViewport(editorView),
            Comment(rawValue: iOSEditorTextKit2Diagnostics(editorView))
        )
    }

    @Test("SyntaxEditorView supports ranged iOS selection after horizontal scroll")
    @MainActor
    func syntaxEditorViewIOSSupportsRangedSelectionAfterHorizontalScroll() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let stableOffsetX = editorView.contentOffset.x
        let visibleRect = editorView.bounds
        let startPoint = CGPoint(x: visibleRect.minX + 120, y: visibleRect.minY + 54)
        let endPoint = CGPoint(x: visibleRect.minX + 280, y: visibleRect.minY + 54)

        guard let startPosition = editorView.closestPosition(to: startPoint),
              let endPosition = editorView.closestPosition(to: endPoint),
              let textRange = editorView.textRange(from: startPosition, to: endPosition)
        else {
            Issue.record("SyntaxEditorView could not resolve scrolled ranged selection points")
            return
        }

        editorView.selectedTextRange = textRange
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.selectedRange.length > 0)
        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)

        let selectionRects = editorView.selectionRects(for: textRange)
        #expect(!selectionRects.isEmpty)
        #expect(selectionRects.contains { $0.rect.intersects(visibleRect) })

        #expect(editorView.contentSize.width >= editorView.contentOffset.x + editorView.bounds.width - 1)
    }

    @Test("SyntaxEditorView updates ranged iOS selection after horizontal scroll")
    @MainActor
    func syntaxEditorViewIOSUpdatesRangedSelectionAfterHorizontalScroll() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.setContentOffset(CGPoint(x: 700, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let viewportStartPoint = CGPoint(x: 120, y: 54)
        let viewportEndPoint = CGPoint(x: 280, y: 54)
        let extendedViewportEndPoint = CGPoint(x: 340, y: 54)

        guard let viewportStartPosition = editorView.closestPosition(to: viewportStartPoint),
              let viewportEndPosition = editorView.closestPosition(to: viewportEndPoint),
              let extendedViewportEndPosition = editorView.closestPosition(to: extendedViewportEndPoint)
        else {
            Issue.record("SyntaxEditorView could not resolve viewport-local selection points")
            return
        }

        guard let viewportTextRange = editorView.textRange(from: viewportStartPosition, to: viewportEndPosition),
              let documentRange = editorView.textRange(from: editorView.beginningOfDocument, to: editorView.endOfDocument),
              let constrainedViewportEndPosition = editorView.closestPosition(to: viewportEndPoint, within: documentRange),
              let characterRange = editorView.characterRange(at: viewportStartPoint)
        else {
            Issue.record("SyntaxEditorView could not resolve viewport-local ranged selection helpers")
            return
        }

        editorView.selectedTextRange = viewportTextRange
        layoutIOSEditorView(editorView, width: 393, height: 658)
        let initialSelectionLength = editorView.selectedRange.length

        guard let extendedTextRange = editorView.textRange(
            from: viewportStartPosition,
            to: extendedViewportEndPosition
        ) else {
            Issue.record("SyntaxEditorView could not extend a viewport-local ranged selection")
            return
        }

        editorView.selectedTextRange = extendedTextRange
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.selectedRange.length > 0)
        #expect(editorView.selectedRange.length >= initialSelectionLength)
        #expect(editorView.offset(from: editorView.beginningOfDocument, to: constrainedViewportEndPosition) ==
            editorView.offset(from: editorView.beginningOfDocument, to: viewportEndPosition))
        let characterRangeStartOffset = editorView.offset(
            from: editorView.beginningOfDocument,
            to: characterRange.start
        )
        let viewportStartOffset = editorView.offset(
            from: editorView.beginningOfDocument,
            to: viewportStartPosition
        )
        #expect(abs(characterRangeStartOffset - viewportStartOffset) <= 1)
    }

    @Test("SyntaxEditorView keeps iOS closest position inside collapsed constrained range")
    @MainActor
    func syntaxEditorViewIOSKeepsClosestPositionInsideCollapsedConstrainedRange() {
        let source = "abcdef\nuvwxyz"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let constrainedPosition = editorView.position(from: editorView.beginningOfDocument, offset: 2),
              let constrainedRange = editorView.textRange(from: constrainedPosition, to: constrainedPosition),
              let closestPosition = editorView.closestPosition(to: CGPoint(x: 250, y: 80), within: constrainedRange)
        else {
            Issue.record("SyntaxEditorView could not resolve a collapsed constrained closest position")
            return
        }

        #expect(editorView.offset(from: editorView.beginningOfDocument, to: closestPosition) == 2)
    }

    @Test("SyntaxEditorView clamps iOS character-offset positions to supplied range")
    @MainActor
    func syntaxEditorViewIOSClampsCharacterOffsetPositionsToSuppliedRange() {
        let source = "abcdef"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        guard let rangeStart = editorView.position(from: editorView.beginningOfDocument, offset: 1),
              let rangeEnd = editorView.position(from: editorView.beginningOfDocument, offset: 4),
              let range = editorView.textRange(from: rangeStart, to: rangeEnd),
              let beforeRange = editorView.position(within: range, atCharacterOffset: -3),
              let afterRange = editorView.position(within: range, atCharacterOffset: 10)
        else {
            Issue.record("SyntaxEditorView could not resolve range-constrained character offsets")
            return
        }

        #expect(editorView.offset(from: editorView.beginningOfDocument, to: beforeRange) == 1)
        #expect(editorView.offset(from: editorView.beginningOfDocument, to: afterRange) == 4)
    }

    @Test("SyntaxEditorView resolves iOS character-offset positions by composed characters")
    @MainActor
    func syntaxEditorViewIOSResolvesCharacterOffsetPositionsByComposedCharacters() {
        let source = "🙂a"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        guard let range = editorView.textRange(
            from: editorView.beginningOfDocument,
            to: editorView.endOfDocument
        ),
              let afterEmoji = editorView.position(within: range, atCharacterOffset: 1),
              let afterEnd = editorView.position(within: range, atCharacterOffset: 10)
        else {
            Issue.record("SyntaxEditorView could not resolve composed character offsets")
            return
        }

        #expect(editorView.offset(from: editorView.beginningOfDocument, to: afterEmoji) == ("🙂" as NSString).length)
        #expect(editorView.offset(from: editorView.beginningOfDocument, to: afterEnd) == source.utf16.count)
        #expect(editorView.characterOffset(of: afterEmoji, within: range) == 1)
        #expect(editorView.characterOffset(of: afterEnd, within: range) == 2)
    }

    @Test("SyntaxEditorView clears stale horizontal content size after iOS wrapping toggles")
    @MainActor
    func syntaxEditorViewIOSWrappingToggleClearsStaleHorizontalContentSize() async {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(model: model)

        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        model.lineWrappingEnabled = false

        editorView.synchronizeModelForTesting()
        #expect(!editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        let restoredHorizontalOverflow = iOSEditorHasHorizontalOverflow(editorView)
        if !restoredHorizontalOverflow {
            print(iOSEditorHorizontalOverflowDiagnostics(editorView))
        }
        #expect(restoredHorizontalOverflow)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        model.lineWrappingEnabled = true

        editorView.synchronizeModelForTesting()
        #expect(editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
    }

    @Test("SyntaxEditorView omits editing key commands while read-only on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyOmitsEditingKeyCommands() {
        let model = SyntaxEditorModel(
            text: "let answer = 42",
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(model: model)

        let readOnlyCommands = editorView.keyCommands
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "\t", modifierFlags: []))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "\t", modifierFlags: [.shift]))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "]", modifierFlags: [.command]))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "[", modifierFlags: [.command]))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "/", modifierFlags: [.command]))

        model.isEditable = true

        let editableCommands = editorView.keyCommands
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "\t", modifierFlags: []))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "\t", modifierFlags: [.shift]))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "]", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "[", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "/", modifierFlags: [.command]))

        let indentActionTarget = editorView.target(
            forAction: NSSelectorFromString("handleIndentCommand"),
            withSender: nil
        ) as AnyObject?
        #expect(indentActionTarget === editorView)
    }

    @Test("SyntaxEditorView read-only handlers do not mutate text on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyHandlersDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(model: model)
        editorView.selectedRange = NSRange(location: 0, length: source.utf16.count)

        editorView.insertText("\t")
        #expect(performSyntaxEditorSelector("handleIndentCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleOutdentCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleToggleCommentCommand", on: editorView))

        #expect(model.text == source)
        #expect(editorView.text == source)
    }

    @Test("SyntaxEditorView uses native iOS undo stack for text input")
    @MainActor
    func syntaxEditorViewIOSNativeTextInputUndoRedo() {
        let source = "let answer = 42"
        let editedSource = "\(source)!"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        #expect(!editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))

        editorView.insertText("!")

        #expect(model.text == editedSource)
        #expect(editorView.text == editedSource)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        #expect(editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))
        #expect(performSyntaxEditorSelector("handleUndoCommand", on: editorView))

        #expect(model.text == source)
        #expect(editorView.text == source)
        #expect(undoManager.canRedo)
        #expect(!editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))

        #expect(performSyntaxEditorSelector("handleRedoCommand", on: editorView))

        #expect(model.text == editedSource)
        #expect(editorView.text == editedSource)
        #expect(editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))
    }

    @Test("SyntaxEditorView read-only undo and redo do not mutate text on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyUndoRedoDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        editorView.selectedRange = NSRange(location: 0, length: 0)

        #expect(performSyntaxEditorSelector("handleIndentCommand", on: editorView))
        let indentedSource = "    \(source)"
        #expect(model.text == indentedSource)
        #expect(editorView.text == indentedSource)

        model.isEditable = false

        #expect(!editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))
        #expect(performSyntaxEditorSelector("handleUndoCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleRedoCommand", on: editorView))

        #expect(model.text == indentedSource)
        #expect(editorView.text == indentedSource)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        undoManager.undo()
        undoManager.redo()

        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)
        #expect(model.text == indentedSource)
        #expect(editorView.text == indentedSource)

        model.isEditable = true

        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.text == source)
        #expect(editorView.text == source)
    }

    @Test("SyntaxEditorView restores command selection through iOS undo and redo")
    @MainActor
    func syntaxEditorViewIOSCommandUndoRedoRestoresSelection() {
        let source = "let answer = 42"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        editorView.selectedRange = NSRange(location: 4, length: 0)

        #expect(performSyntaxEditorSelector("handleIndentCommand", on: editorView))
        let indentedSource = "    \(source)"
        let indentedSelection = NSRange(location: 8, length: 0)
        #expect(model.text == indentedSource)
        #expect(editorView.text == indentedSource)
        #expect(editorView.selectedRange == indentedSelection)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(model.text == source)
        #expect(editorView.text == source)
        #expect(editorView.selectedRange == NSRange(location: 4, length: 0))

        #expect(undoManager.canRedo)
        undoManager.redo()
        #expect(model.text == indentedSource)
        #expect(editorView.text == indentedSource)
        #expect(editorView.selectedRange == indentedSelection)
    }

    @Test("SyntaxEditorView reapplies iOS bracket highlight after syntax refresh")
    @MainActor
    func syntaxEditorViewIOSReappliesBracketHighlightAfterSyntaxRefresh() async {
        let source = "let pair = ()"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        let bracketLocation = (source as NSString).range(of: "(").location
        editorView.selectedRange = NSRange(location: bracketLocation + 1, length: 0)
        await editorView.waitForPendingHighlightForTesting()

        #expect(iOSEditorHasBackgroundAttribute(editorView, at: bracketLocation))

        model.text = "\(source) "

        editorView.synchronizeModelForTesting()
        #expect(editorView.text == model.text)
        await editorView.waitForPendingHighlightForTesting()
        #expect(iOSEditorHasBackgroundAttribute(editorView, at: bracketLocation))
    }

    @Test("SyntaxEditorView keeps selection and copy available while read-only on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyKeepsSelectionAndCopy() {
        let source = "copy me"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.javascript,
            isEditable: false
        )
        let editorView = SyntaxEditorView(model: model)
        editorView.isSelectable = true

        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.loadViewIfNeeded()
        controller.view.addSubview(editorView)
        window.makeKeyAndVisible()

        #expect(editorView.becomeFirstResponder())
        #expect(editorView.isFirstResponder)

        let selectedRange = NSRange(location: 0, length: 4)
        editorView.selectedRange = selectedRange

        withExtendedLifetime(window) {
            #expect(editorView.isSelectable)
            #expect(editorView.selectedRange == selectedRange)
            #expect(editorView.canPerformAction(
                #selector(UIResponderStandardEditActions.copy(_:)),
                withSender: nil
            ))
        }

        #expect(editorView.resignFirstResponder())
        #expect(!editorView.isFirstResponder)
    }
#endif

#if canImport(AppKit)
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

    @Test("SyntaxEditorView reflects model text mutations on macOS")
    @MainActor
    func syntaxEditorViewMacTextObservation() async {
        let model = SyntaxEditorModel(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(model: model)

        model.text = "{\"enabled\":true}"

        editorView.synchronizeModelForTesting()
        #expect(editorView.textView.string == "{\"enabled\":true}")
    }

    @Test("SyntaxEditorView reflects custom macOS color theme")
    @MainActor
    func syntaxEditorViewMacColorThemeObservation() async {
        let source = "let value = \"text\""
        let initialTheme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456)
        )
        let updatedTheme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter()
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let editorView = SyntaxEditorView(model: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.colorTheme = updatedTheme

        editorView.synchronizeModelForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
    }

    @Test("SyntaxEditorView reapplies cached macOS syntax colors without highlighting")
    @MainActor
    func syntaxEditorViewMacColorThemeReusesCachedHighlightTokens() async {
        let source = "let value = \"text\""
        let initialTheme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
        )
        let updatedTheme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x654321),
            keyword: syntaxEditorUITestColor(hex: 0x876543)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxHighlightToken(
                    range: NSRange(location: 0, length: 3),
                    captureName: "keyword"
                ),
            ]
        )
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let editorView = SyntaxEditorView(model: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), initialTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.colorTheme = updatedTheme

        editorView.synchronizeModelForTesting()
        #expect(
            syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.keyword)
                && syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground)
        )
        await editorView.waitForPendingHighlightForTesting()
        #expect(await highlighter.callCount() == initialCallCount)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
    }

    @Test("SyntaxEditorView preserves macOS syntax colors after editor state changes")
    @MainActor
    func syntaxEditorViewMacEditorStateDoesNotResetSyntaxColors() async {
        let source = "let value = \"text\""
        let theme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(model: model)

        editorView.textView.textStorage?.addAttribute(
            .foregroundColor,
            value: theme.keyword,
            range: NSRange(location: 0, length: 3)
        )
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.lineWrappingEnabled = true

        editorView.synchronizeModelForTesting()
        #expect(editorView.hasHorizontalScroller == false)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.isEditable = false

        editorView.synchronizeModelForTesting()
        #expect(editorView.textView.isEditable == false)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewMacEditorStateObservation() async {
        let model = SyntaxEditorModel(text: "body {}", language: SyntaxLanguage.css)
        let editorView = SyntaxEditorView(model: model)

        model.isEditable = false
        model.lineWrappingEnabled = true

        editorView.synchronizeModelForTesting()
        #expect(
            editorView.textView.isEditable == false
                && editorView.hasHorizontalScroller == false
        )

        model.lineWrappingEnabled = false

        editorView.synchronizeModelForTesting()
        #expect(editorView.hasHorizontalScroller == true)
    }

    @Test("SyntaxEditorView redraws macOS text after enabling wrapping from a horizontal scroll")
    @MainActor
    func syntaxEditorViewMacWrappingResetsHorizontalClipOrigin() async {
        let model = SyntaxEditorModel(
            text: String(repeating: "let horizontalScrollNeedsWrapping = true; ", count: 32),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutMacEditorView(editorView)

        editorView.textView.frame.size.width = 1_600
        editorView.contentView.scroll(to: NSPoint(x: 600, y: editorView.contentView.bounds.origin.y))
        editorView.reflectScrolledClipView(editorView.contentView)
        #expect(editorView.contentView.bounds.origin.x > 0)

        model.lineWrappingEnabled = true

        editorView.synchronizeModelForTesting()
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

    @Test("SyntaxEditorView wraps to unobscured macOS content width")
    @MainActor
    func syntaxEditorViewMacWrappingAccountsForContentInsets() async {
        let model = SyntaxEditorModel(
            text: String(repeating: "let insetAwareWrappingWidth = true; ", count: 16),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(model: model)
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
        let model = SyntaxEditorModel(
            text: String(repeating: "let resizedWrappingWidth = true; ", count: 16),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(model: model)
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

    @Test("SyntaxEditorView keeps inset macOS wrapping geometry after resize")
    @MainActor
    func syntaxEditorViewMacWrappingTracksInsetContentWidthAfterResize() async {
        let model = SyntaxEditorModel(
            text: String(repeating: "let insetResizeWrappingWidth = true; ", count: 16),
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(model: model)
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
        let model = SyntaxEditorModel(text: "let answer = 42", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)

        model.language = SyntaxLanguage.json
        model.isEditable = false

        editorView.synchronizeModelForTesting()
        #expect(editorView.textView.isEditable == false)

        model.text = "{\"answer\":42}"

        editorView.synchronizeModelForTesting()
        #expect(editorView.textView.string == "{\"answer\":42}")
    }

    @Test("SyntaxEditorView read-only delegate commands do not mutate text on macOS")
    @MainActor
    func syntaxEditorViewMacReadOnlyDelegateCommandsDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(model: model)
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
            #expect(model.text == source)
            #expect(editorView.textView.string == source)
        }
    }

    @Test("SyntaxEditorView read-only key equivalents do not mutate text on macOS")
    @MainActor
    func syntaxEditorViewMacReadOnlyKeyEquivalentsDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorModel(
            text: source,
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(model: model)
        editorView.textView.setSelectedRange(NSRange(location: 0, length: source.utf16.count))

        for character in ["/", "]", "["] {
            guard let event = makeMacCommandKeyEvent(character) else {
                Issue.record("Failed to create command key event for \(character)")
                continue
            }

            _ = editorView.textView.performKeyEquivalent(with: event)
            #expect(model.text == source)
            #expect(editorView.textView.string == source)
        }
    }

    @Test("SyntaxEditorView uses native macOS undo stack for text input")
    @MainActor
    func syntaxEditorViewMacNativeTextInputUndoRedo() async {
        let source = "let answer = 42"
        let editedSource = "\(source)!"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
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

        #expect(model.text == editedSource)
        #expect(editorView.textView.string == editedSource)

        let undoSelector = NSSelectorFromString("undo:")
        let redoSelector = NSSelectorFromString("redo:")
        let undoItem = NSMenuItem(title: "Undo", action: undoSelector, keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: redoSelector, keyEquivalent: "Z")

        #expect(undoManager.canUndo)
        #expect(editorView.textView.validateUserInterfaceItem(undoItem))

        model.isEditable = false
        editorView.synchronizeModelForTesting()
        #expect(editorView.textView.isEditable == false)
        #expect(!undoManager.canUndo)
        #expect(!editorView.textView.validateUserInterfaceItem(undoItem))

        #expect(NSApplication.shared.sendAction(undoSelector, to: editorView.textView, from: undoItem))
        #expect(model.text == editedSource)
        #expect(editorView.textView.string == editedSource)

        model.isEditable = true
        editorView.synchronizeModelForTesting()
        #expect(editorView.textView.isEditable == true)

        #expect(undoManager.canUndo)
        #expect(NSApplication.shared.sendAction(undoSelector, to: editorView.textView, from: undoItem))

        #expect(model.text == source)
        #expect(editorView.textView.string == source)
        #expect(undoManager.canRedo)
        #expect(editorView.textView.validateUserInterfaceItem(redoItem))
        #expect(NSApplication.shared.sendAction(redoSelector, to: editorView.textView, from: redoItem))

        #expect(model.text == editedSource)
        #expect(editorView.textView.string == editedSource)
    }

    @Test("SyntaxEditorView preserves undo history when undo manager runs while read-only on macOS")
    @MainActor
    func syntaxEditorViewMacReadOnlyUndoManagerPreservesHistory() async {
        let source = "let answer = 42"
        let onceIndentedSource = "    \(source)"
        let twiceIndentedSource = "        \(source)"
        let model = SyntaxEditorModel(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(model: model)
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
        #expect(model.text == twiceIndentedSource)

        model.isEditable = false
        undoManager.undo()
        undoManager.undo()

        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)
        #expect(model.text == twiceIndentedSource)
        #expect(editorView.textView.string == twiceIndentedSource)

        model.isEditable = true

        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.text == onceIndentedSource)
        #expect(editorView.textView.string == onceIndentedSource)
        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.text == source)
        #expect(editorView.textView.string == source)
        #expect(undoManager.canRedo)

        model.isEditable = false
        undoManager.redo()
        undoManager.redo()

        #expect(model.text == source)
        #expect(editorView.textView.string == source)
        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)

        model.isEditable = true

        #expect(undoManager.canRedo)
        undoManager.redo()

        #expect(model.text == twiceIndentedSource)
        #expect(editorView.textView.string == twiceIndentedSource)
    }

    @Test("SyntaxEditorViewController enables undo support on macOS")
    @MainActor
    func syntaxEditorViewControllerMacUndo() {
        let model = SyntaxEditorModel(text: "{}", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        let textView = controller.textView
        #expect(textView.allowsUndo == true)
    }

    @Test("SyntaxEditorViewController preserves Observable conformance on macOS")
    @MainActor
    func syntaxEditorViewControllerMacObservableCompatibility() {
        let model = SyntaxEditorModel(text: "{}", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(model: model)

        requireObservable(controller)
        requireNSTextViewDelegate(controller)
        #expect(controller.model === model)
        #expect(
            controller.textView(
                controller.textView,
                shouldChangeTextIn: NSRange(location: 0, length: 0),
                replacementString: "a"
            )
        )
    }

    @Test("SyntaxEditorViewController reflects model text mutations on macOS")
    @MainActor
    func syntaxEditorViewControllerMacTextObservation() async {
        let model = SyntaxEditorModel(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.text = "{\"enabled\":true}"

        controller.synchronizeModelForTesting()
        #expect(controller.textView.string == "{\"enabled\":true}")
    }

    @Test("SyntaxEditorViewController reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacEditorStateObservation() async {
        let model = SyntaxEditorModel(text: "body {}", language: SyntaxLanguage.css)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.isEditable = false
        model.lineWrappingEnabled = true

        controller.synchronizeModelForTesting()
        #expect(
            controller.textView.isEditable == false
                && controller.scrollView.hasHorizontalScroller == false
        )

        model.lineWrappingEnabled = false

        controller.synchronizeModelForTesting()
        #expect(controller.scrollView.hasHorizontalScroller == true)
    }

    @Test("SyntaxEditorViewController keeps synchronizing after language changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacLanguageChangeKeepsObservationAlive() async {
        let model = SyntaxEditorModel(text: "let answer = 42", language: SyntaxLanguage.swift)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.language = SyntaxLanguage.json
        model.isEditable = false

        controller.synchronizeModelForTesting()
        #expect(controller.textView.isEditable == false)

        model.text = "{\"answer\":42}"

        controller.synchronizeModelForTesting()
        #expect(controller.textView.string == "{\"answer\":42}")
    }
#endif
}
