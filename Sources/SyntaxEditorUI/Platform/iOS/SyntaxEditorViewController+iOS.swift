#if canImport(UIKit)
import Observation
import ObservationBridge
import SyntaxEditorCore
import UIKit

@MainActor
private final class SyntaxEditorReadOnlyGuardedUndoManager: UndoManager {
    var allowsMutation: () -> Bool = { true }

    override var canUndo: Bool {
        allowsMutation() && super.canUndo
    }

    override var canRedo: Bool {
        allowsMutation() && super.canRedo
    }

    override func undo() {
        guard allowsMutation() else { return }
        super.undo()
    }

    override func redo() {
        guard allowsMutation() else { return }
        super.redo()
    }

    override func undoNestedGroup() {
        guard allowsMutation() else { return }
        super.undoNestedGroup()
    }
}

private enum SyntaxEditorVisibleRectRequestSource {
    case scrollRect
    case scrollRange
}

@MainActor
private final class SyntaxEditorNativeTextView: UITextView {
    var guardedUndoManager: UndoManager?
    var keyCommandsProvider: (() -> [UIKeyCommand]?)?
    var actionAvailabilityOverride: ((Selector, Any?) -> Bool?)?
    var visibleRectRequestHandler: ((CGRect, SyntaxEditorVisibleRectRequestSource) -> Void)?

    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            super.contentOffset = .zero
        }
    }

    override var undoManager: UndoManager? {
        guardedUndoManager ?? super.undoManager
    }

    override var keyCommands: [UIKeyCommand]? {
        let providedCommands = keyCommandsProvider?() ?? []
        return (super.keyCommands ?? []) + providedCommands
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if let result = actionAvailabilityOverride?(action, sender) {
            return result
        }

        return super.canPerformAction(action, withSender: sender)
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        resetInternalScrollPosition()
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        visibleRectRequestHandler?(rect, .scrollRect)
        resetInternalScrollPosition()
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        let caretLocation = range.location + range.length
        guard let position = position(from: beginningOfDocument, offset: caretLocation) else {
            resetInternalScrollPosition()
            return
        }

        visibleRectRequestHandler?(caretRect(for: position), .scrollRange)
        resetInternalScrollPosition()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resetInternalScrollPosition()
    }

    func resetInternalScrollPosition() {
        guard !super.contentOffset.isAlmostEqual(to: .zero) else { return }
        UIView.performWithoutAnimation {
            super.setContentOffset(.zero, animated: false)
            super.layer.removeAllAnimations()
        }
    }
}

@MainActor
@Observable
public final class SyntaxEditorView: UIScrollView, UITextViewDelegate {
    private static let horizontalLayoutDebugEnvironmentKey = "SYNTAXEDITORUI_HORIZONTAL_LAYOUT_LOGS"

    public private(set) var model: SyntaxEditorModel
    public let textView: UITextView
    @ObservationIgnored
    private let fallbackUndoManager = UndoManager()
    @ObservationIgnored
    private let guardedUndoManager = SyntaxEditorReadOnlyGuardedUndoManager()

    @ObservationIgnored
    private let highlighter = SyntaxHighlighterEngine()
    @ObservationIgnored
    private let commandEngine = EditorCommandEngine()
    @ObservationIgnored
    private var highlightTask: Task<Void, Never>?
    @ObservationIgnored
    private var isApplyingModel = false
    @ObservationIgnored
    private var isApplyingHighlight = false
    @ObservationIgnored
    private var lastAppliedLanguageIdentifier: String?
    @ObservationIgnored
    private var pendingEditStartUTF16: Int?
    @ObservationIgnored
    private var matchedBracketRanges: [NSRange] = []
    @ObservationIgnored
    private var isApplyingUndoRedo = false
    @ObservationIgnored
    private var isApplyingCommandSelection = false
    @ObservationIgnored
    private var keyboardAccessoryModel: SyntaxEditorKeyboardAccessoryModel?
    @ObservationIgnored
    private let modelObservations = ObservationScope()
    @ObservationIgnored
    private var needsTextLayoutMetricsUpdate = true
    @ObservationIgnored
    private var lastLayoutBoundsSize = CGSize.zero
    @ObservationIgnored
    private var measuredNonWrappingTextViewWidth = CGFloat.zero

