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

#if canImport(UIKit)
private func requireUITextViewDelegate(_ value: any UITextViewDelegate) {}

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

@MainActor
private func waitUntilIOSEditorCondition(
    nanoseconds: UInt64 = 5_000_000_000,
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .nanoseconds(Int64(nanoseconds)))

    while !condition() {
        guard clock.now < deadline else {
            return false
        }
        await Task.yield()
    }

    return true
}

private let longIOSSyntaxEditorLine = String(
    repeating: "let extremelyLongIdentifierName = syntaxEditorHorizontalScrollValue; ",
    count: 16
)

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
    return editorView.contentSize.width > editorView.bounds.width + 1
        && editorView.textContainer.size.width > editorView.bounds.width
        && editorView.textContainer.size.width <= editorView.contentSize.width + 1
}

@MainActor
private func iOSEditorTextLocationNearVisibleMid(
    _ editorView: SyntaxEditorView,
    utf16Length: Int
) -> Int {
    let visibleMidX = editorView.contentOffset.x + editorView.bounds.width / 2
    for location in 0..<min(utf16Length, 160) {
        guard let position = editorView.textView.position(
            from: editorView.textView.beginningOfDocument,
            offset: location
        ) else {
            continue
        }

        let caretRect = editorView.textView.caretRect(for: position)
        if abs(caretRect.midX - visibleMidX) <= 12 {
            return location
        }
    }

    return 0
}
#endif

