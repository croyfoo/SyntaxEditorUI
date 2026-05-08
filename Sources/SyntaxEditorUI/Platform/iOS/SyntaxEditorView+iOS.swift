#if canImport(UIKit)
import Observation
import ObservationBridge
import SyntaxEditorCore
import UIKit

@MainActor
public final class SyntaxEditorView: UIScrollView, UITextInput, UITextInputTraits, UITextInteractionDelegate, @preconcurrency NSTextViewportLayoutControllerDelegate {
    public private(set) var model: SyntaxEditorModel

    let guardedUndoManager = SyntaxEditorReadOnlyGuardedUndoManager()
    let textContentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    let container = NSTextContainer()
    let textContentView = SyntaxEditorTextContentView()
    let editableTextInteraction = UITextInteraction(for: .editable)
    let nonEditableTextInteraction = UITextInteraction(for: .nonEditable)
    static let estimatedTabColumnWidth = 4
    static let defaultEditorFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    let highlighter: any SyntaxHighlighting
    let commandEngine = EditorCommandEngine()
    var highlightTask: Task<Void, Never>?
    var lastHighlightTokens: [SyntaxHighlightToken] = []
    var lastHighlightSource: String?
    var lastHighlightLanguage: SyntaxLanguage?
    var isApplyingModel = false
    var isApplyingHighlight = false
    var isApplyingUndoRedo = false
    var isApplyingCommandSelection = false
    var lastAppliedLanguageIdentifier: String?
    var matchedBracketRanges: [NSRange] = []
    var lastAppliedLineWrappingEnabled: Bool
    var lastAppliedColorTheme: SyntaxEditorColorTheme
    var isApplyingEditorOwnedScroll = false
    var isIgnoringTextInteractionHorizontalOffsetPreservation = false
    var preservedTextInteractionHorizontalOffset: CGFloat?
    var textInteractionHorizontalOffsetLockGeneration = 0
    var cachedHorizontalDocumentLayoutWidth: CGFloat?
    var isLayingOutText = false
    var needsTextRelayout = false
    var fragmentViewMap = NSMapTable<NSTextLayoutFragment, SyntaxEditorTextLayoutFragmentView>.weakToWeakObjects()
    var lastUsedFragmentViews: Set<SyntaxEditorTextLayoutFragmentView> = []
    var postLayoutAction: (() -> Void)?
    var markedRange: NSRange?
    var markedTextUndoAnchor: EditorUndoState?
    var pendingTextInteractionCaretOverride: SyntaxEditorTextInteractionCaretOverride?
    var isTextInteractionSelectionDrag = false
    var keyboardAccessoryModel: SyntaxEditorKeyboardAccessoryModel?
    var keyboardAccessoryView: UIView?
    let modelObservations = ObservationScope()
    var storage: NSTextStorage {
        guard let textStorage = textContentStorage.textStorage else {
            fatalError("SyntaxEditorView requires NSTextContentStorage-backed NSTextStorage")
        }
        return textStorage
    }

    internal var textStorage: NSTextStorage {
        storage
    }

    internal var textLayoutManager: NSTextLayoutManager? {
        layoutManager
    }

    internal var textContainer: NSTextContainer {
        container
    }

    internal var attributedText: NSAttributedString? {
        storage.copy() as? NSAttributedString
    }

    internal var renderedTextContentFrameForTesting: CGRect {
        textContentView.frame
    }

    internal var bracketHighlightRangesForTesting: [NSRange] {
        matchedBracketRanges
    }

