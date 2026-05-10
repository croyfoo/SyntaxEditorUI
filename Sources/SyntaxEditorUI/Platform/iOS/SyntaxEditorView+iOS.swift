#if canImport(UIKit)
import Observation
import ObservationBridge
import SyntaxEditorCore
import UIKit

struct SyntaxEditorMarkedTextUndoAnchor {
    let source: String
    let selectedRange: NSRange
    let refreshStartUTF16: Int
}

@MainActor
public final class SyntaxEditorView: UIScrollView, UITextInput, UITextInputTraits, UITextInteractionDelegate, @preconcurrency NSTextViewportLayoutControllerDelegate {
    public private(set) var document: SyntaxEditorDocument
    public private(set) var configuration: SyntaxEditorConfiguration

    let guardedUndoManager = SyntaxEditorReadOnlyGuardedUndoManager()
    let textContentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    let container = NSTextContainer()
    let textContentView = SyntaxEditorTextContentView()
    let editableTextInteraction = UITextInteraction(for: .editable)
    let nonEditableTextInteraction = UITextInteraction(for: .nonEditable)
    var findCoordinator: SyntaxEditorFindCoordinator?
    static let estimatedTabColumnWidth = 4
    static let defaultEditorFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    let highlighter: any SyntaxHighlighting
    let commandEngine = EditorCommandEngine()
    var highlightTask: Task<Void, Never>?
    var lastHighlightTokens: [SyntaxHighlightToken] = []
    var lastHighlightRevision: Int?
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
    var lineMetricsIndex = LineMetricsIndex(tabWidth: SyntaxEditorView.estimatedTabColumnWidth)
    var lastAppliedDocumentRevision = 0
    var isLayingOutText = false
    var needsTextRelayout = false
    var fragmentViewMap = NSMapTable<NSTextLayoutFragment, SyntaxEditorTextLayoutFragmentView>.weakToWeakObjects()
    var lastUsedFragmentViews: Set<SyntaxEditorTextLayoutFragmentView> = []
    var postLayoutAction: (() -> Void)?
    var markedRange: NSRange?
    var markedTextUndoAnchor: SyntaxEditorMarkedTextUndoAnchor?
    var pendingTextInteractionCaretOverride: SyntaxEditorTextInteractionCaretOverride?
    var isTextInteractionSelectionDrag = false
    var findFoundRanges: [NSRange] = []
    var findHighlightedRanges: [NSRange] = []
    var findDecorationBatchDepth = 0
    var pendingFindDecorationInvalidationRanges: [NSRange] = []
    var findHighlightUpdatePassCount = 0
    var keyboardAccessoryModel: SyntaxEditorKeyboardAccessoryModel?
    var keyboardAccessoryView: UIView?
    let documentObservations = ObservationScope()
    let configurationObservations = ObservationScope()
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

    internal var findFoundRangesForTesting: [NSRange] {
        findFoundRanges
    }

    internal var findHighlightedRangesForTesting: [NSRange] {
        findHighlightedRanges
    }

    internal var findHighlightUpdatePassCountForTesting: Int {
        findHighlightUpdatePassCount
    }

    public var isFindInteractionEnabled = true {
        didSet {
            guard isFindInteractionEnabled != oldValue else { return }
            updateFindInteraction()
        }
    }

