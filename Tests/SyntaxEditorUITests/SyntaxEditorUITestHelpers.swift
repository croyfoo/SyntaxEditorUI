import Foundation
import Observation
import ObservationBridge
import SwiftUI
import Testing
@testable import SyntaxEditorUI

#if canImport(UIKit)
import UIKit
@testable import SyntaxEditorUIUIKit
#endif

#if canImport(AppKit)
import AppKit
@testable import SyntaxEditorUIAppKit
#endif

@MainActor
@Observable
final class SyntaxEditorSwiftUIProbe {
    var tick = 0
    let document = SyntaxEditorDocument(text: "let value = 1")
    var configuration = SyntaxEditorConfiguration(language: SyntaxLanguage.javascript)
}

struct SyntaxEditorDefaultWrapperHost: View {
    var probe: SyntaxEditorSwiftUIProbe

    var body: some View {
        VStack {
            SyntaxEditor()
            Text("\(probe.tick)")
        }
    }
}

struct SyntaxEditorConfigurationReplacementHost: View {
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
func syntaxEditorUIView<Subview: UIView>(
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
func syntaxEditorSettleUIKitHost<Content: View>(_ controller: UIHostingController<Content>) {
    controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

@MainActor
func syntaxEditorAttachUIKitHost<Content: View>(_ controller: UIHostingController<Content>) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    syntaxEditorSettleUIKitHost(controller)
    return window
}
#elseif canImport(AppKit)
@MainActor
func syntaxEditorNSView<Subview: NSView>(
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
func syntaxEditorSettleAppKitHost<Content: View>(_ controller: NSHostingController<Content>) {
    controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    controller.view.needsLayout = true
    controller.view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
#endif

@MainActor
struct SyntaxEditorTestContext {
    let document: SyntaxEditorDocument
    let configuration: SyntaxEditorConfiguration

    init(
        text: String = "",
        language: SyntaxLanguage = .javascript,
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false,
        colorTheme: SyntaxEditorColorTheme = .default,
        drawsBackground: Bool = true,
        fontSizeDelta: Int = 0
    ) {
        self.document = SyntaxEditorDocument(text: text)
        self.configuration = SyntaxEditorConfiguration(
            language: language,
            isEditable: isEditable,
            lineWrappingEnabled: lineWrappingEnabled,
            colorTheme: colorTheme,
            drawsBackground: drawsBackground,
            fontSizeDelta: fontSizeDelta
        )
    }
}

struct SyntaxEditorRenderedEditorState: Sendable, Equatable {
    var isEditable: Bool
    var wrapsLines: Bool
}

@MainActor
final class SyntaxEditorObservationPassCounter {
    var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

@MainActor
func syntaxEditorDrainMainActorObservationDelivery<Value>(
    recording values: ObservedValues<Value>,
    stablePassCount: Int = 2,
    maximumDrainPasses: Int = 8
) async {
    var previousCount = values.snapshot().count
    var stableCount = 0

    for _ in 0..<maximumDrainPasses {
        await Task { @MainActor in }.value

        let currentCount = values.snapshot().count
        if currentCount == previousCount {
            stableCount += 1
            if stableCount >= stablePassCount {
                return
            }
        } else {
            previousCount = currentCount
            stableCount = 0
        }
    }
}

extension SyntaxEditorView {
    convenience init(testContext: SyntaxEditorTestContext) {
        self.init(document: testContext.document, configuration: testContext.configuration)
    }

    convenience init(testContext: SyntaxEditorTestContext, highlighter: any SyntaxHighlighting) {
        self.init(document: testContext.document, configuration: testContext.configuration, highlighter: highlighter)
    }
}

extension SyntaxEditorViewController {
    convenience init(testContext: SyntaxEditorTestContext) {
        self.init(document: testContext.document, configuration: testContext.configuration)
    }
}

func syntaxEditorUITestColor(hex: UInt32) -> SyntaxEditorColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255.0
    let green = CGFloat((hex >> 8) & 0xFF) / 255.0
    let blue = CGFloat(hex & 0xFF) / 255.0

#if canImport(UIKit)
    return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
#elseif canImport(AppKit)
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
#endif
}

func syntaxEditorUITestColorTheme(
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
    punctuation: SyntaxEditorColor = syntaxEditorUITestColor(hex: 0xB0B1B2),
    background: SyntaxEditorColor = .clear
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
        punctuation: punctuation,
        background: background
    )
}

func syntaxEditorUITestColorsEqual(_ lhs: SyntaxEditorColor?, _ rhs: SyntaxEditorColor) -> Bool {
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

actor ManualSyntaxHighlightGate {
    struct SuspensionWaiter {
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    var suspensionCount = 0
    var suspensionWaiters: [SuspensionWaiter] = []
    var resumeContinuations: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        suspensionCount += 1
        resumeReadySuspensionWaiters()

        await withCheckedContinuation { continuation in
            resumeContinuations.append(continuation)
        }
    }

    func currentSuspensionCount() -> Int {
        suspensionCount
    }

    func waitUntilSuspended(_ minimumCount: Int = 1) async {
        guard suspensionCount < minimumCount else { return }

        await withCheckedContinuation { continuation in
            suspensionWaiters.append(
                SuspensionWaiter(minimumCount: minimumCount, continuation: continuation)
            )
        }
    }

    func waitUntilSuspended(after previousCount: Int) async {
        await waitUntilSuspended(previousCount + 1)
    }

    func resumeOne() {
        guard !resumeContinuations.isEmpty else { return }
        let continuation = resumeContinuations.removeFirst()
        continuation.resume()
    }

    func resumeAll() {
        let continuations = resumeContinuations
        resumeContinuations.removeAll()

        for continuation in continuations {
            continuation.resume()
        }
    }

    func resumeReadySuspensionWaiters() {
        var readyContinuations: [CheckedContinuation<Void, Never>] = []
        suspensionWaiters.removeAll { waiter in
            guard suspensionCount >= waiter.minimumCount else {
                return false
            }
            readyContinuations.append(waiter.continuation)
            return true
        }

        for continuation in readyContinuations {
            continuation.resume()
        }
    }
}

actor SyntaxEditorUITestHighlighter: SyntaxHighlighting {
    let tokens: [SyntaxHighlightToken]
    let updateTokens: [SyntaxHighlightToken]?
    let resetGate: ManualSyntaxHighlightGate?
    let updateGate: ManualSyntaxHighlightGate?
    let updateRefreshRange: NSRange?
    var resetCount = 0
    var updateCount = 0

    init(
        tokens: [SyntaxHighlightToken] = [],
        updateTokens: [SyntaxHighlightToken]? = nil,
        resetGate: ManualSyntaxHighlightGate? = nil,
        updateGate: ManualSyntaxHighlightGate? = nil,
        updateRefreshRange: NSRange? = nil
    ) {
        self.tokens = tokens
        self.updateTokens = updateTokens
        self.resetGate = resetGate
        self.updateGate = updateGate
        self.updateRefreshRange = updateRefreshRange
    }

    func reset(source: String, language: SyntaxLanguage, revision: Int) async -> SyntaxHighlightResult {
        resetCount += 1
        if let resetGate {
            await resetGate.suspend()
        }
        return result(source: source, language: language, revision: revision, refreshRange: nil)
    }

    func update(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> SyntaxHighlightResult {
        updateCount += 1
        if let updateGate {
            await updateGate.suspend()
        }
        return result(
            tokens: updateTokens ?? tokens,
            source: source,
            language: language,
            revision: revision,
            refreshRange: updateRefreshRange
        )
    }

    func callCount() -> Int {
        resetCount + updateCount
    }

    func result(
        tokens: [SyntaxHighlightToken]? = nil,
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        refreshRange: NSRange?
    ) -> SyntaxHighlightResult {
        SyntaxHighlightResult(
            tokens: tokens ?? self.tokens,
            source: source,
            language: language,
            revision: revision,
            refreshRange: refreshRange ?? NSRange(location: 0, length: source.utf16.count)
        )
    }
}

actor SyntaxEditorLanguageAwareTestHighlighter: SyntaxHighlighting {
    let swiftTokens: [SyntaxHighlightToken]
    let jsonTokens: [SyntaxHighlightToken]
    let resetGate: ManualSyntaxHighlightGate?
    let updateGate: ManualSyntaxHighlightGate?

    init(
        swiftTokens: [SyntaxHighlightToken],
        jsonTokens: [SyntaxHighlightToken],
        resetGate: ManualSyntaxHighlightGate? = nil,
        updateGate: ManualSyntaxHighlightGate? = nil
    ) {
        self.swiftTokens = swiftTokens
        self.jsonTokens = jsonTokens
        self.resetGate = resetGate
        self.updateGate = updateGate
    }

    func reset(source: String, language: SyntaxLanguage, revision: Int) async -> SyntaxHighlightResult {
        if let resetGate {
            await resetGate.suspend()
        }
        return result(source: source, language: language, revision: revision)
    }

    func update(
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation,
        revision: Int
    ) async -> SyntaxHighlightResult {
        if let updateGate {
            await updateGate.suspend()
        }
        return result(source: source, language: language, revision: revision)
    }

    func result(source: String, language: SyntaxLanguage, revision: Int) -> SyntaxHighlightResult {
        let tokens: [SyntaxHighlightToken] = if language == SyntaxLanguage.swift {
            swiftTokens
        } else if language == SyntaxLanguage.json {
            jsonTokens
        } else {
            []
        }
        return SyntaxHighlightResult(
            tokens: tokens,
            source: source,
            language: language,
            revision: revision,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }
}

func syntaxEditorDenseHighlightFixture(
    tokenCount: Int = 2_400
) -> (source: String, tokens: [SyntaxHighlightToken]) {
    let source = String(repeating: "x", count: tokenCount)
    let tokens = (0..<tokenCount).map { index in
        SyntaxHighlightToken(
            range: NSRange(location: index, length: 1),
            rawCaptureName: syntaxEditorDenseHighlightCaptureName(at: index)
        )
    }
    return (source, tokens)
}

func syntaxEditorDenseHighlightCaptureName(at index: Int) -> String {
    switch index % 3 {
    case 0: "editor.syntax.swift.keyword"
    case 1: "editor.syntax.swift.string"
    default: "editor.syntax.swift.comment"
    }
}

func syntaxEditorDenseHighlightColor(
    in theme: SyntaxEditorColorTheme,
    at index: Int
) -> SyntaxEditorColor {
    switch index % 3 {
    case 0: theme.keyword
    case 1: theme.string
    default: theme.comment
    }
}

#if canImport(UIKit)
let syntaxEditorKeyCommandModifierMask: UIKeyModifierFlags = [
    .command,
    .control,
    .alternate,
    .shift,
]

@MainActor
func syntaxEditorKeyCommand(
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
func hasSyntaxEditorKeyCommand(
    _ commands: [UIKeyCommand]?,
    input: String,
    modifierFlags: UIKeyModifierFlags
) -> Bool {
    syntaxEditorKeyCommand(commands, input: input, modifierFlags: modifierFlags) != nil
}

@MainActor
func syntaxEditorChildMenu(_ menu: UIMenu, title: String) -> UIMenu? {
    menu.children.compactMap { $0 as? UIMenu }.first { $0.title == title }
}

@MainActor
func syntaxEditorChildKeyCommand(_ menu: UIMenu, title: String) -> UIKeyCommand? {
    for child in menu.children {
        if let command = child as? UIKeyCommand,
           command.title == title {
            return command
        }

        if let submenu = child as? UIMenu,
           let command = syntaxEditorChildKeyCommand(submenu, title: title) {
            return command
        }
    }

    return nil
}

@MainActor
@discardableResult
func performSyntaxEditorSelector(_ selectorName: String, on view: SyntaxEditorView) -> Bool {
    let selector = NSSelectorFromString(selectorName)
    guard view.responds(to: selector) else {
        Issue.record("SyntaxEditorView does not respond to \(selectorName)")
        return false
    }

    _ = view.perform(selector, with: nil)
    return true
}

let longSyntaxEditorLine = String(
    repeating: "let extremelyLongIdentifierName = syntaxEditorHorizontalScrollValue; ",
    count: 4
)

let longSyntaxEditorMultilineText = """
const answer = 42;
function greet(name) {
    \(String(repeating: "return HelloName; ", count: 10))
}
"""

let visibleMidSyntaxEditorLocation = 20

final class SyntaxEditorUITestInputDelegate: NSObject, UITextInputDelegate {
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

final class SyntaxEditorUITestForeignTextPosition: UITextPosition {}

let offscreenWideSyntaxEditorText: String = {
    let leadingShortLines = (0..<20).map { "let short\($0) = true;" }
    let wideLine = [String(repeating: "let offscreenHorizontalScrollRange = value; ", count: 24)]
    let trailingShortLines = (20..<60).map { "let short\($0) = false;" }
    return (leadingShortLines + wideLine + trailingShortLines).joined(separator: "\n")
}()

let offscreenWideUnicodeSyntaxEditorLine = String(repeating: "漢字🙂", count: 80)

let offscreenWideUnicodeSyntaxEditorText: String = {
    let leadingShortLines = (0..<20).map { "let short\($0) = true;" }
    let trailingShortLines = (20..<60).map { "let short\($0) = false;" }
    return (leadingShortLines + [offscreenWideUnicodeSyntaxEditorLine] + trailingShortLines)
        .joined(separator: "\n")
}()

@MainActor
func layoutIOSEditorView(
    _ editorView: SyntaxEditorView,
    width: CGFloat = 160,
    height: CGFloat = 120
) {
    editorView.frame = CGRect(x: 0, y: 0, width: width, height: height)
    editorView.setNeedsLayout()
    editorView.layoutIfNeeded()
}

@MainActor
func iOSEditorStableHorizontalOffset(_ editorView: SyntaxEditorView) -> CGFloat {
    max(0, (editorView.contentSize.width - editorView.bounds.width) * 0.25)
}

@MainActor
func iOSEditorLineMidY(_ editorView: SyntaxEditorView, lineIndex: Int) -> CGFloat {
    editorView.textContainerInset.top + editorView.font.lineHeight * (CGFloat(lineIndex) + 0.5)
}

@MainActor
func iOSEditorHasHorizontalOverflow(_ editorView: SyntaxEditorView) -> Bool {
    layoutIOSEditorView(editorView)
    return !editorView.textContainer.widthTracksTextView
        && editorView.contentSize.width > editorView.bounds.width + 1
        && editorView.textContainer.size.width > editorView.bounds.width
}

@MainActor
func iOSEditorHorizontalOverflowDiagnostics(_ editorView: SyntaxEditorView) -> String {
    layoutIOSEditorView(editorView)
    return "widthTracksTextView=\(editorView.textContainer.widthTracksTextView) "
        + "contentSize=\(editorView.contentSize) "
        + "bounds=\(editorView.bounds) "
        + "textContainer.size=\(editorView.textContainer.size) "
        + "lineBreakMode=\(String(describing: iOSEditorLineBreakMode(editorView)))"
}

@MainActor
func iOSEditorRenderedContentFrame(_ editorView: SyntaxEditorView) -> CGRect? {
    let frame = editorView.renderedTextContentFrameForTesting
    guard frame.width > 0 else { return nil }

    return frame
}

@MainActor
func iOSEditorTextUsageHeight(_ editorView: SyntaxEditorView) -> CGFloat {
    (editorView.textLayoutManager?.usageBoundsForTextContainer.maxY ?? 0)
        + editorView.textContainerInset.top
        + editorView.textContainerInset.bottom
}

@MainActor
func iOSEditorVisibleTextContainerRect(_ editorView: SyntaxEditorView) -> CGRect {
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
func editorTextLayoutUsageBoundsCoverVisibleHorizontalViewport(_ editorView: SyntaxEditorView) -> Bool {
    guard let textLayoutManager = editorView.textLayoutManager else {
        return false
    }

    let visibleRect = iOSEditorVisibleTextContainerRect(editorView)
    textLayoutManager.ensureLayout(for: visibleRect)

    return textLayoutManager.usageBoundsForTextContainer.maxX >= visibleRect.maxX - 1
}

@MainActor
func editorTextLayoutDiagnostics(_ editorView: SyntaxEditorView) -> String {
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
func iOSEditorHasBackgroundAttribute(_ editorView: SyntaxEditorView, at location: Int) -> Bool {
    editorView.bracketHighlightRangesForTesting.contains { NSLocationInRange(location, $0) }
}

@MainActor
func iOSEditorForegroundColor(_ editorView: SyntaxEditorView, at location: Int) -> UIColor? {
    guard let attributedText = editorView.attributedText,
          location >= 0,
          location < attributedText.length
    else {
        return nil
    }

    if let color = editorView.syntaxForegroundColorForTesting(at: location) {
        return color
    }

    if let color = attributedText.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor {
        return color
    }

    return editorView.baseForegroundColorForTesting()
}

@MainActor
func iOSEditorFont(_ editorView: SyntaxEditorView, at location: Int) -> UIFont? {
    guard let attributedText = editorView.attributedText,
          location >= 0,
          location < attributedText.length
    else {
        return nil
    }

    return attributedText.attribute(.font, at: location, effectiveRange: nil) as? UIFont
}

func syntaxEditorUITestFontsEqual(_ lhs: UIFont?, _ rhs: UIFont?) -> Bool {
    guard let lhs, let rhs else { return false }
    return lhs.fontName == rhs.fontName
        && abs(lhs.pointSize - rhs.pointSize) < 0.01
}

@MainActor
func iOSEditorLineFragmentForegroundColor(_ editorView: SyntaxEditorView, at location: Int) -> UIColor? {
    if let color = editorView.syntaxForegroundColorForTesting(at: location) {
        return color
    }

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
    if let color = lineFragment.attributedString.attribute(.foregroundColor, at: localLocation, effectiveRange: nil) as? UIColor {
        return color
    }

    return editorView.baseForegroundColorForTesting()
}

@MainActor
func iOSEditorLineBreakMode(_ editorView: SyntaxEditorView, at location: Int = 0) -> NSLineBreakMode? {
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
func iOSEditorParagraphSpacing(_ editorView: SyntaxEditorView, at location: Int = 0) -> CGFloat? {
    guard let attributedText = editorView.attributedText,
          location >= 0,
          location < attributedText.length
    else {
        return nil
    }

    return (attributedText.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?
        .paragraphSpacing
}

@MainActor
func iOSEditorUnderlineStyle(_ editorView: SyntaxEditorView, at location: Int) -> Int? {
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
func iOSEditorUnderlineColor(_ editorView: SyntaxEditorView, at location: Int) -> UIColor? {
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
let syntaxEditorMenuItemModifierMask: NSEvent.ModifierFlags = [
    .command,
    .control,
    .option,
    .shift,
]

final class SyntaxEditorNotificationRecorder: NSObject {
    private(set) var count = 0

    @objc
    func record(_ notification: Notification) {
        count += 1
    }
}

@MainActor
func macEditorForegroundColor(_ editorView: SyntaxEditorView, at location: Int) -> NSColor? {
    guard let textStorage = editorView.textView.textStorage else {
        return nil
    }
    guard location >= 0,
          location < textStorage.length
    else {
        return nil
    }

    editorView.materializeSyntaxForegroundForTesting(in: NSRange(location: location, length: 1))
    if let color = editorView.syntaxForegroundColorForTesting(at: location) {
        return color
    }

    if let color = textStorage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor {
        return color
    }

    return editorView.baseForegroundColorForTesting()
}

@MainActor
func macEditorPermanentForegroundColor(_ editorView: SyntaxEditorView, at location: Int) -> NSColor? {
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

@MainActor
func macEditorFont(_ editorView: SyntaxEditorView, at location: Int) -> NSFont? {
    guard let textStorage = editorView.textView.textStorage else {
        return nil
    }
    guard location >= 0,
          location < textStorage.length
    else {
        return nil
    }

    return textStorage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
}

func syntaxEditorUITestFontsEqual(_ lhs: NSFont?, _ rhs: NSFont?) -> Bool {
    guard let lhs, let rhs else { return false }
    return lhs.fontName == rhs.fontName
        && abs(lhs.pointSize - rhs.pointSize) < 0.01
}

@MainActor
func macEditorUnderlineStyle(_ editorView: SyntaxEditorView, at location: Int) -> Int? {
    guard let textStorage = editorView.textView.textStorage else {
        return nil
    }
    guard location >= 0,
          location < textStorage.length
    else {
        return nil
    }

    let value = textStorage.attribute(.underlineStyle, at: location, effectiveRange: nil)
    if let number = value as? NSNumber {
        return number.intValue
    }
    return value as? Int
}

@MainActor
func macEditorBackgroundColor(_ editorView: SyntaxEditorView, at location: Int) -> NSColor? {
    guard let textStorage = editorView.textView.textStorage else {
        return nil
    }
    guard location >= 0,
          location < textStorage.length
    else {
        return nil
    }

    if let color = editorView.textView.layoutManager?.temporaryAttribute(
        .backgroundColor,
        atCharacterIndex: location,
        effectiveRange: nil
    ) as? NSColor {
        return color
    }

    return textStorage.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
}

@MainActor
func macEditorHasBackgroundAttribute(_ editorView: SyntaxEditorView, at location: Int) -> Bool {
    if editorView.bracketHighlightRangesForTesting.contains(where: { NSLocationInRange(location, $0) }) {
        return true
    }
    return macEditorBackgroundColor(editorView, at: location) != nil
}

@MainActor
func macEditorTextStorageBackgroundColor(_ editorView: SyntaxEditorView, at location: Int) -> NSColor? {
    guard let textStorage = editorView.textView.textStorage else {
        return nil
    }
    guard location >= 0,
          location < textStorage.length
    else {
        return nil
    }

    return textStorage.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
}

@MainActor
func macEditorVisibleFragmentViews(_ editorView: SyntaxEditorView) -> [SyntaxEditorTextLayoutFragmentView] {
    editorView.textView.layoutVisibleViewport()
    return editorView.textView.textContentView.subviews.compactMap { $0 as? SyntaxEditorTextLayoutFragmentView }
}

func makeMacCommandKeyEvent(
    _ character: String,
    modifierFlags: NSEvent.ModifierFlags = [.command]
) -> NSEvent? {
    makeMacKeyEvent(character, modifierFlags: modifierFlags)
}

func makeMacKeyEvent(
    _ character: String,
    modifierFlags: NSEvent.ModifierFlags = []
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

@MainActor
func syntaxEditorSubmenu(_ menu: NSMenu, title: String) -> NSMenu? {
    menu.item(withTitle: title)?.submenu
}
#endif
