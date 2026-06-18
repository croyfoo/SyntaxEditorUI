#if canImport(UIKit)
import Foundation
import Observation
import ObservationBridge
import SwiftUI
import Testing
import UIKit
@testable import SyntaxEditorUI
@testable import SyntaxEditorUICommon
@testable import SyntaxEditorUIUIKit

extension SyntaxEditorUITests {
    @Test("SyntaxEditorViewController renders source-of-truth state on iOS")
    @MainActor
    func syntaxEditorViewControllerIOSRendersSourceOfTruthState() async {
        let model = SyntaxEditorTestContext(text: "{}", language: SyntaxLanguage.javascript)
        let controller = SyntaxEditorViewController(testContext: model)
        controller.loadViewIfNeeded()

        #expect(controller.model === model.model)
        #expect(controller.editorView.model === model.model)

        guard let delivery = controller.editorView.modelDeliveryForTesting else {
            Issue.record("Expected SyntaxEditorViewController to expose its production model delivery")
            return
        }
        let renderedText = await delivery.values {
            controller.editorView.text
        }

        #expect(await renderedText.waitUntilValue("{}"))

        model.model.replaceText("{\"enabled\":true}")

        #expect(await renderedText.waitUntilValue("{\"enabled\":true}"))

        let originalEditorView = controller.editorView
        let replacementModel = SyntaxEditorModel(text: "let replacement = true", language: SyntaxLanguage.swift)

        controller.update(model: replacementModel)

        #expect(controller.editorView === originalEditorView)
        #expect(controller.editorView.model === replacementModel)
        #expect(delivery.isActive == false)

        guard let replacementDelivery = controller.editorView.modelDeliveryForTesting else {
            Issue.record("Expected replacement model delivery")
            return
        }
        let replacementRenderedText = await replacementDelivery.values {
            controller.editorView.text
        }
        #expect(await replacementRenderedText.waitUntilValue("let replacement = true"))
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
            TextLayoutGeometry.ranges(
                ranges,
                intersecting: NSRange(location: 12, length: 25)
            ) == [
                NSRange(location: 12, length: 3),
                NSRange(location: 30, length: 7),
            ]
        )
        #expect(TextLayoutGeometry.ranges(ranges, intersecting: NSRange(location: 100, length: 5)).isEmpty)
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

        #expect(TextLayoutGeometry.ranges(
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

        model.model.replaceText("let other = other")
        editorView.synchronizeDocumentForTesting()