    public var findInteraction: UIFindInteraction? {
        findCoordinator?.findInteraction
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
        get { configuration.isEditable }
        set {
            guard configuration.isEditable != newValue else { return }
            configuration.isEditable = newValue
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
            replaceDocumentText(newValue)
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

    public convenience init(
        document: SyntaxEditorDocument = SyntaxEditorDocument(),
        configuration: SyntaxEditorConfiguration = SyntaxEditorConfiguration()
    ) {
        self.init(document: document, configuration: configuration, highlighter: SyntaxHighlighterEngine())
    }

    package init(
        document: SyntaxEditorDocument = SyntaxEditorDocument(),
        configuration: SyntaxEditorConfiguration = SyntaxEditorConfiguration(),
        highlighter: any SyntaxHighlighting
    ) {
        self.document = document
        self.configuration = configuration
        self.highlighter = highlighter
        self.lastAppliedLineWrappingEnabled = configuration.lineWrappingEnabled
        self.lastAppliedColorTheme = configuration.colorTheme
        self.lastAppliedDocumentRevision = document.revision

        super.init(frame: .zero)

        configureTextSystem()
        configureScrollView()
        configureUndoObservation()
        configureTraitChangeObservation()
        applyObservedConfiguration(
            language: configuration.language,
            isEditable: configuration.isEditable,
            lineWrappingEnabled: configuration.lineWrappingEnabled,
            colorTheme: configuration.colorTheme,
            forceLanguageRefresh: true,
            schedulesHighlight: false
        )
        replaceEntireStorageText(document.textSnapshot())
        scheduleHighlight(
            source: text,
            language: configuration.language,
            revision: document.revision,
            refreshStartUTF16: 0
        )
        startDocumentObservation()
        startConfigurationObservation()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        highlightTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public func update(
        document nextDocument: SyntaxEditorDocument,
        configuration nextConfiguration: SyntaxEditorConfiguration
    ) {
        let documentChanged = document !== nextDocument
        let configurationChanged = configuration !== nextConfiguration
        guard documentChanged || configurationChanged else { return }

        if documentChanged {
            documentObservations.cancelAll()
            document = nextDocument
        }

        if configurationChanged {
            configurationObservations.cancelAll()
            configuration = nextConfiguration
            applyObservedConfiguration(
                language: nextConfiguration.language,
                isEditable: nextConfiguration.isEditable,
                lineWrappingEnabled: nextConfiguration.lineWrappingEnabled,
                colorTheme: nextConfiguration.colorTheme,
                forceLanguageRefresh: true,
                schedulesHighlight: !documentChanged
            )
            startConfigurationObservation()
        }

        if documentChanged {
            applyObservedDocumentChange(forceTextUpdate: true)
            startDocumentObservation()
        }
    }

    public override var undoManager: UndoManager? {
        guardedUndoManager
    }

    public override var inputAccessoryView: UIView? {
        keyboardAccessoryView
    }

    internal func synchronizeDocumentForTesting() {
        applyObservedConfiguration(
            language: configuration.language,
            isEditable: configuration.isEditable,
            lineWrappingEnabled: configuration.lineWrappingEnabled,
            colorTheme: configuration.colorTheme
        )
        applyObservedDocumentChange()
    }

    internal func waitForPendingHighlightForTesting() async {
        await highlightTask?.value
    }

    internal var lineMetricsFullRebuildCountForTesting: Int {
        lineMetricsIndex.fullRebuildCount
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
            return configuration.isEditable && (activeUndoManager?.canUndo ?? false)
        }

        if isRedoAction(action) {
            return configuration.isEditable && (activeUndoManager?.canRedo ?? false)
        }

        if isLineWrappingCommandAction(action) {
            return true
        }

        if isEditorCommandAction(action) {
            return configuration.isEditable
        }

        switch action {
        case #selector(UIResponderStandardEditActions.useSelectionForFind(_:)):
            return isFindInteractionEnabled && findInteraction != nil && selectedRange.length > 0
        case #selector(UIResponderStandardEditActions.copy(_:)):
            return isSelectable && selectedRange.length > 0
        case #selector(UIResponderStandardEditActions.cut(_:)),
             #selector(UIResponderStandardEditActions.delete(_:)):
            return configuration.isEditable && selectedRange.length > 0
        case #selector(UIResponderStandardEditActions.paste(_:)):
            return configuration.isEditable && UIPasteboard.general.hasStrings
        case #selector(UIResponderStandardEditActions.selectAll(_:)):
            return isSelectable && !text.isEmpty
        default:
            if isFindAndReplaceCommandAction(action) {
                return configuration.isEditable && isFindInteractionEnabled && findInteraction != nil
            }
            if isFindCommandAction(action) {
                return isFindInteractionEnabled && findInteraction != nil
            }
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
        guard configuration.isEditable, selectedRange.length > 0 else { return }
        copy(sender)
        applyUserReplacement(in: selectedRange, replacement: "", deletionIntent: .unspecified)
    }

    public override func paste(_ sender: Any?) {
        guard configuration.isEditable,
              let pastedText = UIPasteboard.general.string
        else {
            return
        }
        insertPastedText(pastedText)
    }

    func insertPastedText(_ pastedText: String) {
        guard configuration.isEditable else { return }
        insertText(pastedText)
    }

    public override func delete(_ sender: Any?) {
        guard configuration.isEditable else { return }
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

    public override func find(_ sender: Any?) {
        findInteraction?.presentFindNavigator(showingReplace: false)
    }

    public override func findAndReplace(_ sender: Any?) {
        guard configuration.isEditable else { return }
        findInteraction?.presentFindNavigator(showingReplace: true)
    }

    public override func findNext(_ sender: Any?) {
        findInteraction?.findNext()
    }

    public override func findPrevious(_ sender: Any?) {
        findInteraction?.findPrevious()
    }

    public override func useSelectionForFind(_ sender: Any?) {
        guard selectedRange.length > 0,
              let selectedText = string(in: selectedRange)
        else {
            return
        }
        findInteraction?.searchText = selectedText
        findInteraction?.presentFindNavigator(showingReplace: false)
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
        updateFindInteraction()

        guardedUndoManager.allowsMutation = { [weak self] in
            self?.configuration.isEditable ?? true
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

        if configuration.isEditable {
            addEditableInteraction()
        } else if isSelectable {
            addNonEditableInteraction()
        } else {
            removeTextInteractions()
        }
    }

    func updateFindInteraction() {
        if isFindInteractionEnabled {
            let coordinator: SyntaxEditorFindCoordinator
            if let findCoordinator {
                coordinator = findCoordinator
            } else {
                coordinator = SyntaxEditorFindCoordinator(editorView: self)
                findCoordinator = coordinator
            }

            if coordinator.findInteraction.view == nil {
                addInteraction(coordinator.findInteraction)
            }
        } else if let findCoordinator {
            findCoordinator.invalidateActiveSearch()
            clearFindDecorations()
            removeInteraction(findCoordinator.findInteraction)
            self.findCoordinator = nil
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
        reapplyCachedHighlight()
        updateFindHighlightFragmentViews()
        updateBracketHighlightFragmentViews()
        setNeedsDisplayForVisibleTextFragments()
    }

    func editorKeyCommands() -> [UIKeyCommand]? {
        var commands = [
            makeKeyCommand(input: "l", modifierFlags: [.control, .shift, .command], action: #selector(handleToggleLineWrappingCommand), title: "Wrap Lines"),
        ]

        guard configuration.isEditable else {
            return commands
        }

        commands.append(contentsOf: [
            makeKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleInsertTabCommand), title: "Insert Tab"),
            makeKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleOutdentCommand), title: "Outdent"),
            makeKeyCommand(input: "/", modifierFlags: [.command], action: #selector(handleToggleCommentCommand), title: "Toggle Comment"),
            makeKeyCommand(input: "]", modifierFlags: [.command], action: #selector(handleIndentCommand), title: "Indent"),
            makeKeyCommand(input: "[", modifierFlags: [.command], action: #selector(handleOutdentCommand), title: "Outdent"),
            makeKeyCommand(
                input: "v",
                modifierFlags: [.command],
                action: #selector(handlePasteCommand),
                title: "Paste"
            ),
        ])
        return commands
    }

    func isEditorCommandAction(_ action: Selector) -> Bool {
        action == #selector(handleInsertTabCommand)
            || action == #selector(handleIndentCommand)
            || action == #selector(handleOutdentCommand)
            || action == #selector(handleToggleCommentCommand)
            || action == #selector(handlePasteCommand)
    }

    func isLineWrappingCommandAction(_ action: Selector) -> Bool {
        action == #selector(handleToggleLineWrappingCommand)
    }

    func isFindCommandAction(_ action: Selector) -> Bool {
        action == #selector(UIResponderStandardEditActions.find(_:))
            || action == #selector(UIResponderStandardEditActions.findNext(_:))
            || action == #selector(UIResponderStandardEditActions.findPrevious(_:))
    }

    func isFindAndReplaceCommandAction(_ action: Selector) -> Bool {
        action == #selector(UIResponderStandardEditActions.findAndReplace(_:))
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
        command.wantsPriorityOverSystemBehavior = true
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
        keyboardAccessoryModel.isUndoable = configuration.isEditable && (activeUndoManager?.canUndo ?? false)
        keyboardAccessoryModel.isRedoable = configuration.isEditable && (activeUndoManager?.canRedo ?? false)
    }

    var typingAttributes: [NSAttributedString.Key: Any] = [:]

    func updateTypingAttributes() {
        typingAttributes = baseAttributes()
    }

    func startConfigurationObservation() {
        configurationObservations.update {
            configuration.observe([\.language, \.isEditable, \.lineWrappingEnabled, \.colorTheme.id]) { [weak self] in
                guard let self else { return }
                self.applyObservedConfiguration(
                    language: self.configuration.language,
                    isEditable: self.configuration.isEditable,
                    lineWrappingEnabled: self.configuration.lineWrappingEnabled,
                    colorTheme: self.configuration.colorTheme
                )
            }
            .store(in: configurationObservations)
        }
    }

    func startDocumentObservation() {
        documentObservations.update {
            document.observe(\.revision) { [weak self] _ in
                guard let self else { return }
                self.applyObservedDocumentChange()
            }
            .store(in: documentObservations)
        }
    }

    func applyObservedDocumentChange(forceTextUpdate: Bool = false) {
        let revision = document.revision
        guard forceTextUpdate || revision != lastAppliedDocumentRevision else { return }

        isApplyingModel = true
        defer {
            isApplyingModel = false
        }

        let previousText = text
        let nextText = document.textSnapshot()
        let textNeedsUpdate = forceTextUpdate || previousText != nextText

        if textNeedsUpdate {
            commandEngine.invalidateTransientState()
            let previousSelection = selectedRange
            if let change = document.latestChange,
               change.revision == revision,
               !change.isWholeDocumentReplacement,
               !forceTextUpdate,
               lastAppliedDocumentRevision == revision - 1 {
                performRawEdits(change.edits, previousText: previousText)
            } else {
                replaceEntireStorageText(nextText)
            }
            let change = document.latestChange
            let nextSelection: NSRange
            if change?.isWholeDocumentReplacement == true,
               change?.selectedRange == NSRange(location: 0, length: 0) {
                nextSelection = previousSelection
            } else {
                nextSelection = change?.selectedRange ?? previousSelection
            }
            setSelectedRange(
                clampedTextRange(nextSelection, in: nextText),
                preservesCommandState: true,
                schedulesSelectionScroll: true
            )
            updateTypingAttributes()
            updateTextContainerForCurrentWrappingMode()
            invalidateTextLayout()
            scheduleHighlight(
                source: nextText,
                language: configuration.language,
                revision: revision,
                mutation: document.latestChange.flatMap(Self.highlightMutation),
                refreshStartUTF16: 0
            )
        } else {
            updateTypingAttributes()
        }

        lastAppliedDocumentRevision = revision
        refreshKeyboardAccessoryState()
    }

    func applyObservedConfiguration(
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
                revision: document.revision,
                refreshStartUTF16: 0
            )
        } else if colorThemeChanged && schedulesHighlight {
            reapplyCachedHighlight()
        }
        refreshKeyboardAccessoryState()
        invalidateTextLayout()
    }

    func replaceEntireStorageText(_ nextText: String) {
        lineMetricsIndex.reset(source: nextText)
        textContentStorage.performEditingTransaction {
            storage.setAttributedString(NSAttributedString(string: nextText, attributes: baseAttributes()))
        }
        invalidateFindResultsAfterTextChange()
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
        invalidateRenderingAttributes(for: fullRange)
    }

    func applyBaseForegroundColorChange(
        from previousColorTheme: SyntaxEditorColorTheme,
        to colorTheme: SyntaxEditorColorTheme
    ) {
        let textRange = NSRange(location: 0, length: storage.length)
        guard textRange.length > 0 else { return }

        let previousBaseForeground = resolvedSyntaxColor(previousColorTheme.baseForeground)
        let nextBaseForeground = resolvedSyntaxColor(colorTheme.baseForeground)
        var rangesToUpdate: [NSRange] = []
        unsafe storage.enumerateAttribute(.foregroundColor, in: textRange) { value, range, _ in
            guard let color = value as? UIColor,
                  color.isEqual(previousBaseForeground)
            else {
                return
            }
            rangesToUpdate.append(range)
        }

        guard !rangesToUpdate.isEmpty else { return }

        storage.beginEditing()
        for range in rangesToUpdate {
            storage.addAttribute(.foregroundColor, value: nextBaseForeground, range: range)
        }
        storage.endEditing()
        invalidateRenderingAttributes(for: textRange)
    }

    func applyUserReplacement(
        in range: NSRange,
        replacement: String,
        deletionIntent: EditorCommandEngine.DeletionIntent,
        allowsCommandTransform: Bool = true
    ) {
        guard configuration.isEditable else {
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
               language: configuration.language,
               deletionIntent: deletionIntent
           ) {
            applyCommandResult(result)
            return
        }

        let nextSelection = NSRange(
            location: clampedRange.location + replacement.utf16.count,
            length: 0
        )

        commitEdits(
            [SyntaxEditorTextEdit(range: clampedRange, replacement: replacement)],
            selectedRange: nextSelection,
            refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                in: source,
                around: clampedRange.location
            )
        )
    }

    func replaceFindText(in range: NSRange, with replacement: String) {
        applyUserReplacement(
            in: range,
            replacement: replacement,
            deletionIntent: .unspecified,
            allowsCommandTransform: false
        )
    }

    @discardableResult
    func replaceAllFindMatches(
        queryString: String,
        compareOptions: NSString.CompareOptions,
        wordMatchMethod: UITextSearchOptions.WordMatchMethod,
        with replacement: String
    ) -> Bool {
        guard configuration.isEditable else { return false }

        let source = text
        let ranges = SyntaxEditorFindCoordinator.searchRanges(
            in: source,
            queryString: queryString,
            compareOptions: compareOptions,
            wordMatchMethod: wordMatchMethod
        )
        guard let firstRange = ranges.first else { return false }

        let edits = ranges.map {
            SyntaxEditorTextEdit(range: $0, replacement: replacement)
        }
        let nextTextLength = source.utf16.count + ranges.reduce(0) { total, range in
            total + replacement.utf16.count - range.length
        }

        let selectionLocation = min(
            firstRange.location + replacement.utf16.count,
            nextTextLength
        )
        let refreshStartUTF16 = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
            in: source,
            around: selectionLocation
        )
        commitEdits(
            edits,
            selectedRange: NSRange(location: selectionLocation, length: 0),
            refreshStartUTF16: refreshStartUTF16
        )
        return true
    }

    func replaceDocumentText(_ nextText: String) {
        let previousText = text
        guard previousText != nextText else {
            updateTypingAttributes()
            return
        }

        isApplyingModel = true
        defer {
            isApplyingModel = false
        }

        commandEngine.invalidateTransientState()
        let change = document.replaceText(
            nextText,
            selectedRange: clampedTextRange(selectedRange, in: nextText)
        )
        lastAppliedDocumentRevision = change.revision
        replaceEntireStorageText(nextText)
        updateTypingAttributes()
        updateTextContainerForCurrentWrappingMode()
        invalidateTextLayout()
        scheduleHighlight(
            source: nextText,
            language: configuration.language,
            revision: change.revision,
            refreshStartUTF16: 0
        )
        refreshKeyboardAccessoryState()
    }

    func commitEdits(
        _ edits: [SyntaxEditorTextEdit],
        selectedRange nextSelection: NSRange,
        refreshStartUTF16: Int,
        registersUndo: Bool = true,
        preservesMarkedTextUndoAnchor: Bool = false,
        preservesCommandState: Bool = false,
        notifiesInputDelegate: Bool = true
    ) {
        guard configuration.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        guard !edits.isEmpty else {
            setSelectedRange(
                clampedTextRange(nextSelection),
                preservesCommandState: preservesCommandState,
                schedulesSelectionScroll: true
            )
            applyMatchingBracketHighlight()
            refreshKeyboardAccessoryState()
            return
        }

        let previousText = text
        let previousSelection = selectedRange

        if registersUndo, !isApplyingUndoRedo {
            registerUndoAction(
                restore: EditorUndoState(
                    edits: SyntaxEditorDocument.inverseEdits(for: edits, in: previousText),
                    selectedRange: previousSelection,
                    refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                        in: previousText,
                        around: refreshStartUTF16
                    )
                ),
                counterpart: EditorUndoState(
                    edits: edits,
                    selectedRange: nextSelection,
                    refreshStartUTF16: refreshStartUTF16
                )
            )
        }

        isApplyingModel = true
        if notifiesInputDelegate {
            inputDelegate?.textWillChange(self)
            inputDelegate?.selectionWillChange(self)
        }

        performWithoutUndoRegistration {
            performRawEdits(
                edits,
                previousText: previousText,
                preservesMarkedTextUndoAnchor: preservesMarkedTextUndoAnchor
            )
        }

        let change = document.commitEdits(
            edits,
            selectedRange: nextSelection,
            isWholeDocumentReplacement: false
        )
        lastAppliedDocumentRevision = change.revision
        let nextText = document.textSnapshot()
        currentSelectedRange = clampedTextRange(nextSelection, in: nextText)
        syncTextLayoutSelection()
        updateTypingAttributes()
        updateTextContainerForCurrentWrappingMode()
        invalidateTextLayout()
        layoutAndScrollSelectionForTextInputGeometry()
        isApplyingModel = false

        let refreshStart = min(
            refreshStartUTF16,
            edits.map(\.range.location).min() ?? refreshStartUTF16
        )
        scheduleHighlight(
            source: nextText,
            language: configuration.language,
            revision: change.revision,
            mutation: Self.highlightMutation(change),
            refreshStartUTF16: refreshStart
        )
        handleSelectionDidChange(preservesCommandState: preservesCommandState)

        if notifiesInputDelegate {
            inputDelegate?.selectionDidChange(self)
            inputDelegate?.textDidChange(self)
        }
        refreshKeyboardAccessoryState()
    }

    func performRawEdits(
        _ edits: [SyntaxEditorTextEdit],
        previousText: String,
        preservesMarkedTextUndoAnchor: Bool = false
    ) {
        textContentStorage.performEditingTransaction {
            for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
                if edit.replacement.isEmpty {
                    storage.replaceCharacters(in: edit.range, with: "")
                } else {
                    storage.replaceCharacters(
                        in: edit.range,
                        with: NSAttributedString(string: edit.replacement, attributes: typingAttributes)
                    )
                }
            }
        }
        lineMetricsIndex.apply(edits: edits, previousSource: previousText)
        invalidateFindResultsAfterTextChange()
        if !preservesMarkedTextUndoAnchor {
            markedTextUndoAnchor = nil
        }
        markedRange = nil
        invalidateTextLayout()
    }

