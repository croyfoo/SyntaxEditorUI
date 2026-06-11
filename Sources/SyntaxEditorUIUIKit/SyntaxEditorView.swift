#if canImport(UIKit)
import ObservationBridge
import SyntaxEditorCore
import SyntaxEditorUICommon
import UIKit

struct SyntaxEditorMarkedTextUndoAnchor {
    let source: String
    let selectedRange: NSRange
    let refreshStartUTF16: Int
}

private struct SyntaxHighlightAttributeKey: Hashable {
    let syntaxID: EditorSourceSyntaxID
    let language: SyntaxLanguage
}

private struct SyntaxHighlightStyle {
    let foregroundColor: UIColor
    let font: UIFont
}

private struct ScheduledHighlightRequest {
    let id: Int
    let model: SyntaxEditorModel
    let language: SyntaxLanguage
    let revision: Int
    let mutation: SyntaxHighlightMutation?
}

private struct HighlightPhaseRecord: Equatable {
    let revision: Int
    let phase: SyntaxHighlightPhase
}

private struct HighlightPhaseWaiter {
    let id: Int
    let revision: Int
    let phase: SyntaxHighlightPhase
    let continuation: CheckedContinuation<Bool, Never>
}

private struct SyntaxHighlightAttributeResolver {
    let theme: SyntaxEditorTheme
    let defaultLanguage: SyntaxLanguage
    let appearance: SyntaxEditorThemeAppearance
    let fontSizeDelta: Int
    let resolveColor: (UIColor) -> UIColor

    private var styleCache: [SyntaxHighlightAttributeKey: SyntaxHighlightStyle] = [:]
    private var missingAttributeKeys: Set<SyntaxHighlightAttributeKey> = []
    private var fontCache: [SyntaxEditorFontDescriptor: UIFont] = [:]

    init(
        theme: SyntaxEditorTheme,
        defaultLanguage: SyntaxLanguage,
        appearance: SyntaxEditorThemeAppearance,
        fontSizeDelta: Int,
        resolveColor: @escaping (UIColor) -> UIColor
    ) {
        self.theme = theme
        self.defaultLanguage = defaultLanguage
        self.appearance = appearance
        self.fontSizeDelta = fontSizeDelta
        self.resolveColor = resolveColor
    }

    mutating func style(
        for syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage?
    ) -> (key: SyntaxHighlightAttributeKey, style: SyntaxHighlightStyle)? {
        let effectiveLanguage = language ?? defaultLanguage
        let key = SyntaxHighlightAttributeKey(syntaxID: syntaxID, language: effectiveLanguage)

        if let cached = styleCache[key] {
            return (key, cached)
        }
        guard !missingAttributeKeys.contains(key) else {
            return nil
        }

        guard let style = SyntaxEditorHighlightTheme.style(
            for: syntaxID,
            in: theme,
            language: effectiveLanguage,
            appearance: appearance
        ) else {
            missingAttributeKeys.insert(key)
            return nil
        }

        let resolvedStyle = SyntaxHighlightStyle(
            foregroundColor: resolveColor(style.foreground),
            font: platformFont(for: style.font)
        )
        styleCache[key] = resolvedStyle
        return (key, resolvedStyle)
    }

    private mutating func platformFont(for descriptor: SyntaxEditorFontDescriptor) -> UIFont {
        if let cached = fontCache[descriptor] {
            return cached
        }
        let font = descriptor.platformFont(fontSizeDelta: fontSizeDelta)
        fontCache[descriptor] = font
        return font
    }
}

@MainActor
public final class SyntaxEditorView: UIScrollView, UITextInput, UITextInputTraits, UITextInteractionDelegate, @preconcurrency NSTextViewportLayoutControllerDelegate {
    public private(set) var model: SyntaxEditorModel

    let guardedUndoManager = SyntaxEditorReadOnlyGuardedUndoManager()
    let textSystem = EditorTextSystem()
    var textContentStorage: NSTextContentStorage { textSystem.textContentStorage }
    var layoutManager: NSTextLayoutManager { textSystem.layoutManager }
    var container: NSTextContainer { textSystem.container }
    var highlightStyleStore: HighlightRenderSnapshotStore { textSystem.styleStore }
    let textContentView = SyntaxEditorTextContentView()
    let editableTextInteraction = UITextInteraction(for: .editable)
    let nonEditableTextInteraction = UITextInteraction(for: .nonEditable)
    var findCoordinator: SyntaxEditorFindCoordinator?
    static let estimatedTabColumnWidth = 4

