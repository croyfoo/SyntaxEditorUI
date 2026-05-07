#if canImport(UIKit)
import Observation
import ObservationBridge
import SyntaxEditorCore
import UIKit

@MainActor
private final class SyntaxEditorReadOnlyGuardedUndoManager: UndoManager {
    var allowsMutation: () -> Bool = { true }
    var undoManagerProvider: () -> UndoManager? = { nil }

    private var targetUndoManager: UndoManager? {
        guard let undoManager = undoManagerProvider(),
              undoManager !== self
        else {
            return nil
        }

        return undoManager
    }

    override var canUndo: Bool {
        guard allowsMutation() else { return false }
        return (targetUndoManager?.canUndo ?? false) || super.canUndo
    }

    override var canRedo: Bool {
        guard allowsMutation() else { return false }
        return (targetUndoManager?.canRedo ?? false) || super.canRedo
    }

    override func undo() {
        guard allowsMutation() else { return }
        if let targetUndoManager, targetUndoManager.canUndo {
            targetUndoManager.undo()
        } else {
            super.undo()
        }
    }

    override func redo() {
        guard allowsMutation() else { return }
        if let targetUndoManager, targetUndoManager.canRedo {
            targetUndoManager.redo()
        } else {
            super.redo()
        }
    }

    override func undoNestedGroup() {
        guard allowsMutation() else { return }
        if let targetUndoManager, targetUndoManager.canUndo {
            targetUndoManager.undoNestedGroup()
        } else {
            super.undoNestedGroup()
        }
    }
}

@MainActor
public final class SyntaxEditorView: UITextView, UITextViewDelegate {
    public private(set) var model: SyntaxEditorModel

    private let guardedUndoManager = SyntaxEditorReadOnlyGuardedUndoManager()
    private let defaultTextContainerSize = NSTextContainer().size
    private static let estimatedTabColumnWidth = 4
    private static let defaultEditorFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    private let highlighter: any SyntaxHighlighting
    private let commandEngine = EditorCommandEngine()
    private var highlightTask: Task<Void, Never>?
    private var lastHighlightTokens: [SyntaxHighlightToken] = []
    private var lastHighlightSource: String?
    private var lastHighlightLanguage: SyntaxLanguage?
    private var isApplyingModel = false
    private var isApplyingHighlight = false
    private var lastAppliedLanguageIdentifier: String?
    private var pendingEditStartUTF16: Int?
    private var pendingHighlightMutation: SyntaxHighlightMutation?
    private var matchedBracketRanges: [NSRange] = []
    private var isApplyingUndoRedo = false
    private var isApplyingCommandSelection = false
    private var ignoredProgrammaticSelectionRange: NSRange?
    private var isSynchronizingContentSize = false
    private var lastAppliedLineWrappingEnabled: Bool?
    private var lastAppliedColorTheme: SyntaxEditorColorTheme?
    private var keyboardAccessoryModel: SyntaxEditorKeyboardAccessoryModel?
    private var keyboardAccessoryView: UIView?
    private let modelObservations = ObservationScope()
    private var modelRenderingWaiters: [ModelRenderingWaiter] = []

    private struct ModelRenderingWaiter {
        let condition: @MainActor () -> Bool
        let continuation: CheckedContinuation<Bool, Never>
    }

    public convenience init(model: SyntaxEditorModel) {
        self.init(model: model, highlighter: SyntaxHighlighterEngine())
    }

    package init(model: SyntaxEditorModel, highlighter: any SyntaxHighlighting) {
        self.model = model
        self.highlighter = highlighter

        super.init(frame: .zero, textContainer: nil)

        guardedUndoManager.allowsMutation = { [weak self] in
            self?.model.isEditable ?? true
        }
        guardedUndoManager.undoManagerProvider = { [weak self] in
            self?.nativeUndoManager
        }

        configureTextView()
        configureUndoObservation()
        configureTraitChangeObservation()
        applyObservedEditorState(
            language: model.language,
            isEditable: model.isEditable,
            lineWrappingEnabled: model.lineWrappingEnabled,
            colorTheme: model.colorTheme,
            forceLanguageRefresh: true,
            schedulesHighlight: false
        )
        applyObservedText(
            model.text,
            forceTextUpdate: true
        )
        startModelObservation()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        highlightTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public override var undoManager: UndoManager? {
        guardedUndoManager
    }

    private var nativeUndoManager: UndoManager? {
        super.undoManager
    }

    internal func waitForModelRenderingForTesting(
        until condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        guard !condition() else { return true }

        return await withCheckedContinuation { continuation in
            modelRenderingWaiters.append(
                ModelRenderingWaiter(
                    condition: condition,
                    continuation: continuation
                )
            )
        }
    }

    internal func waitForPendingHighlightForTesting() async {
        await highlightTask?.value
    }

    public override var canBecomeFirstResponder: Bool {
        isEditable || isSelectable
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        refreshKeyboardAccessoryState()
        return didBecomeFirstResponder
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshKeyboardAccessoryState()
    }

    public override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + (editorKeyCommands() ?? [])
    }

    public override var bounds: CGRect {
        didSet {
            guard bounds.size != oldValue.size else { return }
            updateTextContainerForCurrentWrappingMode()
            updateScrollableContentSizeForCurrentWrappingMode()
        }
    }

