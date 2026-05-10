import Foundation
import Observation
import SwiftUI
import Testing
@testable import SyntaxEditorUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

private func requireObservable<T: Observable>(_ value: T) {}

@MainActor
@Observable
private final class SyntaxEditorSwiftUIProbe {
    var tick = 0
    let document = SyntaxEditorDocument(text: "let value = 1")
    var configuration = SyntaxEditorConfiguration(language: SyntaxLanguage.javascript)
}

private struct SyntaxEditorDefaultWrapperHost: View {
    var probe: SyntaxEditorSwiftUIProbe

    var body: some View {
        VStack {
            SyntaxEditor()
            Text("\(probe.tick)")
        }
    }
}

private struct SyntaxEditorConfigurationReplacementHost: View {
    var probe: SyntaxEditorSwiftUIProbe

    var body: some View {
        VStack {
            SyntaxEditor(document: probe.document, configuration: probe.configuration)
            Text("\(probe.tick)")
        }
    }
}

#if canImport(UIKit)
@MainActor
private func syntaxEditorUIView<Subview: UIView>(
    ofType type: Subview.Type,
    in view: UIView
) -> Subview? {
    if let view = view as? Subview {
        return view
    }

    for subview in view.subviews {
        if let match = syntaxEditorUIView(ofType: type, in: subview) {
            return match
        }
    }

    return nil
}

@MainActor
private func syntaxEditorSettleUIKitHost<Content: View>(_ controller: UIHostingController<Content>) {
    controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
#elseif canImport(AppKit)
@MainActor
private func syntaxEditorNSView<Subview: NSView>(
    ofType type: Subview.Type,
    in view: NSView
) -> Subview? {
    if let view = view as? Subview {
        return view
    }

    for subview in view.subviews {
        if let match = syntaxEditorNSView(ofType: type, in: subview) {
            return match
        }
    }

    return nil
}

@MainActor
private func syntaxEditorSettleAppKitHost<Content: View>(_ controller: NSHostingController<Content>) {
    controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    controller.view.needsLayout = true
    controller.view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
#endif

@MainActor
private struct SyntaxEditorTestContext {
    let document: SyntaxEditorDocument
    let configuration: SyntaxEditorConfiguration

    init(
        text: String = "",
        language: SyntaxLanguage = .javascript,
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false,
        colorTheme: SyntaxEditorColorTheme = .xcode
    ) {
        self.document = SyntaxEditorDocument(text: text)
        self.configuration = SyntaxEditorConfiguration(
            language: language,
            isEditable: isEditable,
            lineWrappingEnabled: lineWrappingEnabled,
            colorTheme: colorTheme
        )
    }
}

extension SyntaxEditorView {
    fileprivate convenience init(testContext: SyntaxEditorTestContext) {
        self.init(document: testContext.document, configuration: testContext.configuration)
    }

    fileprivate convenience init(testContext: SyntaxEditorTestContext, highlighter: any SyntaxHighlighting) {
        self.init(document: testContext.document, configuration: testContext.configuration, highlighter: highlighter)
    }
}

extension SyntaxEditorViewController {
    fileprivate convenience init(testContext: SyntaxEditorTestContext) {
        self.init(document: testContext.document, configuration: testContext.configuration)
    }
}

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
    private let updateRefreshRange: NSRange?
    private var resetCount = 0
    private var updateCount = 0

    init(
        tokens: [SyntaxHighlightToken] = [],
        delayNanoseconds: UInt64 = 0,
        updateRefreshRange: NSRange? = nil
    ) {
        self.tokens = tokens
        self.delayNanoseconds = delayNanoseconds
        self.updateRefreshRange = updateRefreshRange
    }

    func reset(source: String, language: SyntaxLanguage, revision: Int) async -> SyntaxHighlightResult {
        resetCount += 1
        await delayIfNeeded()
        return result(source: source, language: language, revision: revision, refreshRange: nil)
    }

    func update(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> SyntaxHighlightResult {
        updateCount += 1
        await delayIfNeeded()
        return result(source: source, language: language, revision: revision, refreshRange: updateRefreshRange)
    }

    func callCount() -> Int {
        resetCount + updateCount
    }

    private func delayIfNeeded() async {
        guard delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }

    private func result(
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        refreshRange: NSRange?
    ) -> SyntaxHighlightResult {
        SyntaxHighlightResult(
            tokens: tokens,
            source: source,
            language: language,
            revision: revision,
            refreshRange: refreshRange ?? NSRange(location: 0, length: source.utf16.count)
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
private func syntaxEditorKeyCommand(
    _ commands: [UIKeyCommand]?,
    input: String,
    modifierFlags: UIKeyModifierFlags
) -> UIKeyCommand? {
    commands?.first { command in
        command.input == input
            && command.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == modifierFlags
    }
}

@MainActor
private func hasSyntaxEditorKeyCommand(
    _ commands: [UIKeyCommand]?,
    input: String,
    modifierFlags: UIKeyModifierFlags
) -> Bool {
    syntaxEditorKeyCommand(commands, input: input, modifierFlags: modifierFlags) != nil
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
private func iOSEditorLineFragmentForegroundColor(_ editorView: SyntaxEditorView, at location: Int) -> UIColor? {
    guard let textLayoutManager = editorView.textLayoutManager,
          let textLocation = editorView.textLocation(forUTF16Offset: location)
    else {
        return nil
    }

    guard let layoutFragment = textLayoutManager.textLayoutFragment(for: textLocation),
          let lineFragment = layoutFragment.textLineFragments.first(where: {
              NSLocationInRange(location, $0.characterRange)
          })
    else {
        return nil
    }

    let localLocation = location - lineFragment.characterRange.location
    guard localLocation >= 0, localLocation < lineFragment.attributedString.length else {
        return nil
    }
    return lineFragment.attributedString.attribute(.foregroundColor, at: localLocation, effectiveRange: nil) as? UIColor
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

private func makeMacCommandKeyEvent(
    _ character: String,
    modifierFlags: NSEvent.ModifierFlags = [.command]
) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
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
    @Test("SyntaxEditor preserves default SwiftUI document across parent updates")
    @MainActor
    func syntaxEditorPreservesDefaultSwiftUIDocumentAcrossParentUpdates() throws {
        let probe = SyntaxEditorSwiftUIProbe()
        let editedText = "let edited = 2"

#if canImport(UIKit)
        let controller = UIHostingController(rootView: SyntaxEditorDefaultWrapperHost(probe: probe))
        syntaxEditorSettleUIKitHost(controller)
        let firstEditor = try #require(syntaxEditorUIView(ofType: SyntaxEditorView.self, in: controller.view))

        firstEditor.document.replaceText(editedText)
        firstEditor.synchronizeDocumentForTesting()
        syntaxEditorSettleUIKitHost(controller)
        probe.tick += 1
        syntaxEditorSettleUIKitHost(controller)

        let secondEditor = try #require(syntaxEditorUIView(ofType: SyntaxEditorView.self, in: controller.view))
        #expect(firstEditor === secondEditor)
        #expect(secondEditor.document === firstEditor.document)
        #expect(secondEditor.document.textSnapshot() == editedText)
        #expect(secondEditor.text == editedText)
#elseif canImport(AppKit)
        let controller = NSHostingController(rootView: SyntaxEditorDefaultWrapperHost(probe: probe))
        syntaxEditorSettleAppKitHost(controller)
        let firstEditor = try #require(syntaxEditorNSView(ofType: SyntaxEditorView.self, in: controller.view))

        firstEditor.document.replaceText(editedText)
        firstEditor.synchronizeDocumentForTesting()
        syntaxEditorSettleAppKitHost(controller)
        probe.tick += 1
        syntaxEditorSettleAppKitHost(controller)

        let secondEditor = try #require(syntaxEditorNSView(ofType: SyntaxEditorView.self, in: controller.view))
        #expect(firstEditor === secondEditor)
        #expect(secondEditor.document === firstEditor.document)
        #expect(secondEditor.document.textSnapshot() == editedText)
        #expect(secondEditor.textView.string == editedText)
#endif
    }

    @Test("SyntaxEditor rebinds replaced SwiftUI configuration without recreating native view")
    @MainActor
    func syntaxEditorRebindsReplacedSwiftUIConfigurationWithoutRecreatingNativeView() throws {
        let probe = SyntaxEditorSwiftUIProbe()
        let replacementConfiguration = SyntaxEditorConfiguration(
            language: SyntaxLanguage.json,
            isEditable: false,
            lineWrappingEnabled: true
        )

#if canImport(UIKit)
        let controller = UIHostingController(rootView: SyntaxEditorConfigurationReplacementHost(probe: probe))
        syntaxEditorSettleUIKitHost(controller)
        let firstEditor = try #require(syntaxEditorUIView(ofType: SyntaxEditorView.self, in: controller.view))

        probe.configuration = replacementConfiguration
        probe.tick += 1
        syntaxEditorSettleUIKitHost(controller)

        let secondEditor = try #require(syntaxEditorUIView(ofType: SyntaxEditorView.self, in: controller.view))
        #expect(firstEditor === secondEditor)
        #expect(secondEditor.configuration === replacementConfiguration)
        #expect(secondEditor.configuration.language == SyntaxLanguage.json)
        #expect(secondEditor.configuration.isEditable == false)
#elseif canImport(AppKit)
        let controller = NSHostingController(rootView: SyntaxEditorConfigurationReplacementHost(probe: probe))
        syntaxEditorSettleAppKitHost(controller)
        let firstEditor = try #require(syntaxEditorNSView(ofType: SyntaxEditorView.self, in: controller.view))

        probe.configuration = replacementConfiguration
        probe.tick += 1
        syntaxEditorSettleAppKitHost(controller)

        let secondEditor = try #require(syntaxEditorNSView(ofType: SyntaxEditorView.self, in: controller.view))
        #expect(firstEditor === secondEditor)
        #expect(secondEditor.configuration === replacementConfiguration)
        #expect(secondEditor.configuration.language == SyntaxLanguage.json)
        #expect(secondEditor.configuration.isEditable == false)
        #expect(secondEditor.textView.isEditable == false)
#endif
    }

    @Test("SyntaxEditorView clears undo state when rebinding document")
    @MainActor
    func syntaxEditorViewClearsUndoStateWhenRebindingDocument() throws {
        let source = "let value = 1"
        let editedSource = "\(source)!"
        let replacementDocument = SyntaxEditorDocument(text: "let other = 2")
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)

#if canImport(UIKit)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        editorView.insertText("!")
        let undoManager = try #require(editorView.undoManager)

        #expect(model.document.textSnapshot() == editedSource)
        #expect(undoManager.canUndo)

        editorView.update(document: replacementDocument, configuration: model.configuration)

        #expect(editorView.document === replacementDocument)
        #expect(editorView.text == replacementDocument.textSnapshot())
        #expect(!undoManager.canUndo)
#elseif canImport(AppKit)
        let editorView = SyntaxEditorView(testContext: model)
        let undoManager = try #require(editorView.textView.undoManager)
        let editRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(editRange)
        editorView.textView.insertText("!", replacementRange: editRange)
        editorView.textView.breakUndoCoalescing()

        #expect(model.document.textSnapshot() == editedSource)
        #expect(undoManager.canUndo)

        editorView.update(document: replacementDocument, configuration: model.configuration)

        #expect(editorView.document === replacementDocument)
        #expect(editorView.textView.string == replacementDocument.textSnapshot())
        #expect(!undoManager.canUndo)
#endif
    }

    @Test("SyntaxEditorView clears undo state for observed whole document replacements")
    @MainActor
    func syntaxEditorViewClearsUndoStateForObservedWholeDocumentReplacements() throws {
        let source = "abc"
        let editedSource = "\(source)!"
        let replacementText = "x"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)

#if canImport(UIKit)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        editorView.insertText("!")
        let undoManager = try #require(editorView.undoManager)

        #expect(model.document.textSnapshot() == editedSource)
        #expect(undoManager.canUndo)

        model.document.replaceText(replacementText)
        editorView.synchronizeDocumentForTesting()

        #expect(editorView.text == replacementText)
        #expect(!undoManager.canUndo)
#elseif canImport(AppKit)
        let editorView = SyntaxEditorView(testContext: model)
        let undoManager = try #require(editorView.textView.undoManager)
        let editRange = NSRange(location: source.utf16.count, length: 0)
        editorView.textView.setSelectedRange(editRange)
        editorView.textView.insertText("!", replacementRange: editRange)
        editorView.textView.breakUndoCoalescing()

        #expect(model.document.textSnapshot() == editedSource)
        #expect(undoManager.canUndo)

        model.document.replaceText(replacementText)
        editorView.synchronizeDocumentForTesting()

        #expect(editorView.textView.string == replacementText)
        #expect(!undoManager.canUndo)
#endif
    }

    @Test("SyntaxEditorView does not reuse cached highlights after document rebind")
    @MainActor
    func syntaxEditorViewDoesNotReuseCachedHighlightsAfterDocumentRebind() async {
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
            ],
            delayNanoseconds: 30_000_000
        )
        let model = SyntaxEditorTestContext(
            text: "let old = 1",
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let replacementDocument = SyntaxEditorDocument(text: "abc new = 1")

#if canImport(UIKit)
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), initialTheme.keyword))

        editorView.update(document: replacementDocument, configuration: model.configuration)
        model.configuration.colorTheme = updatedTheme
        editorView.synchronizeDocumentForTesting()

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), updatedTheme.baseForeground))
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
#elseif canImport(AppKit)
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), initialTheme.keyword))

        editorView.update(document: replacementDocument, configuration: model.configuration)
        model.configuration.colorTheme = updatedTheme
        editorView.synchronizeDocumentForTesting()

        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.baseForeground))
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
#endif
    }