#if canImport(AppKit)
private func requireNSTextViewDelegate(_ value: any NSTextViewDelegate) {}

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
        let model = SyntaxEditorModel(text: "{}", language: BuiltinSyntaxLanguages.javascript)
        let controller = SyntaxEditorViewController(model: model)

        requireObservable(controller)
        requireUITextViewDelegate(controller)
        #expect(controller.model === model)
        #expect(
            controller.textView(
                controller.textView,
                shouldChangeTextIn: NSRange(location: 0, length: 0),
                replacementText: "a"
            )
        )
    }

    @Test("SyntaxEditorView applies transformed iOS text input to the model")
    @MainActor
    func syntaxEditorViewIOSAppliesTransformedTextInputToModel() {
        let model = SyntaxEditorModel(text: "", language: BuiltinSyntaxLanguages.javascript)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        #expect(!editorView.textView(
            editorView.textView,
            shouldChangeTextIn: NSRange(location: 0, length: 0),
            replacementText: "{"
        ))
        #expect(editorView.text == "{}")
        #expect(model.text == "{}")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))

        #expect(!editorView.textView(
            editorView.textView,
            shouldChangeTextIn: editorView.selectedRange,
            replacementText: "\n"
        ))
        #expect(editorView.text == "{\n    \n}")
        #expect(model.text == "{\n    \n}")
        #expect(editorView.selectedRange == NSRange(location: 6, length: 0))
    }

    @Test("SyntaxEditorView reflects model text mutations on iOS")
    @MainActor
    func syntaxEditorViewIOSTextObservation() async {
        let model = SyntaxEditorModel(text: "const answer = 42;", language: BuiltinSyntaxLanguages.javascript)
        let editorView = SyntaxEditorView(model: model)

        model.text = "{\"enabled\":true}"

        #expect(await waitUntilIOSEditorCondition {
            editorView.text == "{\"enabled\":true}"
        })
    }

    @Test("SyntaxEditorView reflects editable and wrapping changes on iOS")
    @MainActor
    func syntaxEditorViewIOSEditorStateObservation() async {
        let model = SyntaxEditorModel(text: longIOSSyntaxEditorLine, language: BuiltinSyntaxLanguages.swift)
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        model.isEditable = false
        model.lineWrappingEnabled = true

        #expect(await waitUntilIOSEditorCondition {
            editorView.isEditable == false
        })
        #expect(await waitUntilIOSEditorCondition {
            layoutIOSEditorView(editorView)
            return editorView.textContainer.widthTracksTextView
                && editorView.textContainer.lineBreakMode == .byWordWrapping
                && editorView.showsHorizontalScrollIndicator == false
                && editorView.alwaysBounceHorizontal == false
                && editorView.contentSize.width <= editorView.bounds.width + 1
        })

        model.lineWrappingEnabled = false

        #expect(await waitUntilIOSEditorCondition {
            layoutIOSEditorView(editorView)
            return !editorView.textContainer.widthTracksTextView
                && editorView.textContainer.lineBreakMode == .byClipping
                && editorView.showsHorizontalScrollIndicator
                && editorView.alwaysBounceHorizontal
                && editorView.contentSize.width > editorView.bounds.width + 1
                && editorView.textContainer.size.width <= editorView.contentSize.width + 1
        })

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        model.lineWrappingEnabled = true

        #expect(await waitUntilIOSEditorCondition {
            layoutIOSEditorView(editorView)
            return editorView.contentOffset.x == 0
                && editorView.contentSize.width <= editorView.bounds.width + 1
        })
    }

    @Test("SyntaxEditorView enables horizontal scrolling for initial long iOS line")
    @MainActor
    func syntaxEditorViewIOSInitialLongLineScrollsHorizontally() async {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)

        #expect(await waitUntilIOSEditorCondition {
            iOSEditorHasHorizontalOverflow(editorView)
        })

        let viewportContentSize = CGSize(
            width: editorView.bounds.width,
            height: editorView.contentSize.height
        )
        editorView.contentSize = viewportContentSize
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)
    }

    @Test("SyntaxEditorView grows horizontal content size after observed iOS text update")
    @MainActor
    func syntaxEditorViewIOSObservedLongTextUpdateGrowsHorizontalContentSize() async {
        let model = SyntaxEditorModel(
            text: "let short = true",
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        model.text = longIOSSyntaxEditorLine

        #expect(await waitUntilIOSEditorCondition {
            iOSEditorHasHorizontalOverflow(editorView)
        })
    }

    @Test("SyntaxEditorView grows horizontal content size after direct iOS text assignment")
    @MainActor
    func syntaxEditorViewIOSDirectTextAssignmentGrowsHorizontalContentSize() async {
        let model = SyntaxEditorModel(
            text: "let short = true",
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)

        editorView.text = longIOSSyntaxEditorLine

        #expect(model.text == longIOSSyntaxEditorLine)
        #expect(await waitUntilIOSEditorCondition {
            iOSEditorHasHorizontalOverflow(editorView)
        })
    }

    @Test("SyntaxEditorView keeps iOS scroll ownership while editing")
    @MainActor
    func syntaxEditorViewIOSKeepsScrollOwnershipWhileEditing() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        let insertionLocation = iOSEditorTextLocationNearVisibleMid(
            editorView,
            utf16Length: longIOSSyntaxEditorLine.utf16.count
        )
        #expect(insertionLocation > 0)

        editorView.selectedRange = NSRange(location: insertionLocation, length: 0)
        layoutIOSEditorView(editorView)
        let stableOuterOffsetX = editorView.contentOffset.x
        #expect(stableOuterOffsetX > 0)
        editorView.textView.contentOffset = CGPoint(x: 48, y: 24)

        let insertionStart = editorView.textView.position(
            from: editorView.textView.beginningOfDocument,
            offset: insertionLocation
        )
        #expect(insertionStart != nil)
        guard let insertionStart,
              let insertionRange = editorView.textView.textRange(from: insertionStart, to: insertionStart)
        else {
            return
        }
        editorView.textView.replace(insertionRange, withText: "x")
        editorView.textViewDidChange(editorView.textView)
        layoutIOSEditorView(editorView)

        #expect(editorView.textView.contentOffset == .zero)
        #expect(editorView.textView.bounds.origin == .zero)
        #expect(abs(editorView.contentOffset.x - stableOuterOffsetX) <= 1)
    }

    @Test("SyntaxEditorView keeps iOS scroll ownership while moving cursor")
    @MainActor
    func syntaxEditorViewIOSKeepsScrollOwnershipWhileMovingCursor() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOuterOffsetX = editorView.contentOffset.x
        #expect(stableOuterOffsetX > 0)

        let targetLocation = iOSEditorTextLocationNearVisibleMid(
            editorView,
            utf16Length: longIOSSyntaxEditorLine.utf16.count
        )
        #expect(targetLocation > 0)

        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        layoutIOSEditorView(editorView)

        #expect(editorView.textView.contentOffset == .zero)
        #expect(editorView.textView.bounds.origin == .zero)
        #expect(abs(editorView.contentOffset.x - stableOuterOffsetX) <= 1)
    }

    @Test("SyntaxEditorView ignores oversized iOS ancestor scroll requests while moving cursor")
    @MainActor
    func syntaxEditorViewIOSIgnoresOversizedAncestorScrollRequestsWhileMovingCursor() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOuterOffsetX = editorView.contentOffset.x
        #expect(stableOuterOffsetX > 0)

        editorView.scrollRectToVisible(editorView.textView.frame, animated: true)
        layoutIOSEditorView(editorView)
        #expect(abs(editorView.contentOffset.x - stableOuterOffsetX) <= 1)

        let targetLocation = iOSEditorTextLocationNearVisibleMid(
            editorView,
            utf16Length: longIOSSyntaxEditorLine.utf16.count
        )
        #expect(targetLocation > 0)

        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        editorView.scrollRectToVisible(editorView.textView.frame, animated: true)
        layoutIOSEditorView(editorView)

        #expect(editorView.textView.contentOffset == .zero)
        #expect(editorView.textView.bounds.origin == .zero)
        #expect(abs(editorView.contentOffset.x - stableOuterOffsetX) <= 1)
    }

    @Test("SyntaxEditorView routes iOS native range scroll requests through outer scroll view")
    @MainActor
    func syntaxEditorViewIOSRoutesNativeRangeScrollRequestsThroughOuterScrollView() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOuterOffsetX = editorView.contentOffset.x
        #expect(stableOuterOffsetX > 0)

        let targetLocation = min(longIOSSyntaxEditorLine.utf16.count - 1, 120)
        #expect(editorView.textView.position(
            from: editorView.textView.beginningOfDocument,
            offset: targetLocation
        ) != nil)

        editorView.textView.scrollRangeToVisible(NSRange(location: targetLocation, length: 0))
        layoutIOSEditorView(editorView)

        #expect(editorView.textView.contentOffset == .zero)
        #expect(editorView.textView.bounds.origin == .zero)
        #expect(editorView.contentOffset.x > stableOuterOffsetX)
    }

    @Test("SyntaxEditorView ignores unrelated far-right iOS native scroll rect requests while moving cursor")
    @MainActor
    func syntaxEditorViewIOSIgnoresUnrelatedFarRightNativeScrollRectRequestsWhileMovingCursor() {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(model: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let targetLocation = iOSEditorTextLocationNearVisibleMid(
            editorView,
            utf16Length: longIOSSyntaxEditorLine.utf16.count
        )
        #expect(targetLocation > 0)
        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        layoutIOSEditorView(editorView)

        let stableOuterOffsetX = editorView.contentOffset.x
        let farRightRect = CGRect(
            x: max(0, editorView.textView.bounds.width - 2),
            y: editorView.textView.caretRect(for: editorView.textView.selectedTextRange?.end ?? editorView.textView.endOfDocument).minY,
            width: 2,
            height: editorView.bounds.height
        )

        editorView.textView.scrollRectToVisible(farRightRect, animated: true)
        layoutIOSEditorView(editorView)

        #expect(editorView.textView.contentOffset == .zero)
        #expect(editorView.textView.bounds.origin == .zero)
        #expect(abs(editorView.contentOffset.x - stableOuterOffsetX) <= 1)
    }

    @Test("SyntaxEditorView clears stale horizontal content size after iOS wrapping toggles")
    @MainActor
    func syntaxEditorViewIOSWrappingToggleClearsStaleHorizontalContentSize() async {
        let model = SyntaxEditorModel(
            text: longIOSSyntaxEditorLine,
            language: BuiltinSyntaxLanguages.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(model: model)

        #expect(await waitUntilIOSEditorCondition {
            layoutIOSEditorView(editorView)
            return editorView.contentSize.width <= editorView.bounds.width + 1
        })

        model.lineWrappingEnabled = false

        #expect(await waitUntilIOSEditorCondition {
            iOSEditorHasHorizontalOverflow(editorView)
        })

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        model.lineWrappingEnabled = true

        #expect(await waitUntilIOSEditorCondition {
            layoutIOSEditorView(editorView)
            return editorView.contentOffset.x == 0
                && editorView.contentSize.width <= editorView.bounds.width + 1
        })
    }

    @Test("SyntaxEditorView omits editing key commands while read-only on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyOmitsEditingKeyCommands() {
        let model = SyntaxEditorModel(
            text: "let answer = 42",
            language: BuiltinSyntaxLanguages.swift,
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

        let indentActionTarget = editorView.textView.target(
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
            language: BuiltinSyntaxLanguages.swift,
            isEditable: false
        )
        let editorView = SyntaxEditorView(model: model)
        editorView.selectedRange = NSRange(location: 0, length: source.utf16.count)

        #expect(!editorView.textView(
            editorView.textView,
            shouldChangeTextIn: NSRange(location: 0, length: 0),
            replacementText: "\t"
        ))
        #expect(performSyntaxEditorSelector("handleIndentCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleOutdentCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleToggleCommentCommand", on: editorView))

        #expect(model.text == source)
        #expect(editorView.text == source)
    }

    @Test("SyntaxEditorView read-only undo and redo do not mutate text on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyUndoRedoDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorModel(text: source, language: BuiltinSyntaxLanguages.swift)
        let editorView = SyntaxEditorView(model: model)
        editorView.selectedRange = NSRange(location: 0, length: 0)

        #expect(performSyntaxEditorSelector("handleIndentCommand", on: editorView))
        let indentedSource = "    \(source)"
        #expect(model.text == indentedSource)
        #expect(editorView.text == indentedSource)

        model.isEditable = false

        #expect(!editorView.canPerformAction(Selector(("undo:")), withSender: nil))
        #expect(!editorView.canPerformAction(Selector(("redo:")), withSender: nil))
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

    @Test("SyntaxEditorView keeps selection and copy available while read-only on iOS")
    @MainActor
    func syntaxEditorViewIOSReadOnlyKeepsSelectionAndCopy() {
        let source = "copy me"
        let model = SyntaxEditorModel(
            text: source,
            language: BuiltinSyntaxLanguages.javascript,
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
    private func waitUntilEditorCondition(
        nanoseconds: UInt64 = 5_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .nanoseconds(Int64(nanoseconds)))

        while !condition() {
            guard clock.now < deadline else {
                return false
            }
            await Task.yield()
        }

        return true
    }

    @Test("SyntaxEditorView reflects model text mutations on macOS")
    @MainActor
    func syntaxEditorViewMacTextObservation() async {
        let model = SyntaxEditorModel(text: "const answer = 42;", language: BuiltinSyntaxLanguages.javascript)
        let editorView = SyntaxEditorView(model: model)

        model.text = "{\"enabled\":true}"

        #expect(await waitUntilEditorCondition {
            editorView.textView.string == "{\"enabled\":true}"
        })
    }

    @Test("SyntaxEditorView reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewMacEditorStateObservation() async {
        let model = SyntaxEditorModel(text: "body {}", language: BuiltinSyntaxLanguages.css)
        let editorView = SyntaxEditorView(model: model)

        model.isEditable = false
        model.lineWrappingEnabled = true

        #expect(await waitUntilEditorCondition {
            editorView.textView.isEditable == false
        })
        #expect(await waitUntilEditorCondition {
            editorView.hasHorizontalScroller == false
        })

        model.lineWrappingEnabled = false

        #expect(await waitUntilEditorCondition {
            editorView.hasHorizontalScroller == true
        })
    }

    @Test("SyntaxEditorView keeps synchronizing after language changes on macOS")
    @MainActor
    func syntaxEditorViewMacLanguageChangeKeepsObservationAlive() async {
        let model = SyntaxEditorModel(text: "let answer = 42", language: BuiltinSyntaxLanguages.swift)
        let editorView = SyntaxEditorView(model: model)

        model.language = BuiltinSyntaxLanguages.json
        model.isEditable = false

        #expect(await waitUntilEditorCondition {
            editorView.textView.isEditable == false
        })

        model.text = "{\"answer\":42}"

        #expect(await waitUntilEditorCondition {
            editorView.textView.string == "{\"answer\":42}"
        })
    }

    @Test("SyntaxEditorView read-only delegate commands do not mutate text on macOS")
    @MainActor
    func syntaxEditorViewMacReadOnlyDelegateCommandsDoNotMutateText() {
        let source = "let answer = 42"
        let model = SyntaxEditorModel(
            text: source,
            language: BuiltinSyntaxLanguages.swift,
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
            language: BuiltinSyntaxLanguages.swift,
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

    @Test("SyntaxEditorView preserves undo history when undo manager runs while read-only on macOS")
    @MainActor
    func syntaxEditorViewMacReadOnlyUndoManagerPreservesHistory() async {
        let source = "let answer = 42"
        let onceIndentedSource = "    \(source)"
        let twiceIndentedSource = "        \(source)"
        let model = SyntaxEditorModel(text: source, language: BuiltinSyntaxLanguages.swift)
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
        let model = SyntaxEditorModel(text: "{}", language: BuiltinSyntaxLanguages.javascript)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        let textView = controller.textView
        #expect(textView.allowsUndo == true)
    }

    @Test("SyntaxEditorViewController preserves Observable conformance on macOS")
    @MainActor
    func syntaxEditorViewControllerMacObservableCompatibility() {
        let model = SyntaxEditorModel(text: "{}", language: BuiltinSyntaxLanguages.javascript)
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
        let model = SyntaxEditorModel(text: "const answer = 42;", language: BuiltinSyntaxLanguages.javascript)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.text = "{\"enabled\":true}"

        #expect(await waitUntilEditorCondition {
            controller.textView.string == "{\"enabled\":true}"
        })
    }

    @Test("SyntaxEditorViewController reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacEditorStateObservation() async {
        let model = SyntaxEditorModel(text: "body {}", language: BuiltinSyntaxLanguages.css)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.isEditable = false
        model.lineWrappingEnabled = true

        #expect(await waitUntilEditorCondition {
            controller.textView.isEditable == false
        })
        #expect(await waitUntilEditorCondition {
            controller.scrollView.hasHorizontalScroller == false
        })

        model.lineWrappingEnabled = false

        #expect(await waitUntilEditorCondition {
            controller.scrollView.hasHorizontalScroller == true
        })
    }

    @Test("SyntaxEditorViewController keeps synchronizing after language changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacLanguageChangeKeepsObservationAlive() async {
        let model = SyntaxEditorModel(text: "let answer = 42", language: BuiltinSyntaxLanguages.swift)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.language = BuiltinSyntaxLanguages.json
        model.isEditable = false

        #expect(await waitUntilEditorCondition {
            controller.textView.isEditable == false
        })

        model.text = "{\"answer\":42}"

        #expect(await waitUntilEditorCondition {
            controller.textView.string == "{\"answer\":42}"
        })
    }
#endif
}