    public init(model: SyntaxEditorModel) {
        self.model = model

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: .zero)
        layoutManager.addTextContainer(textContainer)

        let nativeTextView = SyntaxEditorNativeTextView(frame: .zero, textContainer: textContainer)
        self.textView = nativeTextView

        super.init(frame: .zero)
        nativeTextView.guardedUndoManager = guardedUndoManager
        nativeTextView.keyCommandsProvider = { [weak self] in
            self?.editorKeyCommands()
        }
        nativeTextView.actionAvailabilityOverride = { [weak self] action, sender in
            self?.editorActionAvailabilityOverride(action, withSender: sender)
        }
        nativeTextView.visibleRectRequestHandler = { [weak self] rect, source in
            self?.handleTextViewVisibleRectRequest(rect, source: source)
        }
        guardedUndoManager.allowsMutation = { [weak self] in
            self?.model.isEditable ?? true
        }
        configureScrollView()
        configureTextView()
        configureTraitChangeObservation()
        applyObservedEditorState(
            language: model.language,
            isEditable: model.isEditable,
            lineWrappingEnabled: model.lineWrappingEnabled,
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
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        highlightTask?.cancel()
    }

    public override var undoManager: UndoManager? {
        textView.undoManager ?? guardedUndoManager
    }

    public override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + (editorKeyCommands() ?? [])
    }

    public override var canBecomeFirstResponder: Bool {
        textView.canBecomeFirstResponder
    }

    public override var isFirstResponder: Bool {
        textView.isFirstResponder
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        textView.resignFirstResponder()
    }

    public var text: String! {
        get { textView.text }
        set {
            let nextText = newValue ?? ""
            let textNeedsUpdate = textView.text != nextText
            let modelNeedsUpdate = model.text != nextText
            guard textNeedsUpdate || modelNeedsUpdate else { return }

            if textNeedsUpdate {
                commandEngine.invalidateTransientState()
                isApplyingModel = true
                textView.text = nextText
                textView.typingAttributes = baseAttributes()
                isApplyingModel = false

                markTextLayoutMetricsNeedsUpdate()
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
                layoutIfNeeded()
                scrollSelectionToVisibleIfNeeded()
            }
        }
    }

    public var selectedRange: NSRange {
        get { textView.selectedRange }
        set { textView.selectedRange = newValue }
    }

    public var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    public var isSelectable: Bool {
        get { textView.isSelectable }
        set { textView.isSelectable = newValue }
    }

    public var textContainer: NSTextContainer {
        textView.textContainer
    }

    public override func layoutSubviews() {
        logHorizontalLayout("layout.begin")
        if bounds.size != lastLayoutBoundsSize {
            lastLayoutBoundsSize = bounds.size
            needsTextLayoutMetricsUpdate = true
        }

        super.layoutSubviews()
        logHorizontalLayout("layout.afterSuper")
        updateTextViewFrameForCurrentWrappingMode()
        logHorizontalLayout("layout.end")
    }

    public override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        scrollContentRectToVisible(rect)
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if let result = editorActionAvailabilityOverride(action, withSender: sender) {
            return result
        }

        if isEditorCommandAction(action) {
            return model.isEditable
        }

        return textView.canPerformAction(action, withSender: sender)
    }

    public func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingModel, !isApplyingHighlight else {
            pendingEditStartUTF16 = nil
            return
        }

        let nextText = textView.text ?? ""
        if model.text != nextText {
            model.text = nextText
        }
        markTextLayoutMetricsNeedsUpdate()

        let editStartUTF16 = pendingEditStartUTF16 ?? textView.selectedRange.location
        pendingEditStartUTF16 = nil
        let refreshStartUTF16 = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
            in: nextText,
            around: editStartUTF16
        )
        scheduleHighlight(
            source: nextText,
            language: model.language,
            refreshStartUTF16: refreshStartUTF16
        )
        refreshKeyboardAccessoryState()
        layoutIfNeeded()
        scrollSelectionToVisibleIfNeeded()
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        if !isApplyingCommandSelection {
            commandEngine.invalidateTransientState()
        }
        applyMatchingBracketHighlight()
        scrollSelectionToVisibleIfNeeded()
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard !isApplyingModel, !isApplyingHighlight else {
            return true
        }

        guard model.isEditable else {
            pendingEditStartUTF16 = nil
            return false
        }

        pendingEditStartUTF16 = range.location

        let currentSource = textView.text ?? ""
        let isBackwardDelete = text.isEmpty
            && range.length == 1
            && textView.selectedRange.length == 0
            && textView.selectedRange.location == range.location + range.length
        if let result = commandEngine.transformInput(
            source: currentSource,
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

    private func configureScrollView() {
        backgroundColor = .clear
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        addSubview(textView)
    }

    private func configureTextView() {
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.contentInset = .zero
        textView.scrollIndicatorInsets = .zero
        textView.contentInsetAdjustmentBehavior = .never
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.delegate = self
        textView.isEditable = model.isEditable

        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no

        applyLineWrappingConfiguration(lineWrappingEnabled: model.lineWrappingEnabled)
        applyBaseTextViewAppearance()
        textView.inputAccessoryView = makeInputAccessoryView()
        refreshKeyboardAccessoryState()
    }

    private func configureTraitChangeObservation() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            guard previousTraitCollection.hasDifferentColorAppearance(comparedTo: self.traitCollection) else {
                return
            }
            self.refreshForColorAppearanceChange()
        }
    }

    private func refreshForColorAppearanceChange() {
        applyBaseTextViewAppearance()
        scheduleHighlight(
            source: textView.text ?? "",
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

    private func editorActionAvailabilityOverride(
        _ action: Selector,
        withSender sender: Any?
    ) -> Bool? {
        if !model.isEditable,
           action == Selector(("undo:")) || action == Selector(("redo:")) {
            return false
        }

        return nil
    }

    private func isEditorCommandAction(_ action: Selector) -> Bool {
        action == #selector(handleIndentCommand)
            || action == #selector(handleOutdentCommand)
            || action == #selector(handleToggleCommentCommand)
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
        textView.undoManager ?? fallbackUndoManager
    }

    private func refreshKeyboardAccessoryState() {
        guard let keyboardAccessoryModel else { return }
        keyboardAccessoryModel.isUndoable = model.isEditable && (activeUndoManager?.canUndo ?? false)
        keyboardAccessoryModel.isRedoable = model.isEditable && (activeUndoManager?.canRedo ?? false)
    }

    private func applyBaseTextViewAppearance() {
        let base = baseAttributes()
        textView.font = base[.font] as? UIFont
        textView.textColor = base[.foregroundColor] as? UIColor
        textView.typingAttributes = base
    }

    private func startModelObservation() {
        modelObservations.update {
            model.observe(\.text) { [weak self] text in
                guard let self else { return }
                self.applyObservedText(text)
            }
            .store(in: modelObservations)

            model.observe([\.language, \.isEditable, \.lineWrappingEnabled]) { [weak self] in
                guard let self else { return }
                self.applyObservedEditorState(
                    language: self.model.language,
                    isEditable: self.model.isEditable,
                    lineWrappingEnabled: self.model.lineWrappingEnabled
                )
            }
            .store(in: modelObservations)
        }
    }

    private func applyObservedText(_ text: String, forceTextUpdate: Bool = false) {
        isApplyingModel = true
        defer { isApplyingModel = false }

        let textNeedsUpdate = forceTextUpdate || textView.text != text
        if textNeedsUpdate {
            commandEngine.invalidateTransientState()
            textView.text = text
            markTextLayoutMetricsNeedsUpdate()
        }

        textView.typingAttributes = baseAttributes()
        if textNeedsUpdate {
            scheduleHighlight(
                source: text,
                language: model.language,
                refreshStartUTF16: 0
            )
        }
        refreshKeyboardAccessoryState()
    }

    private func applyObservedEditorState(
        language: any SyntaxLanguage,
        isEditable: Bool,
        lineWrappingEnabled: Bool,
        forceLanguageRefresh: Bool = false,
        schedulesHighlight: Bool = true
    ) {
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }

        applyLineWrappingConfiguration(lineWrappingEnabled: lineWrappingEnabled)

        let languageChanged = forceLanguageRefresh || lastAppliedLanguageIdentifier != language.syntaxHighlightCacheKey
        lastAppliedLanguageIdentifier = language.syntaxHighlightCacheKey

        textView.typingAttributes = baseAttributes()
        if languageChanged && schedulesHighlight {
            scheduleHighlight(
                source: textView.text ?? "",
                language: language,
                refreshStartUTF16: 0
            )
        }
        refreshKeyboardAccessoryState()
    }

    private func applyCommandResult(_ result: EditorCommandResult) {
        guard model.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        let previousText = textView.text ?? ""
        let previousSelection = textView.selectedRange
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
            appliedMutation = applyTextMutation(
                previousText: previousText,
                nextText: result.text
            )
            if appliedMutation == nil {
                textView.text = result.text
            }
        }
        isApplyingCommandSelection = true
        textView.selectedRange = result.selectedRange
        isApplyingCommandSelection = false
        textView.typingAttributes = baseAttributes()
        isApplyingModel = false

        pendingEditStartUTF16 = nil

        if textChanged, model.text != result.text {
            model.text = result.text
        }

        if textChanged {
            markTextLayoutMetricsNeedsUpdate()

            let refreshStartUTF16: Int
            if let appliedMutation {
                let mutationLineStart = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                    in: result.text,
                    around: appliedMutation.range.location
                )
                refreshStartUTF16 = min(result.refreshStartUTF16, mutationLineStart)
            } else {
                refreshStartUTF16 = 0
            }

            scheduleHighlight(
                source: result.text,
                language: model.language,
                refreshStartUTF16: refreshStartUTF16
            )
        } else {
            applyMatchingBracketHighlight()
        }
        refreshKeyboardAccessoryState()
        layoutIfNeeded()
        scrollSelectionToVisibleIfNeeded()
    }

    private func registerUndoAction(restore: EditorUndoState, counterpart: EditorUndoState) {
        guard restore != counterpart else { return }
        guard let activeUndoManager = activeUndoManager else { return }

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
            refreshKeyboardAccessoryState()
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

    private func applyTextMutation(
        previousText: String,
        nextText: String
    ) -> TextMutation? {
        guard let mutation = TextMutation.diff(from: previousText, to: nextText) else {
            return nil
        }

        let textLength = (textView.text as NSString?)?.length ?? 0
        guard mutation.range.location + mutation.range.length <= textLength else {
            return nil
        }

        guard let start = textView.position(
            from: textView.beginningOfDocument,
            offset: mutation.range.location
        ),
            let end = textView.position(
                from: start,
                offset: mutation.range.length
            ),
            let textRange = textView.textRange(from: start, to: end)
        else {
            return nil
        }

        textView.replace(textRange, withText: mutation.replacement)

        return mutation
    }

    @objc private func handleIndentCommand() {
        guard model.isEditable else { return }

        let source = textView.text ?? ""
        guard let result = commandEngine.indentSelection(
            source: source,
            selection: textView.selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleOutdentCommand() {
        guard model.isEditable else { return }

        let source = textView.text ?? ""
        guard let result = commandEngine.outdentSelection(
            source: source,
            selection: textView.selectedRange
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleToggleCommentCommand() {
        guard model.isEditable else { return }

        let source = textView.text ?? ""
        guard let result = commandEngine.toggleComment(
            source: source,
            selection: textView.selectedRange,
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

        let handled = UIApplication.shared.sendAction(
            Selector(("undo:")),
            to: nil,
            from: self,
            for: nil
        )
        if !handled {
            activeUndoManager?.undo()
        }
        refreshKeyboardAccessoryState()
    }

    @objc private func handleRedoCommand() {
        guard model.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        let handled = UIApplication.shared.sendAction(
            Selector(("redo:")),
            to: nil,
            from: self,
            for: nil
        )
        if !handled {
            activeUndoManager?.redo()
        }
        refreshKeyboardAccessoryState()
    }

    @objc private func handleDismissKeyboardCommand() {
        window?.endEditing(true)
    }

    private func scheduleHighlight(
        source: String,
        language: any SyntaxLanguage,
        refreshStartUTF16: Int = 0
    ) {
        let expectedSource = source
        let utf16Length = expectedSource.utf16.count
        let clampedRefreshStart = min(max(0, refreshStartUTF16), utf16Length)
        let refreshRange = NSRange(
            location: clampedRefreshStart,
            length: utf16Length - clampedRefreshStart
        )

        highlightTask?.cancel()

        let highlighter = self.highlighter
        highlightTask = Task { [weak self] in
            let tokens = await highlighter.render(source: expectedSource, language: language)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.applyHighlight(
                tokens,
                expectedSource: expectedSource,
                refreshRange: refreshRange
            )
        }
    }

    private func applyHighlight(
        _ tokens: [SyntaxHighlightToken],
        expectedSource: String,
        refreshRange: NSRange
    ) {
        guard textView.text == expectedSource else { return }

        let textStorage = textView.textStorage
        let textLength = textStorage.length
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: textLength)
        guard targetRange.length > 0 else {
            applyMatchingBracketHighlight()
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
        textView.typingAttributes = base
        applyMatchingBracketHighlight()
    }

    private func applyMatchingBracketHighlight() {
        let source = textView.text ?? ""
        let textStorage = textView.textStorage
        let textLength = textStorage.length

        textStorage.beginEditing()

        for range in matchedBracketRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            textStorage.removeAttribute(.backgroundColor, range: clamped)
        }

        let newRanges = BracketMatcher.matchedRanges(
            in: source,
            caretUTF16Offset: textView.selectedRange.location
        )

        for range in newRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            textStorage.addAttribute(
                .backgroundColor,
                value: UIColor.syntaxEditor(dynamic: SyntaxEditorHighlightTheme.bracketBackground).withAlphaComponent(0.24),
                range: clamped
            )
        }

        textStorage.endEditing()
        matchedBracketRanges = newRanges
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor.syntaxEditor(dynamic: SyntaxEditorHighlightTheme.baseForeground),
        ]
    }

    private func styleAttributes(for captureName: String) -> [NSAttributedString.Key: Any] {
        guard let pair = SyntaxEditorHighlightTheme.colorPair(for: captureName) else {
            return [:]
        }
        return [.foregroundColor: UIColor.syntaxEditor(dynamic: pair)]
    }

    private func applyLineWrappingConfiguration(lineWrappingEnabled: Bool) {
        logHorizontalLayout("applyLineWrapping.begin", extra: "requested=\(lineWrappingEnabled)")
        if lineWrappingEnabled {
            textView.textContainer.widthTracksTextView = true
            textView.textContainer.lineBreakMode = .byWordWrapping
            showsHorizontalScrollIndicator = false
            alwaysBounceHorizontal = false
            if contentOffset.x != 0 {
                contentOffset.x = 0
            }
        } else {
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.lineBreakMode = .byClipping
            showsHorizontalScrollIndicator = true
            alwaysBounceHorizontal = true
        }
        markTextLayoutMetricsNeedsUpdate()
        logHorizontalLayout("applyLineWrapping.end", extra: "requested=\(lineWrappingEnabled)")
    }

    private func markTextLayoutMetricsNeedsUpdate() {
        needsTextLayoutMetricsUpdate = true
        measuredNonWrappingTextViewWidth = 0
        setNeedsLayout()
    }

    private func updateTextViewFrameForCurrentWrappingMode() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let textViewWidth: CGFloat
        if model.lineWrappingEnabled {
            textViewWidth = bounds.width
        } else {
            textViewWidth = measuredTextViewWidthForNonWrappingText()
        }

        updateTextContainerSize(forTextViewWidth: textViewWidth)

        let fittingSize = textView.sizeThatFits(
            CGSize(
                width: textViewWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        let textViewHeight = max(bounds.height, ceil(fittingSize.height))
        let nextFrame = CGRect(
            origin: .zero,
            size: CGSize(width: textViewWidth, height: textViewHeight)
        )

        if !textView.frame.isAlmostEqual(to: nextFrame) {
            logHorizontalLayout("textView.frame.update", extra: "from=\(textView.frame) to=\(nextFrame)")
            textView.frame = nextFrame
        }

        if !contentSize.isAlmostEqual(to: nextFrame.size) {
            logHorizontalLayout("contentSize.update", extra: "from=\(contentSize) to=\(nextFrame.size)")
            contentSize = nextFrame.size
        }

        resetInternalTextViewScrollPosition()
        clampContentOffsetToCurrentContentSize()
        needsTextLayoutMetricsUpdate = false
    }

    private func updateTextContainerSize(forTextViewWidth textViewWidth: CGFloat) {
        let containerSize = CGSize(
            width: max(0, textViewWidth - horizontalTextInsets),
            height: CGFloat.greatestFiniteMagnitude
        )
        guard !textView.textContainer.size.isAlmostEqual(to: containerSize) else { return }

        logHorizontalLayout(
            "container.update",
            extra: "from=\(textView.textContainer.size) to=\(containerSize)"
        )
        textView.textContainer.size = containerSize
        invalidateTextLayout()
    }

    private var horizontalTextInsets: CGFloat {
        textView.textContainerInset.left + textView.textContainerInset.right
    }

    private func invalidateTextLayout() {
        let textRange = NSRange(location: 0, length: textView.textStorage.length)
        textView.layoutManager.invalidateLayout(forCharacterRange: textRange, actualCharacterRange: nil)
        textView.layoutManager.invalidateDisplay(forCharacterRange: textRange)
    }

    private func measuredTextViewWidthForNonWrappingText() -> CGFloat {
        if !needsTextLayoutMetricsUpdate,
           measuredNonWrappingTextViewWidth > 0 {
            return max(bounds.width, measuredNonWrappingTextViewWidth)
        }

        let source = (textView.text ?? "") as NSString
        let attributes = baseAttributes()
        var widestLineWidth = CGFloat.zero

        source.enumerateSubstrings(
            in: NSRange(location: 0, length: source.length),
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, _ in
            let line = source.substring(with: lineRange) as NSString
            widestLineWidth = max(
                widestLineWidth,
                ceil(line.size(withAttributes: attributes).width)
            )
        }

        let measuredContentWidth = max(
            max(0, bounds.width - horizontalTextInsets),
            widestLineWidth + textView.textContainer.lineFragmentPadding * 2
        )
        let measuredWidth = max(bounds.width, ceil(measuredContentWidth + horizontalTextInsets))
        measuredNonWrappingTextViewWidth = measuredWidth
        logHorizontalLayout(
            "measureNonWrappingWidth",
            extra: "widestLineWidth=\(widestLineWidth) measuredWidth=\(measuredWidth) textLength=\(source.length)"
        )
        return measuredWidth
    }

    private func clampContentOffsetToCurrentContentSize() {
        let clampedOffset = clampedContentOffset(contentOffset)

        guard !contentOffset.isAlmostEqual(to: clampedOffset) else { return }
        logHorizontalLayout("contentOffset.clamp", extra: "from=\(contentOffset) to=\(clampedOffset)")
        contentOffset = clampedOffset
    }

    private func clampedContentOffset(_ proposedOffset: CGPoint) -> CGPoint {
        let maximumOffsetX = max(0, contentSize.width - bounds.width + adjustedContentInset.right)
        let maximumOffsetY = max(0, contentSize.height - bounds.height + adjustedContentInset.bottom)
        let minimumOffset = CGPoint(x: -adjustedContentInset.left, y: -adjustedContentInset.top)
        return CGPoint(
            x: min(max(proposedOffset.x, minimumOffset.x), maximumOffsetX),
            y: min(max(proposedOffset.y, minimumOffset.y), maximumOffsetY)
        )
    }

    private func scrollSelectionToVisibleIfNeeded() {
        guard let selectedTextRange = textView.selectedTextRange else { return }

        resetInternalTextViewScrollPosition()
        scrollTextViewRectToVisible(textView.caretRect(for: selectedTextRange.end))
    }

    private func handleTextViewVisibleRectRequest(
        _ rect: CGRect,
        source: SyntaxEditorVisibleRectRequestSource
    ) {
        switch source {
        case .scrollRange:
            scrollTextViewRectToVisible(rect)
        case .scrollRect:
            guard shouldHonorNativeScrollRectRequest(rect) else {
                logHorizontalLayout("nativeScrollRect.ignored", extra: "rect=\(rect)")
                return
            }
            scrollTextViewRectToVisible(rect)
        }
    }

    private func shouldHonorNativeScrollRectRequest(_ rect: CGRect) -> Bool {
        let targetRect = rect.standardized
        guard targetRect.isFinite else { return false }
        guard let selectedTextRange = textView.selectedTextRange else { return true }

        let caretRect = textView.caretRect(for: selectedTextRange.end)
        guard caretRect.isFinite else { return false }

        let allowedRect = caretRect.insetBy(
            dx: -max(bounds.width, textView.textContainer.lineFragmentPadding * 2),
            dy: -max(bounds.height, 24)
        )
        return allowedRect.intersects(targetRect) || allowedRect.contains(targetRect.origin)
    }

    private func scrollTextViewRectToVisible(_ rect: CGRect) {
        var contentRect = rect.insetBy(dx: -textView.textContainer.lineFragmentPadding, dy: -4)
        contentRect = contentRect.offsetBy(dx: textView.frame.minX, dy: textView.frame.minY)
        scrollContentRectToVisible(contentRect)
    }

    private func scrollContentRectToVisible(_ rect: CGRect) {
        let targetRect = rect.standardized
        let visibleRect = visibleContentRect
        guard !visibleRect.contains(targetRect) else { return }

        var targetOffset = contentOffset
        if targetRect.width < visibleRect.width {
            if targetRect.minX < visibleRect.minX {
                targetOffset.x = targetRect.minX - adjustedContentInset.left
            } else if targetRect.maxX > visibleRect.maxX {
                targetOffset.x = targetRect.maxX - bounds.width + adjustedContentInset.right
            }
        } else if targetRect.maxX < visibleRect.minX {
            targetOffset.x = targetRect.maxX - bounds.width + adjustedContentInset.right
        } else if targetRect.minX > visibleRect.maxX {
            targetOffset.x = targetRect.minX - adjustedContentInset.left
        }

        if targetRect.height < visibleRect.height {
            if targetRect.minY < visibleRect.minY {
                targetOffset.y = targetRect.minY - adjustedContentInset.top
            } else if targetRect.maxY > visibleRect.maxY {
                targetOffset.y = targetRect.maxY - bounds.height + adjustedContentInset.bottom
            }
        } else if targetRect.maxY < visibleRect.minY {
            targetOffset.y = targetRect.maxY - bounds.height + adjustedContentInset.bottom
        } else if targetRect.minY > visibleRect.maxY {
            targetOffset.y = targetRect.minY - adjustedContentInset.top
        }

        let clampedOffset = clampedContentOffset(targetOffset)
        guard !contentOffset.isAlmostEqual(to: clampedOffset) else { return }
        logHorizontalLayout("contentRect.scroll", extra: "rect=\(targetRect) from=\(contentOffset) to=\(clampedOffset)")
        setContentOffsetWithoutAnimation(clampedOffset)
    }

    private func setContentOffsetWithoutAnimation(_ offset: CGPoint) {
        UIView.performWithoutAnimation {
            setContentOffset(offset, animated: false)
            layer.removeAllAnimations()
        }
    }

    private func resetInternalTextViewScrollPosition() {
        if let nativeTextView = textView as? SyntaxEditorNativeTextView {
            nativeTextView.resetInternalScrollPosition()
        } else if !textView.contentOffset.isAlmostEqual(to: .zero) {
            textView.contentOffset = .zero
        }
    }

    private var visibleContentRect: CGRect {
        CGRect(
            x: contentOffset.x + adjustedContentInset.left,
            y: contentOffset.y + adjustedContentInset.top,
            width: max(0, bounds.width - adjustedContentInset.left - adjustedContentInset.right),
            height: max(0, bounds.height - adjustedContentInset.top - adjustedContentInset.bottom)
        )
    }

    private func logHorizontalLayout(_ event: String, extra: String = "") {
        guard Self.isHorizontalLayoutDebugLoggingEnabled else { return }

        let subviews = horizontalLayoutSubviewSummary(in: self, depth: 0, maxDepth: 2)
        let message = """
        SyntaxEditorUI.horizontalLayout event=\(event) wrap=\(model.lineWrappingEnabled) tracks=\(textView.textContainer.widthTracksTextView) break=\(textView.textContainer.lineBreakMode.rawValue) bounds=\(bounds) contentSize=\(contentSize) contentOffset=\(contentOffset) adjustedInset=\(adjustedContentInset) textViewFrame=\(textView.frame) textContainer=\(textView.textContainer.size) needsMetrics=\(needsTextLayoutMetricsUpdate) measuredWidth=\(measuredNonWrappingTextViewWidth) \(extra)
        \(subviews)
        """
        NSLog("%@", message)
    }

    private static var isHorizontalLayoutDebugLoggingEnabled: Bool {
        switch ProcessInfo.processInfo.environment[horizontalLayoutDebugEnvironmentKey] {
        case "1":
            return true
        default:
            return false
        }
    }

    private func horizontalLayoutSubviewSummary(
        in view: UIView,
        depth: Int,
        maxDepth: Int
    ) -> String {
        guard depth <= maxDepth else { return "" }

        let indent = String(repeating: "  ", count: depth)
        return view.subviews.map { subview in
            let line = "\(indent)- \(NSStringFromClass(type(of: subview))) frame=\(subview.frame) bounds=\(subview.bounds) hidden=\(subview.isHidden) clips=\(subview.clipsToBounds) subviews=\(subview.subviews.count)"
            let children = horizontalLayoutSubviewSummary(
                in: subview,
                depth: depth + 1,
                maxDepth: maxDepth
            )
            return children.isEmpty ? line : line + "\n" + children
        }
        .joined(separator: "\n")
    }
}

private extension CGFloat {
    func isAlmostEqual(to value: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        abs(self - value) <= tolerance
    }
}

private extension CGPoint {
    func isAlmostEqual(to point: CGPoint, tolerance: CGFloat = 0.5) -> Bool {
        x.isAlmostEqual(to: point.x, tolerance: tolerance)
            && y.isAlmostEqual(to: point.y, tolerance: tolerance)
    }
}

private extension CGSize {
    func isAlmostEqual(to size: CGSize, tolerance: CGFloat = 0.5) -> Bool {
        width.isAlmostEqual(to: size.width, tolerance: tolerance)
            && height.isAlmostEqual(to: size.height, tolerance: tolerance)
    }
}

private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
    }

    func isAlmostEqual(to rect: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        origin.isAlmostEqual(to: rect.origin, tolerance: tolerance)
            && size.isAlmostEqual(to: rect.size, tolerance: tolerance)
    }
}

@MainActor
@Observable
public final class SyntaxEditorViewController: UIViewController, UITextViewDelegate {
    public private(set) var model: SyntaxEditorModel
    @ObservationIgnored
    public let editorView: SyntaxEditorView

    public var textView: UITextView {
        editorView.textView
    }

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

    public func textViewDidChange(_ textView: UITextView) {
        editorView.textViewDidChange(textView)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        editorView.textViewDidChangeSelection(textView)
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        editorView.textView(
            textView,
            shouldChangeTextIn: range,
            replacementText: text
        )
    }
}

private extension UIColor {
    static func syntaxEditor(dynamic pair: SyntaxEditorHexColorPair) -> UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return syntaxEditor(hex: pair.dark)
            }
            return syntaxEditor(hex: pair.light)
        }
    }

    static func syntaxEditor(hex: UInt32) -> UIColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
#endif