    let highlighter: any SyntaxHighlighting
    let commandEngine = EditorCommandEngine()
    var highlightTask: Task<Void, Never>?
    private var scheduledHighlightRequest: ScheduledHighlightRequest?
    private var nextScheduledHighlightRequestID = 0
    var lastHighlightTokens: [SyntaxHighlightToken] = []
    var lastHighlightSource: String?
    var lastHighlightRevision: Int?
    var lastHighlightLanguage: SyntaxLanguage?
    private var materializedHighlightPhase: SyntaxHighlightPhase?
    private var materializedHighlightRevision: Int?
    private var materializedHighlightLanguage: SyntaxLanguage?
    private var appliedHighlightPhaseRecordsForTesting: [HighlightPhaseRecord] = []
    private var appliedHighlightPhaseWaitersForTesting: [HighlightPhaseWaiter] = []
    private var skippedHighlightPhaseRecordsForTesting: [HighlightPhaseRecord] = []
    private var skippedHighlightPhaseWaitersForTesting: [HighlightPhaseWaiter] = []
    private var nextHighlightPhaseWaiterID = 0
    var isApplyingModel = false
    var isApplyingHighlight = false
    var isApplyingUndoRedo = false
    var isApplyingCommandSelection = false
    var lastAppliedLanguageIdentifier: String?
    var matchedBracketRanges: [NSRange] = []
    var lastAppliedLineWrappingEnabled: Bool
    var lastAppliedTheme: SyntaxEditorTheme
    var lastAppliedThemeAppearance: SyntaxEditorThemeAppearance?
    var lastAppliedFontSizeDelta: Int
    var isApplyingEditorOwnedScroll = false
    var isIgnoringTextInteractionHorizontalOffsetPreservation = false
    var preservedTextInteractionHorizontalOffset: CGFloat?
    var textInteractionHorizontalOffsetLockGeneration = 0
    var lineMetrics = DocumentLineMetrics(tabWidth: SyntaxEditorView.estimatedTabColumnWidth)
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
    let modelObservations = ObservationScope()
    var modelDeliveryForTesting: ObservationDelivery?
    var modelConfigurationDeliveryForTesting: ObservationDelivery?
    var storage: NSTextStorage {
        textSystem.textStorage
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

    internal func syntaxForegroundColorForTesting(at location: Int) -> UIColor? {
        guard location >= 0,
              location < storage.length
        else {
            return nil
        }
        return highlightStyleStore.foregroundColor(at: location)
    }

    internal func syntaxFontForTesting(at location: Int) -> UIFont? {
        guard location >= 0,
              location < storage.length
        else {
            return nil
        }
        return highlightStyleStore.font(at: location)
    }

    internal func baseForegroundColorForTesting() -> UIColor? {
        highlightStyleStore.baseForeground
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

    var font: UIFont {
        resolvedBaseFont()
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
        model: SyntaxEditorModel
    ) {
        self.init(model: model, highlighter: SyntaxHighlighterEngine())
    }

    package init(
        model: SyntaxEditorModel,
        highlighter: any SyntaxHighlighting
    ) {
        self.model = model
        self.highlighter = highlighter
        self.lastAppliedLineWrappingEnabled = model.lineWrappingEnabled
        self.lastAppliedTheme = model.theme
        self.lastAppliedThemeAppearance = nil
        self.lastAppliedFontSizeDelta = model.fontSizeDelta
        self.lastAppliedDocumentRevision = model.revision
        self.lastAppliedLanguageIdentifier = model.language.syntaxHighlightCacheKey

        super.init(frame: .zero)

        configureTextSystem()
        configureScrollView()
        configureUndoObservation()
        configureTraitChangeObservation()
        startModelObservation(schedulesInitialHighlight: false)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        highlightTask?.cancel()
        modelObservations.cancelAll()
        NotificationCenter.default.removeObserver(self)
    }

    public func update(model nextModel: SyntaxEditorModel) {
        guard model !== nextModel else { return }

        modelObservations.cancelAll()
        activeUndoManager?.removeAllActions()
        commandEngine.invalidateTransientState()
        clearHighlightCache()
        model = nextModel
        synchronizeReboundModel()
        refreshKeyboardAccessoryState()
        startModelObservation(schedulesInitialHighlight: false, skipsInitialModelDelivery: true)
    }

    public override var undoManager: UndoManager? {
        guardedUndoManager
    }

    public override var inputAccessoryView: UIView? {
        keyboardAccessoryView
    }

    internal func synchronizeDocumentForTesting() {
        applyObservedConfiguration(
            language: model.language,
            isEditable: model.isEditable,
            lineWrappingEnabled: model.lineWrappingEnabled,
            theme: model.theme,
            drawsBackground: model.drawsBackground,
            fontSizeDelta: model.fontSizeDelta
        )
        applyObservedModelChange(forceTextUpdate: text != model.text)
        applyObservedSelection(model.selectedRange)
    }

    @discardableResult
    internal func waitForPendingHighlightForTesting() async -> Bool {
        // Deterministic: a result that cannot apply yet (payload gating,
        // revision races) reschedules and lets its task complete unapplied, so
        // follow reschedules by generation until a waited task finishes
        // without scheduling a successor. No wall-clock is involved — a
        // pipeline that never settles is a real bug and surfaces as the
        // suite's time limit, never as a racy early false.
        while true {
            guard let task = highlightTask else { return true }
            let generation = nextScheduledHighlightRequestID
            await task.value
            if nextScheduledHighlightRequestID == generation {
                return true
            }
        }
    }

    internal func waitForAppliedHighlightPhaseForTesting(
        _ phase: SyntaxHighlightPhase
    ) async -> Bool {
        let expectedRevision = model.revision
        guard !hasAppliedHighlightPhaseForTesting(phase, revision: expectedRevision) else {
            return true
        }

        let waiterID = nextHighlightPhaseWaiterID
        nextHighlightPhaseWaiterID += 1
        return await withCheckedContinuation { continuation in
            appliedHighlightPhaseWaitersForTesting.append(
                HighlightPhaseWaiter(
                    id: waiterID,
                    revision: expectedRevision,
                    phase: phase,
                    continuation: continuation
                )
            )
        }
    }

    internal func waitForSkippedHighlightPhaseForTesting(
        _ phase: SyntaxHighlightPhase
    ) async -> Bool {
        let expectedRevision = model.revision
        guard !hasSkippedHighlightPhaseForTesting(phase, revision: expectedRevision) else {
            return true
        }

        let waiterID = nextHighlightPhaseWaiterID
        nextHighlightPhaseWaiterID += 1
        return await withCheckedContinuation { continuation in
            skippedHighlightPhaseWaitersForTesting.append(
                HighlightPhaseWaiter(
                    id: waiterID,
                    revision: expectedRevision,
                    phase: phase,
                    continuation: continuation
                )
            )
        }
    }

    internal func setApplyingHighlightForTesting(_ isApplying: Bool) {
        isApplyingHighlight = isApplying
    }

    internal var lineMetricsFullRebuildCountForTesting: Int {
        lineMetrics.fullRebuildCount
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

        if isLineWrappingCommandAction(action) {
            return true
        }

        if isFontSizeCommandAction(action) {
            return true
        }

        if action == #selector(handlePasteCommand) {
            return model.isEditable
        }

        if action == #selector(handleInsertTabCommand) {
            return model.isEditable
        }

        if isEditorCommandAction(action) {
            return model.isEditable && model.language.supportsCodeEditingCommands
        }

        switch action {
        case #selector(UIResponderStandardEditActions.useSelectionForFind(_:)):
            return isFindInteractionEnabled && findInteraction != nil && selectedRange.length > 0
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
            if isFindAndReplaceCommandAction(action) {
                return model.isEditable && isFindInteractionEnabled && findInteraction != nil
            }
            if isFindCommandAction(action) {
                return isFindInteractionEnabled && findInteraction != nil
            }
            return super.canPerformAction(action, withSender: sender)
        }
    }

    public override func validate(_ command: UICommand) {
        super.validate(command)

        guard let editorCommand = SyntaxEditorMenuCommand(selector: command.action) else {
            return
        }

        command.attributes = canPerformAction(command.action, withSender: command) ? [] : .disabled
        command.state = editorCommand == .wrapLines && model.lineWrappingEnabled ? .on : .off
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
        insertPastedText(pastedText)
    }

    func insertPastedText(_ pastedText: String) {
        guard model.isEditable else { return }
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

    public override func find(_ sender: Any?) {
        findInteraction?.presentFindNavigator(showingReplace: false)
    }

    public override func findAndReplace(_ sender: Any?) {
        guard model.isEditable else { return }
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
        layoutManager.textViewportLayoutController.delegate = self
        configureSyntaxRenderingAttributesValidator()

        addSubview(textContentView)

        editableTextInteraction.textInput = self
        editableTextInteraction.delegate = self
        nonEditableTextInteraction.textInput = self
        nonEditableTextInteraction.delegate = self
        updateTextInteractions()
        updateFindInteraction()

        guardedUndoManager.allowsMutation = { [weak self] in
            self?.model.isEditable ?? true
        }
    }

    private func configureSyntaxRenderingAttributesValidator() {
        layoutManager.renderingAttributesValidator = { [weak self] textLayoutManager, textLayoutFragment in
            MainActor.assumeIsolated {
                self?.validateSyntaxRenderingAttributes(
                    in: textLayoutFragment,
                    using: textLayoutManager
                )
            }
        }
    }

    private func validateSyntaxRenderingAttributes(
        in textLayoutFragment: NSTextLayoutFragment,
        using textLayoutManager: NSTextLayoutManager
    ) {
        let fragmentRange = textRange(for: textLayoutFragment)
        guard fragmentRange.length > 0 else { return }

        guard let targetTextRange = textRange(forUTF16Range: fragmentRange) else { return }
        if let baseForeground = typingAttributes[.foregroundColor] as? UIColor {
            textLayoutManager.addRenderingAttribute(
                .foregroundColor,
                value: baseForeground,
                for: targetTextRange
            )
        }

        let resolvedRuns = highlightStyleStore.resolveVisibleRuns(in: fragmentRange)
        for colorRun in resolvedRuns.colorRuns {
            guard let textRange = textRange(forUTF16Range: colorRun.range) else { continue }
            textLayoutManager.addRenderingAttribute(
                .foregroundColor,
                value: colorRun.color,
                for: textRange
            )
        }

        for fontRun in resolvedRuns.fontRuns {
            guard let textRange = textRange(forUTF16Range: fontRun.range) else { continue }
            textLayoutManager.addRenderingAttribute(
                .font,
                value: fontRun.font,
                for: textRange
            )
        }
    }

    func configureScrollView() {
        updateEditorBackgroundColor()
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
        let previousAppearance = lastAppliedThemeAppearance ?? currentThemeAppearance
        let nextAppearance = currentThemeAppearance
        let theme = lastAppliedTheme
        let baseFontChanged = !resolvedBaseFont(
            for: theme.resolved(for: model.language, appearance: previousAppearance),
            fontSizeDelta: lastAppliedFontSizeDelta
        ).isEqual(resolvedBaseFont(
            for: theme.resolved(for: model.language, appearance: nextAppearance),
            fontSizeDelta: lastAppliedFontSizeDelta
        ))
        lastAppliedThemeAppearance = nextAppearance

        updateEditorBackgroundColor()
        invalidateHorizontalMeasurement()
        applyBaseForegroundColorChange(from: theme, to: theme)
        updateTypingAttributes()
        if baseFontChanged {
            applyResolvedFontsToExistingText()
        }
        reapplyCachedHighlight()
        updateFindHighlightFragmentViews()
        updateBracketHighlightFragmentViews()
        updateTextContainerForCurrentWrappingMode()
        invalidateTextLayout()
    }

    func editorKeyCommands() -> [UIKeyCommand]? {
        let supportsCodeEditingCommands = model.isEditable && model.language.supportsCodeEditingCommands
        var commands = SyntaxEditorMenu.makeKeyCommands(includeEditingCommands: supportsCodeEditingCommands)

        guard model.isEditable else {
            return commands
        }

        commands.append(
            makeKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleInsertTabCommand), title: "Insert Tab")
        )