    func applyCommandResult(_ result: EditorCommandResult) {
        guard configuration.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        commitEdits(
            result.edits,
            selectedRange: result.selectedRange,
            refreshStartUTF16: result.refreshStartUTF16,
            preservesCommandState: true
        )
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
        guard configuration.isEditable else {
            return
        }

        registerUndoAction(restore: counterpart, counterpart: restore)

        isApplyingUndoRedo = true
        applyCommandResult(
            EditorCommandResult(
                edits: restore.edits,
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

        performRawEdits(
            [SyntaxEditorTextEdit(range: mutation.range, replacement: mutation.replacement)],
            previousText: previousText
        )
        return mutation
    }

    @objc private func handleIndentCommand() {
        guard configuration.isEditable else { return }

        guard let result = commandEngine.indentSelection(
            source: text,
            selection: selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleInsertTabCommand() {
        guard configuration.isEditable else { return }

        guard let result = commandEngine.insertTab(
            source: text,
            selection: selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleOutdentCommand() {
        guard configuration.isEditable else { return }

        guard let result = commandEngine.outdentSelection(
            source: text,
            selection: selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleToggleCommentCommand() {
        guard configuration.isEditable else { return }

        guard let result = commandEngine.toggleComment(
            source: text,
            selection: selectedRange,
            language: configuration.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handlePasteCommand() {
        paste(nil)
    }

    @objc private func handleToggleLineWrappingCommand() {
        configuration.lineWrappingEnabled.toggle()
    }

    @objc private func handleUndoCommand() {
        guard configuration.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        activeUndoManager?.undo()
        refreshKeyboardAccessoryState()
    }

    @objc private func handleRedoCommand() {
        guard configuration.isEditable else {
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
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        mutation: SyntaxHighlightMutation? = nil,
        refreshStartUTF16 _: Int = 0
    ) {
        let expectedSource = source

        highlightTask?.cancel()

        let highlighter = self.highlighter
        highlightTask = Task { [weak self] in
            let result: SyntaxHighlightResult
            if let mutation {
                result = await highlighter.update(
                    source: expectedSource,
                    language: language,
                    mutation: mutation,
                    revision: revision
                )
            } else {
                result = await highlighter.reset(
                    source: expectedSource,
                    language: language,
                    revision: revision
                )
            }
            guard let self else { return }
            guard !Task.isCancelled else {
                return
            }
            guard self.document.revision == result.revision else {
                return
            }
            let refreshRange = self.highlightApplicationRefreshRange(
                for: result,
                mutation: mutation
            )
            self.applyHighlight(
                result.tokens,
                expectedRevision: result.revision,
                source: result.source,
                refreshRange: refreshRange
            )
            self.lastHighlightTokens = result.tokens
            self.lastHighlightRevision = result.revision
            self.lastHighlightLanguage = result.language
        }
    }

    func highlightApplicationRefreshRange(
        for result: SyntaxHighlightResult,
        mutation: SyntaxHighlightMutation?
    ) -> NSRange {
        guard mutation != nil else {
            return result.refreshRange
        }

        guard lastHighlightRevision == result.revision - 1,
              lastHighlightLanguage == result.language
        else {
            return NSRange(location: 0, length: result.source.utf16.count)
        }

        return result.refreshRange
    }

    func reapplyCachedHighlight() {
        let source = text
        guard lastHighlightRevision == document.revision, lastHighlightLanguage == configuration.language else {
            scheduleHighlight(source: source, language: configuration.language, revision: document.revision)
            return
        }

        applyHighlight(
            lastHighlightTokens,
            expectedRevision: document.revision,
            source: source,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }

    static func highlightMutation(_ change: SyntaxEditorDocumentChange) -> SyntaxHighlightMutation? {
        guard change.edits.count == 1, let edit = change.edits.first else { return nil }
        return SyntaxHighlightMutation(
            location: edit.range.location,
            length: edit.range.length,
            replacement: edit.replacement
        )
    }

    func applyHighlight(
        _ tokens: [SyntaxHighlightToken],
        expectedRevision: Int,
        source expectedSource: String,
        refreshRange: NSRange
    ) {
        guard document.revision == expectedRevision else { return }

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
        invalidateRenderingAttributes(for: targetRange)
        applyMarkedTextAttributes()
        updateTypingAttributes()
        applyMatchingBracketHighlight(force: true)
        setNeedsDisplayForVisibleTextFragments()
    }

    func reapplyTextAttributes(in range: NSRange) {
        let textLength = text.utf16.count
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
        guard targetRange.length > 0 else { return }

        if lastHighlightRevision == document.revision, lastHighlightLanguage == configuration.language {
            applyHighlight(
                lastHighlightTokens,
                expectedRevision: document.revision,
                source: text,
                refreshRange: targetRange
            )
        } else {
            storage.beginEditing()
            storage.setAttributes(baseAttributes(), range: targetRange)
            storage.endEditing()
            invalidateRenderingAttributes(for: targetRange)
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
        invalidateRenderingAttributes(for: targetRange)
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
            .foregroundColor: resolvedSyntaxColor(lastAppliedColorTheme.baseForeground),
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
        return [.foregroundColor: resolvedSyntaxColor(color)]
    }

    func resolvedSyntaxColor(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: traitCollection)
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
        if !lastAppliedLineWrappingEnabled {
            let horizontalInset = textContainerInset.left + textContainerInset.right
            return CGSize(
                width: max(0, measuredHorizontalDocumentLayoutWidth() - horizontalInset),
                height: CGFloat(lineMetricsIndex.lineCount) * font.lineHeight
            )
        }

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

    func updateFindHighlightFragmentViews() {
        findHighlightUpdatePassCount += 1
        for case let fragmentView as SyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            configureFindHighlights(for: fragmentView, layoutFragmentFrame: fragmentView.layoutFragment.layoutFragmentFrame)
        }
    }

    func configureFindHighlights(
        for fragmentView: SyntaxEditorTextLayoutFragmentView,
        layoutFragmentFrame: CGRect
    ) {
        let foundRects: [CGRect]
        let highlightedRects: [CGRect]
        if findFoundRanges.isEmpty && findHighlightedRanges.isEmpty {
            foundRects = []
            highlightedRects = []
        } else {
            let fragmentRange = textRange(for: fragmentView.layoutFragment)
            foundRects = textHighlightRects(
                in: layoutFragmentFrame,
                ranges: Self.ranges(findFoundRanges, intersecting: fragmentRange)
            )
            highlightedRects = textHighlightRects(
                in: layoutFragmentFrame,
                ranges: Self.ranges(findHighlightedRanges, intersecting: fragmentRange)
            )
        }
        let foundColor = foundRects.isEmpty
            ? nil
            : UIColor
                .syntaxEditorAlpha(.systemYellow, alpha: 0.28)
                .resolvedColor(with: traitCollection)
                .cgColor
        let highlightedColor = highlightedRects.isEmpty
            ? nil
            : UIColor
                .syntaxEditorAlpha(.systemOrange, alpha: 0.42)
                .resolvedColor(with: traitCollection)
                .cgColor

        let foundChanged = fragmentView.findHighlightRects != foundRects
            || !Self.optionalColorsEqual(fragmentView.findHighlightColor, foundColor)
        let highlightedChanged = fragmentView.currentFindHighlightRects != highlightedRects
            || !Self.optionalColorsEqual(fragmentView.currentFindHighlightColor, highlightedColor)

        fragmentView.findHighlightRects = foundRects
        fragmentView.findHighlightColor = foundColor
        fragmentView.currentFindHighlightRects = highlightedRects
        fragmentView.currentFindHighlightColor = highlightedColor
        if foundChanged || highlightedChanged {
            fragmentView.setNeedsDisplay()
        }
    }

    func configureBracketHighlights(
        for fragmentView: SyntaxEditorTextLayoutFragmentView,
        layoutFragmentFrame: CGRect
    ) {
        let rects: [CGRect]
        if matchedBracketRanges.isEmpty {
            rects = []
        } else {
            let fragmentRange = textRange(for: fragmentView.layoutFragment)
            rects = textHighlightRects(
                in: layoutFragmentFrame,
                ranges: Self.ranges(matchedBracketRanges, intersecting: fragmentRange)
            )
        }
        let color = rects.isEmpty
            ? nil
            : UIColor
                .syntaxEditorAlpha(lastAppliedColorTheme.bracketBackground, alpha: 0.24)
                .resolvedColor(with: traitCollection)
                .cgColor
        let colorChanged = !Self.optionalColorsEqual(fragmentView.bracketHighlightColor, color)
        let rectsChanged = fragmentView.bracketHighlightRects != rects

        fragmentView.bracketHighlightRects = rects
        fragmentView.bracketHighlightColor = color
        if rectsChanged || colorChanged {
            fragmentView.setNeedsDisplay()
        }
    }

    func textRange(for layoutFragment: NSTextLayoutFragment) -> NSRange {
        let fragmentStart = utf16Offset(for: layoutFragment.rangeInElement.location)
        let fragmentEnd = utf16Offset(for: layoutFragment.rangeInElement.endLocation)
        return NSRange(location: fragmentStart, length: max(0, fragmentEnd - fragmentStart))
    }

    static func ranges(_ ranges: [NSRange], intersecting fragmentRange: NSRange) -> [NSRange] {
        guard !ranges.isEmpty, fragmentRange.length > 0 else { return [] }
        return ranges.compactMap { range in
            let intersection = NSIntersectionRange(range, fragmentRange)
            return intersection.length > 0 ? intersection : nil
        }
    }

    static func optionalColorsEqual(_ lhs: CGColor?, _ rhs: CGColor?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            true
        case let (.some(lhs), .some(rhs)):
            CFEqual(lhs, rhs)
        default:
            false
        }
    }

    func textHighlightRects(in layoutFragmentFrame: CGRect, ranges: [NSRange]) -> [CGRect] {
        guard !ranges.isEmpty else { return [] }

        let fragmentLocalBounds = CGRect(origin: .zero, size: layoutFragmentFrame.size)
        var rects: [CGRect] = []
        for nsRange in ranges {
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

    func decorateFindTextRange(_ range: NSRange, style: UITextSearchFoundTextStyle) {
        let clampedRange = clampedTextRange(range)
        guard clampedRange.length > 0 else { return }

        switch style {
        case .normal:
            guard findFoundRanges.contains(clampedRange) || findHighlightedRanges.contains(clampedRange) else {
                return
            }
            findFoundRanges.removeAll { $0 == clampedRange }
            findHighlightedRanges.removeAll { $0 == clampedRange }
        case .found:
            guard !findFoundRanges.contains(clampedRange) || findHighlightedRanges.contains(clampedRange) else {
                return
            }
            findFoundRanges.removeAll { $0 == clampedRange }
            findHighlightedRanges.removeAll { $0 == clampedRange }
            findFoundRanges.append(clampedRange)
        case .highlighted:
            guard findFoundRanges.contains(clampedRange) || !findHighlightedRanges.contains(clampedRange) else {
                return
            }
            findFoundRanges.removeAll { $0 == clampedRange }
            findHighlightedRanges.removeAll { $0 == clampedRange }
            findHighlightedRanges.append(clampedRange)
        @unknown default:
            guard !findFoundRanges.contains(clampedRange) || findHighlightedRanges.contains(clampedRange) else {
                return
            }
            findFoundRanges.removeAll { $0 == clampedRange }
            findHighlightedRanges.removeAll { $0 == clampedRange }
            findFoundRanges.append(clampedRange)
        }

        invalidateFindDecorationRanges([clampedRange])
    }

    func clearFindDecorations() {
        let previousRanges = findFoundRanges + findHighlightedRanges
        guard !previousRanges.isEmpty else { return }

        findFoundRanges.removeAll()
        findHighlightedRanges.removeAll()
        invalidateFindDecorationRanges(previousRanges)
    }

    func beginFindDecorationBatch() {
        findDecorationBatchDepth += 1
    }

    func endFindDecorationBatch() {
        guard findDecorationBatchDepth > 0 else { return }
        findDecorationBatchDepth -= 1
        guard findDecorationBatchDepth == 0 else { return }

        let ranges = pendingFindDecorationInvalidationRanges
        pendingFindDecorationInvalidationRanges.removeAll(keepingCapacity: true)
        guard !ranges.isEmpty else { return }

        setNeedsDisplayForTextRanges(ranges)
        updateFindHighlightFragmentViews()
    }

    func invalidateFindDecorationRanges(_ ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }

        if findDecorationBatchDepth > 0 {
            pendingFindDecorationInvalidationRanges.append(contentsOf: ranges)
        } else {
            setNeedsDisplayForTextRanges(ranges)
            updateFindHighlightFragmentViews()
        }
    }

    func invalidateFindResultsAfterTextChange() {
        clearFindDecorations()
        findCoordinator?.invalidateResultsAfterTextChange()
    }

    func measuredHorizontalDocumentLayoutWidth() -> CGFloat {
        guard !text.isEmpty else {
            return bounds.width
        }

        return max(
            bounds.width,
            lineMetricsIndex.horizontalDocumentWidth(
                columnWidth: Self.estimatedMonospacedColumnWidth(for: font),
                textContainerInset: textContainerInset.left + textContainerInset.right,
                lineFragmentPadding: container.lineFragmentPadding
            )
        )
    }

    static func estimatedMonospacedColumnWidth(for font: UIFont) -> CGFloat {
        font.pointSize * 0.65
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

    func invalidateRenderingAttributes(for range: NSRange) {
        guard let textRange = textRange(forUTF16Range: range) else { return }
        layoutManager.invalidateRenderingAttributes(for: textRange)
    }

    func invalidateHorizontalMeasurement() {
        setNeedsLayout()
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
        setNeedsDisplayForTextRanges(ranges)
    }

    func setNeedsDisplayForTextRanges(_ ranges: [NSRange]) {
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
        configureFindHighlights(for: fragmentView, layoutFragmentFrame: layoutFragmentFrame)
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

        if !isLayingOutText {
            updateContentSizeIfNeeded()
        }
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
        clampedTextRange(range, utf16Length: storage.length)
    }

    func clampedTextRange(_ range: NSRange, in source: String) -> NSRange {
        clampedTextRange(range, utf16Length: source.utf16.count)
    }

    func clampedTextRange(_ range: NSRange, utf16Length: Int) -> NSRange {
        let location = min(max(0, range.location), utf16Length)
        let length = min(max(0, range.length), utf16Length - location)
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