    public var textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0) {
        didSet {
            guard textContainerInset != oldValue else { return }
            invalidateHorizontalMeasurement()
            updateTextContainerForCurrentWrappingMode()
            invalidateTextLayout()
        }
    }

    public var font: UIFont = SyntaxEditorView.defaultEditorFont {
        didSet {
            guard font != oldValue else { return }
            invalidateHorizontalMeasurement()
            updateTypingAttributes()
            applyBaseAttributesToExistingText()
            reapplyCachedHighlight()
            updateTextContainerForCurrentWrappingMode()
            invalidateTextLayout()
        }
    }

    public var isEditable: Bool {
        get { model.isEditable }
        set {
            guard model.isEditable != newValue else { return }
            model.isEditable = newValue
        }
    }

    public var isSelectable = true {
        didSet {
            guard isSelectable != oldValue else { return }
            updateTextInteractions()
        }
    }

    public var text: String {
        get {
            storage.string
        }
        set {
            applyExternalText(newValue, updatesModel: true, forceTextUpdate: false)
        }
    }

    public var selectedRange: NSRange {
        get {
            currentSelectedRange
        }
        set {
            let nextRange = clampedTextRange(newValue)
            clearMarkedTextIfSelectionLeavesComposition(nextRange)
            setSelectedRange(
                nextRange,
                preservesCommandState: false,
                schedulesSelectionScroll: true
            )
        }
    }

    var currentSelectedRange = NSRange(location: 0, length: 0)
    public weak var inputDelegate: UITextInputDelegate?
    var tokenizerStorage: (any UITextInputTokenizer)?
    public var tokenizer: any UITextInputTokenizer {
        if let tokenizerStorage {
            return tokenizerStorage
        }
        let tokenizer = SyntaxEditorTextInputTokenizer(textInput: self)
        tokenizerStorage = tokenizer
        return tokenizer
    }
    public var markedTextStyle: [NSAttributedString.Key: Any]?

    public var autocapitalizationType: UITextAutocapitalizationType = .none
    public var autocorrectionType: UITextAutocorrectionType = .no
    public var spellCheckingType: UITextSpellCheckingType = .no
    public var smartQuotesType: UITextSmartQuotesType = .no
    public var smartDashesType: UITextSmartDashesType = .no
    public var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    public var keyboardType: UIKeyboardType = .default
    public var keyboardAppearance: UIKeyboardAppearance = .default
    public var returnKeyType: UIReturnKeyType = .default
    public var enablesReturnKeyAutomatically = false
    public var isSecureTextEntry = false
    public var textContentType: UITextContentType?
    public var passwordRules: UITextInputPasswordRules?

    public convenience init(model: SyntaxEditorModel) {
        self.init(model: model, highlighter: SyntaxHighlighterEngine())
    }

    package init(model: SyntaxEditorModel, highlighter: any SyntaxHighlighting) {
        self.model = model
        self.highlighter = highlighter
        self.lastAppliedLineWrappingEnabled = model.lineWrappingEnabled
        self.lastAppliedColorTheme = model.colorTheme

        super.init(frame: .zero)

        configureTextSystem()
        configureScrollView()
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
        applyExternalText(model.text, updatesModel: false, forceTextUpdate: true)
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

    public override var inputAccessoryView: UIView? {
        keyboardAccessoryView
    }

    internal func synchronizeModelForTesting() {
        applyObservedEditorState(
            language: model.language,
            isEditable: model.isEditable,
            lineWrappingEnabled: model.lineWrappingEnabled,
            colorTheme: model.colorTheme
        )
        applyObservedText(model.text)
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
        editorKeyCommands()
    }

    public override var bounds: CGRect {
        didSet {
            guard bounds.size != oldValue.size else { return }
            updateTextContainerForCurrentWrappingMode()
            setNeedsLayout()
        }
    }

    public override var frame: CGRect {
        didSet {
            guard frame.size != oldValue.size else { return }
            updateTextContainerForCurrentWrappingMode()
            setNeedsLayout()
        }
    }

    public override var contentOffset: CGPoint {
        get {
            super.contentOffset
        }
        set {
            super.contentOffset = contentOffsetConstrainedForTextInteraction(newValue)
        }
    }

    public override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(
            contentOffsetConstrainedForTextInteraction(contentOffset),
            animated: animated
        )
    }

    public override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        guard shouldPreserveHorizontalOffsetForImplicitTextInteractionScroll,
              let preservedX = preservedTextInteractionHorizontalOffset else {
            super.scrollRectToVisible(rect, animated: animated)
            return
        }

        super.scrollRectToVisible(rect, animated: animated)
        guard !contentOffset.x.isNearlyEqual(to: preservedX) else { return }
        super.setContentOffset(CGPoint(x: preservedX, y: contentOffset.y), animated: false)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateTextContainerForCurrentWrappingMode()
        layoutTextIfNeeded()

        if let action = postLayoutAction {
            postLayoutAction = nil
            action()
        }
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if isUndoAction(action) {
            return model.isEditable && (activeUndoManager?.canUndo ?? false)
        }

        if isRedoAction(action) {
            return model.isEditable && (activeUndoManager?.canRedo ?? false)
        }

        if isEditorCommandAction(action) {
            return model.isEditable
        }

        switch action {
        case #selector(UIResponderStandardEditActions.copy(_:)):
            return isSelectable && selectedRange.length > 0
        case #selector(UIResponderStandardEditActions.cut(_:)),
             #selector(UIResponderStandardEditActions.delete(_:)):
            return model.isEditable && selectedRange.length > 0
        case #selector(UIResponderStandardEditActions.paste(_:)):
            return model.isEditable && UIPasteboard.general.hasStrings
        case #selector(UIResponderStandardEditActions.selectAll(_:)):
            return isSelectable && !text.isEmpty
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    public override func copy(_ sender: Any?) {
        guard selectedRange.length > 0,
              let selectedText = string(in: selectedRange)
        else {
            return
        }
        UIPasteboard.general.string = selectedText
    }

    public override func cut(_ sender: Any?) {
        guard model.isEditable, selectedRange.length > 0 else { return }
        copy(sender)
        applyUserReplacement(in: selectedRange, replacement: "", deletionIntent: .unspecified)
    }

    public override func paste(_ sender: Any?) {
        guard model.isEditable,
              let pastedText = UIPasteboard.general.string
        else {
            return
        }
        insertText(pastedText)
    }

    public override func delete(_ sender: Any?) {
        guard model.isEditable else { return }
        if selectedRange.length > 0 {
            applyUserReplacement(in: selectedRange, replacement: "", deletionIntent: .unspecified)
        } else {
            deleteBackward()
        }
    }

    public override func selectAll(_ sender: Any?) {
        guard isSelectable else { return }
        selectedRange = NSRange(location: 0, length: text.utf16.count)
    }

    @objc private func undo(_ sender: Any?) {
        handleUndoCommand()
    }

    @objc private func redo(_ sender: Any?) {
        handleRedoCommand()
    }

    func configureTextSystem() {
        container.lineFragmentPadding = 5
        layoutManager.textContainer = container
        layoutManager.textViewportLayoutController.delegate = self
        textContentStorage.addTextLayoutManager(layoutManager)
        textContentStorage.primaryTextLayoutManager = layoutManager

        addSubview(textContentView)

        editableTextInteraction.textInput = self
        editableTextInteraction.delegate = self
        nonEditableTextInteraction.textInput = self
        nonEditableTextInteraction.delegate = self
        updateTextInteractions()

        guardedUndoManager.allowsMutation = { [weak self] in
            self?.model.isEditable ?? true
        }
    }

    func configureScrollView() {
        backgroundColor = .clear
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        delaysContentTouches = false
        panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirect.rawValue),
        ]

        autocapitalizationType = .none
        autocorrectionType = .no
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no

        keyboardAccessoryView = makeInputAccessoryView()
        refreshKeyboardAccessoryState()
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        applyMarkedTextAttributes()
    }

    func updateTextInteractions() {
        func addEditableInteraction() {
            removeInteraction(nonEditableTextInteraction)
            if editableTextInteraction.view == nil {
                addInteraction(editableTextInteraction)
            }
        }

        func addNonEditableInteraction() {
            removeInteraction(editableTextInteraction)
            if nonEditableTextInteraction.view == nil {
                addInteraction(nonEditableTextInteraction)
            }
        }

        func removeTextInteractions() {
            removeInteraction(editableTextInteraction)
            removeInteraction(nonEditableTextInteraction)
        }

        if model.isEditable {
            addEditableInteraction()
        } else if isSelectable {
            addNonEditableInteraction()
        } else {
            removeTextInteractions()
        }
    }

    public func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
        return true
    }

    public func interactionWillBegin(_ interaction: UITextInteraction) {
        isTextInteractionSelectionDrag = false
    }

    public func interactionDidEnd(_ interaction: UITextInteraction) {
        pendingTextInteractionCaretOverride = nil
        isTextInteractionSelectionDrag = false
    }

    func configureUndoObservation() {
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
    func handleUndoManagerStateDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === guardedUndoManager else { return }
        refreshKeyboardAccessoryState()
    }

    func configureTraitChangeObservation() {
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) {
            (self: Self, previousTraitCollection: UITraitCollection) in
            guard previousTraitCollection.hasDifferentColorAppearance(comparedTo: self.traitCollection) else {
                return
            }
            self.refreshForColorAppearanceChange()
        }
    }

    func refreshForColorAppearanceChange() {
        updateTypingAttributes()
        updateBracketHighlightFragmentViews()
        scheduleHighlight(
            source: text,
            language: model.language,
            refreshStartUTF16: 0
        )
    }

    func editorKeyCommands() -> [UIKeyCommand]? {
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

    func isEditorCommandAction(_ action: Selector) -> Bool {
        action == #selector(handleIndentCommand)
            || action == #selector(handleOutdentCommand)
            || action == #selector(handleToggleCommentCommand)
    }

    func isUndoAction(_ action: Selector) -> Bool {
        NSStringFromSelector(action) == "undo:"
    }

    func isRedoAction(_ action: Selector) -> Bool {
        let actionName = NSStringFromSelector(action)
        return actionName == "redo:"
    }

    func makeKeyCommand(
        input: String,
        modifierFlags: UIKeyModifierFlags,
        action: Selector,
        title: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        command.discoverabilityTitle = title
        return command
    }

    func makeInputAccessoryView() -> UIView {
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

    var activeUndoManager: UndoManager? {
        guardedUndoManager
    }

    func refreshKeyboardAccessoryState() {
        guard let keyboardAccessoryModel else { return }
        keyboardAccessoryModel.isUndoable = model.isEditable && (activeUndoManager?.canUndo ?? false)
        keyboardAccessoryModel.isRedoable = model.isEditable && (activeUndoManager?.canRedo ?? false)
    }

    var typingAttributes: [NSAttributedString.Key: Any] = [:]

    func updateTypingAttributes() {
        typingAttributes = baseAttributes()
    }

    func startModelObservation() {
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

    func applyObservedText(_ text: String, forceTextUpdate: Bool = false) {
        guard text == model.text else { return }
        applyExternalText(text, updatesModel: false, forceTextUpdate: forceTextUpdate)
    }

    func applyExternalText(_ nextText: String, updatesModel: Bool, forceTextUpdate: Bool) {
        isApplyingModel = true
        defer {
            isApplyingModel = false
        }

        let previousText = text
        let textNeedsUpdate = forceTextUpdate || previousText != nextText

        if textNeedsUpdate {
            commandEngine.invalidateTransientState()
            let previousSelection = selectedRange
            replaceEntireStorageText(nextText)
            setSelectedRange(
                clampedTextRange(previousSelection, in: nextText),
                preservesCommandState: true,
                schedulesSelectionScroll: true
            )
            updateTypingAttributes()
            updateTextContainerForCurrentWrappingMode()
            invalidateTextLayout()
            scheduleHighlight(
                previousSource: previousText,
                source: nextText,
                language: model.language,
                mutation: TextMutation.diff(from: previousText, to: nextText).map(SyntaxHighlightMutation.init),
                refreshStartUTF16: 0
            )
        } else {
            updateTypingAttributes()
        }

        if updatesModel, model.text != nextText {
            model.text = nextText
        }
        refreshKeyboardAccessoryState()
    }

    func applyObservedEditorState(
        language: SyntaxLanguage,
        isEditable: Bool,
        lineWrappingEnabled: Bool,
        colorTheme: SyntaxEditorColorTheme,
        forceLanguageRefresh: Bool = false,
        schedulesHighlight: Bool = true
    ) {
        let lineWrappingChanged = lastAppliedLineWrappingEnabled != lineWrappingEnabled
        lastAppliedLineWrappingEnabled = lineWrappingEnabled

        let previousColorTheme = lastAppliedColorTheme
        let colorThemeChanged = previousColorTheme != colorTheme
        if colorThemeChanged {
            applyBaseForegroundColorChange(from: previousColorTheme, to: colorTheme)
        }
        lastAppliedColorTheme = colorTheme

        updateTextInteractions()
        applyLineWrappingConfiguration(lineWrappingEnabled: lineWrappingEnabled)
        applyParagraphStyleToExistingText()
        updateTextContainerForCurrentWrappingMode()
        if lineWrappingChanged && lineWrappingEnabled {
            resetHorizontalContentOffset()
        }

        let languageChanged = forceLanguageRefresh || lastAppliedLanguageIdentifier != language.syntaxHighlightCacheKey
        lastAppliedLanguageIdentifier = language.syntaxHighlightCacheKey

        updateTypingAttributes()
        if languageChanged && schedulesHighlight {
            scheduleHighlight(
                source: text,
                language: language,
                refreshStartUTF16: 0
            )
        } else if colorThemeChanged && schedulesHighlight {
            reapplyCachedHighlight()
        }
        refreshKeyboardAccessoryState()
        invalidateTextLayout()
    }

    func replaceEntireStorageText(_ nextText: String) {
        invalidateHorizontalMeasurement()
        textContentStorage.performEditingTransaction {
            storage.setAttributedString(NSAttributedString(string: nextText, attributes: baseAttributes()))
        }
        markedRange = nil
        markedTextUndoAnchor = nil
        syncTextLayoutSelection()
    }

    func applyBaseAttributesToExistingText() {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()
        storage.addAttributes(baseAttributes(), range: fullRange)
        storage.endEditing()
    }

    func applyBaseForegroundColorChange(
        from previousColorTheme: SyntaxEditorColorTheme,
        to colorTheme: SyntaxEditorColorTheme
    ) {
        let textRange = NSRange(location: 0, length: storage.length)
        guard textRange.length > 0 else { return }

        var rangesToUpdate: [NSRange] = []
        unsafe storage.enumerateAttribute(.foregroundColor, in: textRange) { value, range, _ in
            guard let color = value as? UIColor,
                  color.isEqual(previousColorTheme.baseForeground)
            else {
                return
            }
            rangesToUpdate.append(range)
        }

        guard !rangesToUpdate.isEmpty else { return }

        storage.beginEditing()
        for range in rangesToUpdate {
            storage.addAttribute(.foregroundColor, value: colorTheme.baseForeground, range: range)
        }
        storage.endEditing()
    }

    func applyUserReplacement(
        in range: NSRange,
        replacement: String,
        deletionIntent: EditorCommandEngine.DeletionIntent,
        allowsCommandTransform: Bool = true
    ) {
        guard model.isEditable else {
            return
        }

        let source = text
        let clampedRange = clampedTextRange(range, in: source)

        if allowsCommandTransform,
           !isApplyingModel,
           !isApplyingHighlight,
           let result = commandEngine.transformInput(
               source: source,
               range: clampedRange,
               replacementText: replacement,
               language: model.language,
               deletionIntent: deletionIntent
           ) {
            applyCommandResult(result)
            return
        }

        let previousSelection = selectedRange
        let nextSelection = NSRange(
            location: clampedRange.location + replacement.utf16.count,
            length: 0
        )
        let nextText = (source as NSString).replacingCharacters(in: clampedRange, with: replacement)

        if !isApplyingUndoRedo {
            registerUndoAction(
                restore: EditorUndoState(
                    text: source,
                    selectedRange: previousSelection,
                    refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                        in: source,
                        around: clampedRange.location
                    )
                ),
                counterpart: EditorUndoState(
                    text: nextText,
                    selectedRange: nextSelection,
                    refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                        in: nextText,
                        around: clampedRange.location
                    )
                )
            )
        }

        inputDelegate?.textWillChange(self)
        inputDelegate?.selectionWillChange(self)
        performRawReplacement(in: clampedRange, replacement: replacement)
        currentSelectedRange = clampedTextRange(nextSelection, in: nextText)
        syncTextLayoutSelection()
        handleTextDidChange(
            previousText: source,
            nextText: nextText,
            mutation: SyntaxHighlightMutation(
                location: clampedRange.location,
                length: clampedRange.length,
                replacement: replacement
            ),
            editStartUTF16: clampedRange.location
        )
        handleSelectionDidChange(preservesCommandState: false)
        layoutAndScrollSelectionForTextInputGeometry()

        inputDelegate?.selectionDidChange(self)
        inputDelegate?.textDidChange(self)
    }

    func handleTextDidChange(
        previousText: String,
        nextText: String,
        mutation: SyntaxHighlightMutation?,
        editStartUTF16: Int
    ) {
        if model.text != nextText {
            model.text = nextText
        }

        updateTextContainerForCurrentWrappingMode()
        invalidateTextLayout()

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

    func performRawReplacement(
        in range: NSRange,
        replacement: String,
        preservesMarkedTextUndoAnchor: Bool = false
    ) {
        invalidateHorizontalMeasurement()
        textContentStorage.performEditingTransaction {
            if replacement.isEmpty {
                storage.replaceCharacters(in: range, with: "")
            } else {
                storage.replaceCharacters(
                    in: range,
                    with: NSAttributedString(string: replacement, attributes: typingAttributes)
                )
            }
        }
        if !preservesMarkedTextUndoAnchor {
            markedTextUndoAnchor = nil
        }
        markedRange = nil
        invalidateTextLayout()
    }

    func applyCommandResult(_ result: EditorCommandResult) {
        guard model.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        let previousText = text
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
            inputDelegate?.textWillChange(self)
            performWithoutUndoRegistration {
                appliedMutation = applyTextMutation(
                    previousText: previousText,
                    nextText: result.text
                )
                if appliedMutation == nil {
                    replaceEntireStorageText(result.text)
                }
                updateTextContainerForCurrentWrappingMode()
                invalidateTextLayout()
            }
        }
        setTextSelectionPreservingCommandState(clampedTextRange(result.selectedRange, in: result.text))
        updateTypingAttributes()
        layoutAndScrollSelectionForTextInputGeometry()
        isApplyingModel = false

        if textChanged, model.text != result.text {
            model.text = result.text
        }
        if textChanged {
            inputDelegate?.textDidChange(self)
        }

        if textChanged {
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

    func registerUndoAction(restore: EditorUndoState, counterpart: EditorUndoState) {
        guard restore != counterpart else { return }
        guard let activeUndoManager else { return }

        registerUndoAction(restore: restore, counterpart: counterpart, in: activeUndoManager)
    }

    func registerUndoAction(
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

    func applyUndoAction(restore: EditorUndoState, counterpart: EditorUndoState) {
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

    func setTextSelectionPreservingCommandState(_ range: NSRange) {
        isApplyingCommandSelection = true
        setSelectedRange(
            range,
            preservesCommandState: true,
            schedulesSelectionScroll: true
        )
        isApplyingCommandSelection = false
    }

    func setSelectedRange(
        _ range: NSRange,
        preservesCommandState: Bool,
        schedulesSelectionScroll: Bool
    ) {
        let clamped = clampedTextRange(range)
        let changed = currentSelectedRange != clamped

        if changed {
            inputDelegate?.selectionWillChange(self)
            currentSelectedRange = clamped
            syncTextLayoutSelection()
            inputDelegate?.selectionDidChange(self)
        }

        handleSelectionDidChange(preservesCommandState: preservesCommandState || isApplyingCommandSelection)

        if schedulesSelectionScroll {
            scheduleScrollSelectionToVisibleIfNeeded()
        }
    }

    func syncTextLayoutSelection() {
        if let textRange = textRange(forUTF16Range: currentSelectedRange) {
            let affinity: NSTextSelection.Affinity = currentSelectedRange.length == 0
                && isHardLineBreakCaretLocation(currentSelectedRange.location)
                ? .upstream
                : .downstream
            layoutManager.textSelections = [
                NSTextSelection(range: textRange, affinity: affinity, granularity: .character),
            ]
        } else {
            layoutManager.textSelections = []
        }
    }

    func handleSelectionDidChange(preservesCommandState: Bool) {
        if !preservesCommandState {
            commandEngine.invalidateTransientState()
        }
        applyMatchingBracketHighlight()
        refreshKeyboardAccessoryState()
    }

    func performWithoutUndoRegistration(_ work: () -> Void) {
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

    func applyTextMutation(
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

        performRawReplacement(in: mutation.range, replacement: mutation.replacement)
        return mutation
    }

    @objc private func handleIndentCommand() {
        guard model.isEditable else { return }

        guard let result = commandEngine.indentSelection(
            source: text,
            selection: selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleOutdentCommand() {
        guard model.isEditable else { return }

        guard let result = commandEngine.outdentSelection(
            source: text,
            selection: selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleToggleCommentCommand() {
        guard model.isEditable else { return }

        guard let result = commandEngine.toggleComment(
            source: text,
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

    func scheduleHighlight(
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

    func reapplyCachedHighlight() {
        let source = text
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

    static func combinedRefreshRange(
        _ lhs: NSRange,
        _ rhs: NSRange,
        sourceUTF16Length: Int
    ) -> NSRange {
        let lhs = SyntaxEditorRangeUtilities.clampedRange(lhs, utf16Length: sourceUTF16Length)
        let rhs = SyntaxEditorRangeUtilities.clampedRange(rhs, utf16Length: sourceUTF16Length)
        let location = min(lhs.location, rhs.location)
        return NSRange(location: location, length: sourceUTF16Length - location)
    }

    func applyHighlight(
        _ tokens: [SyntaxHighlightToken],
        expectedSource: String,
        refreshRange: NSRange
    ) {
        guard text == expectedSource else { return }

        let textLength = expectedSource.utf16.count
        let clampedRefreshRange = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: textLength)
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(
            (expectedSource as NSString).paragraphRange(for: clampedRefreshRange),
            utf16Length: textLength
        )
        guard targetRange.length > 0 else {
            applyMatchingBracketHighlight(force: true)
            return
        }
        let base = baseAttributes()

        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        storage.beginEditing()
        storage.setAttributes(base, range: targetRange)

        for token in tokens {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: textLength)
            let intersection = SyntaxEditorRangeUtilities.intersection(of: clamped, and: targetRange)
            guard intersection.length > 0 else { continue }

            var attributes = base
            for (key, value) in styleAttributes(for: token.captureName) {
                attributes[key] = value
            }
            storage.setAttributes(attributes, range: intersection)
        }

        storage.endEditing()
        applyMarkedTextAttributes()
        updateTypingAttributes()
        applyMatchingBracketHighlight(force: true)
        setNeedsDisplayForVisibleTextFragments()
    }

    func reapplyTextAttributes(in range: NSRange) {
        let textLength = text.utf16.count
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
        guard targetRange.length > 0 else { return }

        if lastHighlightSource == text, lastHighlightLanguage == model.language {
            applyHighlight(lastHighlightTokens, expectedSource: text, refreshRange: targetRange)
        } else {
            storage.beginEditing()
            storage.setAttributes(baseAttributes(), range: targetRange)
            storage.endEditing()
            setNeedsDisplayForVisibleTextFragments()
        }
    }

    func applyMarkedTextAttributes() {
        let textLength = text.utf16.count
        guard let markedRange else { return }
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(markedRange, utf16Length: textLength)
        guard targetRange.length > 0 else { return }

        storage.beginEditing()
        storage.addAttributes(markedTextAttributes(), range: targetRange)
        storage.endEditing()
        setNeedsDisplayForVisibleTextFragments()
    }

    func markedTextAttributes() -> [NSAttributedString.Key: Any] {
        [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: tintColor ?? UIColor.systemBlue,
        ]
    }

    func applyMatchingBracketHighlight(force: Bool = false) {
        let source = text
        let selection = selectedRange

        guard selection.length == 0 else {
            clearMatchingBracketHighlight()
            return
        }

        let newRanges = BracketMatcher.matchedRanges(
            in: source,
            caretUTF16Offset: selection.location
        )

        guard force || newRanges != matchedBracketRanges else {
            return
        }

        let rangesToInvalidate = matchedBracketRanges + newRanges
        matchedBracketRanges = newRanges
        updateBracketHighlightFragmentViews()
        setNeedsDisplayForBracketHighlightRanges(rangesToInvalidate)
    }

    func clearMatchingBracketHighlight() {
        guard !matchedBracketRanges.isEmpty else { return }

        let rangesToInvalidate = matchedBracketRanges
        matchedBracketRanges = []
        updateBracketHighlightFragmentViews()
        setNeedsDisplayForBracketHighlightRanges(rangesToInvalidate)
    }

    func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: lastAppliedColorTheme.baseForeground,
            .paragraphStyle: baseParagraphStyle(),
        ]
    }

    func baseParagraphStyle() -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = lastAppliedLineWrappingEnabled ? .byCharWrapping : .byClipping
        return paragraphStyle
    }

    func applyParagraphStyleToExistingText() {
        let textRange = NSRange(location: 0, length: storage.length)
        guard textRange.length > 0 else { return }

        let targetLineBreakMode: NSLineBreakMode = lastAppliedLineWrappingEnabled ? .byCharWrapping : .byClipping
        var updates: [(range: NSRange, style: NSParagraphStyle)] = []

        unsafe storage.enumerateAttribute(.paragraphStyle, in: textRange) { value, range, _ in
            let paragraphStyle = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            guard value == nil || paragraphStyle.lineBreakMode != targetLineBreakMode else { return }

            paragraphStyle.lineBreakMode = targetLineBreakMode
            updates.append((range, paragraphStyle.copy() as! NSParagraphStyle))
        }

        guard !updates.isEmpty else { return }

        storage.beginEditing()
        for update in updates {
            storage.addAttribute(.paragraphStyle, value: update.style, range: update.range)
        }
        storage.endEditing()
    }

    func styleAttributes(for captureName: String) -> [NSAttributedString.Key: Any] {
        guard let color = SyntaxEditorHighlightTheme.color(for: captureName, in: lastAppliedColorTheme) else {
            return [:]
        }
        return [.foregroundColor: color]
    }

    func applyLineWrappingConfiguration(lineWrappingEnabled: Bool) {
        alwaysBounceHorizontal = !lineWrappingEnabled
        showsHorizontalScrollIndicator = !lineWrappingEnabled
        updateTextContainerForCurrentWrappingMode()
        setNeedsLayout()
    }

    func updateTextContainerForCurrentWrappingMode() {
        let lineWrappingEnabled = lastAppliedLineWrappingEnabled
        let lineBreakMode: NSLineBreakMode = lineWrappingEnabled ? .byCharWrapping : .byClipping

        if container.widthTracksTextView != lineWrappingEnabled {
            container.widthTracksTextView = lineWrappingEnabled
        }
        if container.lineBreakMode != lineBreakMode {
            container.lineBreakMode = lineBreakMode
        }

        guard bounds.width > 0, bounds.height > 0 else { return }

        let availableWidth = max(0, bounds.width - textContainerInset.left - textContainerInset.right)
        let containerWidth = lineWrappingEnabled
            ? availableWidth
            : max(availableWidth, measuredHorizontalDocumentLayoutWidth() - textContainerInset.left - textContainerInset.right)
        let nextSize = CGSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        if !container.size.isNearlyEqual(to: nextSize) {
            container.size = nextSize
            invalidateLayoutManagerLayout()
        }
    }

    func layoutTextIfNeeded() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        isLayingOutText = true
        defer {
            isLayingOutText = false
        }

        updateTextContentViewFrameIfNeeded(contentSize: contentSize)

        var remainingIterations = 5
        while remainingIterations > 0 {
            needsTextRelayout = false
            layoutManager.textViewportLayoutController.layoutViewport()
            if !needsTextRelayout {
                break
            }
            remainingIterations -= 1
        }

        updateContentSizeIfNeeded()
    }

    func updateContentSizeIfNeeded() {
        let estimatedLayoutSize = estimatedDocumentLayoutSize()
        let textHeight = max(font.lineHeight, ceil(estimatedLayoutSize.height))
        let targetWidth = lastAppliedLineWrappingEnabled
            ? bounds.width
            : max(bounds.width, measuredHorizontalDocumentLayoutWidth(), ceil(estimatedLayoutSize.width + textContainerInset.left + textContainerInset.right))
        let targetHeight = max(bounds.height, ceil(textHeight + textContainerInset.top + textContainerInset.bottom))
        let nextContentSize = CGSize(width: targetWidth, height: targetHeight)

        if !contentSize.isNearlyEqual(to: nextContentSize) {
            contentSize = nextContentSize
        }

        updateTextContentViewFrameIfNeeded(contentSize: nextContentSize)
    }

    func updateTextContentViewFrameIfNeeded(contentSize: CGSize) {
        let contentViewFrame = CGRect(
            x: textContainerInset.left,
            y: textContainerInset.top,
            width: max(container.size.width, contentSize.width - textContainerInset.left - textContainerInset.right),
            height: max(font.lineHeight, contentSize.height - textContainerInset.top - textContainerInset.bottom)
        )

        guard !textContentView.frame.isNearlyEqual(to: contentViewFrame) else { return }
        textContentView.frame = contentViewFrame
    }

    func estimatedDocumentLayoutSize() -> CGSize {
        var estimatedSize = layoutManager.usageBoundsForTextContainer.size
        let documentEndLocation = textContentStorage.documentRange.endLocation

        layoutManager.enumerateTextLayoutFragments(
            from: documentEndLocation,
            options: [.reverse, .ensuresLayout, .ensuresExtraLineFragment]
        ) { layoutFragment in
            estimatedSize.width = max(estimatedSize.width, layoutFragment.layoutFragmentFrame.maxX)
            return false
        }

        let endRange = NSTextRange(location: documentEndLocation)
        layoutManager.ensureLayout(for: endRange)
        layoutManager.enumerateTextSegments(
            in: endRange,
            type: .standard,
            options: [.middleFragmentsExcluded]
        ) { _, rect, _, _ in
            estimatedSize.height = max(estimatedSize.height, rect.maxY)
            return true
        }

        return estimatedSize
    }

    func updateBracketHighlightFragmentViews() {
        for case let fragmentView as SyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            configureBracketHighlights(for: fragmentView, layoutFragmentFrame: fragmentView.layoutFragment.layoutFragmentFrame)
        }
    }

    func configureBracketHighlights(
        for fragmentView: SyntaxEditorTextLayoutFragmentView,
        layoutFragmentFrame: CGRect
    ) {
        let rects = bracketHighlightRects(in: layoutFragmentFrame)
        let color = rects.isEmpty
            ? nil
            : UIColor
                .syntaxEditorAlpha(lastAppliedColorTheme.bracketBackground, alpha: 0.24)
                .resolvedColor(with: traitCollection)
                .cgColor
        let colorChanged = switch (fragmentView.bracketHighlightColor, color) {
        case (.none, .none):
            false
        case let (.some(previousColor), .some(nextColor)):
            !CFEqual(previousColor, nextColor)
        default:
            true
        }
        let rectsChanged = fragmentView.bracketHighlightRects != rects

        fragmentView.bracketHighlightRects = rects
        fragmentView.bracketHighlightColor = color
        if rectsChanged || colorChanged {
            fragmentView.setNeedsDisplay()
        }
    }

    func bracketHighlightRects(in layoutFragmentFrame: CGRect) -> [CGRect] {
        guard !matchedBracketRanges.isEmpty else { return [] }

        let fragmentLocalBounds = CGRect(origin: .zero, size: layoutFragmentFrame.size)
        var rects: [CGRect] = []
        for nsRange in matchedBracketRanges {
            guard let textRange = textRange(forUTF16Range: nsRange) else { continue }
            layoutManager.ensureLayout(for: textRange)
            layoutManager.enumerateTextSegments(
                in: textRange,
                type: .standard,
                options: [.rangeNotRequired]
            ) { _, segmentRect, _, _ in
                let localRect = segmentRect.offsetBy(
                    dx: -layoutFragmentFrame.minX,
                    dy: -layoutFragmentFrame.minY
                )
                guard localRect.intersects(fragmentLocalBounds) else { return true }
                rects.append(localRect)
                return true
            }
        }
        return rects
    }

    func measuredHorizontalDocumentLayoutWidth() -> CGFloat {
        if let cachedHorizontalDocumentLayoutWidth {
            return cachedHorizontalDocumentLayoutWidth
        }

        guard !text.isEmpty else {
            return bounds.width
        }

        let columnWidth = Self.estimatedMonospacedColumnWidth(for: font)
        let maxColumns = Self.maximumDisplayColumnCount(
            in: text,
            tabWidth: Self.estimatedTabColumnWidth
        )
        let textWidth = CGFloat(maxColumns) * columnWidth
        let measuredWidth = ceil(
            textWidth
                + container.lineFragmentPadding * 2
                + textContainerInset.left
                + textContainerInset.right
        )
        cachedHorizontalDocumentLayoutWidth = measuredWidth
        return measuredWidth
    }

    static func estimatedMonospacedColumnWidth(for font: UIFont) -> CGFloat {
        font.pointSize * 0.65
    }

    static func maximumDisplayColumnCount(in source: String, tabWidth: Int) -> Int {
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

    static func displayColumnWidth(for scalar: Unicode.Scalar) -> Int {
        let value = scalar.value

        if isZeroWidthScalar(value) {
            return 0
        }

        if isWideScalar(value) {
            return 2
        }

        return 1
    }

    static func isZeroWidthScalar(_ value: UInt32) -> Bool {
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

    static func isWideScalar(_ value: UInt32) -> Bool {
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

    func invalidateTextLayout() {
        invalidateLayoutManagerLayout()
        setNeedsDisplayForVisibleTextFragments()
        setNeedsLayout()
    }

    func invalidateLayoutManagerLayout() {
        layoutManager.invalidateLayout(for: textContentStorage.documentRange)
        layoutManager.textSelectionNavigation.flushLayoutCache()
    }

    func invalidateHorizontalMeasurement() {
        cachedHorizontalDocumentLayoutWidth = nil
    }

    func setNeedsTextLayout() {
        if isLayingOutText {
            needsTextRelayout = true
        } else {
            setNeedsLayout()
        }
    }

    func setNeedsDisplayForVisibleTextFragments() {
        for case let fragmentView as SyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            fragmentView.setNeedsDisplay()
        }
    }

    func setNeedsDisplayForBracketHighlightRanges(_ ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }

        var invalidatedRect = CGRect.null
        for range in ranges {
            guard let rect = contentRectForScrollRange(range) else { continue }
            invalidatedRect = invalidatedRect.union(rect.offsetBy(dx: -textContentView.frame.minX, dy: -textContentView.frame.minY))
        }

        if invalidatedRect.isNull {
            setNeedsDisplayForVisibleTextFragments()
        } else {
            invalidateTextFragmentViews(intersecting: invalidatedRect.insetBy(dx: -2, dy: -2))
        }
    }

    func invalidateTextFragmentViews(intersecting rect: CGRect) {
        for case let fragmentView as SyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            guard fragmentView.frame.intersects(rect) else { continue }
            fragmentView.setNeedsDisplay(rect.offsetBy(dx: -fragmentView.frame.minX, dy: -fragmentView.frame.minY))
        }
    }

    func resetHorizontalContentOffset() {
        let targetX = -adjustedContentInset.left
        guard !contentOffset.x.isNearlyEqual(to: targetX) else { return }

        performEditorOwnedScroll {
            setContentOffset(CGPoint(x: targetX, y: contentOffset.y), animated: false)
        }
    }

    public func scrollRangeToVisible(_ range: NSRange) {
        layoutTextIfNeeded()
        let clampedRange = clampedTextRange(range)
        guard let targetRect = withTextInteractionHorizontalOffsetPreservationDisabled({
            contentRectForScrollRange(clampedRange)
        }) else {
            return
        }
        ensureContentSizeContains(targetRect)

        let visibleRect = adjustedVisibleContentRect
        if targetRect.intersects(visibleRect.insetBy(dx: -container.lineFragmentPadding, dy: -4)) {
            return
        }

        scrollContentRectToVisible(targetRect)
    }

    func scheduleScrollSelectionToVisibleIfNeeded() {
        postLayoutAction = { [weak self] in
            self?.scrollSelectionToVisibleIfNeeded()
        }
        setNeedsLayout()
    }

    func layoutAndScrollSelectionForTextInputGeometry() {
        guard bounds.width > 0, bounds.height > 0 else {
            scheduleScrollSelectionToVisibleIfNeeded()
            return
        }

        layoutTextIfNeeded()
        scrollSelectionToVisibleIfNeeded()
    }

    func scrollSelectionToVisibleIfNeeded() {
        guard let targetRect = withTextInteractionHorizontalOffsetPreservationDisabled({
            contentRectForScrollRange(selectedRange)
        }) else { return }
        ensureContentSizeContains(targetRect)
        let visibleRect = adjustedVisibleContentRect
        if targetRect.intersects(visibleRect.insetBy(dx: -container.lineFragmentPadding, dy: -4)) {
            return
        }
        scrollContentRectToVisible(targetRect)
    }

    func contentRectForScrollRange(_ range: NSRange) -> CGRect? {
        if range.length > 0 {
            let firstTextRect = firstRect(for: SyntaxEditorTextRange(nsRange: range))
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

    func contentCaretRectForTextLocation(_ location: Int) -> CGRect? {
        var targetRect = caretRect(for: SyntaxEditorTextPosition(offset: location))
        guard targetRect.origin.x.isFinite,
              targetRect.origin.y.isFinite,
              targetRect.size.width.isFinite,
              targetRect.size.height.isFinite else {
            return nil
        }

        if targetRect.width.isZero {
            targetRect = targetRect.insetBy(dx: -container.lineFragmentPadding, dy: 0)
        }
        targetRect.size.width = max(targetRect.size.width, 2)
        return targetRect
    }

    var adjustedVisibleContentRect: CGRect {
        let insets = adjustedContentInset
        return CGRect(
            x: contentOffset.x + insets.left,
            y: contentOffset.y + insets.top,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
    }

    func scrollContentRectToVisible(_ rect: CGRect) {
        ensureContentSizeContains(rect)
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

        performEditorOwnedScroll {
            setContentOffset(nextOffset, animated: false)
        }
    }

    func ensureContentSizeContains(_ rect: CGRect) {
        let nextContentSize = CGSize(
            width: max(contentSize.width, bounds.width, ceil(rect.maxX + adjustedContentInset.right)),
            height: max(contentSize.height, bounds.height, ceil(rect.maxY + adjustedContentInset.bottom))
        )
        guard !contentSize.isNearlyEqual(to: nextContentSize) else { return }

        contentSize = nextContentSize
        updateTextContentViewFrameIfNeeded(contentSize: nextContentSize)
    }

    func performEditorOwnedScroll(_ scroll: () -> Void) {
        textInteractionHorizontalOffsetLockGeneration += 1
        preservedTextInteractionHorizontalOffset = nil
        isApplyingEditorOwnedScroll = true
        defer {
            isApplyingEditorOwnedScroll = false
        }
        scroll()
    }

    func withTextInteractionHorizontalOffsetPreservationDisabled<T>(_ work: () -> T) -> T {
        let wasIgnoring = isIgnoringTextInteractionHorizontalOffsetPreservation
        isIgnoringTextInteractionHorizontalOffsetPreservation = true
        defer {
            isIgnoringTextInteractionHorizontalOffsetPreservation = wasIgnoring
        }
        return work()
    }

    func preserveTextInteractionHorizontalOffsetForCurrentTurn() {
        guard !lastAppliedLineWrappingEnabled,
              !isIgnoringTextInteractionHorizontalOffsetPreservation else {
            return
        }

        textInteractionHorizontalOffsetLockGeneration += 1
        let generation = textInteractionHorizontalOffsetLockGeneration
        preservedTextInteractionHorizontalOffset = contentOffset.x

        Task { @MainActor [weak self] in
            guard let self,
                  self.textInteractionHorizontalOffsetLockGeneration == generation else {
                return
            }
            self.preservedTextInteractionHorizontalOffset = nil
        }
    }

    func contentOffsetConstrainedForTextInteraction(_ proposedOffset: CGPoint) -> CGPoint {
        guard !isApplyingEditorOwnedScroll,
              !lastAppliedLineWrappingEnabled,
              !isTracking,
              !isDragging,
              !isDecelerating,
              let preservedX = preservedTextInteractionHorizontalOffset else {
            return proposedOffset
        }

        return CGPoint(x: preservedX, y: proposedOffset.y)
    }

    var shouldPreserveHorizontalOffsetForImplicitTextInteractionScroll: Bool {
        !isApplyingEditorOwnedScroll
            && !lastAppliedLineWrappingEnabled
            && !isTracking
            && !isDragging
            && !isDecelerating
            && preservedTextInteractionHorizontalOffset != nil
    }

    public func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        let scrollInsets = adjustedContentInset
        return CGRect(
            x: bounds.origin.x - scrollInsets.left - textContainerInset.left,
            y: bounds.origin.y - scrollInsets.top - textContainerInset.top,
            width: bounds.width
                + scrollInsets.left
                + scrollInsets.right
                + textContainerInset.left
                + textContainerInset.right,
            height: bounds.height
                + scrollInsets.top
                + scrollInsets.bottom
                + textContainerInset.top
                + textContainerInset.bottom
        )
    }

    public func textViewportLayoutControllerWillLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        lastUsedFragmentViews = Set(
            fragmentViewMap.objectEnumerator()?.allObjects as? [SyntaxEditorTextLayoutFragmentView] ?? []
        )
    }

    public func textViewportLayoutController(
        _ textViewportLayoutController: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
    ) {
        let layoutFragmentFrame = textLayoutFragment.layoutFragmentFrame
        let fragmentView: SyntaxEditorTextLayoutFragmentView
        if let cachedFragmentView = fragmentViewMap.object(forKey: textLayoutFragment) {
            fragmentView = cachedFragmentView
            lastUsedFragmentViews.remove(cachedFragmentView)
        } else {
            fragmentView = SyntaxEditorTextLayoutFragmentView(
                layoutFragment: textLayoutFragment,
                frame: layoutFragmentFrame
            )
            fragmentViewMap.setObject(fragmentView, forKey: textLayoutFragment)
        }
        configureBracketHighlights(for: fragmentView, layoutFragmentFrame: layoutFragmentFrame)

        if !fragmentView.frame.isNearlyEqual(to: layoutFragmentFrame) {
            fragmentView.frame = layoutFragmentFrame
            fragmentView.setNeedsDisplay()
        }

        if fragmentView.superview != textContentView {
            textContentView.addSubview(fragmentView)
        }
    }

    public func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        for staleView in lastUsedFragmentViews {
            staleView.removeFromSuperview()
        }
        lastUsedFragmentViews.removeAll()

        if let viewportRange = textViewportLayoutController.viewportRange {
            layoutManager.ensureLayout(for: viewportRange)
        }

        updateContentSizeIfNeeded()
    }

    func textLocation(forUTF16Offset offset: Int) -> NSTextLocation? {
        let clampedOffset = min(max(0, offset), text.utf16.count)
        return textContentStorage.location(
            textContentStorage.documentRange.location,
            offsetBy: clampedOffset
        )
    }

    func utf16Offset(for textLocation: NSTextLocation) -> Int {
        textContentStorage.offset(
            from: textContentStorage.documentRange.location,
            to: textLocation
        )
    }

    func textRange(forUTF16Range range: NSRange) -> NSTextRange? {
        let clampedRange = clampedTextRange(range)
        guard let startLocation = textLocation(forUTF16Offset: clampedRange.location),
              let endLocation = textLocation(forUTF16Offset: clampedRange.location + clampedRange.length)
        else {
            return nil
        }
        return NSTextRange(location: startLocation, end: endLocation)
    }

    func utf16Range(for textRange: NSTextRange) -> NSRange {
        NSRange(
            location: textContentStorage.offset(
                from: textContentStorage.documentRange.location,
                to: textRange.location
            ),
            length: textContentStorage.offset(
                from: textRange.location,
                to: textRange.endLocation
            )
        )
    }

    func clampedTextRange(_ range: NSRange) -> NSRange {
        clampedTextRange(range, in: text)
    }

    func clampedTextRange(_ range: NSRange, in source: String) -> NSRange {
        let textLength = source.utf16.count
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return NSRange(location: location, length: length)
    }

    func string(in range: NSRange) -> String? {
        let clamped = clampedTextRange(range)
        guard clamped.location != NSNotFound else { return nil }
        return (text as NSString).substring(with: clamped)
    }

    func offset(for position: UITextPosition) -> Int? {
        guard let position = position as? SyntaxEditorTextPosition else { return nil }
        return min(max(0, position.offset), text.utf16.count)
    }
}
#endif