    public override var frame: CGRect {
        didSet {
            guard frame.size != oldValue.size else { return }
            updateTextContainerForCurrentWrappingMode()
            updateScrollableContentSizeForCurrentWrappingMode()
        }
    }

    public override var contentSize: CGSize {
        didSet {
            guard !isSynchronizingContentSize else { return }
            updateScrollableContentSizeForCurrentWrappingMode()
        }
    }

    public override var text: String! {
        get {
            super.text
        }
        set {
            let nextText = newValue ?? ""
            let currentText = super.text ?? ""
            let textNeedsUpdate = currentText != nextText
            let modelNeedsUpdate = model.text != nextText
            guard textNeedsUpdate || modelNeedsUpdate else { return }

            if textNeedsUpdate {
                commandEngine.invalidateTransientState()
                let previousSelection = selectedRange
                isApplyingModel = true
                super.text = nextText
                selectedRange = clampedTextRange(previousSelection, in: nextText)
                typingAttributes = baseAttributes()
                applyParagraphStyleToExistingText()
                updateTextContainerForCurrentWrappingMode()
                updateScrollableContentSizeForCurrentWrappingMode()
                isApplyingModel = false

                scheduleHighlight(
                    source: nextText,
                    language: model.language,
                    refreshStartUTF16: 0
                )
            }

            if modelNeedsUpdate {
                model.text = nextText
            }

            refreshKeyboardAccessoryState()
            if textNeedsUpdate {
                setNeedsLayout()
            }
        }
    }

    public override func insertText(_ text: String) {
        guard model.isEditable else {
            pendingEditStartUTF16 = nil
            return
        }

        let range = selectedRange
        pendingEditStartUTF16 = range.location
        pendingHighlightMutation = SyntaxHighlightMutation(
            location: range.location,
            length: range.length,
            replacement: text
        )

        if !isApplyingModel,
           !isApplyingHighlight,
           let result = commandEngine.transformInput(
               source: super.text ?? "",
               range: range,
               replacementText: text,
               language: model.language,
               deletionIntent: .unspecified
           ) {
            applyCommandResult(result)
            return
        }

        pendingHighlightMutation = nil
        super.insertText(text)
    }

    public override func deleteBackward() {
        guard model.isEditable else {
            pendingEditStartUTF16 = nil
            return
        }

        let currentSelection = selectedRange
        let deletionRange: NSRange
        let deletionIntent: EditorCommandEngine.DeletionIntent
        if currentSelection.length > 0 {
            deletionRange = currentSelection
            deletionIntent = .unspecified
        } else {
            guard currentSelection.location > 0 else { return }
            deletionRange = NSRange(location: currentSelection.location - 1, length: 1)
            deletionIntent = .backward
        }

        pendingEditStartUTF16 = deletionRange.location
        pendingHighlightMutation = SyntaxHighlightMutation(
            location: deletionRange.location,
            length: deletionRange.length,
            replacement: ""
        )

        if !isApplyingModel,
           !isApplyingHighlight,
           let result = commandEngine.transformInput(
               source: super.text ?? "",
               range: deletionRange,
               replacementText: "",
               language: model.language,
               deletionIntent: deletionIntent
           ) {
            applyCommandResult(result)
            return
        }

        pendingHighlightMutation = nil
        super.deleteBackward()
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if !model.isEditable,
           isUndoRedoAction(action) {
            return false
        }

        if isEditorCommandAction(action) {
            return model.isEditable
        }

        return super.canPerformAction(action, withSender: sender)
    }

    public override func scrollRangeToVisible(_ range: NSRange) {
        let clampedRange = clampedTextRange(range)
        guard !model.lineWrappingEnabled else {
            super.scrollRangeToVisible(clampedRange)
            return
        }

        guard let targetRect = contentRectForScrollRange(clampedRange) else {
            super.scrollRangeToVisible(clampedRange)
            return
        }

        let visibleRect = adjustedVisibleContentRect
        if targetRect.intersects(visibleRect.insetBy(dx: -textContainer.lineFragmentPadding, dy: -4)) {
            return
        }

        scrollContentRectToVisible(targetRect)
    }

    private func contentRectForScrollRange(_ range: NSRange) -> CGRect? {
        if range.length > 0,
           let start = position(from: beginningOfDocument, offset: range.location),
           let end = position(from: start, offset: range.length),
           let textRange = textRange(from: start, to: end) {
            let firstTextRect = firstRect(for: textRange)
            if firstTextRect.origin.x.isFinite,
               firstTextRect.origin.y.isFinite,
               firstTextRect.size.width.isFinite,
               firstTextRect.size.height.isFinite,
               !firstTextRect.isNull,
               !firstTextRect.isEmpty {
                return firstTextRect
            }
        }

        return contentCaretRectForTextLocation(range.location + range.length)
    }

    private func contentCaretRectForTextLocation(_ location: Int) -> CGRect? {
        guard let position = position(
            from: beginningOfDocument,
            offset: location
        ) else {
            return nil
        }

        var targetRect = caretRect(for: position)
        guard targetRect.origin.x.isFinite,
              targetRect.origin.y.isFinite,
              targetRect.size.width.isFinite,
              targetRect.size.height.isFinite else {
            return nil
        }

        if targetRect.width.isZero {
            targetRect = targetRect.insetBy(dx: -textContainer.lineFragmentPadding, dy: 0)
        }
        targetRect.size.width = max(targetRect.size.width, 2)
        return targetRect
    }