        #expect(editorView.findFoundRangesForTesting.isEmpty)
        #expect(editorView.findHighlightedRangesForTesting.isEmpty)
    }

    @Test("SyntaxEditorView scrolls iOS highlighted find ranges through the editor scroll pipeline")
    @MainActor
    func syntaxEditorViewIOSScrollsHighlightedFindRangesThroughEditorScrollPipeline() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorLine,
            language: .swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 120, height: 80)
        let targetLocation = max(0, longSyntaxEditorLine.utf16.count - 20)
        let targetRange = NSRange(location: targetLocation, length: 5)

        editorView.findCoordinator?.willHighlight(
            foundTextRange: SyntaxEditorView.TextRange(nsRange: targetRange),
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
        #expect(model.model.text == "{")
        #expect(editorView.text == "{")

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        undoManager.undo()
        #expect(model.model.text == source)
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
        #expect(model.model.text == "bar bar bar")
        #expect(editorView.text == "bar bar bar")

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        undoManager.undo()
        #expect(model.model.text == source)
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
        #expect(model.model.text == source)
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
        #expect(model.model.text == "{}")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))

        editorView.insertText("\n")
        #expect(editorView.text == "{\n    \n}")
        #expect(model.model.text == "{\n    \n}")
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

    @Test("SyntaxEditorView exposes active iOS marked text during input delegate updates")
    @MainActor
    func syntaxEditorViewIOSMarkedTextRangeIsCurrentDuringInputDelegateUpdate() {
        let source = "let value = "
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        let inputDelegate = SyntaxEditorUITestInputDelegate()
        var observedMarkedRange: NSRange?
        inputDelegate.textDidChangeHandler = { textInput in
            guard let editorView = textInput as? SyntaxEditorView,
                  let markedRange = editorView.markedTextRange as? SyntaxEditorView.TextRange
            else {
                return
            }
            observedMarkedRange = markedRange.nsRange
        }
        layoutIOSEditorView(editorView)
        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        editorView.inputDelegate = inputDelegate

        editorView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))

        #expect(observedMarkedRange == NSRange(location: source.utf16.count, length: "かな".utf16.count))
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
        #expect(model.model.text == source + " ")
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
        editorView.selectedRange = NSRange(location: model.model.text.utf16.count, length: 0)

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
        #expect(model.model.text == source)
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
        #expect(model.model.text == source)
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
        #expect(model.model.text == committedSource)
        #expect(editorView.selectedRange == NSRange(location: committedSource.utf16.count, length: 0))

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(editorView.text == source)
        #expect(model.model.text == source)
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
        #expect(model.model.text == expectedSource)
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
        #expect(model.model.text == expectedText)
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
        #expect(model.model.text == "X" + source + "かな")
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
        #expect(model.model.text == "X" + source + "かな")
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
        model.model.isEditable = false
        editorView.synchronizeDocumentForTesting()
        editorView.insertText("作成")

        #expect(editorView.text == source + "かな")
        #expect(model.model.text == source + "かな")
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
        #expect(model.model.text == "ab")
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
                  byExtending: SyntaxEditorView.TextPosition(offset: beforeCombiningCharacterOffset),
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
        #expect(model.model.text == source + "\"\"\"")
        #expect(editorView.selectedRange == NSRange(location: source.utf16.count + 3, length: 0))
    }

    @Test("SyntaxEditorView reflects document text replacements on iOS")
    @MainActor
    func syntaxEditorViewIOSTextObservation() async {
        let model = SyntaxEditorTestContext(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(testContext: model)
        guard let delivery = editorView.modelDeliveryForTesting else {
            Issue.record("Expected SyntaxEditorView to expose its production document delivery")
            return
        }
        let renderedText = await delivery.values {
            editorView.text
        }

        #expect(await renderedText.waitUntilValue("const answer = 42;"))

        model.model.replaceText("{\"enabled\":true}")

        #expect(await renderedText.waitUntilValue("{\"enabled\":true}"))
    }

    @Test("SyntaxEditorView does not rerun iOS configuration observation for document changes")
    @MainActor
    func syntaxEditorViewIOSConfigurationObservationIgnoresDocumentChanges() async {
        let model = SyntaxEditorTestContext(text: "const answer = 42;", language: SyntaxLanguage.javascript)
        let editorView = SyntaxEditorView(testContext: model)
        guard let configurationDelivery = editorView.modelConfigurationDeliveryForTesting,
              let documentDelivery = editorView.modelDeliveryForTesting
        else {
            Issue.record("Expected SyntaxEditorView to expose its production deliveries")
            return
        }
        let configurationPassCounter = SyntaxEditorObservationPassCounter()
        let configurationPasses = await configurationDelivery.values {
            configurationPassCounter.next()
        }
        let renderedText = await documentDelivery.values {
            editorView.text
        }

        #expect(await configurationPasses.waitUntilValue(1))

        model.model.language = SyntaxLanguage.json

        #expect(await configurationPasses.waitUntilValue(2))

        model.model.replaceText("{\"enabled\":true}")

        #expect(await renderedText.waitUntilValue("{\"enabled\":true}"))
        await syntaxEditorDrainMainActorObservationDelivery(recording: configurationPasses)
        #expect(configurationPasses.snapshot() == [1, 2])
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
        #expect(editorView.model.latestTextChange?.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView clamps iOS horizontal offset after observed text replacement")
    @MainActor
    func syntaxEditorViewIOSClampsHorizontalOffsetAfterObservedTextReplacement() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        editorView.scrollRangeToVisible(NSRange(location: longSyntaxEditorLine.utf16.count - 1, length: 0))
        layoutIOSEditorView(editorView)
        #expect(editorView.contentOffset.x > 0)

        model.model.replaceText("let value = 42")
        editorView.synchronizeDocumentForTesting()
        layoutIOSEditorView(editorView)

        #expect(editorView.text == "let value = 42")
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(editorView.contentOffset.x <= 1)
    }

    @Test("SyntaxEditorView reflects custom iOS theme")
    @MainActor
    func syntaxEditorViewIOSThemeObservation() async {
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

        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.complete))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.model.theme = updatedTheme

        editorView.synchronizeDocumentForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.complete))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), updatedTheme.baseForeground))
    }

    @Test("SyntaxEditorView refreshes iOS permanent base foreground after appearance changes")
    @MainActor
    func syntaxEditorViewIOSRefreshesPermanentBaseForegroundAfterAppearanceChanges() throws {
        let model = SyntaxEditorTestContext(
            text: "plain text",
            language: SyntaxLanguage.swift,
            theme: .default
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: SyntaxEditorUITestHighlighter())

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let controller = UIViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = window.bounds
        editorView.frame = controller.view.bounds
        editorView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(editorView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        editorView.overrideUserInterfaceStyle = .light
        controller.view.layoutIfNeeded()
        editorView.refreshForColorAppearanceChange()
        #expect(editorView.traitCollection.userInterfaceStyle == .light)
        let lightForeground = try #require(iOSEditorPermanentForegroundColor(editorView, at: 0))

        editorView.overrideUserInterfaceStyle = .dark
        controller.view.layoutIfNeeded()
        editorView.refreshForColorAppearanceChange()
        #expect(editorView.traitCollection.userInterfaceStyle == .dark)
        let darkBaseForeground = try #require(editorView.baseForegroundColorForTesting())

        withExtendedLifetime(window) {
            #expect(syntaxEditorUITestColorsEqual(iOSEditorPermanentForegroundColor(editorView, at: 0), darkBaseForeground))
            #expect(!syntaxEditorUITestColorsEqual(lightForeground, darkBaseForeground))
        }
    }

    @Test("SyntaxEditorView reflects iOS background drawing configuration")
    @MainActor
    func syntaxEditorViewIOSDrawsBackgroundObservation() async {
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
        let clearsBackground = await delivery.values {
            syntaxEditorUITestColorsEqual(editorView.backgroundColor, UIColor.clear)
                && syntaxEditorUITestColorsEqual(editorView.textContentView.backgroundColor, UIColor.clear)
                && editorView.isOpaque == false
        }

        #expect(syntaxEditorUITestColorsEqual(editorView.backgroundColor, background))
        #expect(syntaxEditorUITestColorsEqual(editorView.textContentView.backgroundColor, background))
        #expect(editorView.isOpaque)

        model.model.drawsBackground = false

        #expect(await clearsBackground.waitUntilValue(true))
    }

    @Test("SyntaxEditorView resets nested empty-style iOS tokens to the base theme")
    @MainActor
    func syntaxEditorViewIOSResetsNestedEmptyStyleTokensToBaseTheme() async {
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

        #expect(await editorView.waitForPendingHighlightForTesting())

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), theme.baseForeground))
    }

    @Test("SyntaxEditorView resets multi-level empty-style iOS tokens to the base theme")
    @MainActor
    func syntaxEditorViewIOSResetsMultiLevelEmptyStyleTokensToBaseTheme() async {
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

        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.complete))

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 2), theme.string))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 4), theme.baseForeground))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 6), theme.string))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 8), theme.keyword))
    }

    @Test("SyntaxEditorView clears iOS syntax runs when switching to plain text")
    @MainActor
    func syntaxEditorViewIOSClearsSyntaxRunsWhenSwitchingToPlainText() async {
        let source = "const answer = 42;"
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 5),
                    rawCaptureName: "editor.syntax.javascript.keyword",
                    language: .javascript
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
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(editorView.syntaxForegroundColorForTesting(at: 0) != nil)

        model.model.language = .plainText
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.syntaxForegroundColorForTesting(at: 0) == nil)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.baseForeground))
    }

    @Test("SyntaxEditorView reapplies iOS same-style tokens after empty-style splits")
    @MainActor
    func syntaxEditorViewIOSReappliesSameStyleTokensAfterEmptyStyleSplits() async {
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

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), theme.baseForeground))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 6), theme.string))
    }

    @Test("SyntaxEditorView keeps iOS empty-style gaps between separated same-style runs")
    @MainActor
    func syntaxEditorViewIOSKeepsEmptyStyleGapsBetweenSeparatedSameStyleRuns() async {
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

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 4), theme.string))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 5), theme.baseForeground))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 6), theme.string))
    }

    @Test("SyntaxEditorView reapplies cached iOS syntax colors without highlighting")
    @MainActor
    func syntaxEditorViewIOSThemeReusesCachedHighlightTokens() async {
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
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), initialTheme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), initialTheme.baseForeground))

        model.model.theme = updatedTheme

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

    @Test("SyntaxEditorView refreshes iOS syntax colors when theme changes after incremental edits")
    @MainActor
    func syntaxEditorViewIOSThemeRefreshesAfterIncrementalEditDropsCachedTokens() async {
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
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), initialTheme.keyword))

        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        editorView.insertText("!")
        await editorView.waitForPendingHighlightForTesting()
        let editedCallCount = await highlighter.callCount()
        #expect(editedCallCount == initialCallCount + 1)

        model.model.theme = updatedTheme
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(await highlighter.callCount() == editedCallCount + 1)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
    }

    @Test("SyntaxEditorView preserves cached iOS syntax colors after font size delta changes")
    @MainActor
    func syntaxEditorViewIOSFontSizeDeltaPreservesCachedHighlightTokens() async throws {
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
        let initialFont = try #require(iOSEditorFont(editorView, at: 0))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorPermanentForegroundColor(editorView, at: 0), theme.baseForeground))

        model.model.fontSizeDelta = 4
        editorView.synchronizeDocumentForTesting()

        #expect(await highlighter.callCount() == initialCallCount)
        let highlightedFont = try #require(iOSEditorFont(editorView, at: 0))
        let plainFont = try #require(iOSEditorFont(editorView, at: 3))
        #expect(abs(highlightedFont.pointSize - (initialFont.pointSize + 4)) < 0.01)
        #expect(abs(plainFont.pointSize - highlightedFont.pointSize) < 0.01)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorPermanentForegroundColor(editorView, at: 0), theme.baseForeground))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 3), theme.baseForeground))
    }

    @Test("SyntaxEditorView applies built-in iOS theme fonts after theme changes")
    @MainActor
    func syntaxEditorViewIOSAppliesBuiltInThemeFontsAfterThemeChanges() async throws {
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
        let highlightedFont = try #require(iOSEditorFont(editorView, at: 0))
        let plainFont = try #require(iOSEditorFont(editorView, at: 4))
        #expect(abs(highlightedFont.pointSize - 30) < 0.01)
        #expect(abs(plainFont.pointSize - 30) < 0.01)
    }

    @Test("SyntaxEditorView reapplies long iOS tokens when refreshing inside their range")
    @MainActor
    func syntaxEditorViewIOSRefreshesInteriorOfLongTokens() async {
        let source = String(repeating: "x", count: 80)
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            comment: syntaxEditorUITestColor(hex: 0x305070),
            string: syntaxEditorUITestColor(hex: 0x507030),
            keyword: syntaxEditorUITestColor(hex: 0x703050)
        )
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: source.utf16.count),
                    rawCaptureName: "editor.syntax.swift.comment.doc"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 10, length: 2),
                    rawCaptureName: "editor.syntax.swift.keyword"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 20, length: 2),
                    rawCaptureName: "editor.syntax.swift.string"
                ),
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 30, length: 2),
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
        let refreshRange = NSRange(location: 60, length: 1)

        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.complete))
        let initialForeground = iOSEditorForegroundColor(editorView, at: refreshRange.location)
        #expect(syntaxEditorUITestColorsEqual(initialForeground, theme.comment))
        #expect(
            syntaxEditorUITestColorsEqual(
                iOSEditorPermanentForegroundColor(editorView, at: refreshRange.location),
                theme.baseForeground
            )
        )

        editorView.reapplyTextAttributes(in: refreshRange)

        #expect(
            syntaxEditorUITestColorsEqual(
                iOSEditorPermanentForegroundColor(editorView, at: refreshRange.location),
                theme.baseForeground
            )
        )
        let reappliedForeground = iOSEditorForegroundColor(editorView, at: refreshRange.location)
        #expect(syntaxEditorUITestColorsEqual(reappliedForeground, theme.comment))
    }

    @Test("SyntaxEditorView applies built-in iOS theme base font to plain and highlighted text")
    @MainActor
    func syntaxEditorViewIOSAppliesBuiltInThemeBaseFont() async throws {
        let source = "let\nvalue"
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

        let highlightedFont = try #require(iOSEditorFont(editorView, at: 0))
        let plainFont = try #require(iOSEditorFont(editorView, at: 4))
        #expect(abs(highlightedFont.pointSize - plainFont.pointSize) < 0.01)
        #expect(abs(plainFont.pointSize - 30) < 0.01)
    }

    @Test("SyntaxEditorView keeps iOS syntax attributes out of TextKit storage")
    @MainActor
    func syntaxEditorViewIOSKeepsSyntaxAttributesOutOfTextKitStorage() async throws {
        let source = "/// doc\nlet value = 1"
        let highlighter = SyntaxEditorUITestHighlighter(
            tokens: [
                SyntaxEditorHighlighting.Token(
                    range: NSRange(location: 0, length: 7),
                    rawCaptureName: "editor.syntax.swift.comment.doc"
                ),
            ]
        )
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await editorView.waitForPendingHighlightForTesting()

        let renderedSyntaxFont = try #require(iOSEditorFont(editorView, at: 0))
        let permanentSyntaxFont = try #require(iOSEditorPermanentFont(editorView, at: 0))
        let permanentPlainFont = try #require(iOSEditorPermanentFont(editorView, at: 8))
        let renderedSyntaxForeground = try #require(iOSEditorForegroundColor(editorView, at: 0))
        let permanentSyntaxForeground = try #require(iOSEditorPermanentForegroundColor(editorView, at: 0))
        let permanentPlainForeground = try #require(iOSEditorPermanentForegroundColor(editorView, at: 8))

        #expect(!syntaxEditorUITestFontsEqual(renderedSyntaxFont, permanentSyntaxFont))
        #expect(syntaxEditorUITestFontsEqual(permanentSyntaxFont, permanentPlainFont))
        #expect(!syntaxEditorUITestColorsEqual(renderedSyntaxForeground, permanentSyntaxForeground))
        #expect(syntaxEditorUITestColorsEqual(permanentSyntaxForeground, permanentPlainForeground))
    }

    @Test("SyntaxEditorView applies iOS font size delta to built-in theme fonts")
    @MainActor
    func syntaxEditorViewIOSAppliesFontSizeDeltaToBuiltInThemeFonts() async throws {
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

        let highlightedFont = try #require(iOSEditorFont(editorView, at: 0))
        let plainFont = try #require(iOSEditorFont(editorView, at: 4))
        #expect(abs(highlightedFont.pointSize - plainFont.pointSize) < 0.01)
        #expect(abs(plainFont.pointSize - 33) < 0.01)
    }

    @Test("SyntaxEditorView clamps iOS font size delta")
    @MainActor
    func syntaxEditorViewIOSClampsFontSizeDelta() async throws {
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
        let maximumHighlightedFont = try #require(iOSEditorFont(editorView, at: 0))
        let maximumPlainFont = try #require(iOSEditorFont(editorView, at: 4))
        #expect(abs(maximumHighlightedFont.pointSize - 64) < 0.01)
        #expect(abs(maximumPlainFont.pointSize - 64) < 0.01)

        model.model.fontSizeDelta = -100
        editorView.synchronizeDocumentForTesting()

        let minimumHighlightedFont = try #require(iOSEditorFont(editorView, at: 0))
        let minimumPlainFont = try #require(iOSEditorFont(editorView, at: 4))
        #expect(abs(minimumHighlightedFont.pointSize - 4) < 0.01)
        #expect(abs(minimumPlainFont.pointSize - 4) < 0.01)
    }

    @Test("SyntaxEditorView keeps iOS font size commands aligned with rendered bounds")
    @MainActor
    func syntaxEditorViewIOSKeepsFontSizeCommandsAlignedWithRenderedBounds() throws {
        let model = SyntaxEditorTestContext(
            text: "let value = 1",
            language: SyntaxLanguage.swift,
            theme: .presentationLarge
        )
        let editorView = SyntaxEditorView(testContext: model)

        for _ in 0..<100 {
            model.model.decreaseFontSize()
        }
        editorView.synchronizeDocumentForTesting()

        #expect(model.model.fontSizeDelta == -26)
        let minimumFont = try #require(iOSEditorFont(editorView, at: 0))
        #expect(abs(minimumFont.pointSize - 4) < 0.01)

        model.model.fontSizeDelta = -100
        model.model.increaseFontSize()
        editorView.synchronizeDocumentForTesting()

        #expect(model.model.fontSizeDelta == -25)
        let increasedFont = try #require(iOSEditorFont(editorView, at: 0))
        #expect(abs(increasedFont.pointSize - 5) < 0.01)

        for _ in 0..<100 {
            model.model.increaseFontSize()
        }
        editorView.synchronizeDocumentForTesting()

        #expect(model.model.fontSizeDelta == 34)
        let maximumFont = try #require(iOSEditorFont(editorView, at: 0))
        #expect(abs(maximumFont.pointSize - 64) < 0.01)
    }

    @Test("SyntaxEditorView applies iOS base attributes before delayed highlight")
    @MainActor
    func syntaxEditorViewIOSAppliesBaseAttributesBeforeDelayedHighlight() async throws {
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
            lineWrappingEnabled: true,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        await resetGate.waitUntilSuspended()
        #expect(syntaxEditorUITestFontsEqual(iOSEditorFont(editorView, at: 0), editorView.font))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.baseForeground))
        #expect(iOSEditorLineBreakMode(editorView) == .byCharWrapping)

        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(iOSEditorLineBreakMode(editorView) == .byCharWrapping)
    }

    @Test("SyntaxEditorView applies iOS fast pass highlight before final phase")
    @MainActor
    func syntaxEditorViewIOSAppliesFastPassHighlightBeforeFinalPhase() async {
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
        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 4), theme.baseForeground))
        #expect(await highlighter.callCount() == 1)

        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))

        let updatedTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x112233),
            string: syntaxEditorUITestColor(hex: 0x556677),
            keyword: syntaxEditorUITestColor(hex: 0x334455)
        )
        model.model.theme = updatedTheme
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(await highlighter.callCount() == 1)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), updatedTheme.string))
    }

    @Test("SyntaxEditorView applies iOS incremental fast pass before any complete highlight")
    @MainActor
    func syntaxEditorViewIOSAppliesIncrementalFastPassBeforeAnyCompleteHighlight() async {
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
        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))

        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        editorView.insertText("x")

        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))
        #expect(editorView.text == "\(source)x")

        await completeGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView keeps iOS complete incremental materialization inside refresh range")
    @MainActor
    func syntaxEditorViewIOSKeepsCompleteIncrementalMaterializationInsideRefreshRange() async {
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
        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        await completeGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))

        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        let updateSuspensionCount = await completeGate.currentSuspensionCount()
        editorView.insertText("x")
        await completeGate.waitUntilSuspended(after: updateSuspensionCount)

        await completeGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.text == "\(source)x")
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(
            syntaxEditorUITestColorsEqual(
                iOSEditorForegroundColor(editorView, at: source.utf16.count),
                theme.keyword
            )
        )
    }

    @Test("SyntaxEditorView applies iOS incremental fast pass after empty complete highlight")
    @MainActor
    func syntaxEditorViewIOSAppliesIncrementalFastPassAfterEmptyCompleteHighlight() async {
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

        editorView.selectedRange = NSRange(location: 0, length: 0)
        editorView.insertText("l")

        #expect(await editorView.waitForAppliedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(editorView.text == "l")

        await completeGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
    }

    @Test("SyntaxEditorView preserves iOS semantic highlight during incremental fast pass")
    @MainActor
    func syntaxEditorViewIOSPreservesSemanticHighlightDuringIncrementalFastPass() async {
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
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))

        editorView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        editorView.insertText("x")

        let skippedFastPass = await editorView.waitForSkippedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass)
        #expect(skippedFastPass)
        #expect(editorView.text == "\(source)x")
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))

        await completeGate.resumeAll()
        if skippedFastPass {
            await editorView.waitForPendingHighlightForTesting()
            #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))
        }
    }

    @Test("SyntaxEditorView preserves iOS semantic highlight across rapid incremental fast passes")
    @MainActor
    func syntaxEditorViewIOSPreservesSemanticHighlightAcrossRapidIncrementalFastPasses() async {
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
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))

        let firstSuspensionCount = await completeGate.currentSuspensionCount()
        editorView.selectedRange = NSRange(location: 0, length: 0)
        editorView.insertText("x")

        await completeGate.waitUntilSuspended(after: firstSuspensionCount)
        #expect(await editorView.waitForSkippedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(editorView.text == "x\(source)")
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 1), theme.string))

        let secondSuspensionCount = await completeGate.currentSuspensionCount()
        editorView.selectedRange = NSRange(location: editorView.text.utf16.count, length: 0)
        editorView.insertText("y")

        await completeGate.waitUntilSuspended(after: secondSuspensionCount)
        #expect(await editorView.waitForSkippedHighlightPhaseForTesting(SyntaxEditorHighlighting.Result.Phase.syntacticFastPass))
        #expect(editorView.text == "x\(source)y")
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 1), theme.string))

        await completeGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))
    }

    @Test("SyntaxEditorView applies iOS base attributes to inserted text before delayed update highlight")
    @MainActor
    func syntaxEditorViewIOSAppliesBaseAttributesToInsertedTextBeforeDelayedUpdateHighlight() async {
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
        await editorView.waitForPendingHighlightForTesting()

        editorView.selectedRange = NSRange(location: 0, length: 0)
        let previousSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.insertText(insertedPrefix)

        await updateGate.waitUntilSuspended(after: previousSuspensionCount)
        #expect(editorView.text == insertedPrefix + source)
        #expect(syntaxEditorUITestFontsEqual(iOSEditorFont(editorView, at: 0), editorView.font))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.baseForeground))

        await updateGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
    }

    @Test("SyntaxEditorView keeps iOS command transforms while attribute highlight is applying")
    @MainActor
    func syntaxEditorViewIOSKeepsCommandTransformsWhileAttributeHighlightIsApplying() async {
        let model = SyntaxEditorTestContext(text: "", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model, highlighter: SyntaxEditorUITestHighlighter())
        await editorView.waitForPendingHighlightForTesting()

        editorView.selectedRange = NSRange(location: 0, length: 0)
        editorView.setApplyingHighlightForTesting(true)
        editorView.insertText("\"")
        editorView.setApplyingHighlightForTesting(false)
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.text == "\"\"")
        #expect(model.model.text == "\"\"")
        #expect(editorView.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("SyntaxEditorView restores iOS base font when syntax font tokens are removed")
    @MainActor
    func syntaxEditorViewIOSRestoresBaseFontWhenSyntaxFontTokensAreRemoved() async throws {
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

        await editorView.waitForPendingHighlightForTesting()
        let baseFont = try #require(iOSEditorFont(editorView, at: 4))
        let highlightedFont = try #require(iOSEditorFont(editorView, at: 0))
        #expect(!syntaxEditorUITestFontsEqual(highlightedFont, baseFont))

        editorView.selectedRange = NSRange(location: 0, length: 3)
        editorView.insertText("var")
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.text == "var value = 1")
        #expect(syntaxEditorUITestFontsEqual(iOSEditorFont(editorView, at: 0), baseFont))
    }

    @Test("SyntaxEditorView restores shifted iOS syntax font after prefix edits")
    @MainActor
    func syntaxEditorViewIOSRestoresShiftedSyntaxFontAfterPrefixEdits() async throws {
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

        await editorView.waitForPendingHighlightForTesting()
        let baseFont = try #require(iOSEditorFont(editorView, at: 4))
        let highlightedFont = try #require(iOSEditorFont(editorView, at: 0))
        #expect(!syntaxEditorUITestFontsEqual(highlightedFont, baseFont))

        editorView.selectedRange = NSRange(location: 0, length: 0)
        editorView.insertText(insertedPrefix)
        await editorView.waitForPendingHighlightForTesting()

        #expect(editorView.text == insertedPrefix + source)
        #expect(syntaxEditorUITestFontsEqual(iOSEditorFont(editorView, at: insertedPrefix.utf16.count), baseFont))
    }

    @Test("SyntaxEditorView applies dense iOS highlight tokens across the document")
    @MainActor
    func syntaxEditorViewIOSAppliesDenseHighlightTokensAcrossDocument() async {
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
                iOSEditorForegroundColor(editorView, at: 0),
                syntaxEditorDenseHighlightColor(in: theme, at: 0)
            )
        )
        #expect(
            syntaxEditorUITestColorsEqual(
                iOSEditorForegroundColor(editorView, at: middleLocation),
                syntaxEditorDenseHighlightColor(in: theme, at: middleLocation)
            )
        )
        #expect(
            syntaxEditorUITestColorsEqual(
                iOSEditorForegroundColor(editorView, at: lastLocation),
                syntaxEditorDenseHighlightColor(in: theme, at: lastLocation)
            )
        )
        #expect(iOSEditorFont(editorView, at: middleLocation) != nil)
    }

    @Test("SyntaxEditorView preserves iOS paragraph style while reapplying cached highlight")
    @MainActor
    func syntaxEditorViewIOSCachedHighlightPreservesParagraphStyle() async {
        let source = "let value = 1"
        let initialTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x654321)
        )
        let updatedTheme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x112233),
            keyword: syntaxEditorUITestColor(hex: 0x332211)
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

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = iOSEditorLineBreakMode(editorView) ?? .byClipping
        paragraphStyle.paragraphSpacing = 11
        editorView.textStorage.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: source.utf16.count)
        )

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), initialTheme.keyword))
        #expect(iOSEditorParagraphSpacing(editorView) == 11)

        model.model.theme = updatedTheme
        editorView.synchronizeDocumentForTesting()
        await editorView.waitForPendingHighlightForTesting()

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), updatedTheme.keyword))
        #expect(iOSEditorParagraphSpacing(editorView) == 11)
    }

    @Test("SyntaxEditorView refreshes iOS TextKit line fragments after async syntax highlight")
    @MainActor
    func syntaxEditorViewIOSRefreshesLineFragmentsAfterAsyncHighlight() async {
        let source = String(
            repeating: "let value = \"text\"\n",
            count: 100
        )
        let theme = syntaxEditorUITestTheme(
            baseForeground: syntaxEditorUITestColor(hex: 0x123456),
            keyword: syntaxEditorUITestColor(hex: 0x345678)
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
            lineWrappingEnabled: false,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)

        layoutIOSEditorView(editorView, width: 393, height: 658)
        await resetGate.waitUntilSuspended()
        #expect(syntaxEditorUITestColorsEqual(iOSEditorLineFragmentForegroundColor(editorView, at: 0), theme.baseForeground))

        await resetGate.resumeOne()
        await editorView.waitForPendingHighlightForTesting()
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorLineFragmentForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView applies latest iOS highlight after model replacement")
    @MainActor
    func syntaxEditorViewIOSAppliesLatestHighlightAfterModelReplacement() async {
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
        layoutIOSEditorView(editorView, width: 393, height: 658)
        await resetGate.waitUntilSuspended()
        let previousSuspensionCount = await resetGate.currentSuspensionCount()

        editorView.update(model: replacementModel)
        await resetGate.waitUntilSuspended(after: previousSuspensionCount)
        await resetGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.model === replacementModel)
        #expect(editorView.text == replacementSource)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.string))
        #expect(syntaxEditorUITestColorsEqual(iOSEditorLineFragmentForegroundColor(editorView, at: 0), theme.string))
    }

    @Test("SyntaxEditorView renders iOS pasted text before async highlight completes")
    @MainActor
    func syntaxEditorViewIOSRendersPastedTextBeforeAsyncHighlightCompletes() async {
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
        layoutIOSEditorView(editorView, width: 393, height: 658)
        await editorView.waitForPendingHighlightForTesting()
        let initialContentHeight = editorView.contentSize.height

        editorView.selectedRange = NSRange(location: 0, length: 0)
        editorView.insertPastedText(pastedText)
        await updateGate.waitUntilSuspended()
        layoutIOSEditorView(editorView, width: 393, height: 658)
        let pastedContentHeight = editorView.contentSize.height

        #expect(editorView.text == pastedText + source)
        #expect(model.model.text == pastedText + source)
        #expect(pastedContentHeight > initialContentHeight + 1_000)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorLineFragmentForegroundColor(editorView, at: 0), theme.baseForeground))

        let previousSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.selectedRange = NSRange(location: 0, length: pastedText.utf16.count)
        editorView.delete(nil)
        await updateGate.waitUntilSuspended(after: previousSuspensionCount)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.text == source)
        #expect(model.model.text == source)
        #expect(editorView.contentSize.height < pastedContentHeight - 1_000)

        await updateGate.resumeAll()
        await editorView.waitForPendingHighlightForTesting()
    }

    @Test("SyntaxEditorView fully applies iOS highlight when skipped revisions precede an incremental result")
    @MainActor
    func syntaxEditorViewIOSFullyAppliesHighlightAfterSkippedIncrementalRevisions() async {
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
            lineWrappingEnabled: false,
            theme: theme
        )
        let editorView = SyntaxEditorView(testContext: model, highlighter: highlighter)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        await resetGate.waitUntilSuspended()

        let firstSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.insertPastedText(firstPaste)
        await updateGate.waitUntilSuspended(after: firstSuspensionCount)
        let secondSuspensionCount = await updateGate.currentSuspensionCount()
        editorView.insertPastedText(secondPaste)
        await updateGate.waitUntilSuspended(after: secondSuspensionCount)

        await resetGate.resumeAll()
        await updateGate.resumeAll()
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
        let model = SyntaxEditorTestContext(text: longSyntaxEditorLine, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        guard let delivery = editorView.modelConfigurationDeliveryForTesting else {
            Issue.record("Expected SyntaxEditorView to expose its production configuration delivery")
            return
        }
        let renderedState = await delivery.values {
            SyntaxEditorRenderedEditorState(
                isEditable: editorView.isEditable,
                wrapsLines: editorView.textContainer.widthTracksTextView
            )
        }

        model.model.isEditable = false
        model.model.lineWrappingEnabled = true

        #expect(
            await renderedState.waitUntilValue(
                SyntaxEditorRenderedEditorState(isEditable: false, wrapsLines: true)
            )
        )
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(editorView.contentSize.height > editorView.bounds.height + 1)
        #expect(iOSEditorLineBreakMode(editorView) == .byCharWrapping)

        model.model.lineWrappingEnabled = false

        #expect(
            await renderedState.waitUntilValue(
                SyntaxEditorRenderedEditorState(isEditable: false, wrapsLines: false)
            )
        )
        layoutIOSEditorView(editorView)
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)
        #expect(editorView.textContainer.size.width > editorView.bounds.width)
        #expect(iOSEditorLineBreakMode(editorView) == .byClipping)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        model.model.lineWrappingEnabled = true

        let finalRenderedState = await delivery.values {
            SyntaxEditorRenderedEditorState(
                isEditable: editorView.isEditable,
                wrapsLines: editorView.textContainer.widthTracksTextView
            )
        }
        #expect(
            await finalRenderedState.waitUntilValue(
                SyntaxEditorRenderedEditorState(isEditable: false, wrapsLines: true)
            )
        )
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
        layoutIOSEditorView(editorView)
        await editorView.waitForPendingHighlightForTesting()

        editorView.textStorage.addAttribute(
            .foregroundColor,
            value: theme.keyword,
            range: NSRange(location: 0, length: 3)
        )
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.model.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))

        model.model.isEditable = false

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.isEditable == false)
        #expect(syntaxEditorUITestColorsEqual(iOSEditorForegroundColor(editorView, at: 0), theme.keyword))
    }

    @Test("SyntaxEditorView enables horizontal scrolling for initial long iOS line")
    @MainActor
    func syntaxEditorViewIOSInitialLongLineScrollsHorizontally() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorLine,
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
            text: offscreenWideSyntaxEditorText,
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
            text: offscreenWideUnicodeSyntaxEditorText,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)

        layoutIOSEditorView(editorView, width: 160, height: 120)
        #expect(editorView.contentSize.width > editorView.bounds.width + 1)

        let measuredLineWidth = (offscreenWideUnicodeSyntaxEditorLine as NSString).size(
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

    @Test("SyntaxEditorView keeps text layout covering horizontal scroll")
    @MainActor
    func syntaxEditorViewTextLayoutCoversHorizontalScrollViewport() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.contentSize.width > editorView.bounds.width + 1)
        #expect(editorView.textLayoutManager != nil)

        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let visibleRightEdge = editorView.contentOffset.x + editorView.bounds.width
        guard let renderedContentFrame = iOSEditorRenderedContentFrame(editorView) else {
            Issue.record("SyntaxEditorView does not expose a rendered content frame")
            return
        }

        #expect(renderedContentFrame.width >= editorView.contentSize.width - 1)
        #expect(renderedContentFrame.maxX >= visibleRightEdge - 1)
        #expect(
            editorTextLayoutUsageBoundsCoverVisibleHorizontalViewport(editorView),
            Comment(rawValue: editorTextLayoutDiagnostics(editorView))
        )
    }

    @Test("SyntaxEditorView keeps text layout covering horizontal scroll after wrapping toggle")
    @MainActor
    func syntaxEditorViewTextLayoutCoversHorizontalScrollAfterWrappingToggle() async {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 504, height: 1104)

        #expect(editorView.textContainer.widthTracksTextView)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(iOSEditorLineBreakMode(editorView) == .byCharWrapping)

        model.model.lineWrappingEnabled = false

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
                editorTextLayoutUsageBoundsCoverVisibleHorizontalViewport(editorView),
                Comment(rawValue: editorTextLayoutDiagnostics(editorView))
            )
        }
    }

    @Test("SyntaxEditorView keeps long iOS lines unwrapped while horizontally scrollable")
    @MainActor
    func syntaxEditorViewIOSNoWrapKeepsLongLinesUnwrapped() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.contentSize.width > editorView.bounds.width + 1)
        #expect(iOSEditorTextUsageHeight(editorView) <= 120)

        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.contentOffset.x > 0)
        #expect(iOSEditorTextUsageHeight(editorView) <= 120)
        #expect(editorView.textLayoutManager != nil)
        #expect(
            editorTextLayoutUsageBoundsCoverVisibleHorizontalViewport(editorView),
            Comment(rawValue: editorTextLayoutDiagnostics(editorView))
        )
    }

    @Test("SyntaxEditorView does not jump to the iOS line end when a visible long range is selected")
    @MainActor
    func syntaxEditorViewIOSVisibleLongRangeSelectionDoesNotJumpToLineEnd() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let stableOffsetX = iOSEditorStableHorizontalOffset(editorView)
        editorView.setContentOffset(CGPoint(x: stableOffsetX, y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let position = editorView.closestPosition(
            to: CGPoint(x: editorView.bounds.midX, y: iOSEditorLineMidY(editorView, lineIndex: 2))
        ) else {
            Issue.record("SyntaxEditorView could not resolve a visible iOS text-input point")
            return
        }
        let location = editorView.offset(from: editorView.beginningOfDocument, to: position)
        editorView.selectedRange = NSRange(location: location, length: 0)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
        #expect(editorView.textLayoutManager != nil)
        #expect(
            editorTextLayoutUsageBoundsCoverVisibleHorizontalViewport(editorView),
            Comment(rawValue: editorTextLayoutDiagnostics(editorView))
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
        let updateGate = ManualSyntaxHighlightGate()
        let highlighter = SyntaxEditorUITestHighlighter(updateGate: updateGate)
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

        var previousCaretX = editorView.caretRect(for: SyntaxEditorView.TextPosition(offset: insertionOffset)).midX
        for insertedSpaceCount in 1...12 {
            let previousSuspensionCount = await updateGate.currentSuspensionCount()
            editorView.insertText(" ")
            await updateGate.waitUntilSuspended(after: previousSuspensionCount)
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

        await updateGate.resumeAll()
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
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
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
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)
        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        guard let visiblePosition = editorView.closestPosition(
            to: CGPoint(x: 240, y: iOSEditorLineMidY(editorView, lineIndex: 0))
        ),
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
            text: longSyntaxEditorLine,
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
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
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
            text: longSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let visibleRect = CGRect(origin: editorView.contentOffset, size: editorView.bounds.size)
        #expect(abs(visibleRect.minX - editorView.contentOffset.x) <= 1)
        #expect(abs(visibleRect.minY - editorView.contentOffset.y) <= 1)
        #expect(abs(visibleRect.width - editorView.bounds.width) <= 1)
        #expect(abs(visibleRect.height - editorView.bounds.height) <= 1)

        let visibleMidPoint = CGPoint(
            x: editorView.bounds.midX,
            y: editorView.bounds.minY + iOSEditorLineMidY(editorView, lineIndex: 2)
        )
        guard let position = editorView.closestPosition(to: visibleMidPoint) else {
            Issue.record("SyntaxEditorView could not resolve a scrolled visible text-input point")
            return
        }

        let location = editorView.offset(from: editorView.beginningOfDocument, to: position)
        #expect(location > 0)
        #expect(location < longSyntaxEditorMultilineText.utf16.count)
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

        model.model.replaceText(longSyntaxEditorLine)

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.text == longSyntaxEditorLine)
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

        editorView.text = longSyntaxEditorLine

        #expect(model.model.text == longSyntaxEditorLine)
        layoutIOSEditorView(editorView)
        #expect(iOSEditorHasHorizontalOverflow(editorView))
    }

    @Test("SyntaxEditorView keeps iOS scroll position while editing")
    @MainActor
    func syntaxEditorViewIOSKeepsScrollPositionWhileEditing() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        let insertionLocation = visibleMidSyntaxEditorLocation
        #expect(insertionLocation > 0)
        #expect(insertionLocation < longSyntaxEditorLine.utf16.count)

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
                index == 1_500 ? longSyntaxEditorLine : "let value\(index) = \(index)"
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
        #expect(model.model.text.contains("let value42x = 42"))
    }

    @Test("SyntaxEditorView does not rebuild iOS line metrics during resize")
    @MainActor
    func syntaxEditorViewIOSResizeDoesNotRebuildLineMetrics() {
        let source = (0..<2_000)
            .map { index in
                index == 1_500 ? longSyntaxEditorLine : "let value\(index) = \(index)"
            }
            .joined(separator: "\n")
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 720, height: 300)

        let rebuildCount = editorView.lineMetricsFullRebuildCountForTesting
        layoutIOSEditorView(editorView, width: 360, height: 300)
        layoutIOSEditorView(editorView, width: 640, height: 300)

        #expect(editorView.lineMetricsFullRebuildCountForTesting == rebuildCount)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
    }

    @Test("SyntaxEditorView keeps iOS scroll position while moving cursor")
    @MainActor
    func syntaxEditorViewIOSKeepsScrollPositionWhileMovingCursor() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let targetLocation = visibleMidSyntaxEditorLocation
        #expect(targetLocation > 0)
        #expect(targetLocation < longSyntaxEditorLine.utf16.count)

        editorView.selectedRange = NSRange(location: targetLocation, length: 0)
        layoutIOSEditorView(editorView)

        #expect(abs(editorView.contentOffset.x - stableOffsetX) <= 1)
    }

    @Test("SyntaxEditorView keeps native iOS bounce enabled")
    @MainActor
    func syntaxEditorViewIOSKeepsNativeBounceEnabled() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorLine,
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
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let targetLocation = max(0, longSyntaxEditorLine.utf16.count - 1)
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
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        editorView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 44)
        layoutIOSEditorView(editorView)

        let targetLocation = max(0, longSyntaxEditorLine.utf16.count - 1)
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
            text: longSyntaxEditorLine,
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
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let targetLocation = visibleMidSyntaxEditorLocation
        #expect(targetLocation > 0)
        #expect(targetLocation < longSyntaxEditorLine.utf16.count)
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
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        editorView.setContentOffset(CGPoint(x: 80, y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let targetLocation = visibleMidSyntaxEditorLocation
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
            text: longSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        #expect(editorView.contentSize.width > editorView.bounds.width + 1)

        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
        let stableOffsetX = editorView.contentOffset.x
        #expect(stableOffsetX > 0)

        let tapPoint = CGPoint(x: stableOffsetX + 200, y: iOSEditorLineMidY(editorView, lineIndex: 2))
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
            editorTextLayoutUsageBoundsCoverVisibleHorizontalViewport(editorView),
            Comment(rawValue: editorTextLayoutDiagnostics(editorView))
        )
    }

    @Test("SyntaxEditorView supports ranged iOS selection after horizontal scroll")
    @MainActor
    func syntaxEditorViewIOSSupportsRangedSelectionAfterHorizontalScroll() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let stableOffsetX = editorView.contentOffset.x
        let visibleRect = editorView.bounds
        let longLineMidY = iOSEditorLineMidY(editorView, lineIndex: 2)
        let startPoint = CGPoint(x: visibleRect.minX + 120, y: visibleRect.minY + longLineMidY)
        let endPoint = CGPoint(x: visibleRect.minX + 280, y: visibleRect.minY + longLineMidY)

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
            text: longSyntaxEditorMultilineText,
            language: SyntaxLanguage.javascript,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        editorView.setContentOffset(CGPoint(x: iOSEditorStableHorizontalOffset(editorView), y: 0), animated: false)
        layoutIOSEditorView(editorView, width: 393, height: 658)

        let longLineMidY = iOSEditorLineMidY(editorView, lineIndex: 2)
        let viewportStartPoint = CGPoint(x: 120, y: longLineMidY)
        let viewportEndPoint = CGPoint(x: 280, y: longLineMidY)
        let extendedViewportEndPoint = CGPoint(x: 340, y: longLineMidY)

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
        let source = String(repeating: "let wrappingHeightMustTrackVisualLines = true; ", count: 48)
        let model = SyntaxEditorTestContext(
            text: source,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: true
        )
        let editorView = SyntaxEditorView(testContext: model)

        layoutIOSEditorView(editorView, width: 240, height: 140)
        let wrappedHeight = editorView.contentSize.height
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(wrappedHeight > editorView.bounds.height + 400)

        model.model.lineWrappingEnabled = false

        editorView.synchronizeDocumentForTesting()
        #expect(!editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView, width: 240, height: 140)
        let unwrappedHeight = editorView.contentSize.height
        #expect(unwrappedHeight < wrappedHeight - 400)
        let restoredHorizontalOverflow = iOSEditorHasHorizontalOverflow(editorView)
        if !restoredHorizontalOverflow {
            Issue.record(Comment(rawValue: iOSEditorHorizontalOverflowDiagnostics(editorView)))
        }
        #expect(restoredHorizontalOverflow)

        editorView.setContentOffset(CGPoint(x: 24, y: 0), animated: false)
        #expect(editorView.contentOffset.x > 0)

        model.model.lineWrappingEnabled = true

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textContainer.widthTracksTextView)
        layoutIOSEditorView(editorView, width: 240, height: 140)
        #expect(editorView.contentSize.width <= editorView.bounds.width + 1)
        #expect(editorView.contentSize.height > unwrappedHeight + 400)
    }

    @Test("SyntaxEditorMenu builds UIKit Editor menu commands")
    @MainActor
    func syntaxEditorMenuBuildsUIKitEditorMenuCommands() {
        let menu = SyntaxEditorMenu.makeMenu()
        #expect(menu.title == "Editor")
        #expect(menu.identifier == SyntaxEditorMenu.editorMenuIdentifier)

        let structureMenu = syntaxEditorChildMenu(menu, title: "Structure")
        #expect(structureMenu != nil)
        #expect(structureMenu?.children.compactMap { $0 as? UIMenu }.map(\.options) == [
            [.displayInline],
            [.displayInline],
        ])
        let shiftRight = structureMenu.flatMap { syntaxEditorChildKeyCommand($0, title: "Shift Right") }
        #expect(shiftRight?.input == "]")
        #expect(shiftRight?.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == [.command])
        #expect(shiftRight?.action == NSSelectorFromString("syntaxEditorShiftRight:"))

        let shiftLeft = structureMenu.flatMap { syntaxEditorChildKeyCommand($0, title: "Shift Left") }
        #expect(shiftLeft?.input == "[")
        #expect(shiftLeft?.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == [.command])
        #expect(shiftLeft?.action == NSSelectorFromString("syntaxEditorShiftLeft:"))

        let commentSelection = structureMenu.flatMap { syntaxEditorChildKeyCommand($0, title: "Comment Selection") }
        #expect(commentSelection?.input == "/")
        #expect(commentSelection?.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == [.command])
        #expect(commentSelection?.action == NSSelectorFromString("syntaxEditorCommentSelection:"))

        let fontSizeMenu = syntaxEditorChildMenu(menu, title: "Font Size")
        #expect(fontSizeMenu != nil)
        #expect(fontSizeMenu?.children.compactMap { $0 as? UIMenu }.map(\.options) == [
            [.displayInline],
            [.displayInline],
        ])
        let increase = fontSizeMenu.flatMap { syntaxEditorChildKeyCommand($0, title: "Increase") }
        #expect(increase?.input == "+")
        #expect(increase?.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == [.command])
        #expect(increase?.action == NSSelectorFromString("syntaxEditorIncreaseFontSize:"))

        let decrease = fontSizeMenu.flatMap { syntaxEditorChildKeyCommand($0, title: "Decrease") }
        #expect(decrease?.input == "-")
        #expect(decrease?.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == [.command])
        #expect(decrease?.action == NSSelectorFromString("syntaxEditorDecreaseFontSize:"))

        let reset = fontSizeMenu.flatMap { syntaxEditorChildKeyCommand($0, title: "Reset") }
        #expect(reset?.input == "0")
        #expect(reset?.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == [.control, .command])
        #expect(reset?.action == NSSelectorFromString("syntaxEditorResetFontSize:"))

        let wrapLines = syntaxEditorChildKeyCommand(menu, title: "Wrap Lines")
        #expect(wrapLines?.input == "l")
        #expect(wrapLines?.modifierFlags.intersection(syntaxEditorKeyCommandModifierMask) == [.control, .shift, .command])
        #expect(wrapLines?.action == NSSelectorFromString("syntaxEditorToggleLineWrapping:"))
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
        #expect(hasSyntaxEditorKeyCommand(readOnlyCommands, input: "+", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(readOnlyCommands, input: "-", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(readOnlyCommands, input: "0", modifierFlags: [.control, .command]))

        let readOnlyLineWrappingActionTarget = editorView.target(
            forAction: NSSelectorFromString("syntaxEditorToggleLineWrapping:"),
            withSender: nil
        ) as AnyObject?
        #expect(readOnlyLineWrappingActionTarget === editorView)

        let readOnlyIncreaseFontSizeActionTarget = editorView.target(
            forAction: NSSelectorFromString("syntaxEditorIncreaseFontSize:"),
            withSender: nil
        ) as AnyObject?
        #expect(readOnlyIncreaseFontSizeActionTarget === editorView)

        let editorMenu = SyntaxEditorMenu.makeMenu()
        if let structureMenu = syntaxEditorChildMenu(editorMenu, title: "Structure"),
           let shiftRightCommand = syntaxEditorChildKeyCommand(structureMenu, title: "Shift Right") {
            editorView.validate(shiftRightCommand)
            #expect(shiftRightCommand.attributes.contains(.disabled))
        } else {
            Issue.record("Expected Structure > Shift Right command")
        }

        if let wrapLinesCommand = syntaxEditorChildKeyCommand(editorMenu, title: "Wrap Lines") {
            editorView.validate(wrapLinesCommand)
            #expect(!wrapLinesCommand.attributes.contains(.disabled))
            #expect(wrapLinesCommand.state == .off)

            model.model.lineWrappingEnabled = true
            editorView.validate(wrapLinesCommand)
            #expect(!wrapLinesCommand.attributes.contains(.disabled))
            #expect(wrapLinesCommand.state == .on)
        } else {
            Issue.record("Expected Wrap Lines command")
        }

        model.model.isEditable = true

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
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "+", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "-", modifierFlags: [.command]))
        #expect(hasSyntaxEditorKeyCommand(editableCommands, input: "0", modifierFlags: [.control, .command]))

        let indentActionTarget = editorView.target(
            forAction: NSSelectorFromString("syntaxEditorShiftRight:"),
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

    @Test("SyntaxEditorView applies iOS font size key commands")
    @MainActor
    func syntaxEditorViewIOSFontSizeKeyCommands() {
        let model = SyntaxEditorTestContext(text: "let answer = 42", language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)

        #expect(performSyntaxEditorSelector("syntaxEditorIncreaseFontSize:", on: editorView))
        #expect(model.model.fontSizeDelta == 1)

        #expect(performSyntaxEditorSelector("syntaxEditorDecreaseFontSize:", on: editorView))
        #expect(model.model.fontSizeDelta == 0)

        model.model.fontSizeDelta = 5
        #expect(performSyntaxEditorSelector("syntaxEditorResetFontSize:", on: editorView))
        #expect(model.model.fontSizeDelta == 0)
    }

    @Test("SyntaxEditorView applies iOS paste payload repeatedly")
    @MainActor
    func syntaxEditorViewIOSAppliesPastePayloadRepeatedly() {
        let model = SyntaxEditorTestContext(text: "let ")
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: model.model.text.utf16.count, length: 0)

        editorView.insertPastedText("42")
        editorView.insertPastedText("42")
        #expect(model.model.text == "let 4242")
    }

    @Test("SyntaxEditorView defers iOS large paste selection scroll until layout")
    @MainActor
    func syntaxEditorViewIOSDefersLargePasteSelectionScrollUntilLayout() {
        let model = SyntaxEditorTestContext(text: "let start = 0\n", lineWrappingEnabled: false)
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)
        let stableOffset = editorView.contentOffset
        editorView.selectedRange = NSRange(location: model.model.text.utf16.count, length: 0)
        let pastedText = String(repeating: "let value = 1\n", count: 500)

        editorView.insertPastedText(pastedText)
        #expect(abs(editorView.contentOffset.y - stableOffset.y) <= 1)

        layoutIOSEditorView(editorView)

        #expect(model.model.text == "let start = 0\n" + pastedText)
        #expect(editorView.contentOffset.y > stableOffset.y + 1)
    }

    @Test("SyntaxEditorView toggles iOS line wrapping key command")
    @MainActor
    func syntaxEditorViewIOSToggleLineWrappingKeyCommand() {
        let model = SyntaxEditorTestContext(
            text: longSyntaxEditorLine,
            language: SyntaxLanguage.swift,
            lineWrappingEnabled: false
        )
        let editorView = SyntaxEditorView(testContext: model)
        layoutIOSEditorView(editorView)

        #expect(performSyntaxEditorSelector("syntaxEditorToggleLineWrapping:", on: editorView))
        #expect(model.model.lineWrappingEnabled)
        editorView.synchronizeDocumentForTesting()
        #expect(editorView.textContainer.widthTracksTextView)

        #expect(performSyntaxEditorSelector("syntaxEditorToggleLineWrapping:", on: editorView))
        #expect(!model.model.lineWrappingEnabled)
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
        #expect(performSyntaxEditorSelector("syntaxEditorShiftRight:", on: editorView))
        #expect(performSyntaxEditorSelector("syntaxEditorShiftLeft:", on: editorView))
        #expect(performSyntaxEditorSelector("syntaxEditorCommentSelection:", on: editorView))
        #expect(performSyntaxEditorSelector("syntaxEditorToggleLineWrapping:", on: editorView))

        #expect(model.model.text == source)
        #expect(editorView.text == source)
        #expect(model.model.lineWrappingEnabled)
    }

    @Test("SyntaxEditorView inserts iOS tab spaces at the caret")
    @MainActor
    func syntaxEditorViewIOSInsertTabAtCaret() {
        let source = "abcde"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: 2, length: 0)

        #expect(performSyntaxEditorSelector("handleInsertTabCommand", on: editorView))

        #expect(model.model.text == "ab  cde")
        #expect(editorView.text == "ab  cde")
        #expect(editorView.selectedRange == NSRange(location: 4, length: 0))
    }

    @Test("SyntaxEditorView inserts raw iOS tab in plain text")
    @MainActor
    func syntaxEditorViewIOSInsertPlainTextTabAtCaret() {
        let source = "abcde"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.plainText)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: 2, length: 0)

        let commands = editorView.keyCommands
        #expect(hasSyntaxEditorKeyCommand(commands, input: "\t", modifierFlags: []))
        #expect(!hasSyntaxEditorKeyCommand(commands, input: "\t", modifierFlags: [.shift]))
        #expect(!hasSyntaxEditorKeyCommand(commands, input: "]", modifierFlags: [.command]))
        #expect(!hasSyntaxEditorKeyCommand(commands, input: "[", modifierFlags: [.command]))
        #expect(!hasSyntaxEditorKeyCommand(commands, input: "/", modifierFlags: [.command]))

        let insertTabActionTarget = editorView.target(
            forAction: NSSelectorFromString("handleInsertTabCommand"),
            withSender: nil
        ) as AnyObject?
        #expect(insertTabActionTarget === editorView)

        #expect(performSyntaxEditorSelector("handleInsertTabCommand", on: editorView))

        #expect(model.model.text == "ab\tcde")
        #expect(editorView.text == "ab\tcde")
        #expect(editorView.selectedRange == NSRange(location: 3, length: 0))
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

        #expect(model.model.text == editedSource)
        #expect(editorView.text == editedSource)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        #expect(editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))
        #expect(performSyntaxEditorSelector("handleUndoCommand", on: editorView))

        #expect(model.model.text == source)
        #expect(editorView.text == source)
        #expect(undoManager.canRedo)
        #expect(!editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))

        #expect(performSyntaxEditorSelector("handleRedoCommand", on: editorView))

        #expect(model.model.text == editedSource)
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

        #expect(performSyntaxEditorSelector("syntaxEditorShiftRight:", on: editorView))
        let indentedSource = "    \(source)"
        #expect(model.model.text == indentedSource)
        #expect(editorView.text == indentedSource)

        model.model.isEditable = false

        #expect(!editorView.canPerformAction(NSSelectorFromString("undo:"), withSender: nil))
        #expect(!editorView.canPerformAction(NSSelectorFromString("redo:"), withSender: nil))
        #expect(performSyntaxEditorSelector("handleUndoCommand", on: editorView))
        #expect(performSyntaxEditorSelector("handleRedoCommand", on: editorView))

        #expect(model.model.text == indentedSource)
        #expect(editorView.text == indentedSource)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        undoManager.undo()
        undoManager.redo()

        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)
        #expect(model.model.text == indentedSource)
        #expect(editorView.text == indentedSource)

        model.model.isEditable = true

        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.model.text == source)
        #expect(editorView.text == source)
    }

    @Test("SyntaxEditorView restores command selection through iOS undo and redo")
    @MainActor
    func syntaxEditorViewIOSCommandUndoRedoRestoresSelection() {
        let source = "let answer = 42"
        let model = SyntaxEditorTestContext(text: source, language: SyntaxLanguage.swift)
        let editorView = SyntaxEditorView(testContext: model)
        editorView.selectedRange = NSRange(location: 4, length: 0)

        #expect(performSyntaxEditorSelector("syntaxEditorShiftRight:", on: editorView))
        let indentedSource = "    \(source)"
        let indentedSelection = NSRange(location: 8, length: 0)
        #expect(model.model.text == indentedSource)
        #expect(editorView.text == indentedSource)
        #expect(editorView.selectedRange == indentedSelection)

        guard let undoManager = editorView.undoManager else {
            Issue.record("SyntaxEditorView has no undo manager")
            return
        }

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(model.model.text == source)
        #expect(editorView.text == source)
        #expect(editorView.selectedRange == NSRange(location: 4, length: 0))

        #expect(undoManager.canRedo)
        undoManager.redo()
        #expect(model.model.text == indentedSource)
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

        model.model.replaceText("\(source) ")

        editorView.synchronizeDocumentForTesting()
        #expect(editorView.text == model.model.text)
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
}
#endif