        if supportsCodeEditingCommands {
            commands.append(
                makeKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleOutdentCommand), title: "Outdent")
            )
        }

        commands.append(contentsOf: [
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
        if let command = SyntaxEditorMenuCommand(selector: action) {
            return command.isEditingCommand
        }

        return action == #selector(handleInsertTabCommand)
            || action == #selector(handleOutdentCommand)
    }

    func isLineWrappingCommandAction(_ action: Selector) -> Bool {
        SyntaxEditorMenuCommand(selector: action) == .wrapLines
    }

    func isFontSizeCommandAction(_ action: Selector) -> Bool {
        switch SyntaxEditorMenuCommand(selector: action) {
        case .increaseFontSize, .decreaseFontSize, .resetFontSize:
            true
        case .shiftRight, .shiftLeft, .commentSelection, .wrapLines, nil:
            false
        }
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
        keyboardAccessoryModel.isUndoable = model.isEditable && (activeUndoManager?.canUndo ?? false)
        keyboardAccessoryModel.isRedoable = model.isEditable && (activeUndoManager?.canRedo ?? false)
    }

    var typingAttributes: [NSAttributedString.Key: Any] = [:]

    func updateTypingAttributes() {
        if let baseForeground = baseAttributes()[.foregroundColor] as? UIColor {
            highlightStyleStore.updateBaseForeground(baseForeground, textLength: storage.length)
        }
        typingAttributes = storageBaseAttributes()
    }

    func startModelObservation(
        schedulesInitialHighlight: Bool = true,
        skipsInitialModelDelivery: Bool = false
    ) {
        modelConfigurationDeliveryForTesting = modelObservations.observe(model, tracking: { model in
            _ = model.language
            _ = model.isEditable
            _ = model.lineWrappingEnabled
            _ = model.theme
            _ = model.drawsBackground
            _ = model.fontSizeDelta
        }) { [weak self] event, model in
            guard let self else { return }
            self.applyObservedConfiguration(
                language: model.language,
                isEditable: model.isEditable,
                lineWrappingEnabled: model.lineWrappingEnabled,
                theme: model.theme,
                drawsBackground: model.drawsBackground,
                fontSizeDelta: model.fontSizeDelta,
                forceLanguageRefresh: event.kind == .initial,
                schedulesHighlight: event.kind != .initial || schedulesInitialHighlight
            )
        }

        modelDeliveryForTesting = modelObservations.observe(model, tracking: { model in
            _ = model.text
            _ = model.revision
            _ = model.selectedRange
        }) { [weak self] event, model in
            guard let self else { return }
            guard !(skipsInitialModelDelivery && event.kind == .initial) else { return }
            self.applyObservedModelChange(
                forceTextUpdate: event.kind == .initial,
                observedRevision: model.revision
            )
            self.applyObservedSelection(model.selectedRange)
        }
    }

    private func synchronizeReboundModel() {
        applyObservedConfiguration(
            language: model.language,
            isEditable: model.isEditable,
            lineWrappingEnabled: model.lineWrappingEnabled,
            theme: model.theme,
            drawsBackground: model.drawsBackground,
            fontSizeDelta: model.fontSizeDelta,
            forceLanguageRefresh: true,
            schedulesHighlight: false
        )
        applyObservedModelChange(forceTextUpdate: true, observedRevision: model.revision)
        applyObservedSelection(model.selectedRange)
    }

    func applyObservedModelChange(forceTextUpdate: Bool = false, observedRevision: Int? = nil) {
        let revision = observedRevision ?? model.revision
        guard forceTextUpdate || revision != lastAppliedDocumentRevision else { return }

        isApplyingModel = true
        defer {
            isApplyingModel = false
        }

        let previousText = text
        let nextText = model.text
        let textNeedsUpdate = forceTextUpdate || previousText != nextText

        if textNeedsUpdate {
            commandEngine.invalidateTransientState()
            let change = model.latestChange
            if change?.kind == .replacement {
                activeUndoManager?.removeAllActions()
            }
            let previousSelection = selectedRange
            if let change,
               change.revision == revision,
               change.kind == .incremental,
               !forceTextUpdate,
               lastAppliedDocumentRevision == revision - 1 {
                performRawEdits(change.edits, previousText: previousText)
            } else {
                replaceEntireStorageText(nextText)
            }
            let nextSelection: NSRange
            if change?.kind == .replacement,
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
            let highlightMutation: SyntaxHighlightMutation? = if model.latestChange?.kind == .replacement {
                nil
            } else {
                model.latestChange.flatMap(Self.highlightMutation)
            }
            scheduleHighlight(
                source: nextText,
                language: model.language,
                revision: revision,
                mutation: highlightMutation,
                refreshStartUTF16: 0
            )
        } else {
            updateTypingAttributes()
        }

        lastAppliedDocumentRevision = revision
        refreshKeyboardAccessoryState()
    }

    func applyObservedSelection(_ range: NSRange) {
        let clamped = clampedTextRange(range)
        guard currentSelectedRange != clamped else { return }

        isApplyingModel = true
        defer {
            isApplyingModel = false
        }
        setSelectedRange(
            clamped,
            preservesCommandState: true,
            schedulesSelectionScroll: true
        )
    }

    func applyObservedConfiguration(
        language: SyntaxLanguage,
        isEditable: Bool,
        lineWrappingEnabled: Bool,
        theme: SyntaxEditorTheme,
        drawsBackground: Bool,
        fontSizeDelta: Int,
        forceLanguageRefresh: Bool = false,
        schedulesHighlight: Bool = true
    ) {
        let lineWrappingChanged = lastAppliedLineWrappingEnabled != lineWrappingEnabled
        lastAppliedLineWrappingEnabled = lineWrappingEnabled

        let previousTheme = lastAppliedTheme
        let themeChanged = previousTheme != theme
        let fontSizeDeltaChanged = lastAppliedFontSizeDelta != fontSizeDelta
        let appearance = currentThemeAppearance
        let previousBaseFont = resolvedBaseFont(
            for: previousTheme.resolved(for: language, appearance: appearance),
            fontSizeDelta: lastAppliedFontSizeDelta
        )
        let nextBaseFont = resolvedBaseFont(
            for: theme.resolved(for: language, appearance: appearance),
            fontSizeDelta: fontSizeDelta
        )
        let baseFontChanged = !previousBaseFont.isEqual(nextBaseFont)
        if themeChanged || fontSizeDeltaChanged {
            invalidateHorizontalMeasurement()
        }
        if themeChanged {
            applyBaseForegroundColorChange(from: previousTheme, to: theme)
        }
        lastAppliedTheme = theme
        lastAppliedThemeAppearance = appearance
        lastAppliedFontSizeDelta = fontSizeDelta
        updateEditorBackgroundColor(drawsBackground: drawsBackground)

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
        if baseFontChanged {
            applyResolvedFontsToExistingText()
        }
        if languageChanged && schedulesHighlight {
            scheduleHighlight(
                source: text,
                language: language,
                revision: model.revision,
                refreshStartUTF16: 0
            )
        } else if (themeChanged || fontSizeDeltaChanged) && schedulesHighlight {
            reapplyCachedHighlight()
        }
        refreshKeyboardAccessoryState()
        invalidateTextLayout()
    }

    func replaceEntireStorageText(_ nextText: String) {
        lineMetrics.reset(source: nextText)
        TextEditingTransaction.perform(on: textContentStorage) { storage in
            storage.setAttributedString(NSAttributedString(string: nextText, attributes: storageBaseAttributes()))
        }
        resetSyntaxHighlightRenderingState(textLength: nextText.utf16.count)
        invalidateFindResultsAfterTextChange()
        markedRange = nil
        markedTextUndoAnchor = nil
        syncTextLayoutSelection()
    }

    func applyResolvedFontsToExistingText() {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0,
              let baseFont = baseAttributes()[.font] as? UIFont
        else { return }

        let source = text

        TextEditingTransaction.perform(on: textContentStorage) { storage in
            storage.addAttribute(.font, value: baseFont, range: fullRange)
        }
        var didRecomputeSyntaxFontRuns = false
        if hasReusableRecordedHighlightSnapshot(
            source: source,
            language: model.language,
            revision: model.revision
        ),
           let baseForeground = baseAttributes()[.foregroundColor] as? UIColor {
            var resolver = makeSyntaxHighlightAttributeResolver(baseAttributes: baseAttributes())
            let runSet = syntaxHighlightRunSet(
                for: lastHighlightTokens,
                renderRange: fullRange,
                textLength: storage.length,
                resolver: &resolver
            )
            highlightStyleStore.commitSnapshot(
                runSet: runSet,
                range: fullRange,
                revision: model.revision,
                language: model.language,
                textLength: storage.length,
                baseForeground: baseForeground,
                baseFont: baseFont,
                suppressionRanges: foregroundSuppressionRanges(textLength: storage.length)
            )
            invalidateSyntaxRenderingAttributes(for: [fullRange])
            didRecomputeSyntaxFontRuns = true
        }
        if !didRecomputeSyntaxFontRuns {
            let invalidatedFontRuns = highlightStyleStore.updateBaseFont(
                baseFont,
                textLength: storage.length,
                clearsFontRuns: true
            )
            invalidateSyntaxRenderingAttributes(for: invalidatedFontRuns)
        }
        invalidateTextLayout()
    }

    func applyBaseForegroundColorChange(
        from _: SyntaxEditorTheme,
        to theme: SyntaxEditorTheme
    ) {
        let nextBaseForeground = resolvedSyntaxColor(
            theme
                .resolved(for: model.language, appearance: currentThemeAppearance)
                .baseForeground
        )
        highlightStyleStore.updateBaseForeground(nextBaseForeground, textLength: storage.length)
        let fullRange = NSRange(location: 0, length: storage.length)
        if fullRange.length > 0 {
            TextEditingTransaction.perform(on: textContentStorage) { storage in
                storage.addAttribute(.foregroundColor, value: nextBaseForeground, range: fullRange)
            }
            invalidateSyntaxRenderingAttributes(for: [fullRange])
        }
        setNeedsDisplayForVisibleTextFragments()
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
        guard model.isEditable else { return false }

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
        let nextSelection = clampedTextRange(selectedRange, in: nextText)
        let change = model.replaceText(
            nextText,
            selectedRange: nextSelection
        )
        guard let change else {
            updateTypingAttributes()
            return
        }
        lastAppliedDocumentRevision = change.revision
        currentSelectedRange = change.selectedRange
        replaceEntireStorageText(nextText)
        updateTypingAttributes()
        updateTextContainerForCurrentWrappingMode()
        invalidateTextLayout()
        scheduleHighlight(
            source: nextText,
            language: model.language,
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
        guard model.isEditable else {
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
                    edits: SyntaxEditorModel.inverseEdits(for: edits, in: previousText),
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
        let shouldDeferSelectionGeometry = shouldDeferSelectionGeometryForTextInputEdits(edits)

        let change = model.commitEdits(
            edits,
            selectedRange: nextSelection
        )
        guard let change else {
            isApplyingModel = false
            refreshKeyboardAccessoryState()
            return
        }
        lastAppliedDocumentRevision = change.revision
        let nextText = model.text
        currentSelectedRange = clampedTextRange(nextSelection, in: nextText)
        syncTextLayoutSelection()
        updateTypingAttributes()
        updateTextContainerForCurrentWrappingMode()
        if shouldDeferSelectionGeometry {
            scheduleScrollSelectionToVisibleIfNeeded()
        } else {
            layoutAndScrollSelectionForTextInputGeometry()
        }
        isApplyingModel = false

        let refreshStart = min(
            refreshStartUTF16,
            edits.map(\.range.location).min() ?? refreshStartUTF16
        )
        scheduleHighlight(
            source: nextText,
            language: model.language,
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

    private func shouldDeferSelectionGeometryForTextInputEdits(_ edits: [SyntaxEditorTextEdit]) -> Bool {
        edits.contains { edit in
            edit.range.length > 4_096 || edit.replacement.utf16.count > 4_096
        }
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
        lineMetrics.apply(edits: edits, previousSource: previousText)
        updateTextContainerForCurrentWrappingMode()
        updateContentSizeIfNeeded()
        invalidateFindResultsAfterTextChange()
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
        guard model.isEditable else {
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
            if !isApplyingModel {
                model.selectedRange = clamped
            }
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

    @objc public func syntaxEditorShiftRight(_ sender: Any?) {
        handleIndentCommand()
    }

    @objc public func syntaxEditorShiftLeft(_ sender: Any?) {
        handleOutdentCommand()
    }

    @objc public func syntaxEditorCommentSelection(_ sender: Any?) {
        handleToggleCommentCommand()
    }

    @objc public func syntaxEditorToggleLineWrapping(_ sender: Any?) {
        handleToggleLineWrappingCommand()
    }

    @objc public func syntaxEditorIncreaseFontSize(_ sender: Any?) {
        handleIncreaseFontSizeCommand()
    }

    @objc public func syntaxEditorDecreaseFontSize(_ sender: Any?) {
        handleDecreaseFontSizeCommand()
    }

    @objc public func syntaxEditorResetFontSize(_ sender: Any?) {
        handleResetFontSizeCommand()
    }

    @objc private func handleIndentCommand() {
        guard model.isEditable, model.language.supportsCodeEditingCommands else { return }

        guard let result = commandEngine.indentSelection(
            source: text,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleInsertTabCommand() {
        guard model.isEditable else { return }

        guard model.language.supportsCodeEditingCommands else {
            insertText("\t")
            return
        }

        guard let result = commandEngine.insertTab(
            source: text,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleOutdentCommand() {
        guard model.isEditable, model.language.supportsCodeEditingCommands else { return }

        guard let result = commandEngine.outdentSelection(
            source: text,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleToggleCommentCommand() {
        guard model.isEditable, model.language.supportsCodeEditingCommands else { return }

        guard let result = commandEngine.toggleComment(
            source: text,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handlePasteCommand() {
        paste(nil)
    }

    @objc private func handleToggleLineWrappingCommand() {
        model.lineWrappingEnabled.toggle()
    }

    @objc private func handleIncreaseFontSizeCommand() {
        model.increaseFontSize()
    }

    @objc private func handleDecreaseFontSizeCommand() {
        model.decreaseFontSize()
    }

    @objc private func handleResetFontSizeCommand() {
        model.resetFontSize()
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

    private func resetAppliedHighlightPhaseTrackingForTesting() {
        appliedHighlightPhaseRecordsForTesting.removeAll()
        skippedHighlightPhaseRecordsForTesting.removeAll()
        resumeAppliedHighlightPhaseWaitersForTesting(result: false)
        resumeSkippedHighlightPhaseWaitersForTesting(result: false)
    }

    private func hasAppliedHighlightPhaseForTesting(
        _ phase: SyntaxHighlightPhase,
        revision: Int
    ) -> Bool {
        appliedHighlightPhaseRecordsForTesting.contains {
            $0.revision == revision && $0.phase == phase
        }
    }

    private func recordAppliedHighlightPhaseForTesting(
        _ phase: SyntaxHighlightPhase,
        revision: Int
    ) {
        appliedHighlightPhaseRecordsForTesting.append(
            HighlightPhaseRecord(revision: revision, phase: phase)
        )
        if appliedHighlightPhaseRecordsForTesting.count > 16 {
            appliedHighlightPhaseRecordsForTesting.removeFirst(
                appliedHighlightPhaseRecordsForTesting.count - 16
            )
        }

        resumeAppliedHighlightPhaseWaitersForTesting(
            revision: revision,
            phase: phase,
            result: true
        )
    }

    private func hasSkippedHighlightPhaseForTesting(
        _ phase: SyntaxHighlightPhase,
        revision: Int
    ) -> Bool {
        skippedHighlightPhaseRecordsForTesting.contains {
            $0.revision == revision && $0.phase == phase
        }
    }

    private func recordSkippedHighlightPhaseForTesting(
        _ phase: SyntaxHighlightPhase,
        revision: Int
    ) {
        skippedHighlightPhaseRecordsForTesting.append(
            HighlightPhaseRecord(revision: revision, phase: phase)
        )
        if skippedHighlightPhaseRecordsForTesting.count > 16 {
            skippedHighlightPhaseRecordsForTesting.removeFirst(
                skippedHighlightPhaseRecordsForTesting.count - 16
            )
        }

        resumeSkippedHighlightPhaseWaitersForTesting(
            revision: revision,
            phase: phase,
            result: true
        )
    }

    private func resumeAppliedHighlightPhaseWaiterForTesting(id: Int, result: Bool) {
        guard let waiterIndex = appliedHighlightPhaseWaitersForTesting.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = appliedHighlightPhaseWaitersForTesting.remove(at: waiterIndex)
        waiter.continuation.resume(returning: result)
    }

    private func resumeAppliedHighlightPhaseWaitersForTesting(
        revision: Int? = nil,
        phase: SyntaxHighlightPhase? = nil,
        result: Bool
    ) {
        var matchedWaiters: [HighlightPhaseWaiter] = []
        appliedHighlightPhaseWaitersForTesting.removeAll { waiter in
            guard revision == nil || waiter.revision == revision,
                  phase == nil || waiter.phase == phase
            else {
                return false
            }
            matchedWaiters.append(waiter)
            return true
        }

        for waiter in matchedWaiters {
            waiter.continuation.resume(returning: result)
        }
    }

    private func resumeSkippedHighlightPhaseWaiterForTesting(id: Int, result: Bool) {
        guard let waiterIndex = skippedHighlightPhaseWaitersForTesting.firstIndex(where: { $0.id == id }) else {
            return
        }

        let waiter = skippedHighlightPhaseWaitersForTesting.remove(at: waiterIndex)
        waiter.continuation.resume(returning: result)
    }

    private func resumeSkippedHighlightPhaseWaitersForTesting(
        revision: Int? = nil,
        phase: SyntaxHighlightPhase? = nil,
        result: Bool
    ) {
        var matchedWaiters: [HighlightPhaseWaiter] = []
        skippedHighlightPhaseWaitersForTesting.removeAll { waiter in
            guard revision == nil || waiter.revision == revision,
                  phase == nil || waiter.phase == phase
            else {
                return false
            }
            matchedWaiters.append(waiter)
            return true
        }

        for waiter in matchedWaiters {
            waiter.continuation.resume(returning: result)
        }
    }

    func scheduleHighlight(
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        mutation: SyntaxHighlightMutation? = nil,
        refreshStartUTF16: Int = 0
    ) {
        let expectedSource = source

        highlightTask?.cancel()
        let requestID = nextScheduledHighlightRequestID
        nextScheduledHighlightRequestID += 1
        scheduledHighlightRequest = ScheduledHighlightRequest(
            id: requestID,
            model: model,
            language: language,
            revision: revision,
            mutation: mutation
        )
        resetAppliedHighlightPhaseTrackingForTesting()
        prepareSyntaxHighlightRenderingForPendingHighlight(
            mutation: mutation,
            source: source,
            refreshStartUTF16: refreshStartUTF16
        )

        let highlighter = self.highlighter
        // Viewport hint: progressive opens and background semantic drains
        // process the chunk nearest this range first (pure ordering hint).
        let visibleRange = visibleCharacterRangeForHighlightHint()
        highlightTask = Task.detached(priority: .utility) { [weak self, highlighter, expectedSource, language, revision, mutation, requestID, visibleRange] in
            defer {
                Task { @MainActor [weak self] in
                    self?.clearScheduledHighlightRequestIfCurrent(id: requestID)
                }
            }
            await Task.yield()
            guard !Task.isCancelled else {
                return
            }
            await highlighter.setVisibleRange(visibleRange)

            let phases: AsyncStream<SyntaxHighlightResult>
            if let mutation {
                phases = await highlighter.updatePhases(
                    source: expectedSource,
                    language: language,
                    mutation: mutation,
                    revision: revision
                )
            } else {
                phases = await highlighter.resetPhases(
                    source: expectedSource,
                    language: language,
                    revision: revision
                )
            }
            for await result in phases {
                guard !Task.isCancelled else { return }
                await self?.applyHighlightResultFromScheduledTask(result, mutation: mutation)
            }
        }
    }

    private func clearScheduledHighlightRequestIfCurrent(id: Int) {
        guard scheduledHighlightRequest?.id == id else { return }
        scheduledHighlightRequest = nil
    }

    private func applyHighlightResultFromScheduledTask(
        _ result: SyntaxHighlightResult,
        mutation: SyntaxHighlightMutation?
    ) async {
        guard !Task.isCancelled else { return }
        guard model.revision == result.revision else { return }
        guard canApplyHighlightTokenPayload(for: result, mutation: mutation) else {
            recordSkippedHighlightPhaseForTesting(result.phase, revision: result.revision)
            scheduleHighlight(source: result.source, language: result.language, revision: result.revision)
            return
        }
        guard shouldMaterializeHighlightResult(result, mutation: mutation) else {
            recordSkippedHighlightPhaseForTesting(result.phase, revision: result.revision)
            return
        }
        let refreshRange = highlightApplicationRefreshRange(
            for: result,
            mutation: mutation
        )
        let didApplyHighlight = await applyHighlightFromScheduledTask(
            result.tokens,
            expectedRevision: result.revision,
            source: result.source,
            language: result.language,
            refreshRange: refreshRange,
            mutation: mutation,
            tokenPayload: result.tokenPayload
        )
        guard didApplyHighlight else { return }
        recordMaterializedHighlight(
            phase: result.phase,
            revision: result.revision,
            language: result.language
        )
        recordAppliedHighlightPhaseForTesting(result.phase, revision: result.revision)
        guard result.phase == .complete else { return }
        recordAppliedHighlightTokenSnapshot(
            tokens: result.tokens,
            source: result.source,
            revision: result.revision,
            language: result.language,
            tokenPayload: result.tokenPayload
        )
    }

    private func shouldMaterializeHighlightResult(
        _ result: SyntaxHighlightResult,
        mutation: SyntaxHighlightMutation?
    ) -> Bool {
        guard mutation != nil,
              result.phase == .syntacticFastPass
        else {
            return true
        }

        return !hasMaterializedCompletedHighlightToAvoidDowngrade(for: result)
    }

    private func hasMaterializedCompletedHighlightToAvoidDowngrade(for result: SyntaxHighlightResult) -> Bool {
        guard materializedHighlightPhase == .complete,
              materializedHighlightLanguage == result.language,
              highlightStyleStore.hasMaterializedRuns,
              let materializedHighlightRevision
        else {
            return false
        }

        return materializedHighlightRevision < result.revision
    }

    func highlightApplicationRefreshRange(
        for result: SyntaxHighlightResult,
        mutation: SyntaxHighlightMutation?
    ) -> NSRange {
        guard mutation != nil else {
            return result.refreshRange
        }
        return result.refreshRange
    }

    private func canApplyHighlightTokenPayload(
        for result: SyntaxHighlightResult,
        mutation: SyntaxHighlightMutation?
    ) -> Bool {
        guard result.tokenPayload == .replacement else {
            return true
        }
        // Reset-origin streams paint progressively: the reset itself defines
        // the (initially bare) baseline these replacements apply onto, so no
        // prior materialization is required.
        if mutation == nil {
            return true
        }
        guard materializedHighlightLanguage == result.language,
              let materializedHighlightRevision
        else {
            return false
        }
        return materializedHighlightRevision <= result.revision
    }

    func reapplyCachedHighlight() {
        if hasScheduledFullResetHighlight(language: model.language, revision: model.revision) {
            return
        }
        let source = text
        guard hasReusableRecordedHighlightSnapshot(
            source: source,
            language: model.language,
            revision: model.revision
        ) else {
            scheduleHighlight(source: source, language: model.language, revision: model.revision)
            return
        }

        applyHighlight(
            lastHighlightTokens,
            expectedRevision: model.revision,
            source: source,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }

    private func hasReusableRecordedHighlightSnapshot(
        source: String,
        language: SyntaxLanguage,
        revision: Int
    ) -> Bool {
        lastHighlightRevision == revision
            && lastHighlightLanguage == language
            && lastHighlightSource == source
    }

    private func hasScheduledFullResetHighlight(
        language: SyntaxLanguage,
        revision: Int
    ) -> Bool {
        guard let scheduledHighlightRequest,
              scheduledHighlightRequest.mutation == nil
        else {
            return false
        }
        return scheduledHighlightRequest.model === model
            && scheduledHighlightRequest.language == language
            && scheduledHighlightRequest.revision == revision
    }

    func clearHighlightCache() {
        highlightTask?.cancel()
        highlightTask = nil
        scheduledHighlightRequest = nil
        resetAppliedHighlightPhaseTrackingForTesting()
        lastHighlightTokens = []
        lastHighlightSource = nil
        lastHighlightRevision = nil
        lastHighlightLanguage = nil
        clearMaterializedHighlightState()
        resetSyntaxHighlightRenderingState(textLength: storage.length)
    }

    private func recordMaterializedHighlight(
        phase: SyntaxHighlightPhase,
        revision: Int,
        language: SyntaxLanguage
    ) {
        materializedHighlightPhase = phase
        materializedHighlightRevision = revision
        materializedHighlightLanguage = language
    }

    private func clearMaterializedHighlightState() {
        materializedHighlightPhase = nil
        materializedHighlightRevision = nil
        materializedHighlightLanguage = nil
    }

    static func highlightMutation(_ change: SyntaxEditorTextChange) -> SyntaxHighlightMutation? {
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
        guard model.revision == expectedRevision else { return }

        let textLength = expectedSource.utf16.count
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: textLength)
        guard targetRange.length > 0 else {
            applyMatchingBracketHighlight(force: true)
            return
        }
        let base = baseAttributes()

        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        commitSyntaxHighlightSnapshot(
            for: tokens,
            targetRange: targetRange,
            baseAttributes: base,
            textLength: textLength,
            revision: expectedRevision,
            language: model.language
        )
        applyMarkedTextAttributes()
        updateTypingAttributes()
        applyMatchingBracketHighlight(force: true)
        setNeedsDisplayForVisibleTextFragments()
        recordMaterializedHighlight(
            phase: .complete,
            revision: expectedRevision,
            language: model.language
        )
    }

    private func applyHighlightFromScheduledTask(
        _ tokens: [SyntaxHighlightToken],
        expectedRevision: Int,
        source expectedSource: String,
        language expectedLanguage: SyntaxLanguage,
        refreshRange: NSRange,
        mutation: SyntaxHighlightMutation?,
        tokenPayload _: SyntaxHighlightTokenPayload = .fullSnapshot
    ) async -> Bool {
        guard model.revision == expectedRevision else { return false }
        guard model.language == expectedLanguage,
              text == expectedSource
        else {
            return false
        }

        let textLength = expectedSource.utf16.count
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: textLength)
        guard targetRange.length > 0 else {
            applyMatchingBracketHighlight(force: true)
            return true
        }
        let base = baseAttributes()

        guard await commitSyntaxHighlightSnapshotFromScheduledTask(
            for: tokens,
            targetRange: targetRange,
            baseAttributes: base,
            textLength: textLength,
            revision: expectedRevision,
            language: expectedLanguage
        ) else {
            return false
        }

        applyMarkedTextAttributes()
        updateTypingAttributes()
        applyMatchingBracketHighlight(force: true)
        setNeedsDisplayForVisibleTextFragments()
        return true
    }

    private func recordAppliedHighlightTokenSnapshot(
        tokens: [SyntaxHighlightToken],
        source: String,
        revision: Int,
        language: SyntaxLanguage,
        tokenPayload: SyntaxHighlightTokenPayload
    ) {
        guard tokenPayload == .fullSnapshot else {
            clearRecordedHighlightTokenSnapshot()
            return
        }
        lastHighlightTokens = tokens
        lastHighlightSource = source
        lastHighlightRevision = revision
        lastHighlightLanguage = language
    }

    private func clearRecordedHighlightTokenSnapshot() {
        lastHighlightTokens = []
        lastHighlightSource = nil
        lastHighlightRevision = nil
        lastHighlightLanguage = nil
    }

    private func makeSyntaxHighlightAttributeResolver(
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> SyntaxHighlightAttributeResolver {
        SyntaxHighlightAttributeResolver(
            theme: lastAppliedTheme,
            defaultLanguage: model.language,
            appearance: currentThemeAppearance,
            fontSizeDelta: model.fontSizeDelta,
            resolveColor: { [weak self] color in
                self?.resolvedSyntaxColor(color) ?? color
            }
        )
    }

    private func syntaxHighlightRunSet(
        for tokens: [SyntaxHighlightToken],
        renderRange: NSRange,
        textLength: Int,
        resolver: inout SyntaxHighlightAttributeResolver
    ) -> HighlightRunSet {
        var colorRuns: [HighlightColorRun] = []
        var fontRuns: [HighlightFontRun] = []
        colorRuns.reserveCapacity(min(tokens.count, 1024))
        fontRuns.reserveCapacity(min(tokens.count, 1024))

        let tokenRangeIndex = HighlightTokenRangeIndex(tokens: tokens)
        let tokenStartIndex = tokenRangeIndex.firstTokenIndex(intersecting: renderRange)
        for token in tokens[tokenStartIndex...] {
            guard token.range.location < renderRange.upperBound else { break }
            let clamped = SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: textLength)
            let intersection = SyntaxEditorRangeUtilities.intersection(of: clamped, and: renderRange)
            guard intersection.length > 0 else {
                continue
            }
            guard let resolved = resolver.style(for: token.syntaxID, language: token.language) else {
                subtractSyntaxHighlightRange(intersection, fromColorRuns: &colorRuns, fontRuns: &fontRuns)
                continue
            }

            subtractSyntaxHighlightRange(intersection, fromColorRuns: &colorRuns, fontRuns: &fontRuns)
            insertHighlightColorRun(
                HighlightColorRun(
                    range: intersection,
                    color: resolved.style.foregroundColor
                ),
                into: &colorRuns
            )

            let font = resolved.style.font
            insertHighlightFontRun(
                HighlightFontRun(range: intersection, font: font),
                into: &fontRuns
            )
        }

        return HighlightRunSet(colorRuns: colorRuns, fontRuns: fontRuns)
    }

    private func insertHighlightColorRun(
        _ run: HighlightColorRun,
        into runs: inout [HighlightColorRun]
    ) {
        let insertionIndex = firstColorRunIndex(startingAtOrAfter: run.range.location, in: runs)
        runs.insert(run, at: insertionIndex)
        coalesceColorRuns(around: insertionIndex, in: &runs)
    }

    private func coalesceColorRuns(
        around insertionIndex: Int,
        in runs: inout [HighlightColorRun]
    ) {
        var index = insertionIndex
        if index > 0, colorRunsCanCoalesce(runs[index - 1], runs[index]) {
            let mergedRange = unionRange(runs[index - 1].range, runs[index].range)
            runs[index - 1].range = mergedRange
            runs.remove(at: index)
            index -= 1
        }
        if index + 1 < runs.count, colorRunsCanCoalesce(runs[index], runs[index + 1]) {
            let mergedRange = unionRange(runs[index].range, runs[index + 1].range)
            runs[index].range = mergedRange
            runs.remove(at: index + 1)
        }
    }

    private func colorRunsCanCoalesce(_ lhs: HighlightColorRun, _ rhs: HighlightColorRun) -> Bool {
        lhs.color.isEqual(rhs.color)
            && lhs.range.upperBound >= rhs.range.location
            && rhs.range.upperBound >= lhs.range.location
    }

    private func insertHighlightFontRun(
        _ run: HighlightFontRun,
        into runs: inout [HighlightFontRun]
    ) {
        let insertionIndex = firstFontRunIndex(startingAtOrAfter: run.range.location, in: runs)
        runs.insert(run, at: insertionIndex)
        coalesceFontRuns(around: insertionIndex, in: &runs)
    }

    private func coalesceFontRuns(
        around insertionIndex: Int,
        in runs: inout [HighlightFontRun]
    ) {
        var index = insertionIndex
        if index > 0, fontRunsCanCoalesce(runs[index - 1], runs[index]) {
            let mergedRange = unionRange(runs[index - 1].range, runs[index].range)
            runs[index - 1].range = mergedRange
            runs.remove(at: index)
            index -= 1
        }
        if index + 1 < runs.count, fontRunsCanCoalesce(runs[index], runs[index + 1]) {
            let mergedRange = unionRange(runs[index].range, runs[index + 1].range)
            runs[index].range = mergedRange
            runs.remove(at: index + 1)
        }
    }

    private func fontRunsCanCoalesce(_ lhs: HighlightFontRun, _ rhs: HighlightFontRun) -> Bool {
        lhs.font.isEqual(rhs.font)
            && lhs.range.upperBound >= rhs.range.location
            && rhs.range.upperBound >= lhs.range.location
    }

    private func unionRange(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let lowerBound = min(lhs.location, rhs.location)
        let upperBound = max(lhs.upperBound, rhs.upperBound)
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private func subtractSyntaxHighlightRange(
        _ range: NSRange,
        fromColorRuns colorRuns: inout [HighlightColorRun],
        fontRuns: inout [HighlightFontRun]
    ) {
        subtractSyntaxHighlightRange(range, fromColorRuns: &colorRuns)
        subtractSyntaxHighlightRange(range, fromFontRuns: &fontRuns)
    }

    private func subtractSyntaxHighlightRange(
        _ range: NSRange,
        fromColorRuns runs: inout [HighlightColorRun]
    ) {
        var index = firstColorRunIndex(intersecting: range, in: runs)
        while index < runs.count {
            let run = runs[index]
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else {
                index += 1
                continue
            }

            let runStart = run.range.location
            let runEnd = run.range.upperBound
            let resetStart = intersection.location
            let resetEnd = intersection.upperBound

            if resetStart <= runStart, resetEnd >= runEnd {
                runs.remove(at: index)
            } else if resetStart <= runStart {
                runs[index].range = NSRange(location: resetEnd, length: runEnd - resetEnd)
                break
            } else if resetEnd >= runEnd {
                runs[index].range = NSRange(location: runStart, length: resetStart - runStart)
                index += 1
            } else {
                let trailingRun = HighlightColorRun(
                    range: NSRange(location: resetEnd, length: runEnd - resetEnd),
                    color: run.color
                )
                runs[index].range = NSRange(location: runStart, length: resetStart - runStart)
                runs.insert(trailingRun, at: index + 1)
                break
            }
        }
    }

    private func subtractSyntaxHighlightRange(
        _ range: NSRange,
        fromFontRuns runs: inout [HighlightFontRun]
    ) {
        var index = firstFontRunIndex(intersecting: range, in: runs)
        while index < runs.count {
            let run = runs[index]
            guard run.range.location < range.upperBound else { break }
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else {
                index += 1
                continue
            }

            let runStart = run.range.location
            let runEnd = run.range.upperBound
            let resetStart = intersection.location
            let resetEnd = intersection.upperBound

            if resetStart <= runStart, resetEnd >= runEnd {
                runs.remove(at: index)
            } else if resetStart <= runStart {
                runs[index].range = NSRange(location: resetEnd, length: runEnd - resetEnd)
                break
            } else if resetEnd >= runEnd {
                runs[index].range = NSRange(location: runStart, length: resetStart - runStart)
                index += 1
            } else {
                let trailingRun = HighlightFontRun(
                    range: NSRange(location: resetEnd, length: runEnd - resetEnd),
                    font: run.font
                )
                runs[index].range = NSRange(location: runStart, length: resetStart - runStart)
                runs.insert(trailingRun, at: index + 1)
                break
            }
        }
    }

    private func firstColorRunIndex(intersecting range: NSRange, in runs: [HighlightColorRun]) -> Int {
        var lowerBound = 0
        var upperBound = runs.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if runs[middle].range.upperBound <= range.location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func firstColorRunIndex(startingAtOrAfter location: Int, in runs: [HighlightColorRun]) -> Int {
        var lowerBound = 0
        var upperBound = runs.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if runs[middle].range.location < location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func firstFontRunIndex(intersecting range: NSRange, in runs: [HighlightFontRun]) -> Int {
        var lowerBound = 0
        var upperBound = runs.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if runs[middle].range.upperBound <= range.location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func firstFontRunIndex(startingAtOrAfter location: Int, in runs: [HighlightFontRun]) -> Int {
        var lowerBound = 0
        var upperBound = runs.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if runs[middle].range.location < location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func commitSyntaxHighlightSnapshot(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        baseAttributes: [NSAttributedString.Key: Any],
        textLength: Int,
        revision: Int,
        language: SyntaxLanguage
    ) {
        guard let baseForeground = baseAttributes[.foregroundColor] as? UIColor else { return }
        var resolver = makeSyntaxHighlightAttributeResolver(baseAttributes: baseAttributes)
        let runSet = syntaxHighlightRunSet(
            for: tokens,
            renderRange: targetRange,
            textLength: textLength,
            resolver: &resolver
        )
        let invalidatedDirtyRanges = highlightStyleStore.commitSnapshot(
            runSet: runSet,
            range: targetRange,
            revision: revision,
            language: language,
            textLength: textLength,
            baseForeground: baseForeground,
            baseFont: baseAttributes[.font] as? UIFont,
            suppressionRanges: foregroundSuppressionRanges(textLength: textLength)
        )
        let invalidatedRanges = [targetRange] + invalidatedDirtyRanges
        invalidateSyntaxRenderingAttributes(for: invalidatedRanges)
        setNeedsDisplayForTextRanges(invalidatedRanges)
    }

    private func foregroundSuppressionRanges(textLength: Int) -> [NSRange] {
        markedRange.map { [SyntaxEditorRangeUtilities.clampedRange($0, utf16Length: textLength)] } ?? []
    }

    private func prepareSyntaxHighlightRenderingForPendingHighlight(
        mutation: SyntaxHighlightMutation?,
        source: String,
        refreshStartUTF16 _: Int
    ) {
        let textLength = source.utf16.count
        guard let mutation else {
            clearSyntaxHighlightRendering()
            return
        }

        let invalidatedRange = pendingTextMutationReplacementRange(in: source, mutation: mutation)
        highlightStyleStore.recordPendingEdit(mutation, currentTextLength: textLength)
        invalidateSyntaxRenderingAttributes(for: [invalidatedRange])
        guard invalidatedRange.length > 0 else { return }
        setNeedsDisplayForTextRanges([invalidatedRange])
    }

    private func clearSyntaxHighlightRendering() {
        let base = baseAttributes()
        guard let baseForeground = base[.foregroundColor] as? UIColor else { return }
        highlightStyleStore.clear(
            textLength: storage.length,
            baseForeground: baseForeground,
            baseFont: base[.font] as? UIFont
        )
        invalidateSyntaxRenderingAttributes(for: [NSRange(location: 0, length: storage.length)])
        clearMaterializedHighlightState()
        setNeedsDisplayForVisibleTextFragments()
    }

    private func resetSyntaxHighlightRenderingState(textLength: Int) {
        highlightStyleStore.reset(textLength: textLength)
        clearMaterializedHighlightState()
    }

    private func pendingTextMutationReplacementRange(
        in source: String,
        mutation: SyntaxHighlightMutation
    ) -> NSRange {
        let textLength = source.utf16.count
        let location = min(max(0, mutation.location), textLength)
        let replacementLength = min(max(0, mutation.replacement.utf16.count), textLength - location)
        if replacementLength > 0 {
            return NSRange(location: location, length: replacementLength)
        }
        guard textLength > 0 else {
            return NSRange(location: 0, length: 0)
        }
        let fallbackLocation = min(location, textLength - 1)
        return NSRange(location: fallbackLocation, length: 1)
    }

    private func commitSyntaxHighlightSnapshotFromScheduledTask(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        baseAttributes: [NSAttributedString.Key: Any],
        textLength: Int,
        revision: Int,
        language: SyntaxLanguage
    ) async -> Bool {
        guard !Task.isCancelled, model.revision == revision else {
            return false
        }
        isApplyingHighlight = true
        defer { isApplyingHighlight = false }
        commitSyntaxHighlightSnapshot(
            for: tokens,
            targetRange: targetRange,
            baseAttributes: baseAttributes,
            textLength: textLength,
            revision: revision,
            language: language
        )
        await Task.yield()
        return !Task.isCancelled && model.revision == revision
    }

    func reapplyTextAttributes(in range: NSRange) {
        let textLength = text.utf16.count
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
        guard targetRange.length > 0 else { return }

        if hasReusableRecordedHighlightSnapshot(
            source: text,
            language: model.language,
            revision: model.revision
        ) {
            applyHighlight(
                lastHighlightTokens,
                expectedRevision: model.revision,
                source: text,
                refreshRange: targetRange
            )
        } else {
            TextEditingTransaction.perform(on: textContentStorage) { storage in
                storage.addAttributes(storageBaseAttributes(), range: targetRange)
            }
            setNeedsDisplayForVisibleTextFragments()
        }
    }

    func applyMarkedTextAttributes() {
        let textLength = text.utf16.count
        let suppressionRanges = foregroundSuppressionRanges(textLength: textLength)
        highlightStyleStore.updateSuppressionRanges(
            suppressionRanges,
            textLength: textLength
        )
        invalidateSyntaxRenderingAttributes(for: suppressionRanges)
        guard let markedRange else { return }
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(markedRange, utf16Length: textLength)
        guard targetRange.length > 0 else { return }

        TextEditingTransaction.perform(on: textContentStorage) { storage in
            storage.addAttributes(markedTextAttributes(), range: targetRange)
        }
        setNeedsDisplayForVisibleTextFragments()
    }

    func clearMarkedTextAttributes(in range: NSRange) {
        let textLength = text.utf16.count
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
        guard targetRange.length > 0 else { return }

        TextEditingTransaction.perform(on: textContentStorage) { storage in
            storage.removeAttribute(.underlineStyle, range: targetRange)
            storage.removeAttribute(.underlineColor, range: targetRange)
        }
        highlightStyleStore.updateSuppressionRanges(
            foregroundSuppressionRanges(textLength: textLength),
            textLength: textLength
        )
        invalidateSyntaxRenderingAttributes(for: [targetRange])
        reapplyTextAttributes(in: targetRange)
        setNeedsDisplayForVisibleTextFragments()
    }

    func markedTextAttributes() -> [NSAttributedString.Key: Any] {
        [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: tintColor ?? UIColor.systemBlue,
        ]
    }

    func baseAttributes() -> [NSAttributedString.Key: Any] {
        let theme = resolvedTheme()
        return [
            .font: resolvedBaseFont(for: theme),
            .foregroundColor: resolvedSyntaxColor(theme.baseForeground),
            .paragraphStyle: baseParagraphStyle(),
        ]
    }

    func storageBaseAttributes() -> [NSAttributedString.Key: Any] {
        baseAttributes()
    }

    func resolvedBaseFont(for theme: SyntaxEditorResolvedTheme? = nil) -> UIFont {
        resolvedBaseFont(for: theme, fontSizeDelta: model.fontSizeDelta)
    }

    func resolvedBaseFont(
        for theme: SyntaxEditorResolvedTheme? = nil,
        fontSizeDelta: Int
    ) -> UIFont {
        let theme = theme ?? resolvedTheme()
        return theme.base.font.platformFont(fontSizeDelta: fontSizeDelta)
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

        TextEditingTransaction.perform(on: textContentStorage) { storage in
            for update in updates {
                storage.addAttribute(.paragraphStyle, value: update.style, range: update.range)
            }
        }
    }

    func resolvedSyntaxColor(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: traitCollection)
    }

    var currentThemeAppearance: SyntaxEditorThemeAppearance {
        traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }

    func resolvedTheme() -> SyntaxEditorResolvedTheme {
        lastAppliedTheme.resolved(
            for: model.language,
            appearance: currentThemeAppearance
        )
    }

    func updateEditorBackgroundColor() {
        updateEditorBackgroundColor(drawsBackground: model.drawsBackground)
    }

    func updateEditorBackgroundColor(drawsBackground: Bool) {
        let color = drawsBackground ? resolvedSyntaxColor(resolvedTheme().background) : .clear
        isOpaque = drawsBackground && color.cgColor.alpha >= 1
        backgroundColor = color
        textContentView.backgroundColor = backgroundColor
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
        let lineHeight = resolvedBaseFont().lineHeight
        let textHeight = max(lineHeight, ceil(estimatedLayoutSize.height))
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
            height: max(resolvedBaseFont().lineHeight, contentSize.height - textContainerInset.top - textContainerInset.bottom)
        )

        guard !textContentView.frame.isNearlyEqual(to: contentViewFrame) else { return }
        textContentView.frame = contentViewFrame
    }

    func estimatedDocumentLayoutSize() -> CGSize {
        if !lastAppliedLineWrappingEnabled {
            let horizontalInset = textContainerInset.left + textContainerInset.right
            return CGSize(
                width: max(0, measuredHorizontalDocumentLayoutWidth() - horizontalInset),
                height: CGFloat(lineMetrics.lineCount) * resolvedBaseFont().lineHeight
            )
        }

        let measuredSize = layoutManager.usageBoundsForTextContainer.size
        let font = resolvedBaseFont()
        let estimatedColumnWidth = Self.estimatedMonospacedColumnWidth(for: font)
        let availableLineWidth = max(1, container.size.width - container.lineFragmentPadding * 2)
        let estimatedHeight = CGFloat(lineMetrics.estimatedWrappedLineCount(
            maxColumnsPerLine: Int(floor(availableLineWidth / estimatedColumnWidth))
        )) * font.lineHeight
        return CGSize(
            width: max(measuredSize.width, bounds.width),
            height: max(measuredSize.height, estimatedHeight)
        )
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
                ranges: TextLayoutGeometry.ranges(findFoundRanges, intersecting: fragmentRange)
            )
            highlightedRects = textHighlightRects(
                in: layoutFragmentFrame,
                ranges: TextLayoutGeometry.ranges(findHighlightedRanges, intersecting: fragmentRange)
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

    func textRange(for layoutFragment: NSTextLayoutFragment) -> NSRange {
        textSystem.utf16Range(for: layoutFragment)
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
        return TextLayoutGeometry.standardRects(
            layoutManager: layoutManager,
            rangeConverter: textSystem.rangeConverter,
            ranges: ranges,
            offsetBy: layoutFragmentFrame.origin
        )
        .filter { $0.intersects(fragmentLocalBounds) }
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
            lineMetrics.horizontalDocumentWidth(
                columnWidth: Self.estimatedMonospacedColumnWidth(for: resolvedBaseFont()),
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

    func invalidateSyntaxRenderingAttributes(for ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }

        var invalidatedRanges: [NSRange] = []
        invalidatedRanges.reserveCapacity(ranges.count)
        for range in ranges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
            guard clamped.length > 0,
                  let textRange = textRange(forUTF16Range: clamped)
            else {
                continue
            }
            layoutManager.invalidateRenderingAttributes(for: textRange)
            invalidatedRanges.append(clamped)
        }

        guard !invalidatedRanges.isEmpty else { return }
        // Revalidate already-laid-out fragments before redrawing: their line
        // fragments cache the rendering attributes captured at layout time, so
        // a bare setNeedsDisplay repaints the stale colors. Applies that arrive
        // without an accompanying layout pass (progressive reset chunks,
        // background drain results) otherwise never recolor the current
        // viewport — only freshly scrolled-in fragments would run the
        // validator. Mirrors the AppKit input view.
        var didInvalidateFragment = false
        for case let fragmentView as SyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            let fragmentRange = textRange(for: fragmentView.layoutFragment)
            guard !TextLayoutGeometry.ranges(invalidatedRanges, intersecting: fragmentRange).isEmpty else {
                continue
            }
            validateSyntaxRenderingAttributes(in: fragmentView.layoutFragment, using: layoutManager)
            fragmentView.setNeedsDisplay()
            didInvalidateFragment = true
        }
        if !didInvalidateFragment {
            setNeedsDisplay()
        }
    }

    func setNeedsDisplayForTextRanges(_ ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }

        var didInvalidateFragment = false
        for case let fragmentView as SyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            let fragmentRange = textRange(for: fragmentView.layoutFragment)
            guard !TextLayoutGeometry.ranges(ranges, intersecting: fragmentRange).isEmpty else {
                continue
            }
            fragmentView.setNeedsDisplay()
            didInvalidateFragment = true
        }
        if !didInvalidateFragment {
            setNeedsDisplay()
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

    /// Currently laid-out viewport as a UTF-16 range, or nil before first
    /// layout — used as the highlighter's drain-ordering hint.
    func visibleCharacterRangeForHighlightHint() -> NSRange? {
        guard let viewportRange = layoutManager.textViewportLayoutController.viewportRange else {
            return nil
        }
        let range = utf16Range(for: viewportRange)
        return range.length > 0 ? range : nil
    }

    func textLocation(forUTF16Offset offset: Int) -> NSTextLocation? {
        textSystem.textLocation(forUTF16Offset: offset)
    }

    func utf16Offset(for textLocation: NSTextLocation) -> Int {
        textSystem.utf16Offset(for: textLocation)
    }

    func textRange(forUTF16Range range: NSRange) -> NSTextRange? {
        textSystem.textRange(forUTF16Range: range)
    }

    func utf16Range(for textRange: NSTextRange) -> NSRange {
        textSystem.utf16Range(for: textRange)
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

private extension UIFont {
    func syntaxEditorFontSizeAdjusted(by delta: Int) -> UIFont {
        withSize(SyntaxEditorFontSize.pointSize(pointSize, applying: delta))
    }
}
#endif