    private var adjustedVisibleContentRect: CGRect {
        let insets = adjustedContentInset
        return CGRect(
            x: contentOffset.x + insets.left,
            y: contentOffset.y + insets.top,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
    }

    private func scrollContentRectToVisible(_ rect: CGRect) {
        let insets = adjustedContentInset
        let maximumOffset = CGPoint(
            x: max(-insets.left, contentSize.width - bounds.width + insets.right),
            y: max(-insets.top, contentSize.height - bounds.height + insets.bottom)
        )
        var nextOffset = contentOffset
        let visibleRect = adjustedVisibleContentRect

        if rect.minX < visibleRect.minX {
            nextOffset.x = rect.minX - insets.left
        } else if rect.maxX > visibleRect.maxX {
            nextOffset.x = rect.maxX - visibleRect.width - insets.left
        }

        if rect.minY < visibleRect.minY {
            nextOffset.y = rect.minY - insets.top
        } else if rect.maxY > visibleRect.maxY {
            nextOffset.y = rect.maxY - visibleRect.height - insets.top
        }

        nextOffset.x = min(max(nextOffset.x, -insets.left), maximumOffset.x)
        nextOffset.y = min(max(nextOffset.y, -insets.top), maximumOffset.y)
        guard !nextOffset.x.isNearlyEqual(to: contentOffset.x)
                || !nextOffset.y.isNearlyEqual(to: contentOffset.y) else {
            return
        }

        setContentOffset(nextOffset, animated: false)
    }

    public func textViewDidChange(_ textView: UITextView) {
        guard textView === self else { return }
        guard !isApplyingModel, !isApplyingHighlight else {
            pendingEditStartUTF16 = nil
            pendingHighlightMutation = nil
            return
        }

        let previousText = model.text
        let nextText = super.text ?? ""
        let mutation = pendingHighlightMutation ??
            TextMutation.diff(from: previousText, to: nextText).map(SyntaxHighlightMutation.init)
        if model.text != nextText {
            model.text = nextText
            updateTextContainerForCurrentWrappingMode()
            updateScrollableContentSizeForCurrentWrappingMode()
        }

        let editStartUTF16 = pendingEditStartUTF16 ?? selectedRange.location
        pendingEditStartUTF16 = nil
        pendingHighlightMutation = nil
        let refreshStartUTF16 = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
            in: nextText,
            around: editStartUTF16
        )
        scheduleHighlight(
            previousSource: previousText,
            source: nextText,
            language: model.language,
            mutation: mutation,
            refreshStartUTF16: refreshStartUTF16
        )
        refreshKeyboardAccessoryState()
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard textView === self else { return }
        let currentSelection = selectedRange
        let preservesCommandState = isApplyingCommandSelection
            || ignoredProgrammaticSelectionRange == currentSelection

        if !preservesCommandState {
            ignoredProgrammaticSelectionRange = nil
            commandEngine.invalidateTransientState()
        }
        applyMatchingBracketHighlight()
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard textView === self else { return true }
        guard !isApplyingModel, !isApplyingHighlight else {
            return true
        }

        guard model.isEditable else {
            pendingEditStartUTF16 = nil
            pendingHighlightMutation = nil
            return false
        }

        pendingEditStartUTF16 = range.location
        pendingHighlightMutation = SyntaxHighlightMutation(
            location: range.location,
            length: range.length,
            replacement: text
        )

        let currentSelection = selectedRange
        let isBackwardDelete = text.isEmpty
            && range.length == 1
            && currentSelection.length == 0
            && currentSelection.location == range.location + range.length

        if let result = commandEngine.transformInput(
            source: super.text ?? "",
            range: range,
            replacementText: text,
            language: model.language,
            deletionIntent: isBackwardDelete ? .backward : .unspecified
        ) {
            applyCommandResult(result)
            return false
        }

        return true
    }

    private func configureTextView() {
        backgroundColor = .clear
        isScrollEnabled = true
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        delegate = self
        isEditable = model.isEditable
        isSelectable = true

        autocapitalizationType = .none
        autocorrectionType = .no
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no

        applyLineWrappingConfiguration(lineWrappingEnabled: model.lineWrappingEnabled)
        configureBaseTextViewAppearance()
        keyboardAccessoryView = makeInputAccessoryView()
        inputAccessoryView = keyboardAccessoryView
        refreshKeyboardAccessoryState()
    }