#if canImport(UIKit)
    @Test("SyntaxEditorViewController preserves Observable conformance on iOS")
    @MainActor
    func syntaxEditorViewControllerIOSObservableCompatibility() {
        let model = SyntaxEditorTestContext(text: "{}", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(testContext: model)

        requireObservable(controller)
        #expect(controller.document === model.document)
        #expect(controller.configuration === model.configuration)
        #expect(controller.editorView.document === model.document)
        #expect(controller.editorView.configuration === model.configuration)
    }

    @Test("SyntaxEditorView is the iOS custom scroll text input surface")
    @MainActor
    func syntaxEditorViewIOSUsesCustomScrollTextInputSurface() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "let value = 1"))
        let scrollSurface: UIScrollView = editorView
        let textInputSurface: any UITextInput = editorView

        #expect(scrollSurface === editorView)
        #expect(textInputSurface.textInputView === editorView)
        #expect(editorView.keyboardType == .default)
    }

    @Test("SyntaxEditorView enables iOS find interaction by default")
    @MainActor
    func syntaxEditorViewIOSEnablesFindInteractionByDefault() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "let value = 1"))

        #expect(editorView.isFindInteractionEnabled)
        #expect(editorView.findInteraction != nil)
        #expect(editorView.canPerformAction(#selector(UIResponderStandardEditActions.find(_:)), withSender: nil))
        #expect(editorView.canPerformAction(#selector(UIResponderStandardEditActions.findAndReplace(_:)), withSender: nil))
        #expect(!editorView.canPerformAction(#selector(UIResponderStandardEditActions.useSelectionForFind(_:)), withSender: nil))

        editorView.selectedRange = NSRange(location: 4, length: 5)
        #expect(editorView.canPerformAction(#selector(UIResponderStandardEditActions.useSelectionForFind(_:)), withSender: nil))

        editorView.isFindInteractionEnabled = false
        #expect(editorView.findInteraction == nil)
        #expect(!editorView.canPerformAction(#selector(UIResponderStandardEditActions.find(_:)), withSender: nil))
        #expect(!editorView.canPerformAction(#selector(UIResponderStandardEditActions.findAndReplace(_:)), withSender: nil))
        #expect(!editorView.canPerformAction(#selector(UIResponderStandardEditActions.useSelectionForFind(_:)), withSender: nil))

        editorView.isFindInteractionEnabled = true
        #expect(editorView.findInteraction != nil)
        #expect(editorView.canPerformAction(#selector(UIResponderStandardEditActions.find(_:)), withSender: nil))
        #expect(editorView.canPerformAction(#selector(UIResponderStandardEditActions.findAndReplace(_:)), withSender: nil))
        #expect(editorView.canPerformAction(#selector(UIResponderStandardEditActions.useSelectionForFind(_:)), withSender: nil))
    }

    @Test("SyntaxEditorView clears iOS find decorations when disabling find interaction")
    @MainActor
    func syntaxEditorViewIOSClearsFindDecorationsWhenDisablingFindInteraction() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "let value = value"))
        let foundRange = NSRange(location: 4, length: 5)
        let highlightedRange = NSRange(location: 12, length: 5)

        editorView.decorateFindTextRange(foundRange, style: .found)
        editorView.decorateFindTextRange(highlightedRange, style: .highlighted)
        #expect(editorView.findFoundRangesForTesting == [foundRange])
        #expect(editorView.findHighlightedRangesForTesting == [highlightedRange])

        editorView.isFindInteractionEnabled = false
        #expect(editorView.findFoundRangesForTesting.isEmpty)
        #expect(editorView.findHighlightedRangesForTesting.isEmpty)
    }

    @Test("SyntaxEditorView batches iOS find decoration redraws during search")
    @MainActor
    func syntaxEditorViewIOSBatchesFindDecorationRedrawsDuringSearch() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "foo foo foo"))
        let ranges = [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 3),
            NSRange(location: 8, length: 3),
        ]
        let initialUpdatePassCount = editorView.findHighlightUpdatePassCountForTesting

        editorView.beginFindDecorationBatch()
        for range in ranges {
            editorView.decorateFindTextRange(range, style: .found)
        }

        #expect(editorView.findFoundRangesForTesting == ranges)
        #expect(editorView.findHighlightUpdatePassCountForTesting == initialUpdatePassCount)

        editorView.endFindDecorationBatch()
        #expect(editorView.findHighlightUpdatePassCountForTesting == initialUpdatePassCount + 1)
    }

    @Test("SyntaxEditorView clips iOS highlight ranges to layout fragments")
    @MainActor
    func syntaxEditorViewIOSClipsHighlightRangesToLayoutFragments() {
        let ranges = [
            NSRange(location: 10, length: 5),
            NSRange(location: 30, length: 10),
            NSRange(location: 60, length: 2),
        ]

        #expect(
            SyntaxEditorView.ranges(
                ranges,
                intersecting: NSRange(location: 12, length: 25)
            ) == [
                NSRange(location: 12, length: 3),
                NSRange(location: 30, length: 7),
            ]
        )
        #expect(SyntaxEditorView.ranges(ranges, intersecting: NSRange(location: 100, length: 5)).isEmpty)
    }

    @Test("SyntaxEditorFindCoordinator matches iOS find options")
    @MainActor
    func syntaxEditorFindCoordinatorIOSMatchesFindOptions() {
        let source = "foo foobar barfoo foo_bar foo"

        #expect(SyntaxEditorFindCoordinator.searchRanges(
            in: source,
            queryString: "foo",
            wordMatchMethod: .contains
        ).count == 5)
        #expect(SyntaxEditorFindCoordinator.searchRanges(
            in: source,
            queryString: "foo",
            wordMatchMethod: .startsWith
        ).count == 4)
        #expect(SyntaxEditorFindCoordinator.searchRanges(
            in: source,
            queryString: "foo",
            wordMatchMethod: .fullWord
        ).count == 2)

        let composedSource = "e\u{301}"
        #expect(SyntaxEditorFindCoordinator.searchRanges(
            in: composedSource,
            queryString: "e",
            compareOptions: [.diacriticInsensitive],
            wordMatchMethod: .contains
        ) == [NSRange(location: 0, length: (composedSource as NSString).length)])

        #expect(SyntaxEditorFindCoordinator.searchRanges(
            in: "é éclair 変数 変数名",
            queryString: "é",
            wordMatchMethod: .fullWord
        ).count == 1)
        #expect(SyntaxEditorFindCoordinator.searchRanges(
            in: "é éclair 変数 変数名",
            queryString: "変数",
            wordMatchMethod: .fullWord
        ).count == 1)
    }

    @Test("SyntaxEditorFindCoordinator exposes iOS replace all selector")
    @MainActor
    func syntaxEditorFindCoordinatorIOSExposesReplaceAllSelector() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "foo foo"))
        let replaceAllSelector = NSSelectorFromString(
            "replaceAllOccurrencesOfQueryString:usingOptions:withText:"
        )

        #expect(editorView.findCoordinator?.responds(to: replaceAllSelector) == true)
    }

    @Test("SyntaxEditorView clips iOS find highlight ranges to a fragment")
    @MainActor
    func syntaxEditorViewIOSClipsFindHighlightRangesToFragment() {
        let ranges = [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3),
            NSRange(location: 12, length: 2),
            NSRange(location: 15, length: 1),
        ]

        #expect(SyntaxEditorView.ranges(
            ranges,
            intersecting: NSRange(location: 10, length: 5)
        ) == [
            NSRange(location: 10, length: 1),
            NSRange(location: 12, length: 2),
        ])
    }

    @Test("SyntaxEditorView clears stale iOS find decorations after text changes")
    @MainActor
    func syntaxEditorViewIOSClearsStaleFindDecorationsAfterTextChanges() {
        let model = SyntaxEditorTestContext(text: "let value = value", language: .swift)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.decorateFindTextRange(NSRange(location: 4, length: 5), style: .highlighted)

        model.document.replaceText("let other = other")
        editorView.synchronizeDocumentForTesting()

        #expect(editorView.findFoundRangesForTesting.isEmpty)
        #expect(editorView.findHighlightedRangesForTesting.isEmpty)
    }

    @Test("SyntaxEditorView scrolls iOS highlighted find ranges through the editor scroll pipeline")
    @MainActor
    func syntaxEditorViewIOSScrollsHighlightedFindRangesThroughEditorScrollPipeline() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: .swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 120, height: 80)
        let targetLocation = max(0, longIOSSyntaxEditorLine.utf16.count - 20)
        let targetRange = NSRange(location: targetLocation, length: 5)

        editorView.findCoordinator?.willHighlight(
            foundTextRange: SyntaxEditorTextRange(nsRange: targetRange),
            document: 0
        )

        #expect(editorView.contentOffset.x > 0)
    }

    @Test("SyntaxEditorView applies iOS find replacement without command transforms")
    @MainActor
    func syntaxEditorViewIOSAppliesFindReplacementWithoutCommandTransforms() {
        let source = "value"
        let model = SyntaxEditorTestContext(text: source, language: .javascript)
        let editorView = SyntaxEditorView(testContext: model)

        editorView.replaceFindText(in: NSRange(location: 0, length: source.utf16.count), with: "{")
        #expect(model.document.textSnapshot() == "{")
        #expect(editorView.text == "{")

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        undoManager.undo()
        #expect(model.document.textSnapshot() == source)
        #expect(editorView.text == source)
    }

    @Test("SyntaxEditorView applies iOS replace all as one undoable edit")
    @MainActor
    func syntaxEditorViewIOSAppliesReplaceAllAsOneUndoableEdit() {
        let source = "foo foo foo"
        let model = SyntaxEditorTestContext(text: source, language: .javascript)
        let editorView = SyntaxEditorView(testContext: model)

        #expect(editorView.replaceAllFindMatches(
            queryString: "foo",
            compareOptions: [],
            wordMatchMethod: .fullWord,
            with: "bar"
        ))
        #expect(model.document.textSnapshot() == "bar bar bar")
        #expect(editorView.text == "bar bar bar")

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        undoManager.undo()
        #expect(model.document.textSnapshot() == source)
        #expect(editorView.text == source)
    }

    @Test("SyntaxEditorView keeps iOS find available while read-only")
    @MainActor
    func syntaxEditorViewIOSKeepsFindAvailableWhileReadOnly() {
        let source = "foo foo"
        let model = SyntaxEditorTestContext(text: source, language: .javascript, isEditable: false)
        let editorView = SyntaxEditorView(testContext: model)

        #expect(editorView.findInteraction != nil)
        #expect(editorView.canPerformAction(#selector(UIResponderStandardEditActions.find(_:)), withSender: nil))
        #expect(!editorView.canPerformAction(#selector(UIResponderStandardEditActions.findAndReplace(_:)), withSender: nil))
        #expect(editorView.findCoordinator?.supportsTextReplacement == false)
        #expect(!editorView.replaceAllFindMatches(
            queryString: "foo",
            compareOptions: [],
            wordMatchMethod: .fullWord,
            with: "bar"
        ))

        editorView.replaceFindText(in: NSRange(location: 0, length: 3), with: "bar")
        #expect(model.document.textSnapshot() == source)
        #expect(editorView.text == source)
    }

    @Test("SyntaxEditorView leaves iOS indirect pointer drags for text selection")
    @MainActor
    func syntaxEditorViewIOSLeavesIndirectPointerDragsForTextSelection() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "let value = 1"))
        let allowedTouchTypes = Set(editorView.panGestureRecognizer.allowedTouchTypes.map { Int($0.intValue) })

        #expect(allowedTouchTypes.contains(UITouch.TouchType.direct.rawValue))
        #expect(allowedTouchTypes.contains(UITouch.TouchType.pencil.rawValue))
        #expect(allowedTouchTypes.contains(UITouch.TouchType.indirect.rawValue))
        #expect(!allowedTouchTypes.contains(UITouch.TouchType.indirectPointer.rawValue))
    }

    @Test("SyntaxEditorView receives iOS text interaction hit tests through the rendering view")
    @MainActor
    func syntaxEditorViewIOSReceivesTextInteractionHitTestsThroughRenderingView() {
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: "let value = 1"))
        layoutIOSEditorView(editorView)

        let hitView = editorView.hitTest(CGPoint(x: 24, y: 24), with: nil)

        #expect(hitView === editorView)
    }

    @Test("SyntaxEditorView applies transformed iOS text input to the document")
    @MainActor
    func syntaxEditorViewIOSAppliesTransformedTextInputToDocument() {
        let model = SyntaxEditorTestContext(text: "", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        editorView.insertText("{")
        #expect(editorView.text == "{}")
        #expect(model.document.textSnapshot() == "{}")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))

        editorView.insertText("\n")
        #expect(editorView.text == "{\n    \n}")
        #expect(model.document.textSnapshot() == "{\n    \n}")
        #expect(editorView.selectedRange == NSRange(location: 6, length: 0))
    }

    @Test("SyntaxEditorView notifies the iOS input delegate for transformed text input")
    @MainActor
    func syntaxEditorViewIOSNotifiesInputDelegateForTransformedTextInput() {
        let model = SyntaxEditorTestContext(text: "", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        #expect(editorView.responds(to: NSSelectorFromString("insertText:alternatives:style:")))
        editorView.insertText(" ", alternatives: [], style: .none)

        #expect(editorView.text == source + " ")
        #expect(model.document.textSnapshot() == source + " ")
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("SyntaxEditorView underlines active iOS marked text")
    @MainActor
    func syntaxEditorViewIOSUnderlinesActiveMarkedText() {
        let model = SyntaxEditorTestContext(text: "let value = ", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let markedTextColor = syntaxEditorUITestColor(hex: 0xFF8800)
        editorView.tintColor = markedTextColor
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: model.document.textSnapshot().utf16.count, length: 0)

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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        #expect(model.document.textSnapshot() == source)
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count, length: 0))
    }

    @Test("SyntaxEditorView registers iOS undo for empty marked text replacement")
    @MainActor
    func syntaxEditorViewIOSRegistersUndoForEmptyMarkedTextReplacement() {
        let source = "let value = 42"
        let selectedRange = (source as NSString).range(of: "value")
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        #expect(model.document.textSnapshot() == source)
        #expect(editorView.selectedRange == selectedRange)
    }

    @Test("SyntaxEditorView replaces iOS marked text when IME commits through insertText")
    @MainActor
    func syntaxEditorViewIOSReplacesMarkedTextWhenIMECommitsThroughInsertText() {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("あいうえお", selectedRange: NSRange(location: 5, length: 0))
        editorView.insertText("作成")

        let committedSource = source + "作成"
        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == committedSource)
        #expect(model.document.textSnapshot() == committedSource)
        #expect(editorView.selectedRange == NSRange(location: committedSource.utf16.count, length: 0))

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(editorView.text == source)
        #expect(model.document.textSnapshot() == source)
    }

    @Test("SyntaxEditorView clears iOS marked text before normal insertion after IME commit")
    @MainActor
    func syntaxEditorViewIOSClearsMarkedTextBeforeNormalInsertionAfterIMECommit() {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("あいうえお", selectedRange: NSRange(location: 5, length: 0))
        editorView.insertText("作成")
        editorView.insertText("!")

        let expectedSource = source + "作成!"
        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == expectedSource)
        #expect(model.document.textSnapshot() == expectedSource)
        #expect(editorView.selectedRange == NSRange(location: expectedSource.utf16.count, length: 0))
    }

    @Test("SyntaxEditorView preserves iOS marked text when nil unmarks composition")
    @MainActor
    func syntaxEditorViewIOSPreservesMarkedTextWhenNilUnmarksComposition() {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        editorView.setMarkedText(nil, selectedRange: NSRange(location: 0, length: 0))

        let expectedText = source + "かな"
        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == expectedText)
        #expect(model.document.textSnapshot() == expectedText)
        #expect(editorView.selectedRange == NSRange(location: expectedText.utf16.count, length: 0))
    }

    @Test("SyntaxEditorView clears iOS marked text when selection leaves composition")
    @MainActor
    func syntaxEditorViewIOSClearsMarkedTextWhenSelectionLeavesComposition() {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        #expect(model.document.textSnapshot() == "X" + source + "かな")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView clears iOS marked text when selectedRange leaves composition")
    @MainActor
    func syntaxEditorViewIOSClearsMarkedTextWhenSelectedRangeLeavesComposition() {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        editorView.selectedRange = NSRange(location: 0, length: 0)
        editorView.insertText("X")

        #expect(editorView.markedTextRange == nil)
        #expect(editorView.text == "X" + source + "かな")
        #expect(model.document.textSnapshot() == "X" + source + "かな")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView does not commit iOS marked text while read-only")
    @MainActor
    func syntaxEditorViewIOSDoesNotCommitMarkedTextWhileReadOnly() {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        model.configuration.isEditable = false
        editorView.synchronizeDocumentForTesting()
        editorView.insertText("作成")

        #expect(editorView.text == source + "かな")
        #expect(model.document.textSnapshot() == source + "かな")
        #expect(editorView.markedTextRange != nil)
    }

    @Test("SyntaxEditorView coalesces repeated iOS marked text updates into one undo")
    @MainActor
    func syntaxEditorViewIOSCoalescesRepeatedMarkedTextUpdatesIntoOneUndo() {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: ("a🙂" as NSString).length, length: 0)

        editorView.deleteBackward()

        #expect(editorView.text == "ab")
        #expect(model.document.textSnapshot() == "ab")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView preserves iOS UTF-16 position round trips")
    @MainActor
    func syntaxEditorViewIOSPreservesUTF16PositionRoundTrips() {
        let source = "🙂"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.toml)
        let editorView = SyntaxEditorView(testContext: model)
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
        #expect(model.document.textSnapshot() == source + "\"\"\"")
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count + 3, length: 0))
    }

    @Test("SyntaxEditorView reflects document text replacements on iOS")
    @MainActor
    func syntaxEditorViewIOSTextObservation() async {
        let model = SyntaxEditorTestContext(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(testContext: model)

        model.document.replaceText("{\"enabled\":true}")

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.text == "{\"enabled\":true}")
    }

    @Test("SyntaxEditorView clamps iOS selection after setting shorter text")
    @MainActor
    func syntaxEditorViewIOSClampsSelectionAfterSettingShorterText() {
        let source = "abcdef"
        let editorView = SyntaxEditorView(testContext: SyntaxEditorTestContext(text: source))
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        editorView.text = "x"

        #expect(editorView.text == "x")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))
        #expect(editorView.document.latestChange?.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView clamps iOS horizontal offset after observed text replacement")
    @MainActor
    func syntaxEditorViewIOSClampsHorizontalOffsetAfterObservedTextReplacement() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.scrollRangeToVisible(NSRange(location: longIOSSyntaxEditorLine.utf16.count - 1, length: 0))
        layoutIOSEditorView(editorView)
        #expect(editorView.contentOffset.x > 0)

        model.document.replaceText("let value = 42")
        editorView.synchronizeDocumentForTesting()
        layoutIOSEditorView(editorView)

        #expect(editorView.text == "let value = 42")
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(editorView.contentOffset.x <= 1)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.configuration.colorTheme = updatedTheme

        editorView.synchronizeDocumentForTesting()
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), initialTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.configuration.colorTheme = updatedTheme

        editorView.synchronizeDocumentForTesting()
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()

        editorView.font = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)

        #expect(await highlighter.callCount() == initialCallCount)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), theme.baseForeground))
    }

    @Test("SyntaxEditorView refreshes iOS TextKit line fragments after async syntax highlight")
    @MainActor
    func syntaxEditorViewIOSRefreshesLineFragmentsAfterAsyncHighlight() async {
        let source = String(
            repeating: "let value = \"text\"\n",
            count: 100
        )
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
            ],
            delayNanoseconds: 1_000_000
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        layoutIOSEditorView(editorView, width: 393, height: 658)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorLineFragmentForegroundColor(editorView, at: 0), theme.baseForeground))

        await editorView.waitForPendingHighlightForTesting()
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorLineFragmentForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView fully applies iOS highlight when skipped revisions precede an incremental result")
    @MainActor
    func syntaxEditorViewIOSFullyAppliesHighlightAfterSkippedIncrementalRevisions() async {
        let firstPaste = "let first = 1\n"
        let secondPaste = "let second = 2\n"
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
                SyntaxHighlightToken(
                    range: NSRange(location: firstPaste.utf16.count, length: 3),
                    captureName: "keyword"
                ),
            ],
            delayNanoseconds: 20_000_000,
            updateRefreshRange: NSRange(location: firstPaste.utf16.count, length: secondPaste.utf16.count)
        )
        let model = SyntaxEditorTestContext(
            text: "",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.insertPastedText(firstPaste)
        editorView.insertPastedText(secondPaste)

        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.text == firstPaste + secondPaste)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(
            syntaxEditorUITestColorsEqual(
                iOSEditorForegroundColor(editorView, at: firstPaste.utf16.count),
                theme.keyword
            )
        )
    }

    @Test("SyntaxEditorView reflects editable and wrapping changes on iOS")
    @MainActor
    func syntaxEditorViewIOSEditorStateObservation() async {
        let model = SyntaxEditorTestContext(text: longIOSSyntaxEditorLine, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        model.configuration.isEditable = false
        model.configuration.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(
            editorView.isEditable == false
                && editorView.textContainer.widthTracksTextView
        )
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(editorView.contentSize.height > editorView.bounds.height + 1)
        #expect(iOSEditorLineBreakMode(editorView) == .byCharWrapping)

        model.configuration.lineWrappingEnabled = false

        editorView.synchronizeDocumentForTesting()
        #expect(!editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)
        #expect(editorView.textContainer.size.width > editorView.bounds.width)
        #expect(iOSEditorLineBreakMode(editorView) == .byClipping)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        model.configuration.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
    }

    @Test("SyntaxEditorView keeps empty no-wrap iOS content width tied to bounds")
    @MainActor
    func syntaxEditorViewIOSEmptyNoWrapContentWidthTracksBounds() {
        let model = SyntaxEditorTestContext(
            text: "",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)

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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        await editorView.waitForPendingHighlightForTesting()

        editorView.textStorage.addAttribute(
            .foregroundColor,
            value: theme.keyword,
            range: NSRange(location: 0, length: 3)
        )
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.configuration.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.configuration.isEditable = false

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.isEditable == false)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView enables horizontal scrolling for initial long iOS line")
    @MainActor
    func syntaxEditorViewIOSInitialLongLineScrollsHorizontally() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)

        layoutIOSEditorView(editorView)
        #expect(iOSEditorHasHorizontalOverflow(editorView))
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)
    }

    @Test("SyntaxEditorView includes offscreen iOS lines in initial horizontal scroll range")
    @MainActor
    func syntaxEditorViewIOSInitialOffscreenLongLineSetsHorizontalScrollRange() {
        let model = SyntaxEditorTestContext(
            text: offscreenWideIOSSyntaxEditorText,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)

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
        let model = SyntaxEditorTestContext(
            text: offscreenWideUnicodeIOSSyntaxEditorText,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)

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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 504, height: 1104)

        #expect(editorView.textContainer.widthTracksTextView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(iOSEditorLineBreakMode(editorView) == .byCharWrapping)

        model.configuration.lineWrappingEnabled = false

        editorView.synchronizeDocumentForTesting()
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.html,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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

    @Test("SyntaxEditorView resolves iOS clicks to the nearest caret before a character midpoint")
    @MainActor
    func syntaxEditorViewIOSResolvesClicksToNearestCaretBeforeCharacterMidpoint() {
        let source = "struct Greeting {\n    let message = \"hello\"\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let wordStart = (source as NSString).range(of: "Greeting").location
        let leadingOffset = wordStart + "Gre".utf16.count
        let trailingOffset = leadingOffset + 1
        guard let leadingPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: leadingOffset
        ),
              let trailingPosition = editorView.position(
                from: editorView.beginningOfDocument,
                offset: trailingOffset
              )
        else {
            Issue.record("SyntaxEditorView could not resolve adjacent word caret positions")
            return
        }

        let leadingRect = editorView.caretRect(for: leadingPosition)
        let trailingRect = editorView.caretRect(for: trailingPosition)
        let tapPoint = CGPoint(
            x: ((leadingRect.midX + trailingRect.midX) / 2) - 0.2,
            y: leadingRect.midY
        )
        guard let resolvedPosition = editorView.closestPosition(to: tapPoint) else {
            Issue.record("SyntaxEditorView could not resolve the word tap point")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: resolvedPosition)
                == leadingOffset
        )
    }

    @Test("SyntaxEditorView keeps the iOS tap caret when UIKit collapses an enclosing word")
    @MainActor
    func syntaxEditorViewIOSKeepsTapCaretWhenUIKitCollapsesEnclosingWord() {
        let source = "struct Greeting {\n    let message = \"hello\"\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let wordStart = (source as NSString).range(of: "Greeting").location
        let tappedOffset = wordStart + "Gre".utf16.count
        let wordEnd = wordStart + "Greeting".utf16.count
        guard let tappedPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: tappedOffset
        ),
              let wordEndPosition = editorView.position(
                from: editorView.beginningOfDocument,
                offset: wordEnd
              ),
              let collapsedWordEndRange = editorView.textRange(from: wordEndPosition, to: wordEndPosition)
        else {
            Issue.record("SyntaxEditorView could not resolve the tapped word positions")
            return
        }

        let tappedRect = editorView.caretRect(for: tappedPosition)
        guard let resolvedPosition = editorView.closestPosition(
            to: CGPoint(x: tappedRect.midX, y: tappedRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve the tapped word caret")
            return
        }
        _ = editorView.tokenizer.rangeEnclosingPosition(
            resolvedPosition,
            with: .word,
            inDirection: UITextDirection(rawValue: 0)
        )

        editorView.selectedTextRange = collapsedWordEndRange

        #expect(editorView.selectedRange == NSRange(location: tappedOffset, length: 0))
    }

    @Test("SyntaxEditorView resolves an adjacent caret boundary for iOS drag selection")
    @MainActor
    func syntaxEditorViewIOSResolvesAdjacentCaretBoundaryForDragSelection() {
        let source = "struct Greeting {\n    let message = \"hello\"\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let wordStart = (source as NSString).range(of: "Greeting").location
        let tappedOffset = wordStart + "Gre".utf16.count
        guard let nextPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: tappedOffset + 1
        ) else {
            Issue.record("SyntaxEditorView could not resolve the adjacent word caret position")
            return
        }

        editorView.selectedRange = NSRange(location: tappedOffset, length: 0)
        let adjacentBoundaryRect = editorView.caretRect(for: nextPosition)
        guard let resolvedPosition = editorView.closestPosition(
            to: CGPoint(x: adjacentBoundaryRect.midX, y: adjacentBoundaryRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve the adjacent word caret boundary")
            return
        }

        #expect(
            editorView.offset(from: editorView.beginningOfDocument, to: resolvedPosition)
                == tappedOffset + 1
        )
    }

    @Test("SyntaxEditorView keeps iOS drag selections separate from tap word-boundary correction")
    @MainActor
    func syntaxEditorViewIOSKeepsDragSelectionsSeparateFromTapWordBoundaryCorrection() {
        let source = "struct Greeting {\n    let message = \"hello\"\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let wordStart = (source as NSString).range(of: "Greeting").location
        let tappedOffset = wordStart + "Gre".utf16.count
        let wordEnd = wordStart + "Greeting".utf16.count
        guard let tappedPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: tappedOffset
        ),
              let wordEndPosition = editorView.position(
                from: editorView.beginningOfDocument,
                offset: wordEnd
              ),
              let dragRange = editorView.textRange(from: tappedPosition, to: wordEndPosition)
        else {
            Issue.record("SyntaxEditorView could not resolve the drag selection positions")
            return
        }

        let tappedRect = editorView.caretRect(for: tappedPosition)
        guard let resolvedPosition = editorView.closestPosition(
            to: CGPoint(x: tappedRect.midX, y: tappedRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve the tapped word caret")
            return
        }
        _ = editorView.tokenizer.rangeEnclosingPosition(
            resolvedPosition,
            with: .word,
            inDirection: UITextDirection(rawValue: 0)
        )

        editorView.selectedTextRange = dragRange

        #expect(editorView.selectedRange == NSRange(location: tappedOffset, length: wordEnd - tappedOffset))
    }

    @Test("SyntaxEditorView resolves iOS clicks at the final line end")
    @MainActor
    func syntaxEditorViewIOSResolvesClicksAtFinalLineEnd() {
        let source = "let value = 123"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let endOffset = source.utf16.count
        guard let lineEndPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: endOffset
        ) else {
            Issue.record("SyntaxEditorView could not resolve final line end position")
            return
        }

        let lineEndRect = editorView.caretRect(for: lineEndPosition)
        guard let resolvedPosition = editorView.closestPosition(
            to: CGPoint(x: lineEndRect.midX, y: lineEndRect.midY)
        ) else {
            Issue.record("SyntaxEditorView could not resolve final line end click")
            return
        }

        #expect(editorView.offset(from: editorView.beginningOfDocument, to: resolvedPosition) == endOffset)
    }

    @Test("SyntaxEditorView resolves iOS clicks right of short lines to the line end")
    @MainActor
    func syntaxEditorViewIOSResolvesClicksRightOfShortLinesToLineEnd() {
        let sourceLines = [
            "let short = 1;",
            "let next = 2;",
        ]
        let source = sourceLines.joined(separator: "\n")
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.selectedRange = NSRange(location: 1, length: 0)
        #expect(editorView.textLayoutManager?.textSelections.first?.affinity == .downstream)

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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.html,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.html,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: "{}",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: "abc", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        let foreignPosition = SyntaxEditorUITestForeignTextPosition()

        #expect(editorView.position(from: foreignPosition, in: .down, offset: 1) == nil)
        #expect(editorView.position(from: foreignPosition, in: .down, offset: 0) === foreignPosition)
    }

    @Test("SyntaxEditorView does not let iOS gesture selection changes own horizontal scrolling")
    @MainActor
    func syntaxEditorViewIOSGestureSelectionDoesNotOwnHorizontalScrolling() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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

    @Test("SyntaxEditorView collapses iOS character range for trailing line-end tap")
    @MainActor
    func syntaxEditorViewIOSCharacterRangeForTrailingLineEndTapIsCollapsed() {
        let source = "const answer = 42;\nfunction greet(name) {\n    return name\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = (source as NSString).range(of: "\n").location
        let pointPastFirstLineText = CGPoint(
            x: editorView.bounds.minX + 260,
            y: editorView.textContainerInset.top + editorView.font.lineHeight * 0.5
        )

        guard let characterRange = editorView.characterRange(at: pointPastFirstLineText) else {
            Issue.record("SyntaxEditorView could not resolve a first-line trailing character range")
            return
        }

        let rangeStart = editorView.offset(from: editorView.beginningOfDocument, to: characterRange.start)
        let rangeEnd = editorView.offset(from: editorView.beginningOfDocument, to: characterRange.end)
        #expect(rangeStart == firstLineEnd)
        #expect(rangeEnd == firstLineEnd)

        editorView.selectedTextRange = characterRange
        #expect(editorView.selectedRange == NSRange(location: firstLineEnd, length: 0))

        guard let adjustedPosition = editorView.position(from: characterRange.end, offset: 1),
              let adjustedRange = editorView.textRange(from: adjustedPosition, to: adjustedPosition)
        else {
            Issue.record("SyntaxEditorView could not simulate UIKit character-range adjustment")
            return
        }
        editorView.selectedTextRange = adjustedRange
        #expect(editorView.selectedRange == NSRange(location: firstLineEnd, length: 0))

        guard let storedRange = editorView.selectedTextRange,
              let storedAdjustedPosition = editorView.position(from: storedRange.end, offset: 1),
              let storedAdjustedRange = editorView.textRange(from: storedAdjustedPosition, to: storedAdjustedPosition)
        else {
            Issue.record("SyntaxEditorView could not resolve explicit movement from stored selection")
            return
        }
        editorView.selectedTextRange = storedAdjustedRange
        #expect(editorView.selectedRange == NSRange(location: firstLineEnd + 1, length: 0))
    }

    @Test("SyntaxEditorView keeps iOS UIKit-adjusted trailing line-end tap before line break")
    @MainActor
    func syntaxEditorViewIOSKeepsUIKitAdjustedTrailingLineEndTapBeforeLineBreak() {
        let source = "const answer = 42;\nfunction greet(name) {\n    return name\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = (source as NSString).range(of: "\n").location
        let pointPastFirstLineText = CGPoint(
            x: editorView.bounds.minX + 260,
            y: editorView.textContainerInset.top + editorView.font.lineHeight * 0.5
        )

        guard let hitPosition = editorView.closestPosition(to: pointPastFirstLineText),
              let hitRange = editorView.textRange(from: hitPosition, to: hitPosition),
              let adjustedPosition = editorView.position(from: hitRange.end, offset: 1),
              let adjustedRange = editorView.textRange(from: adjustedPosition, to: adjustedPosition)
        else {
            Issue.record("SyntaxEditorView could not simulate UIKit trailing line-end tap adjustment")
            return
        }

        editorView.selectedTextRange = adjustedRange
        #expect(editorView.selectedRange == NSRange(location: firstLineEnd, length: 0))

        guard let explicitLineEndPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: firstLineEnd
        ),
              let explicitNextPosition = editorView.position(from: explicitLineEndPosition, offset: 1)
        else {
            Issue.record("SyntaxEditorView could not resolve explicit movement across a line break")
            return
        }

        let explicitNextOffset = editorView.offset(
            from: editorView.beginningOfDocument,
            to: explicitNextPosition
        )
        #expect(explicitNextOffset == firstLineEnd + 1)
    }

    @Test("SyntaxEditorView keeps iOS UIKit-adjusted second-line trailing tap before line break")
    @MainActor
    func syntaxEditorViewIOSKeepsUIKitAdjustedSecondLineTrailingTapBeforeLineBreak() {
        let source = "const answer = 42;\nfunction greet(name) {\n    return name\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineBreak = (source as NSString).range(of: "\n").location
        let secondLineStart = firstLineBreak + 1
        let secondLineEnd = (source as NSString).range(
            of: "\n",
            options: [],
            range: NSRange(location: secondLineStart, length: (source as NSString).length - secondLineStart)
        ).location
        let nextLineContentStart = (source as NSString).range(
            of: "return",
            options: [],
            range: NSRange(location: secondLineEnd, length: (source as NSString).length - secondLineEnd)
        ).location
        let uiKitAdjustedOffset = nextLineContentStart - secondLineEnd
        let pointPastSecondLineText = CGPoint(
            x: editorView.bounds.minX + 260,
            y: editorView.textContainerInset.top + editorView.font.lineHeight * 1.5
        )

        guard let hitPosition = editorView.closestPosition(to: pointPastSecondLineText),
              let hitRange = editorView.textRange(from: hitPosition, to: hitPosition),
              let adjustedPosition = editorView.position(from: hitRange.end, offset: uiKitAdjustedOffset),
              let adjustedRange = editorView.textRange(from: adjustedPosition, to: adjustedPosition)
        else {
            Issue.record("SyntaxEditorView could not simulate UIKit second-line trailing tap adjustment")
            return
        }

        let hitOffset = editorView.offset(from: editorView.beginningOfDocument, to: hitPosition)
        #expect(hitOffset == secondLineEnd)

        editorView.selectedTextRange = adjustedRange
        #expect(editorView.selectedRange == NSRange(location: secondLineEnd, length: 0))

        guard let storedRange = editorView.selectedTextRange,
              let storedAdjustedPosition = editorView.position(from: storedRange.end, offset: uiKitAdjustedOffset),
              let storedAdjustedRange = editorView.textRange(from: storedAdjustedPosition, to: storedAdjustedPosition)
        else {
            Issue.record("SyntaxEditorView could not resolve explicit second-line movement from stored selection")
            return
        }
        editorView.selectedTextRange = storedAdjustedRange
        #expect(editorView.selectedRange == NSRange(location: nextLineContentStart, length: 0))

        guard let explicitLineEndPosition = editorView.position(
            from: editorView.beginningOfDocument,
            offset: secondLineEnd
        ),
              let explicitNextLineContentPosition = editorView.position(
                from: explicitLineEndPosition,
                offset: uiKitAdjustedOffset
              )
        else {
            Issue.record("SyntaxEditorView could not resolve explicit movement to second-line next content")
            return
        }

        let explicitNextLineContentOffset = editorView.offset(
            from: editorView.beginningOfDocument,
            to: explicitNextLineContentPosition
        )
        #expect(explicitNextLineContentOffset == nextLineContentStart)
    }

    @Test("SyntaxEditorView collapses iOS character range for trailing CRLF line-end tap")
    @MainActor
    func syntaxEditorViewIOSCharacterRangeForTrailingCRLFLineEndTapIsCollapsed() {
        let source = "const answer = 42;\r\nfunction greet(name) {\r\n    return name\r\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = (source as NSString).range(of: "\r\n").location
        let pointPastFirstLineText = CGPoint(
            x: editorView.bounds.minX + 260,
            y: editorView.textContainerInset.top + editorView.font.lineHeight * 0.5
        )

        guard let characterRange = editorView.characterRange(at: pointPastFirstLineText) else {
            Issue.record("SyntaxEditorView could not resolve a first-line trailing CRLF character range")
            return
        }

        let rangeStart = editorView.offset(from: editorView.beginningOfDocument, to: characterRange.start)
        let rangeEnd = editorView.offset(from: editorView.beginningOfDocument, to: characterRange.end)
        #expect(rangeStart == firstLineEnd)
        #expect(rangeEnd == firstLineEnd)

        editorView.selectedTextRange = characterRange
        #expect(editorView.selectedRange == NSRange(location: firstLineEnd, length: 0))

        guard let oneStepAdjustedPosition = editorView.position(from: characterRange.end, offset: 1),
              let oneStepAdjustedRange = editorView.textRange(
                from: oneStepAdjustedPosition,
                to: oneStepAdjustedPosition
              ),
              let adjustedPosition = editorView.position(from: characterRange.end, offset: 2),
              let adjustedRange = editorView.textRange(from: adjustedPosition, to: adjustedPosition)
        else {
            Issue.record("SyntaxEditorView could not simulate UIKit CRLF character-range adjustment")
            return
        }
        editorView.selectedTextRange = oneStepAdjustedRange
        #expect(editorView.selectedRange == NSRange(location: firstLineEnd, length: 0))

        editorView.selectedTextRange = adjustedRange
        #expect(editorView.selectedRange == NSRange(location: firstLineEnd, length: 0))
    }

    @Test("SyntaxEditorView keeps iOS UIKit-adjusted trailing CRLF line-end tap before CRLF")
    @MainActor
    func syntaxEditorViewIOSKeepsUIKitAdjustedTrailingCRLFLineEndTapBeforeCRLF() {
        let source = "const answer = 42;\r\nfunction greet(name) {\r\n    return name\r\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineEnd = (source as NSString).range(of: "\r\n").location
        let nextLineContentStart = firstLineEnd + 2
        let pointPastFirstLineText = CGPoint(
            x: editorView.bounds.minX + 260,
            y: editorView.textContainerInset.top + editorView.font.lineHeight * 0.5
        )

        guard let hitPosition = editorView.closestPosition(to: pointPastFirstLineText),
              let hitRange = editorView.textRange(from: hitPosition, to: hitPosition),
              let adjustedPosition = editorView.position(from: hitRange.end, offset: nextLineContentStart - firstLineEnd),
              let adjustedRange = editorView.textRange(from: adjustedPosition, to: adjustedPosition)
        else {
            Issue.record("SyntaxEditorView could not simulate UIKit trailing CRLF line-end tap adjustment")
            return
        }

        editorView.selectedTextRange = adjustedRange
        #expect(editorView.selectedRange == NSRange(location: firstLineEnd, length: 0))
    }

    @Test("SyntaxEditorView keeps iOS UIKit-adjusted trailing CRLF indented tap before CRLF")
    @MainActor
    func syntaxEditorViewIOSKeepsUIKitAdjustedTrailingCRLFIndentedTapBeforeCRLF() {
        let source = "const answer = 42;\r\nfunction greet(name) {\r\n    return name\r\n}"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let firstLineBreak = (source as NSString).range(of: "\r\n").location
        let secondLineStart = firstLineBreak + 2
        let secondLineEnd = (source as NSString).range(
            of: "\r\n",
            options: [],
            range: NSRange(location: secondLineStart, length: (source as NSString).length - secondLineStart)
        ).location
        let nextLineContentStart = (source as NSString).range(
            of: "return",
            options: [],
            range: NSRange(location: secondLineEnd, length: (source as NSString).length - secondLineEnd)
        ).location
        let uiKitAdjustedOffset = nextLineContentStart - secondLineEnd
        let pointPastSecondLineText = CGPoint(
            x: editorView.bounds.minX + 260,
            y: editorView.textContainerInset.top + editorView.font.lineHeight * 1.5
        )

        guard let hitPosition = editorView.closestPosition(to: pointPastSecondLineText),
              let hitRange = editorView.textRange(from: hitPosition, to: hitPosition),
              let adjustedPosition = editorView.position(from: hitRange.end, offset: uiKitAdjustedOffset),
              let adjustedRange = editorView.textRange(from: adjustedPosition, to: adjustedPosition)
        else {
            Issue.record("SyntaxEditorView could not simulate UIKit trailing CRLF indented tap adjustment")
            return
        }

        let hitOffset = editorView.offset(from: editorView.beginningOfDocument, to: hitPosition)
        #expect(hitOffset == secondLineEnd)

        editorView.selectedTextRange = adjustedRange
        #expect(editorView.selectedRange == NSRange(location: secondLineEnd, length: 0))
    }

    @Test("SyntaxEditorView allows explicit iOS scrollRectToVisible to move horizontally")
    @MainActor
    func syntaxEditorViewIOSAllowsExplicitScrollRectToVisibleToMoveHorizontally() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: "let short = true",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        model.document.replaceText(longIOSSyntaxEditorLine)

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.text == longIOSSyntaxEditorLine)
        layoutIOSEditorView(editorView)
        #expect(iOSEditorHasHorizontalOverflow(editorView))
    }

    @Test("SyntaxEditorView grows horizontal content size after direct iOS text assignment")
    @MainActor
    func syntaxEditorViewIOSDirectTextAssignmentGrowsHorizontalContentSize() {
        let model = SyntaxEditorTestContext(
            text: "let short = true",
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        editorView.text = longIOSSyntaxEditorLine

        #expect(model.document.textSnapshot() == longIOSSyntaxEditorLine)
        layoutIOSEditorView(editorView)
        #expect(iOSEditorHasHorizontalOverflow(editorView))
    }

    @Test("SyntaxEditorView keeps iOS scroll position while editing")
    @MainActor
    func syntaxEditorViewIOSKeepsScrollPositionWhileEditing() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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

    @Test("SyntaxEditorView does not fully rebuild iOS line metrics for normal input")
    @MainActor
    func syntaxEditorViewIOSNormalInputDoesNotFullyRebuildLineMetrics() {
        let source = (0..<2_000)
            .map { index in
                index == 1_500 ? longIOSSyntaxEditorLine : "let value\(index) = \(index)"
            }
            .joined(separator: "\n")
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        let targetRange = (source as NSString).range(of: "let value42")
        #expect(targetRange.location != NSNotFound)
        let rebuildCount = editorView.lineMetricsFullRebuildCountForTesting
        let initialWidth = editorView.contentSize.width

        editorView.selectedRange = NSRange(location: targetRange.location + targetRange.length, length: 0)
        editorView.insertText("x")
        layoutIOSEditorView(editorView)

        #expect(editorView.lineMetricsFullRebuildCountForTesting == rebuildCount)
        #expect(abs(editorView.contentSize.width - initialWidth) <= 1)
        #expect(model.document.textSnapshot().contains("let value42x = 42"))
    }

    @Test("SyntaxEditorView keeps iOS scroll position while moving cursor")
    @MainActor
    func syntaxEditorViewIOSKeepsScrollPositionWhileMovingCursor() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        #expect(editorView.bounces)
        #expect(editorView.alwaysBounceVertical)
    }

    @Test("SyntaxEditorView scrolls iOS ranges through the single text view")
    @MainActor
    func syntaxEditorViewIOSScrollsRangesThroughSingleTextView() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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

    @Test("SyntaxEditorView includes iOS horizontal insets in TextKit viewport bounds")
    @MainActor
    func syntaxEditorViewIOSIncludesHorizontalInsetsInViewportBounds() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        editorView.contentInset = UIEdgeInsets(top: 3, left: 5, bottom: 7, right: 11)
        editorView.textContainerInset = UIEdgeInsets(top: 13, left: 17, bottom: 19, right: 23)
        layoutIOSEditorView(editorView)

        guard let textLayoutManager = editorView.textLayoutManager else {
            Issue.record("SyntaxEditorView has no TextKit layout manager")
            return
        }

        let viewportBounds = editorView.viewportBounds(
            for: textLayoutManager.textViewportLayoutController
        )
        let insets = editorView.adjustedContentInset
        let expectedBounds = CGRect(
            x: editorView.bounds.origin.x - insets.left - editorView.textContainerInset.left,
            y: editorView.bounds.origin.y - insets.top - editorView.textContainerInset.top,
            width: editorView.bounds.width
                + insets.left
                + insets.right
                + editorView.textContainerInset.left
                + editorView.textContainerInset.right,
            height: editorView.bounds.height
                + insets.top
                + insets.bottom
                + editorView.textContainerInset.top
                + editorView.textContainerInset.bottom
        )

        #expect(viewportBounds == expectedBounds)
    }

    @Test("SyntaxEditorView keeps iOS horizontal offset after visible cursor click")
    @MainActor
    func syntaxEditorViewIOSKeepsHorizontalOffsetAfterVisibleCursorClick() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
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
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)

        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        model.configuration.lineWrappingEnabled = false

        editorView.synchronizeDocumentForTesting()
        #expect(!editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        let restoredHorizontalOverflow = iOSEditorHasHorizontalOverflow(editorView)
        if !restoredHorizontalOverflow {
            Issue.record(Comment(rawValue: iOSEditorHorizontalOverflowDiagnostics(editorView)))
        }
        #expect(restoredHorizontalOverflow)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        model.configuration.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
    }

    @Test("SyntaxEditorView omits editing key commands while read-only on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyOmitsEditingKeyCommands() {
        let model = SyntaxEditorTestContext(
            text: "let answer = 42",
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(testContext: model)

        let readOnlyCommands = editorView.keyCommands
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "\t", modifierFlags: []))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "\t", modifierFlags: [.shift]))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "]", modifierFlags: [.command]))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "[", modifierFlags: [.command]))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "/", modifierFlags: [.command]))
        #expect(!hasSyntaxEditorKeyCommand(readOnlyCommands, input: "v", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(readOnlyCommands, input: "l", modifierFlags: [.control, .shift, .command]))

        let readOnlyLineWrappingActionTarget = editorView.target(
            forAction: NSSelectorFromString("handleToggleLineWrappingCommand"),
            withSender: nil
        ) as AnyObject?
        #expect(readOnlyLineWrappingActionTarget === editorView)

        model.configuration.isEditable = true

        let editableCommands = editorView.keyCommands
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "\t", modifierFlags: []))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "\t", modifierFlags: [.shift]))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "]", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "[", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "/", modifierFlags: [.command]))
        let pasteCommand = syntaxEditorKeyCommand(editableCommands, input: "v", modifierFlags: [.command])
        #expect(pasteCommand != nil)
        #expect(pasteCommand?.wantsPriorityOverSystemBehavior == true)
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "l", modifierFlags: [.control, .shift, .command]))

        let indentActionTarget = editorView.target(
            forAction: NSSelectorFromString("handleIndentCommand"),
            withSender: nil
        ) as AnyObject?
        #expect(indentActionTarget === editorView)

        let insertTabActionTarget = editorView.target(
            forAction: NSSelectorFromString("handleInsertTabCommand"),
            withSender: nil
        ) as AnyObject?
        #expect(insertTabActionTarget === editorView)

        let pasteActionTarget = editorView.target(
            forAction: NSSelectorFromString("handlePasteCommand"),
            withSender: nil
        ) as AnyObject?
        #expect(pasteActionTarget === editorView)
    }

    @Test("SyntaxEditorView applies iOS paste payload repeatedly")
    @MainActor
    func syntaxEditorViewIOSAppliesPastePayloadRepeatedly() {
        let model = SyntaxEditorTestContext(text: "let ")
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: model.document.textSnapshot().utf16.count, length: 0)

        editorView.insertPastedText("42")
        editorView.insertPastedText("42")
        #expect(model.document.textSnapshot() == "let 4242")
    }

    @Test("SyntaxEditorView toggles iOS line wrapping key command")
    @MainActor
    func syntaxEditorViewIOSToggleLineWrappingKeyCommand() {
        let model = SyntaxEditorTestContext(
            text: longIOSSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        #expect(performSyntaxEditorSelector("handleToggleLineWrappingCommand", on: editorView))
        #expect(model.configuration.lineWrappingEnabled)
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textContainer.widthTracksTextView)

        #expect(performSyntaxEditorSelector("handleToggleLineWrappingCommand", on: editorView))
        #expect(!model.configuration.lineWrappingEnabled)
        editorView.synchronizeDocumentForTesting()
        #expect(!editorView.textContainer.widthTracksTextView)
    }

    @Test("SyntaxEditorView read-only handlers do not mutate text on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyHandlersDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: 0, length: source.utf16.count)

        editorView.insertText("\t")
        #expect(performSyntaxEditorSelector("handleInsertTabCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleIndentCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleOutdentCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleToggleCommentCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleToggleLineWrappingCommand", on: editorView))

        #expect(model.document.textSnapshot() == source)
        #expect(editorView.text == source)
        #expect(model.configuration.lineWrappingEnabled)
    }

    @Test("SyntaxEditorView inserts iOS tab spaces at the caret")
    @MainActor
    func syntaxEditorViewIOSInsertTabAtCaret() {
        let source = "abcde"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: 2, length: 0)

        #expect(performSyntaxEditorSelector("handleInsertTabCommand", on: editorView))

        #expect(model.document.textSnapshot() == "ab  cde")
        #expect(editorView.text == "ab  cde")
        #expect(editorView.selectedRange == NSRange(location: 4, length: 0))
    }

    @Test("SyntaxEditorView uses native iOS undo stack for text input")
    @MainActor
    func syntaxEditorViewIOSNativeTextInputUndoRedo() {
        let source = "let answer = 42"
        let editedSource = "\(source)!"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)

        #expect(!editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))

        editorView.insertText("!")

        #expect(model.document.textSnapshot() == editedSource)
        #expect(editorView.text == editedSource)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        #expect(editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))
        #expect(performSyntaxEditorSelector("handleUndoCommand", on: editorView))

        #expect(model.document.textSnapshot() == source)
        #expect(editorView.text == source)
        #expect(undoManager.canRedo)
        #expect(!editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))

        #expect(performSyntaxEditorSelector("handleRedoCommand", on: editorView))

        #expect(model.document.textSnapshot() == editedSource)
        #expect(editorView.text == editedSource)
        #expect(editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))
    }

    @Test("SyntaxEditorView read-only undo and redo do not mutate text on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyUndoRedoDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: 0, length: 0)

        #expect(performSyntaxEditorSelector("handleIndentCommand", on: editorView))
        let indentedSource = "    \(source)"
        #expect(model.document.textSnapshot() == indentedSource)
        #expect(editorView.text == indentedSource)

        model.configuration.isEditable = false

        #expect(!editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))
        #expect(performSyntaxEditorSelector("handleUndoCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleRedoCommand", on: editorView))

        #expect(model.document.textSnapshot() == indentedSource)
        #expect(editorView.text == indentedSource)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        undoManager.undo()
        undoManager.redo()

        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)
        #expect(model.document.textSnapshot() == indentedSource)
        #expect(editorView.text == indentedSource)

        model.configuration.isEditable = true

        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.document.textSnapshot() == source)
        #expect(editorView.text == source)
    }

    @Test("SyntaxEditorView restores command selection through iOS undo and redo")
    @MainActor
    func syntaxEditorViewIOSCommandUndoRedoRestoresSelection() {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: 4, length: 0)

        #expect(performSyntaxEditorSelector("handleIndentCommand", on: editorView))
        let indentedSource = "    \(source)"
        let indentedSelection = NSRange(location: 8, length: 0)
        #expect(model.document.textSnapshot() == indentedSource)
        #expect(editorView.text == indentedSource)
        #expect(editorView.selectedRange == indentedSelection)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(model.document.textSnapshot() == source)
        #expect(editorView.text == source)
        #expect(editorView.selectedRange == NSRange(location: 4, length: 0))

        #expect(undoManager.canRedo)
        undoManager.redo()
        #expect(model.document.textSnapshot() == indentedSource)
        #expect(editorView.text == indentedSource)
        #expect(editorView.selectedRange == indentedSelection)
    }

    @Test("SyntaxEditorView reapplies iOS bracket highlight after syntax refresh")
    @MainActor
    func syntaxEditorViewIOSReappliesBracketHighlightAfterSyntaxRefresh() async {
        let source = "let pair = ()"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        let bracketLocation = (source as NSString).range(of: "(").location
        editorView.selectedRange = NSRange(location: bracketLocation + 1, length: 0)
        await editorView.waitForPendingHighlightForTesting()

        #expect(iOSEditorHasBackgroundAttribute(editorView, at: bracketLocation))

        model.document.replaceText("\(source) ")

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.text == model.document.textSnapshot())
        await editorView.waitForPendingHighlightForTesting()
        #expect(iOSEditorHasBackgroundAttribute(editorView, at: bracketLocation))
    }

    @Test("SyntaxEditorView keeps selection and copy available while read-only on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyKeepsSelectionAndCopy() {
        let source = "copy me"
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.javascript,
            isEditable: false
        )
        let editorView = SyntaxEditorView(testContext: model)
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

    @Test("SyntaxEditorView reflects document text replacements on macOS")
    @MainActor
    func syntaxEditorViewMacTextObservation() async {
        let model = SyntaxEditorTestContext(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(testContext: model)

        model.document.replaceText("{\"enabled\":true}")

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.string == "{\"enabled\":true}")
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

    @Test("SyntaxEditorView keeps macOS find bar available while read-only")
    @MainActor
    func syntaxEditorViewMacKeepsFindBarAvailableWhileReadOnly() {
        let model = SyntaxEditorTestContext(text: "let value = 1", isEditable: false)
        let editorView = SyntaxEditorView(testContext: model)

        #expect(editorView.isFindInteractionEnabled)
        #expect(editorView.textView.usesFindBar)
        #expect(editorView.textView.isIncrementalSearchingEnabled)
        #expect(editorView.textView.isEditable == false)

        model.configuration.isEditable = true
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.usesFindBar)
        #expect(editorView.textView.isIncrementalSearchingEnabled)
        #expect(editorView.textView.isEditable)

        model.configuration.isEditable = false
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.usesFindBar)
        #expect(editorView.textView.isIncrementalSearchingEnabled)
        #expect(editorView.textView.isEditable == false)
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.configuration.colorTheme = updatedTheme

        editorView.synchronizeDocumentForTesting()
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
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: initialTheme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()
        let initialCallCount = await highlighter.callCount()
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), initialTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.configuration.colorTheme = updatedTheme

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

    @Test("SyntaxEditorView preserves macOS syntax colors after editor state changes")
    @MainActor
    func syntaxEditorViewMacEditorStateDoesNotResetSyntaxColors() async {
        let source = "let value = \"text\""
        let theme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(testContext: model)

        editorView.textView.textStorage?.addAttribute(
            .foregroundColor,
            value: theme.keyword,
            range: NSRange(location: 0, length: 3)
        )
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.configuration.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.hasHorizontalScroller == false)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.configuration.isEditable = false

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.isEditable == false)
        #expect(syntaxEditorUITestColorsEqual(macEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView preserves macOS syntax colors outside command edit ranges")
    @MainActor
    func syntaxEditorViewMacCommandEditsPreserveSyntaxColorsOutsideRefreshRange() async {
        let source = "let value = "
        let theme = syntaxEditorUITestColorTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxHighlightToken(
                    range: NSRange(location: 0, length: 3),
                    captureName: "keyword"
                ),
            ],
            updateRefreshRange: NSRange(location: source.utf16.count, length: 2)
        )
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            colorTheme: theme
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

    @Test("SyntaxEditorView fully applies macOS highlight when skipped revisions precede an incremental result")
    @MainActor
    func syntaxEditorViewMacFullyAppliesHighlightAfterSkippedIncrementalRevisions() async {
        let firstPaste = "let first = 1\n"
        let secondPaste = "let second = 2\n"
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
                SyntaxHighlightToken(
                    range: NSRange(location: firstPaste.utf16.count, length: 3),
                    captureName: "keyword"
                ),
            ],
            delayNanoseconds: 20_000_000,
            updateRefreshRange: NSRange(location: firstPaste.utf16.count, length: secondPaste.utf16.count)
        )
        let model = SyntaxEditorTestContext(
            text: "",
            language: SyntaxLanguage.swift,
            colorTheme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        editorView.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editorView.textView.insertText(firstPaste, replacementRange: NSRange(location: 0, length: 0))
        editorView.textView.setSelectedRange(NSRange(location: firstPaste.utf16.count, length: 0))
        editorView.textView.insertText(
            secondPaste,
            replacementRange: NSRange(location: firstPaste.utf16.count, length: 0)
        )

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

    @Test("SyntaxEditorView reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewMacEditorStateObservation() async {
        let model = SyntaxEditorTestContext(text: "body {}", language: SyntaxLanguage.css)
        let editorView = SyntaxEditorView(testContext: model)

        model.configuration.isEditable = false
        model.configuration.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(
            editorView.textView.isEditable == false
                && editorView.hasHorizontalScroller == false
        )

        model.configuration.lineWrappingEnabled = false

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

        model.configuration.lineWrappingEnabled = true

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

        model.configuration.language = SyntaxLanguage.json
        model.configuration.isEditable = false

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.isEditable == false)

        model.document.replaceText("{\"answer\":42}")

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.string == "{\"answer\":42}")
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
            #expect(model.document.textSnapshot() == source)
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

        #expect(model.document.textSnapshot() == "ab  cde")
        #expect(editorView.textView.string == "ab  cde")
        #expect(editorView.textView.selectedRange() == NSRange(location: 4, length: 0))
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
        #expect(model.configuration.lineWrappingEnabled)
        #expect(editorView.textView.string == source)

        for character in ["/", "]", "["] {
            guard let event = makeMacCommandKeyEvent(character) else {
                Issue.record("Failed to create command key event for \(character)")
                continue
            }

            _ = editorView.textView.performKeyEquivalent(with: event)
            #expect(model.document.textSnapshot() == source)
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
        #expect(model.configuration.lineWrappingEnabled)
        editorView.synchronizeDocumentForTesting()
        #expect(!editorView.hasHorizontalScroller)

        #expect(editorView.textView.performKeyEquivalent(with: event))
        #expect(!model.configuration.lineWrappingEnabled)
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.hasHorizontalScroller)
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

        #expect(model.document.textSnapshot() == editedSource)
        #expect(editorView.textView.string == editedSource)

        let undoSelector = NSSelectorFromString("undo:")
        let redoSelector = NSSelectorFromString("redo:")
        let undoItem = NSMenuItem(title: "Undo", action: undoSelector, keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: redoSelector, keyEquivalent: "Z")

        #expect(undoManager.canUndo)
        #expect(editorView.textView.validateUserInterfaceItem(undoItem))

        model.configuration.isEditable = false
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.isEditable == false)
        #expect(!undoManager.canUndo)
        #expect(!editorView.textView.validateUserInterfaceItem(undoItem))

        #expect(NSApplication.shared.sendAction(undoSelector, to: editorView.textView, from: undoItem))
        #expect(model.document.textSnapshot() == editedSource)
        #expect(editorView.textView.string == editedSource)

        model.configuration.isEditable = true
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textView.isEditable == true)

        #expect(undoManager.canUndo)
        #expect(NSApplication.shared.sendAction(undoSelector, to: editorView.textView, from: undoItem))

        #expect(model.document.textSnapshot() == source)
        #expect(editorView.textView.string == source)
        #expect(undoManager.canRedo)
        #expect(editorView.textView.validateUserInterfaceItem(redoItem))
        #expect(NSApplication.shared.sendAction(redoSelector, to: editorView.textView, from: redoItem))

        #expect(model.document.textSnapshot() == editedSource)
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
        #expect(model.document.textSnapshot() == twiceIndentedSource)

        model.configuration.isEditable = false
        undoManager.undo()
        undoManager.undo()

        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)
        #expect(model.document.textSnapshot() == twiceIndentedSource)
        #expect(editorView.textView.string == twiceIndentedSource)

        model.configuration.isEditable = true

        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.document.textSnapshot() == onceIndentedSource)
        #expect(editorView.textView.string == onceIndentedSource)
        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.document.textSnapshot() == source)
        #expect(editorView.textView.string == source)
        #expect(undoManager.canRedo)

        model.configuration.isEditable = false
        undoManager.redo()
        undoManager.redo()

        #expect(model.document.textSnapshot() == source)
        #expect(editorView.textView.string == source)
        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)

        model.configuration.isEditable = true

        #expect(undoManager.canRedo)
        undoManager.redo()
        undoManager.redo()

        #expect(model.document.textSnapshot() == twiceIndentedSource)
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

    @Test("SyntaxEditorViewController preserves Observable conformance on macOS")
    @MainActor
    func syntaxEditorViewControllerMacObservableCompatibility() {
        let model = SyntaxEditorTestContext(text: "{}", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(testContext: model)

        requireObservable(controller)
        requireNSTextViewDelegate(controller)
        #expect(controller.document === model.document)
        #expect(controller.configuration === model.configuration)
        #expect(
            controller.textView(
                controller.textView,
                shouldChangeTextIn: NSRange(location: 0, length: 0),
                replacementString: "a"
            )
        )
    }

    @Test("SyntaxEditorViewController reflects document text replacements on macOS")
    @MainActor
    func syntaxEditorViewControllerMacTextObservation() async {
        let model = SyntaxEditorTestContext(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()

        model.document.replaceText("{\"enabled\":true}")

        controller.synchronizeDocumentForTesting()
        #expect(controller.textView.string == "{\"enabled\":true}")
    }

    @Test("SyntaxEditorViewController reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacEditorStateObservation() async {
        let model = SyntaxEditorTestContext(text: "body {}", language: SyntaxLanguage.css)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()

        model.configuration.isEditable = false
        model.configuration.lineWrappingEnabled = true

        controller.synchronizeDocumentForTesting()
        #expect(
            controller.textView.isEditable == false
                && controller.scrollView.hasHorizontalScroller == false
        )

        model.configuration.lineWrappingEnabled = false

        controller.synchronizeDocumentForTesting()
        #expect(controller.scrollView.hasHorizontalScroller == true)
    }

    @Test("SyntaxEditorViewController keeps synchronizing after language changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacLanguageChangeKeepsObservationAlive() async {
        let model = SyntaxEditorTestContext(text: "let answer = 42", language: SyntaxLanguage.swift)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()

        model.configuration.language = SyntaxLanguage.json
        model.configuration.isEditable = false

        controller.synchronizeDocumentForTesting()
        #expect(controller.textView.isEditable == false)

        model.document.replaceText("{\"answer\":42}")

        controller.synchronizeDocumentForTesting()
        #expect(controller.textView.string == "{\"answer\":42}")
    }
#endif
}