    private func configureUndoObservation() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleUndoManagerStateDidChange),
            name: .NSUndoManagerDidCloseUndoGroup,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleUndoManagerStateDidChange),
            name: .NSUndoManagerDidUndoChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleUndoManagerStateDidChange),
            name: .NSUndoManagerDidRedoChange,
            object: nil
        )
    }

    @objc
    private func handleUndoManagerStateDidChange(_ notification: Notification) {
        guard observesUndoManagerNotification(from: notification.object) else { return }
        refreshKeyboardAccessoryState()
    }

    private func observesUndoManagerNotification(from object: Any?) -> Bool {
        guard let undoManager = object as? UndoManager else { return false }
        return undoManager === guardedUndoManager || undoManager === nativeUndoManager
    }

    private func configureTraitChangeObservation() {
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) {
            (self: Self, previousTraitCollection: UITraitCollection) in
            guard previousTraitCollection.hasDifferentColorAppearance(comparedTo: self.traitCollection) else {
                return
            }
            self.refreshForColorAppearanceChange()
        }
    }

    private func refreshForColorAppearanceChange() {
        updateTypingAttributes()
        scheduleHighlight(
            source: super.text ?? "",
            language: model.language,
            refreshStartUTF16: 0
        )
    }

    private func editorKeyCommands() -> [UIKeyCommand]? {
        guard model.isEditable else {
            return nil
        }

        return [
            makeKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleIndentCommand), title: "Indent"),
            makeKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleOutdentCommand), title: "Outdent"),
            makeKeyCommand(input: "/", modifierFlags: [.command], action: #selector(handleToggleCommentCommand), title: "Toggle Comment"),
            makeKeyCommand(input: "]", modifierFlags: [.command], action: #selector(handleIndentCommand), title: "Indent"),
            makeKeyCommand(input: "[", modifierFlags: [.command], action: #selector(handleOutdentCommand), title: "Outdent"),
        ]
    }

    private func isEditorCommandAction(_ action: Selector) -> Bool {
        action == #selector(handleIndentCommand)
            || action == #selector(handleOutdentCommand)
            || action == #selector(handleToggleCommentCommand)
    }

    private func isUndoRedoAction(_ action: Selector) -> Bool {
        let actionName = NSStringFromSelector(action)
        return actionName == "undo:" || actionName == "redo:"
    }

    private func makeKeyCommand(
        input: String,
        modifierFlags: UIKeyModifierFlags,
        action: Selector,
        title: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        command.discoverabilityTitle = title
        return command
    }

    private func makeInputAccessoryView() -> UIView {
        let accessoryModel = SyntaxEditorKeyboardAccessoryModel(
            onUndo: { [weak self] in
                self?.handleUndoCommand()
            },
            onRedo: { [weak self] in
                self?.handleRedoCommand()
            },
            onDismissKeyboard: { [weak self] in
                self?.handleDismissKeyboardCommand()
            }
        )
        keyboardAccessoryModel = accessoryModel
        return SyntaxEditorKeyboardAccessoryView(model: accessoryModel)
    }

    private var activeUndoManager: UndoManager? {
        nativeUndoManager ?? guardedUndoManager
    }

    private func refreshKeyboardAccessoryState() {
        guard let keyboardAccessoryModel else { return }
        keyboardAccessoryModel.isUndoable = model.isEditable && (activeUndoManager?.canUndo ?? false)
        keyboardAccessoryModel.isRedoable = model.isEditable && (activeUndoManager?.canRedo ?? false)
    }

    private func configureBaseTextViewAppearance() {
        let base = baseAttributes()
        font = base[.font] as? UIFont ?? font
        textColor = base[.foregroundColor] as? UIColor ?? textColor
        typingAttributes = base
    }

    private func updateTypingAttributes() {
        typingAttributes = baseAttributes()
    }

    private func startModelObservation() {
        modelObservations.update {
            model.observe(\.text) { [weak self] text in
                guard let self else { return }
                self.applyObservedText(text)
            }
            .store(in: modelObservations)

            model.observe([\.language, \.isEditable, \.lineWrappingEnabled, \.colorTheme.id]) { [weak self] in
                guard let self else { return }
                self.applyObservedEditorState(
                    language: self.model.language,
                    isEditable: self.model.isEditable,
                    lineWrappingEnabled: self.model.lineWrappingEnabled,
                    colorTheme: self.model.colorTheme
                )
            }
            .store(in: modelObservations)
        }
    }

    private func recordModelRenderingForTesting() {
        guard !modelRenderingWaiters.isEmpty else { return }

        var pendingWaiters: [ModelRenderingWaiter] = []
        pendingWaiters.reserveCapacity(modelRenderingWaiters.count)

        for waiter in modelRenderingWaiters {
            if waiter.condition() {
                waiter.continuation.resume(returning: true)
                continue
            }

            pendingWaiters.append(waiter)
        }

        modelRenderingWaiters = pendingWaiters
    }

    private func applyObservedText(_ text: String, forceTextUpdate: Bool = false) {
        isApplyingModel = true
        defer {
            isApplyingModel = false
            recordModelRenderingForTesting()
        }

        let previousText = super.text ?? ""
        let textNeedsUpdate = forceTextUpdate || (super.text ?? "") != text
        if textNeedsUpdate {
            commandEngine.invalidateTransientState()
            let previousSelection = selectedRange
            super.text = text
            selectedRange = clampedTextRange(previousSelection, in: text)
            updateTypingAttributes()
            applyParagraphStyleToExistingText()
            updateTextContainerForCurrentWrappingMode()
            updateScrollableContentSizeForCurrentWrappingMode()
            setNeedsLayout()
        } else {
            updateTypingAttributes()
        }

        if textNeedsUpdate {
            scheduleHighlight(
                previousSource: previousText,
                source: text,
                language: model.language,
                mutation: TextMutation.diff(from: previousText, to: text).map(SyntaxHighlightMutation.init),
                refreshStartUTF16: 0
            )
        }
        refreshKeyboardAccessoryState()
    }

    private func applyObservedEditorState(
        language: SyntaxLanguage,
        isEditable: Bool,
        lineWrappingEnabled: Bool,
        colorTheme: SyntaxEditorColorTheme,
        forceLanguageRefresh: Bool = false,
        schedulesHighlight: Bool = true
    ) {
        defer { recordModelRenderingForTesting() }

        let lineWrappingChanged = lastAppliedLineWrappingEnabled.map { $0 != lineWrappingEnabled } ?? false
        lastAppliedLineWrappingEnabled = lineWrappingEnabled
        let previousColorTheme = lastAppliedColorTheme
        let colorThemeChanged = previousColorTheme.map { $0 != colorTheme } ?? true
        if colorThemeChanged {
            applyBaseForegroundColorChange(from: previousColorTheme, to: colorTheme)
        }
        lastAppliedColorTheme = colorTheme

        if self.isEditable != isEditable {
            self.isEditable = isEditable
        }

        applyLineWrappingConfiguration(lineWrappingEnabled: lineWrappingEnabled)
        applyParagraphStyleToExistingText()
        updateTextContainerForCurrentWrappingMode()
        updateScrollableContentSizeForCurrentWrappingMode()
        if lineWrappingChanged && lineWrappingEnabled {
            resetHorizontalContentOffset()
        }

        let languageChanged = forceLanguageRefresh || lastAppliedLanguageIdentifier != language.syntaxHighlightCacheKey
        lastAppliedLanguageIdentifier = language.syntaxHighlightCacheKey

        updateTypingAttributes()
        if languageChanged && schedulesHighlight {
            scheduleHighlight(
                source: super.text ?? "",
                language: language,
                refreshStartUTF16: 0
            )
        } else if colorThemeChanged && schedulesHighlight {
            reapplyCachedHighlight()
        }
        refreshKeyboardAccessoryState()
    }

    private func applyBaseForegroundColorChange(
        from previousColorTheme: SyntaxEditorColorTheme?,
        to colorTheme: SyntaxEditorColorTheme
    ) {
        guard let previousColorTheme else { return }

        let textRange = NSRange(location: 0, length: textStorage.length)
        guard textRange.length > 0 else { return }

        var rangesToUpdate: [NSRange] = []
        unsafe textStorage.enumerateAttribute(.foregroundColor, in: textRange) { value, range, _ in
            guard let color = value as? UIColor,
                  color.isEqual(previousColorTheme.baseForeground)
            else {
                return
            }
            rangesToUpdate.append(range)
        }

        guard !rangesToUpdate.isEmpty else { return }

        textStorage.beginEditing()
        for range in rangesToUpdate {
            textStorage.addAttribute(.foregroundColor, value: colorTheme.baseForeground, range: range)
        }
        textStorage.endEditing()
    }

    private func applyCommandResult(_ result: EditorCommandResult) {
        guard model.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        let previousText = super.text ?? ""
        let previousSelection = selectedRange
        let textChanged = previousText != result.text
        var appliedMutation: TextMutation?

        if textChanged, !isApplyingUndoRedo {
            registerUndoAction(
                restore: EditorUndoState(
                    text: previousText,
                    selectedRange: previousSelection,
                    refreshStartUTF16: 0
                ),
                counterpart: EditorUndoState(
                    text: result.text,
                    selectedRange: result.selectedRange,
                    refreshStartUTF16: result.refreshStartUTF16
                )
            )
        }

        isApplyingModel = true
        if textChanged {
            performWithoutUndoRegistration {
                appliedMutation = applyTextMutation(
                    previousText: previousText,
                    nextText: result.text
                )
                if appliedMutation == nil {
                    super.text = result.text
                }
                updateTextContainerForCurrentWrappingMode()
                updateScrollableContentSizeForCurrentWrappingMode()
            }
        }
        setTextSelectionPreservingCommandState(clampedTextRange(result.selectedRange, in: result.text))
        typingAttributes = baseAttributes()
        isApplyingModel = false

        pendingEditStartUTF16 = nil
        pendingHighlightMutation = nil

        if textChanged, model.text != result.text {
            model.text = result.text
        }

        if textChanged {
            setNeedsLayout()
            let refreshStartUTF16: Int
            let highlightMutation: SyntaxHighlightMutation?
            if let appliedMutation {
                let mutationLineStart = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                    in: result.text,
                    around: appliedMutation.range.location
                )
                refreshStartUTF16 = min(result.refreshStartUTF16, mutationLineStart)
                highlightMutation = SyntaxHighlightMutation(appliedMutation)
            } else {
                refreshStartUTF16 = 0
                highlightMutation = TextMutation.diff(
                    from: previousText,
                    to: result.text
                ).map(SyntaxHighlightMutation.init)
            }

            scheduleHighlight(
                previousSource: previousText,
                source: result.text,
                language: model.language,
                mutation: highlightMutation,
                refreshStartUTF16: refreshStartUTF16
            )
        } else {
            applyMatchingBracketHighlight()
        }
        refreshKeyboardAccessoryState()
    }

    private func registerUndoAction(restore: EditorUndoState, counterpart: EditorUndoState) {
        guard restore != counterpart else { return }
        guard let activeUndoManager else { return }

        registerUndoAction(restore: restore, counterpart: counterpart, in: activeUndoManager)
    }

    private func registerUndoAction(
        restore: EditorUndoState,
        counterpart: EditorUndoState,
        in undoManager: UndoManager
    ) {
        guard restore != counterpart else { return }

        undoManager.registerUndo(withTarget: self) { target in
            target.applyUndoAction(restore: restore, counterpart: counterpart)
        }

        if !undoManager.isUndoing, !undoManager.isRedoing {
            undoManager.setActionName("Edit")
        }
    }

    private func applyUndoAction(restore: EditorUndoState, counterpart: EditorUndoState) {
        guard model.isEditable else {
            return
        }

        registerUndoAction(restore: counterpart, counterpart: restore)

        isApplyingUndoRedo = true
        applyCommandResult(
            EditorCommandResult(
                text: restore.text,
                selectedRange: restore.selectedRange,
                refreshStartUTF16: restore.refreshStartUTF16
            )
        )
        isApplyingUndoRedo = false
    }

    private func setTextSelectionPreservingCommandState(_ range: NSRange) {
        ignoredProgrammaticSelectionRange = range
        isApplyingCommandSelection = true
        selectedRange = range
        isApplyingCommandSelection = false
    }

    private func performWithoutUndoRegistration(_ work: () -> Void) {
        let undoManager = activeUndoManager
        let wasUndoRegistrationEnabled = undoManager?.isUndoRegistrationEnabled ?? false
        if wasUndoRegistrationEnabled {
            undoManager?.disableUndoRegistration()
        }
        defer {
            if wasUndoRegistrationEnabled {
                undoManager?.enableUndoRegistration()
            }
        }

        work()
    }

    private func applyTextMutation(
        previousText: String,
        nextText: String
    ) -> TextMutation? {
        guard let mutation = TextMutation.diff(from: previousText, to: nextText) else {
            return nil
        }

        let textLength = previousText.utf16.count
        guard mutation.range.location >= 0,
              mutation.range.location + mutation.range.length <= textLength else {
            return nil
        }

        guard let start = position(
            from: beginningOfDocument,
            offset: mutation.range.location
        ),
            let end = position(
                from: start,
                offset: mutation.range.length
            ),
            let textRange = textRange(from: start, to: end)
        else {
            return nil
        }

        replace(textRange, withText: mutation.replacement)

        return mutation
    }

    @objc private func handleIndentCommand() {
        guard model.isEditable else { return }

        let source = super.text ?? ""
        guard let result = commandEngine.indentSelection(
            source: source,
            selection: selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleOutdentCommand() {
        guard model.isEditable else { return }

        let source = super.text ?? ""
        guard let result = commandEngine.outdentSelection(
            source: source,
            selection: selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleToggleCommentCommand() {
        guard model.isEditable else { return }

        let source = super.text ?? ""
        guard let result = commandEngine.toggleComment(
            source: source,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleUndoCommand() {
        guard model.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        activeUndoManager?.undo()
        refreshKeyboardAccessoryState()
    }

    @objc private func handleRedoCommand() {
        guard model.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        activeUndoManager?.redo()
        refreshKeyboardAccessoryState()
    }

    @objc private func handleDismissKeyboardCommand() {
        window?.endEditing(true)
    }

    private func scheduleHighlight(
        previousSource: String? = nil,
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation? = nil,
        refreshStartUTF16: Int = 0
    ) {
        let expectedSource = source
        let utf16Length = expectedSource.utf16.count
        let clampedRefreshStart = min(max(0, refreshStartUTF16), utf16Length)
        let fallbackRefreshRange = NSRange(
            location: clampedRefreshStart,
            length: utf16Length - clampedRefreshStart
        )

        highlightTask?.cancel()

        let highlighter = self.highlighter
        highlightTask = Task { [weak self] in
            let result: SyntaxHighlightResult
            if let previousSource, let mutation {
                result = await highlighter.update(
                    previousSource: previousSource,
                    source: expectedSource,
                    language: language,
                    mutation: mutation
                )
            } else {
                result = await highlighter.reset(source: expectedSource, language: language)
            }
            guard let self else { return }
            guard !Task.isCancelled else {
                return
            }
            guard self.text == result.source else {
                return
            }
            self.lastHighlightTokens = result.tokens
            self.lastHighlightSource = result.source
            self.lastHighlightLanguage = result.language
            self.applyHighlight(
                result.tokens,
                expectedSource: result.source,
                refreshRange: Self.combinedRefreshRange(
                    result.refreshRange,
                    fallbackRefreshRange,
                    sourceUTF16Length: result.source.utf16.count
                )
            )
        }
    }

    private func reapplyCachedHighlight() {
        let source = super.text ?? ""
        guard lastHighlightSource == source, lastHighlightLanguage == model.language else {
            scheduleHighlight(source: source, language: model.language)
            return
        }

        applyHighlight(
            lastHighlightTokens,
            expectedSource: source,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }

    private static func combinedRefreshRange(
        _ lhs: NSRange,
        _ rhs: NSRange,
        sourceUTF16Length: Int
    ) -> NSRange {
        let lhs = SyntaxEditorRangeUtilities.clampedRange(lhs, utf16Length: sourceUTF16Length)
        let rhs = SyntaxEditorRangeUtilities.clampedRange(rhs, utf16Length: sourceUTF16Length)
        let location = min(lhs.location, rhs.location)
        return NSRange(location: location, length: sourceUTF16Length - location)
    }

    private func applyHighlight(
        _ tokens: [SyntaxHighlightToken],
        expectedSource: String,
        refreshRange: NSRange
    ) {
        guard super.text == expectedSource else { return }

        let textLength = expectedSource.utf16.count
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: textLength)
        guard targetRange.length > 0 else {
            applyMatchingBracketHighlight(force: true)
            return
        }
        let base = baseAttributes()

        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        textStorage.beginEditing()
        textStorage.setAttributes(base, range: targetRange)

        for token in tokens {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: textLength)
            let intersection = SyntaxEditorRangeUtilities.intersection(of: clamped, and: targetRange)
            guard intersection.length > 0 else { continue }

            var attributes = base
            for (key, value) in styleAttributes(for: token.captureName) {
                attributes[key] = value
            }
            textStorage.setAttributes(attributes, range: intersection)
        }

        textStorage.endEditing()
        typingAttributes = base
        applyMatchingBracketHighlight(force: true)
    }

    private func applyMatchingBracketHighlight(force: Bool = false) {
        let source = super.text ?? ""
        let textLength = source.utf16.count
        let selection = selectedRange

        guard selection.length == 0 else {
            clearMatchingBracketHighlight(textLength: textLength)
            return
        }

        let newRanges = BracketMatcher.matchedRanges(
            in: source,
            caretUTF16Offset: selection.location
        )

        guard force || newRanges != matchedBracketRanges else {
            return
        }

        for range in matchedBracketRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            textStorage.removeAttribute(.backgroundColor, range: clamped)
        }

        for range in newRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            textStorage.addAttributes(
                [.backgroundColor: UIColor.syntaxEditorAlpha(model.colorTheme.bracketBackground, alpha: 0.24)],
                range: clamped
            )
        }

        matchedBracketRanges = newRanges
    }

    private func clearMatchingBracketHighlight(textLength: Int) {
        guard !matchedBracketRanges.isEmpty else { return }

        for range in matchedBracketRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            textStorage.removeAttribute(.backgroundColor, range: clamped)
        }
        matchedBracketRanges = []
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: model.colorTheme.baseForeground,
            .paragraphStyle: baseParagraphStyle(),
        ]
        return attributes
    }

    private func baseParagraphStyle() -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = model.lineWrappingEnabled ? .byCharWrapping : .byClipping
        return paragraphStyle
    }

    private func applyParagraphStyleToExistingText() {
        let textRange = NSRange(location: 0, length: textStorage.length)
        guard textRange.length > 0 else { return }

        let targetLineBreakMode: NSLineBreakMode = model.lineWrappingEnabled ? .byCharWrapping : .byClipping
        var updates: [(range: NSRange, style: NSParagraphStyle)] = []

        unsafe textStorage.enumerateAttribute(.paragraphStyle, in: textRange) { value, range, _ in
            let paragraphStyle = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            guard value == nil || paragraphStyle.lineBreakMode != targetLineBreakMode else { return }

            paragraphStyle.lineBreakMode = targetLineBreakMode
            updates.append((range, paragraphStyle.copy() as! NSParagraphStyle))
        }

        guard !updates.isEmpty else { return }

        textStorage.beginEditing()
        for update in updates {
            textStorage.addAttribute(.paragraphStyle, value: update.style, range: update.range)
        }
        textStorage.endEditing()
    }

    private func styleAttributes(for captureName: String) -> [NSAttributedString.Key: Any] {
        guard let color = SyntaxEditorHighlightTheme.color(for: captureName, in: model.colorTheme) else {
            return [:]
        }
        return [.foregroundColor: color]
    }

    private func applyLineWrappingConfiguration(lineWrappingEnabled: Bool) {
        if lineWrappingEnabled {
            alwaysBounceHorizontal = false
            showsHorizontalScrollIndicator = false
        } else {
            alwaysBounceHorizontal = true
            showsHorizontalScrollIndicator = true
        }
        updateTextContainerForCurrentWrappingMode()
        updateScrollableContentSizeForCurrentWrappingMode()
        setNeedsLayout()
    }

    private func updateTextContainerForCurrentWrappingMode() {
        let lineWrappingEnabled = model.lineWrappingEnabled
        let lineBreakMode: NSLineBreakMode = lineWrappingEnabled ? .byCharWrapping : .byClipping

        if textContainer.widthTracksTextView != lineWrappingEnabled {
            textContainer.widthTracksTextView = lineWrappingEnabled
        }
        if textContainer.lineBreakMode != lineBreakMode {
            textContainer.lineBreakMode = lineBreakMode
        }
        alwaysBounceHorizontal = !lineWrappingEnabled
        showsHorizontalScrollIndicator = !lineWrappingEnabled

        guard bounds.width > 0, bounds.height > 0 else { return }

        if lineWrappingEnabled {
            let wrappedWidth = max(0, bounds.width - textContainerInset.left - textContainerInset.right)
            let nextSize = CGSize(width: wrappedWidth, height: defaultTextContainerSize.height)
            if !textContainer.size.isNearlyEqual(to: nextSize) {
                textContainer.size = nextSize
            }
            return
        }

        let documentWidth = max(bounds.width, measuredHorizontalDocumentLayoutWidth())
        let textContainerWidth = max(0, documentWidth - textContainerInset.left - textContainerInset.right)
        let nextSize = CGSize(width: textContainerWidth, height: defaultTextContainerSize.height)
        if !textContainer.size.isNearlyEqual(to: nextSize) {
            textContainer.size = nextSize
        }
    }

    private func updateScrollableContentSizeForCurrentWrappingMode() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let targetWidth = model.lineWrappingEnabled
            ? bounds.width
            : max(bounds.width, measuredHorizontalDocumentLayoutWidth())
        if !contentSize.width.isNearlyEqual(to: targetWidth) {
            let nextSize = CGSize(width: targetWidth, height: contentSize.height)
            isSynchronizingContentSize = true
            contentSize = nextSize
            isSynchronizingContentSize = false
        }

    }

    private func measuredHorizontalDocumentLayoutWidth() -> CGFloat {
        guard let source = super.text, !source.isEmpty else {
            return bounds.width
        }

        let textFont = font ?? Self.defaultEditorFont
        let columnWidth = Self.estimatedMonospacedColumnWidth(for: textFont)
        let maxColumns = Self.maximumDisplayColumnCount(
            in: source,
            tabWidth: Self.estimatedTabColumnWidth
        )
        let textWidth = CGFloat(maxColumns) * columnWidth
        return ceil(
            textWidth
                + textContainer.lineFragmentPadding * 2
                + textContainerInset.left
                + textContainerInset.right
        )
    }

    private static func estimatedMonospacedColumnWidth(for font: UIFont) -> CGFloat {
        font.pointSize * 0.65
    }

    private static func maximumDisplayColumnCount(in source: String, tabWidth: Int) -> Int {
        var maxColumns = 0
        var currentColumns = 0

        for scalar in source.unicodeScalars {
            switch scalar.value {
            case 9:
                let tabColumns = max(1, tabWidth - (currentColumns % tabWidth))
                currentColumns += tabColumns
            case 10, 13:
                maxColumns = max(maxColumns, currentColumns)
                currentColumns = 0
            default:
                currentColumns += displayColumnWidth(for: scalar)
            }
        }

        return max(maxColumns, currentColumns)
    }

    private static func displayColumnWidth(for scalar: Unicode.Scalar) -> Int {
        let value = scalar.value

        if isZeroWidthScalar(value) {
            return 0
        }

        if isWideScalar(value) {
            return 2
        }

        return 1
    }

    private static func isZeroWidthScalar(_ value: UInt32) -> Bool {
        switch value {
        case 0x0300...0x036F,
             0x1AB0...0x1AFF,
             0x1DC0...0x1DFF,
             0x200B...0x200F,
             0x202A...0x202E,
             0x2060...0x206F,
             0x20D0...0x20FF,
             0xFE00...0xFE0F,
             0xFE20...0xFE2F:
            return true
        default:
            return false
        }
    }

    private static func isWideScalar(_ value: UInt32) -> Bool {
        switch value {
        case 0x1100...0x115F,
             0x2329...0x232A,
             0x2600...0x27BF,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F300...0x1FAFF,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }

    private func resetHorizontalContentOffset() {
        let targetX = -adjustedContentInset.left
        guard !contentOffset.x.isNearlyEqual(to: targetX) else { return }

        setContentOffset(CGPoint(x: targetX, y: contentOffset.y), animated: false)
    }

    private func clampedTextRange(_ range: NSRange) -> NSRange {
        clampedTextRange(range, in: super.text ?? "")
    }

    private func clampedTextRange(_ range: NSRange, in source: String) -> NSRange {
        let textLength = source.utf16.count
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return NSRange(location: location, length: length)
    }
}

@MainActor
@Observable
public final class SyntaxEditorViewController: UIViewController {
    public private(set) var model: SyntaxEditorModel
    @ObservationIgnored
    public let editorView: SyntaxEditorView

    public init(model: SyntaxEditorModel) {
        self.model = model
        self.editorView = SyntaxEditorView(model: model)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        view = editorView
    }
}

private extension UIColor {
    static func syntaxEditorAlpha(_ color: UIColor, alpha: CGFloat) -> UIColor {
        UIColor { traitCollection in
            color.resolvedColor(with: traitCollection).withAlphaComponent(alpha)
        }
    }
}

private extension CGFloat {
    func isNearlyEqual(to other: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        abs(self - other) <= tolerance
    }
}

private extension CGSize {
    func isNearlyEqual(to other: CGSize, tolerance: CGFloat = 0.5) -> Bool {
        width.isNearlyEqual(to: other.width, tolerance: tolerance)
            && height.isNearlyEqual(to: other.height, tolerance: tolerance)
    }
}
#endif
