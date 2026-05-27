#if canImport(AppKit)
import AppKit
import ObservationBridge
import SyntaxEditorCore

private enum MacEditorShortcutAction {
    case indent
    case outdent
    case toggleComment
    case toggleLineWrapping
}

private struct PendingMacHighlightApplication {
    let tokens: [SyntaxHighlightToken]
    let expectedRevision: Int
    let source: String
    let language: SyntaxLanguage
    let refreshRange: NSRange
}

private struct MacSyntaxHighlightAttributeKey: Hashable {
    let syntaxID: EditorSourceSyntaxID
    let language: SyntaxLanguage
}

private struct MacSyntaxHighlightAttributeRun {
    let key: MacSyntaxHighlightAttributeKey
    var range: NSRange
    let attributes: [NSAttributedString.Key: Any]
}

private struct MacSyntaxHighlightAttributeResolver {
    let colorTheme: SyntaxEditorColorTheme
    let defaultLanguage: SyntaxLanguage
    let appearance: SyntaxEditorThemeAppearance
    let baseFont: NSFont

    private var attributeCache: [MacSyntaxHighlightAttributeKey: [NSAttributedString.Key: Any]] = [:]
    private var missingAttributeKeys: Set<MacSyntaxHighlightAttributeKey> = []
    private var fontCache: [SyntaxEditorFontDescriptor: NSFont] = [:]

    init(
        colorTheme: SyntaxEditorColorTheme,
        defaultLanguage: SyntaxLanguage,
        appearance: SyntaxEditorThemeAppearance,
        baseFont: NSFont
    ) {
        self.colorTheme = colorTheme
        self.defaultLanguage = defaultLanguage
        self.appearance = appearance
        self.baseFont = baseFont
    }

    mutating func attributes(
        for syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage?
    ) -> (key: MacSyntaxHighlightAttributeKey, attributes: [NSAttributedString.Key: Any])? {
        let effectiveLanguage = language ?? defaultLanguage
        let key = MacSyntaxHighlightAttributeKey(syntaxID: syntaxID, language: effectiveLanguage)

        if let cached = attributeCache[key] {
            return (key, cached)
        }
        guard !missingAttributeKeys.contains(key) else {
            return nil
        }

        guard let style = SyntaxEditorHighlightTheme.style(
            for: syntaxID,
            in: colorTheme,
            language: effectiveLanguage,
            appearance: appearance
        ) else {
            missingAttributeKeys.insert(key)
            return nil
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: style.foreground,
        ]
        if let fontDescriptor = style.font {
            attributes[.font] = platformFont(for: fontDescriptor)
        }
        attributeCache[key] = attributes
        return (key, attributes)
    }

    private mutating func platformFont(for descriptor: SyntaxEditorFontDescriptor) -> NSFont {
        if let cached = fontCache[descriptor] {
            return cached
        }
        let font = descriptor.platformFont(fallback: baseFont)
        fontCache[descriptor] = font
        return font
    }
}

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

private final class SyntaxEditorNativeTextView: NSTextView {
    var shortcutHandler: ((MacEditorShortcutAction) -> Bool)?
    var guardedUndoManager: UndoManager?

    override class var isCompatibleWithResponsiveScrolling: Bool {
        false
    }

    override var undoManager: UndoManager? {
        guardedUndoManager ?? super.undoManager
    }

    @objc func undo(_ sender: Any?) {
        undoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        undoManager?.redo()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) {
            return undoManager?.canUndo ?? false
        }

        if item.action == #selector(redo(_:)) {
            return undoManager?.canRedo ?? false
        }

        return super.validateUserInterfaceItem(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""

        if key.lowercased() == "l",
           modifiers.contains(.command),
           modifiers.contains(.control),
           modifiers.contains(.shift),
           !modifiers.contains(.option)
        {
            if shortcutHandler?(.toggleLineWrapping) == true {
                return true
            }
        }

        guard modifiers.contains(.command),
              !modifiers.contains(.control),
              !modifiers.contains(.option)
        else {
            return super.performKeyEquivalent(with: event)
        }

        if key == "/" {
            if shortcutHandler?(.toggleComment) == true {
                return true
            }
        }

        if key == "]" {
            if shortcutHandler?(.indent) == true {
                return true
            }
        }

        if key == "[" {
            if shortcutHandler?(.outdent) == true {
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
public final class SyntaxEditorView: NSScrollView, NSTextViewDelegate {
    public private(set) var document: SyntaxEditorDocument
    public private(set) var configuration: SyntaxEditorConfiguration
    public let textView: NSTextView
    public var isFindInteractionEnabled = true {
        didSet {
            guard isFindInteractionEnabled != oldValue else { return }
            applyFindInteractionConfiguration()
        }
    }

    private let fallbackUndoManager = UndoManager()
    private let guardedUndoManager = SyntaxEditorReadOnlyGuardedUndoManager()
    private let textStorage: NSTextStorage
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer

    private let highlighter: any SyntaxHighlighting
    private let commandEngine = EditorCommandEngine()
    private var highlightTask: Task<Void, Never>?
    private var lastHighlightTokens: [SyntaxHighlightToken] = []
    private var lastHighlightSource: String?
    private var lastHighlightRevision: Int?
    private var lastHighlightLanguage: SyntaxLanguage?
    private var isApplyingModel = false
    private var isApplyingHighlight = false
    private var lastAppliedLanguageIdentifier: String?
    private var pendingEditStartUTF16: Int?
    private var pendingHighlightMutation: SyntaxHighlightMutation?
    private var pendingHighlightApplication: PendingMacHighlightApplication?
    private var matchedBracketRanges: [NSRange] = []
    private var isApplyingUndoRedo = false
    private var isApplyingCommandSelection = false
    private var isApplyingLineWrappingConfiguration = false
    private var isScrollViewConfigured = false
    private var lastAppliedColorTheme: SyntaxEditorColorTheme?
    private var lastAppliedDocumentRevision = 0
    private let documentObservations = ObservationScope()
    private let configurationObservations = ObservationScope()
    var documentDeliveryForTesting: ObservationDelivery?
    var configurationDeliveryForTesting: ObservationDelivery?
    var highlightChunkDidApplyForTesting: ((Int) -> Void)?

    private var scrollView: NSScrollView { self }

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
        self.lastAppliedDocumentRevision = document.revision

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        layoutManager.addTextContainer(textContainer)

        let nativeTextView = SyntaxEditorNativeTextView(frame: .zero, textContainer: textContainer)
        self.textStorage = textStorage
        self.layoutManager = layoutManager
        self.textContainer = textContainer
        self.textView = nativeTextView

        super.init(frame: .zero)

        nativeTextView.guardedUndoManager = guardedUndoManager
        guardedUndoManager.allowsMutation = { [weak self] in
            self?.configuration.isEditable ?? true
        }
        nativeTextView.shortcutHandler = { [weak self] action in
            guard let self else { return false }
            return self.handleShortcut(action)
        }

        configureScrollView()
        configureTextView()
        startConfigurationObservation(schedulesInitialHighlight: false)
        startDocumentObservation()
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
            activeUndoManager?.removeAllActions()
            commandEngine.invalidateTransientState()
            clearHighlightCache()
            document = nextDocument
        }

        if configurationChanged {
            configurationObservations.cancelAll()
            configuration = nextConfiguration
            startConfigurationObservation(schedulesInitialHighlight: !documentChanged)
        }

        if documentChanged {
            startDocumentObservation()
        }
    }

    internal func synchronizeDocumentForTesting() {
        applyObservedConfiguration(
            language: configuration.language,
            isEditable: configuration.isEditable,
            lineWrappingEnabled: configuration.lineWrappingEnabled,
            colorTheme: configuration.colorTheme,
            drawsBackground: configuration.drawsBackground
        )
        applyObservedDocumentChange()
    }

    internal func waitForPendingHighlightForTesting() async {
        await highlightTask?.value
    }

    internal var bracketHighlightRangesForTesting: [NSRange] {
        matchedBracketRanges
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        highlightTask?.cancel()
        documentObservations.cancelAll()
        configurationObservations.cancelAll()
    }

    public override func layout() {
        super.layout()
        applyLineWrappingConfiguration(lineWrappingEnabled: configuration.lineWrappingEnabled)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateEditorBackgroundColor()
        updateTextViewFontAndTypingAttributes()
        reapplyCachedHighlight()
        applyMatchingBracketHighlight(force: true)
    }

    public override func tile() {
        super.tile()
        guard isScrollViewConfigured, !isApplyingLineWrappingConfiguration else { return }

        applyLineWrappingConfiguration(lineWrappingEnabled: configuration.lineWrappingEnabled)
    }

    public override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        guard isScrollViewConfigured, !isApplyingLineWrappingConfiguration else { return }

        invalidateVisibleTextDisplay()
    }

    public func textDidChange(_ notification: Notification) {
        guard !isApplyingModel, !isApplyingHighlight else {
            pendingEditStartUTF16 = nil
            pendingHighlightMutation = nil
            return
        }

        let previousText = document.textSnapshot()
        let nextText = textView.string
        let mutation = pendingHighlightMutation ??
            TextMutation.diff(from: previousText, to: nextText).map(SyntaxHighlightMutation.init)
        let change: SyntaxEditorDocumentChange
        if let mutation {
            change = document.commitEdits(
                [
                    SyntaxEditorTextEdit(
                        range: NSRange(location: mutation.location, length: mutation.length),
                        replacement: mutation.replacement
                    ),
                ],
                selectedRange: textView.selectedRange()
            )
        } else {
            change = document.replaceText(nextText, selectedRange: textView.selectedRange())
        }
        lastAppliedDocumentRevision = change.revision

        let editStartUTF16 = pendingEditStartUTF16 ?? textView.selectedRange().location
        pendingEditStartUTF16 = nil
        pendingHighlightMutation = nil
        applyBaseAttributesToInsertedText(for: mutation)
        let refreshStartUTF16 = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
            in: nextText,
            around: editStartUTF16
        )
        scheduleHighlight(
            source: nextText,
            language: configuration.language,
            revision: change.revision,
            mutation: mutation,
            refreshStartUTF16: refreshStartUTF16
        )
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        if !isApplyingCommandSelection {
            commandEngine.invalidateTransientState()
        }
        applyMatchingBracketHighlight()
        applyPendingHighlightIfSelectionAllows()
    }

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard !isApplyingModel, !isApplyingHighlight else {
            return true
        }

        guard configuration.isEditable else {
            pendingEditStartUTF16 = nil
            pendingHighlightMutation = nil
            return false
        }

        pendingEditStartUTF16 = affectedCharRange.location
        guard let replacementString else {
            pendingHighlightMutation = nil
            return true
        }

        pendingHighlightMutation = SyntaxHighlightMutation(
            location: affectedCharRange.location,
            length: affectedCharRange.length,
            replacement: replacementString
        )

        let source = textView.string
        if let result = commandEngine.transformInput(
            source: source,
            range: affectedCharRange,
            replacementText: replacementString,
            language: configuration.language
        ) {
            applyCommandResult(result)
            return false
        }

        return true
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard configuration.isEditable else {
            return false
        }

        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            return runInsertTabCommand()
        case #selector(NSResponder.insertBacktab(_:)):
            return runOutdentCommand()
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            let selectedRange = textView.selectedRange()
            if let result = commandEngine.transformInput(
                source: textView.string,
                range: selectedRange,
                replacementText: "\n",
                language: configuration.language
            ) {
                applyCommandResult(result)
                return true
            }
            return false
        case #selector(NSResponder.deleteBackward(_:)):
            let selectedRange = textView.selectedRange()
            let deleteRange: NSRange
            let deletionIntent: EditorCommandEngine.DeletionIntent
            if selectedRange.length > 0 {
                deleteRange = selectedRange
                deletionIntent = .unspecified
            } else {
                guard selectedRange.location > 0 else { return false }
                deleteRange = NSRange(location: selectedRange.location - 1, length: 1)
                deletionIntent = .backward
            }

            if let result = commandEngine.transformInput(
                source: textView.string,
                range: deleteRange,
                replacementText: "",
                language: configuration.language,
                deletionIntent: deletionIntent
            ) {
                applyCommandResult(result)
                return true
            }
            return false
        default:
            return false
        }
    }

    private func configureScrollView() {
        scrollView.drawsBackground = configuration.drawsBackground
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !configuration.lineWrappingEnabled
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        isScrollViewConfigured = true
    }

    private func configureTextView() {
        textView.delegate = self
        textView.drawsBackground = false
        updateEditorBackgroundColor()
        textView.isEditable = configuration.isEditable
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        textView.isVerticallyResizable = true
        applyFindInteractionConfiguration()
        configureBaseTextViewAppearance()

        applyLineWrappingConfiguration(lineWrappingEnabled: configuration.lineWrappingEnabled)
    }

    private func applyFindInteractionConfiguration() {
        if isFindInteractionEnabled {
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.usesFindPanel = false
        } else {
            isFindBarVisible = false
            textView.isIncrementalSearchingEnabled = false
            textView.usesFindBar = false
            textView.usesFindPanel = false
        }
    }

    private var activeUndoManager: UndoManager? {
        textView.undoManager ?? fallbackUndoManager
    }

    private func configureBaseTextViewAppearance() {
        let base = baseAttributes()
        textView.font = base[.font] as? NSFont ?? textView.font
        textView.textColor = base[.foregroundColor] as? NSColor ?? textView.textColor
        textView.typingAttributes = base
    }

    private func updateTextViewFontAndTypingAttributes() {
        let base = baseAttributes()
        textView.font = base[.font] as? NSFont ?? textView.font
        textView.typingAttributes = base
    }

    private func updateTypingAttributes() {
        textView.typingAttributes = baseAttributes()
    }

    private func startConfigurationObservation(schedulesInitialHighlight: Bool = true) {
        configurationDeliveryForTesting = configurationObservations.observe(configuration) { [weak self] event, configuration in
            guard let self else { return }
            self.applyObservedConfiguration(
                language: configuration.language,
                isEditable: configuration.isEditable,
                lineWrappingEnabled: configuration.lineWrappingEnabled,
                colorTheme: configuration.colorTheme,
                drawsBackground: configuration.drawsBackground,
                forceLanguageRefresh: event.kind == .initial,
                schedulesHighlight: event.kind != .initial || schedulesInitialHighlight
            )
        }
    }

    private func startDocumentObservation() {
        documentDeliveryForTesting = documentObservations.observe(document) { [weak self] event, document in
            guard let self else { return }
            self.applyObservedDocumentChange(
                forceTextUpdate: event.kind == .initial,
                observedRevision: document.revision
            )
        }
    }

    private func applyObservedDocumentChange(forceTextUpdate: Bool = false, observedRevision: Int? = nil) {
        let revision = observedRevision ?? document.revision
        guard forceTextUpdate || revision != lastAppliedDocumentRevision else { return }

        isApplyingModel = true
        defer {
            isApplyingModel = false
        }

        let text = document.textSnapshot()
        let textNeedsUpdate = forceTextUpdate || textView.string != text
        var highlightMutation: SyntaxHighlightMutation?
        if textNeedsUpdate {
            commandEngine.invalidateTransientState()
            let change = document.latestChange
            if change?.isWholeDocumentReplacement == true {
                activeUndoManager?.removeAllActions()
            }
            let canApplyIncrementally = change.map {
                $0.revision == revision
                    && !$0.isWholeDocumentReplacement
                    && !forceTextUpdate
                    && lastAppliedDocumentRevision == revision - 1
            } ?? false
            let didApplyIncrementally = if canApplyIncrementally, let change {
                applyStorageTextEdits(change.edits)
            } else {
                false
            }
            if didApplyIncrementally {
                highlightMutation = change.flatMap(Self.highlightMutation)
            } else {
                replaceEntireStorageText(text)
            }
            if let change,
               !(change.isWholeDocumentReplacement && change.selectedRange == NSRange(location: 0, length: 0)) {
                textView.setSelectedRange(change.selectedRange)
            }
        }

        updateTypingAttributes()
        if textNeedsUpdate {
            scheduleHighlight(
                source: text,
                language: configuration.language,
                revision: revision,
                mutation: highlightMutation,
                refreshStartUTF16: 0
            )
        }
        lastAppliedDocumentRevision = revision
    }

    private func applyObservedConfiguration(
        language: SyntaxLanguage,
        isEditable: Bool,
        lineWrappingEnabled: Bool,
        colorTheme: SyntaxEditorColorTheme,
        drawsBackground: Bool,
        forceLanguageRefresh: Bool = false,
        schedulesHighlight: Bool = true
    ) {
        let previousColorTheme = lastAppliedColorTheme
        let colorThemeChanged = previousColorTheme.map { $0 != colorTheme } ?? true
        if colorThemeChanged {
            applyBaseForegroundColorChange(from: previousColorTheme, to: colorTheme)
        }
        lastAppliedColorTheme = colorTheme
        updateTextViewFontAndTypingAttributes()
        updateEditorBackgroundColor(drawsBackground: drawsBackground)

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }

        applyLineWrappingConfiguration(lineWrappingEnabled: lineWrappingEnabled)

        let languageChanged = forceLanguageRefresh || lastAppliedLanguageIdentifier != language.syntaxHighlightCacheKey
        lastAppliedLanguageIdentifier = language.syntaxHighlightCacheKey

        if languageChanged && schedulesHighlight {
            scheduleHighlight(
                source: textView.string,
                language: language,
                revision: document.revision,
                refreshStartUTF16: 0
            )
        } else if colorThemeChanged && schedulesHighlight {
            reapplyCachedHighlight()
        }
    }

    private func applyBaseForegroundColorChange(
        from previousColorTheme: SyntaxEditorColorTheme?,
        to colorTheme: SyntaxEditorColorTheme
    ) {
        guard let previousColorTheme else { return }

        let textRange = NSRange(location: 0, length: textStorage.length)
        guard textRange.length > 0 else { return }

        var rangesToUpdate: [NSRange] = []
        let previousBaseForeground = previousColorTheme
            .resolved(for: configuration.language, appearance: currentThemeAppearance)
            .baseForeground
        let nextBaseForeground = colorTheme
            .resolved(for: configuration.language, appearance: currentThemeAppearance)
            .baseForeground
        unsafe textStorage.enumerateAttribute(.foregroundColor, in: textRange) { value, range, _ in
            guard let color = value as? NSColor,
                  color.isEqual(previousBaseForeground)
            else {
                return
            }
            rangesToUpdate.append(range)
        }

        guard !rangesToUpdate.isEmpty else { return }

        textStorage.beginEditing()
        for range in rangesToUpdate {
            textStorage.addAttribute(.foregroundColor, value: nextBaseForeground, range: range)
        }
        textStorage.endEditing()
    }

    private func applyCommandResult(_ result: EditorCommandResult) {
        guard configuration.isEditable else {
            return
        }

        let previousText = textView.string
        let previousSelection = textView.selectedRange()
        let textChanged = !result.edits.isEmpty
        let nextText = textChanged
            ? SyntaxEditorDocument.applying(result.edits, to: previousText)
            : previousText

        let undoState: (restore: EditorUndoState, counterpart: EditorUndoState)? =
            if textChanged, !isApplyingUndoRedo {
                (
                    EditorUndoState(
                        edits: SyntaxEditorDocument.inverseEdits(for: result.edits, in: previousText),
                        selectedRange: previousSelection,
                        refreshStartUTF16: 0
                    ),
                    EditorUndoState(
                        edits: result.edits,
                        selectedRange: result.selectedRange,
                        refreshStartUTF16: result.refreshStartUTF16
                    )
                )
            } else {
                nil
            }

        isApplyingModel = true
        if textChanged, !applyTextEdits(result.edits) {
            isApplyingModel = false
            return
        }
        isApplyingCommandSelection = true
        textView.setSelectedRange(result.selectedRange)
        isApplyingCommandSelection = false
        textView.typingAttributes = baseAttributes()
        isApplyingModel = false

        pendingEditStartUTF16 = nil
        pendingHighlightMutation = nil

        if let undoState {
            registerUndoAction(restore: undoState.restore, counterpart: undoState.counterpart)
        }

        var change: SyntaxEditorDocumentChange?
        if textChanged {
            change = document.commitEdits(result.edits, selectedRange: result.selectedRange)
            lastAppliedDocumentRevision = change?.revision ?? lastAppliedDocumentRevision
        }

        if textChanged {
            scheduleHighlight(
                source: nextText,
                language: configuration.language,
                revision: change?.revision ?? document.revision,
                mutation: change.flatMap(Self.highlightMutation),
                refreshStartUTF16: result.refreshStartUTF16
            )
        } else {
            applyMatchingBracketHighlight()
        }
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

    private func applyTextEdits(_ edits: [SyntaxEditorTextEdit]) -> Bool {
        let validationEdits = edits.sorted { $0.range.location < $1.range.location }
        guard editsAreValid(validationEdits) else {
            return false
        }

        let undoManager = activeUndoManager
        let disablesUndoRegistration = undoManager?.isUndoRegistrationEnabled == true
        if disablesUndoRegistration {
            undoManager?.disableUndoRegistration()
        }
        defer {
            if disablesUndoRegistration {
                undoManager?.enableUndoRegistration()
            }
        }

        let affectedRanges = validationEdits.map { NSValue(range: $0.range) }
        let replacementStrings = validationEdits.map(\.replacement)
        guard textView.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings) else {
            return false
        }

        guard applyStorageTextEdits(edits) else { return false }
        textView.didChangeText()
        return true
    }

    private func handleShortcut(_ action: MacEditorShortcutAction) -> Bool {
        switch action {
        case .indent:
            return runIndentCommand()
        case .outdent:
            return runOutdentCommand()
        case .toggleComment:
            return runToggleCommentCommand()
        case .toggleLineWrapping:
            return runToggleLineWrappingCommand()
        }
    }

    private func runInsertTabCommand() -> Bool {
        guard configuration.isEditable else {
            return false
        }

        let source = textView.string
        guard let result = commandEngine.insertTab(
            source: source,
            selection: textView.selectedRange()
        ) else {
            return false
        }
        applyCommandResult(result)
        return true
    }

    private func runIndentCommand() -> Bool {
        guard configuration.isEditable else {
            return false
        }

        let source = textView.string
        guard let result = commandEngine.indentSelection(
            source: source,
            selection: textView.selectedRange()
        ) else {
            return false
        }
        applyCommandResult(result)
        return true
    }

    private func runOutdentCommand() -> Bool {
        guard configuration.isEditable else {
            return false
        }

        let source = textView.string
        guard let result = commandEngine.outdentSelection(
            source: source,
            selection: textView.selectedRange()
        ) else {
            return false
        }
        applyCommandResult(result)
        return true
    }

    private func runToggleCommentCommand() -> Bool {
        guard configuration.isEditable else {
            return false
        }

        let source = textView.string
        guard let result = commandEngine.toggleComment(
            source: source,
            selection: textView.selectedRange(),
            language: configuration.language
        ) else {
            return false
        }
        applyCommandResult(result)
        return true
    }

    private func runToggleLineWrappingCommand() -> Bool {
        configuration.lineWrappingEnabled.toggle()
        return true
    }

    private func scheduleHighlight(
        source: String,
        language: SyntaxLanguage,
        revision: Int,
        mutation: SyntaxHighlightMutation? = nil,
        refreshStartUTF16 _: Int = 0
    ) {
        let expectedSource = source

        highlightTask?.cancel()
        pendingHighlightApplication = nil

        let highlighter = self.highlighter
        highlightTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else {
                return
            }

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
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.document.revision == result.revision else { return }
            let refreshRange = self.highlightApplicationRefreshRange(
                for: result,
                mutation: mutation
            )
            await self.applyHighlightFromScheduledTask(
                result.tokens,
                expectedRevision: result.revision,
                source: result.source,
                language: result.language,
                refreshRange: refreshRange
            )
        }
    }

    private func highlightApplicationRefreshRange(
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

    private func reapplyCachedHighlight() {
        let source = textView.string
        guard lastHighlightRevision == document.revision,
              lastHighlightLanguage == configuration.language,
              lastHighlightSource == source
        else {
            scheduleHighlight(source: source, language: configuration.language, revision: document.revision)
            return
        }

        applyHighlight(
            lastHighlightTokens,
            expectedRevision: document.revision,
            source: source,
            language: configuration.language,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }

    private func clearHighlightCache() {
        highlightTask?.cancel()
        highlightTask = nil
        lastHighlightTokens = []
        lastHighlightSource = nil
        lastHighlightRevision = nil
        lastHighlightLanguage = nil
        pendingHighlightApplication = nil
    }

    private func replaceEntireStorageText(_ nextText: String) {
        textStorage.beginEditing()
        textStorage.setAttributedString(NSAttributedString(string: nextText, attributes: baseAttributes()))
        textStorage.endEditing()
    }

    private func applyStorageTextEdits(_ edits: [SyntaxEditorTextEdit]) -> Bool {
        guard editsAreValid(edits) else { return false }

        let base = baseAttributes()
        textStorage.beginEditing()
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            let replacement = NSAttributedString(string: edit.replacement, attributes: base)
            textStorage.replaceCharacters(in: edit.range, with: replacement)
        }
        textStorage.endEditing()
        return true
    }

    private func applyBaseAttributesToInsertedText(for mutation: SyntaxHighlightMutation?) {
        guard let mutation,
              !mutation.replacement.isEmpty
        else {
            return
        }

        let insertedRange = SyntaxEditorRangeUtilities.clampedRange(
            NSRange(location: mutation.location, length: mutation.replacement.utf16.count),
            utf16Length: textStorage.length
        )
        guard insertedRange.length > 0 else { return }

        textStorage.addAttributes(baseAttributes(), range: insertedRange)
    }

    private func editsAreValid(_ edits: [SyntaxEditorTextEdit]) -> Bool {
        let textLength = textStorage.length
        return edits.allSatisfy { edit in
            edit.range.location >= 0 && edit.range.location + edit.range.length <= textLength
        }
    }

    private static func highlightMutation(_ change: SyntaxEditorDocumentChange) -> SyntaxHighlightMutation? {
        guard change.edits.count == 1, let edit = change.edits.first else { return nil }
        return SyntaxHighlightMutation(
            location: edit.range.location,
            length: edit.range.length,
            replacement: edit.replacement
        )
    }

    @discardableResult
    private func applyHighlight(
        _ tokens: [SyntaxHighlightToken],
        expectedRevision: Int,
        source expectedSource: String,
        language expectedLanguage: SyntaxLanguage,
        refreshRange: NSRange
    ) -> Bool {
        guard document.revision == expectedRevision else { return false }
        guard configuration.language == expectedLanguage,
              textView.string == expectedSource
        else {
            pendingHighlightApplication = nil
            return false
        }
        let pendingApplication = PendingMacHighlightApplication(
            tokens: tokens,
            expectedRevision: expectedRevision,
            source: expectedSource,
            language: expectedLanguage,
            refreshRange: refreshRange
        )
        guard textView.selectedRange().length == 0 else {
            pendingHighlightApplication = pendingApplication
            clearMatchingBracketHighlight()
            return false
        }

        pendingHighlightApplication = nil

        let textLength = textStorage.length
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: textLength)
        guard targetRange.length > 0 else {
            recordAppliedHighlight(
                tokens: tokens,
                source: expectedSource,
                revision: expectedRevision,
                language: expectedLanguage
            )
            applyMatchingBracketHighlight(force: true)
            return true
        }
        let base = baseAttributes()
        var resolver = makeSyntaxHighlightAttributeResolver(baseAttributes: base)
        let runs = syntaxHighlightAttributeRuns(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            resolver: &resolver
        )

        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        textStorage.beginEditing()
        resetSyntaxHighlightBaseAttributes(in: targetRange, baseAttributes: base)
        applySyntaxHighlightAttributeRuns(runs)
        textStorage.endEditing()
        textView.typingAttributes = base
        applyMatchingBracketHighlight(force: true)
        invalidateVisibleTextDisplay()
        recordAppliedHighlight(
            tokens: tokens,
            source: expectedSource,
            revision: expectedRevision,
            language: expectedLanguage
        )
        return true
    }

    @discardableResult
    private func applyHighlightFromScheduledTask(
        _ tokens: [SyntaxHighlightToken],
        expectedRevision: Int,
        source expectedSource: String,
        language expectedLanguage: SyntaxLanguage,
        refreshRange: NSRange
    ) async -> Bool {
        guard document.revision == expectedRevision else { return false }
        guard configuration.language == expectedLanguage,
              textView.string == expectedSource
        else {
            pendingHighlightApplication = nil
            return false
        }
        let pendingApplication = PendingMacHighlightApplication(
            tokens: tokens,
            expectedRevision: expectedRevision,
            source: expectedSource,
            language: expectedLanguage,
            refreshRange: refreshRange
        )
        guard textView.selectedRange().length == 0 else {
            pendingHighlightApplication = pendingApplication
            clearMatchingBracketHighlight()
            return false
        }

        pendingHighlightApplication = nil

        let textLength = textStorage.length
        let targetRange = SyntaxEditorRangeUtilities.clampedRange(refreshRange, utf16Length: textLength)
        guard targetRange.length > 0 else {
            recordAppliedHighlight(
                tokens: tokens,
                source: expectedSource,
                revision: expectedRevision,
                language: expectedLanguage
            )
            applyMatchingBracketHighlight(force: true)
            return true
        }
        let base = baseAttributes()
        var resolver = makeSyntaxHighlightAttributeResolver(baseAttributes: base)
        let runs = syntaxHighlightAttributeRuns(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            resolver: &resolver
        )

        guard await applySyntaxHighlightAttributesInChunks(
            runs,
            targetRange: targetRange,
            baseAttributes: base,
            expectedRevision: expectedRevision,
            pendingApplication: pendingApplication
        ) else {
            return false
        }

        textView.typingAttributes = base
        applyMatchingBracketHighlight(force: true)
        invalidateVisibleTextDisplay()
        recordAppliedHighlight(
            tokens: tokens,
            source: expectedSource,
            revision: expectedRevision,
            language: expectedLanguage
        )
        return true
    }

    private func makeSyntaxHighlightAttributeResolver(
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> MacSyntaxHighlightAttributeResolver {
        MacSyntaxHighlightAttributeResolver(
            colorTheme: configuration.colorTheme,
            defaultLanguage: configuration.language,
            appearance: currentThemeAppearance,
            baseFont: (baseAttributes[.font] as? NSFont) ?? resolvedBaseFont()
        )
    }

    private func syntaxHighlightAttributeRuns(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        resolver: inout MacSyntaxHighlightAttributeResolver
    ) -> [MacSyntaxHighlightAttributeRun] {
        var runs: [MacSyntaxHighlightAttributeRun] = []
        runs.reserveCapacity(min(tokens.count, 1024))

        for token in tokens {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: textLength)
            let intersection = SyntaxEditorRangeUtilities.intersection(of: clamped, and: targetRange)
            guard intersection.length > 0 else {
                continue
            }
            guard let resolved = resolver.attributes(for: token.syntaxID, language: token.language) else {
                subtractSyntaxHighlightRange(intersection, from: &runs)
                continue
            }

            if var last = runs.last,
               last.key == resolved.key,
               last.range.upperBound >= intersection.location,
               intersection.upperBound >= last.range.location {
                let lowerBound = min(last.range.location, intersection.location)
                let upperBound = max(last.range.upperBound, intersection.upperBound)
                last.range = NSRange(
                    location: lowerBound,
                    length: upperBound - lowerBound
                )
                runs[runs.count - 1] = last
            } else {
                runs.append(
                    MacSyntaxHighlightAttributeRun(
                        key: resolved.key,
                        range: intersection,
                        attributes: resolved.attributes
                    )
                )
            }
        }

        return runs
    }

    private func subtractSyntaxHighlightRange(
        _ range: NSRange,
        from runs: inout [MacSyntaxHighlightAttributeRun]
    ) {
        var index = runs.count
        while index > 0 {
            index -= 1
            let run = runs[index]
            let intersection = SyntaxEditorRangeUtilities.intersection(of: run.range, and: range)
            guard intersection.length > 0 else {
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
            } else if resetEnd >= runEnd {
                runs[index].range = NSRange(location: runStart, length: resetStart - runStart)
            } else {
                let trailingRun = MacSyntaxHighlightAttributeRun(
                    key: run.key,
                    range: NSRange(location: resetEnd, length: runEnd - resetEnd),
                    attributes: run.attributes
                )
                runs[index].range = NSRange(location: runStart, length: resetStart - runStart)
                runs.insert(trailingRun, at: index + 1)
            }
        }
    }

    private func resetSyntaxHighlightBaseAttributes(
        in targetRange: NSRange,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        if let baseForeground = baseAttributes[.foregroundColor] {
            textStorage.addAttribute(.foregroundColor, value: baseForeground, range: targetRange)
        } else {
            textStorage.removeAttribute(.foregroundColor, range: targetRange)
        }

        if let baseFont = baseAttributes[.font] as? NSFont {
            restoreBaseFontForSyntaxOverrides(in: targetRange, baseFont: baseFont)
        }
    }

    private func applySyntaxHighlightAttributeRuns(_ runs: [MacSyntaxHighlightAttributeRun]) {
        for run in runs {
            textStorage.addAttributes(run.attributes, range: run.range)
        }
    }

    private func applySyntaxHighlightAttributesInChunks(
        _ runs: [MacSyntaxHighlightAttributeRun],
        targetRange: NSRange,
        baseAttributes: [NSAttributedString.Key: Any],
        expectedRevision: Int,
        pendingApplication: PendingMacHighlightApplication
    ) async -> Bool {
        let chunkSize = 700
        var runIndex = 0

        while runIndex < runs.count || runIndex == 0 {
            guard !Task.isCancelled, document.revision == expectedRevision else {
                return false
            }
            guard textView.selectedRange().length == 0 else {
                pendingHighlightApplication = pendingApplication
                clearMatchingBracketHighlight()
                return false
            }

            isApplyingHighlight = true
            textStorage.beginEditing()
            if runIndex == 0 {
                resetSyntaxHighlightBaseAttributes(in: targetRange, baseAttributes: baseAttributes)
            }
            let upperBound = min(runs.count, runIndex + chunkSize)
            if runIndex < upperBound {
                applySyntaxHighlightAttributeRuns(Array(runs[runIndex..<upperBound]))
            }
            textStorage.endEditing()
            isApplyingHighlight = false

            guard upperBound < runs.count else {
                return !Task.isCancelled && document.revision == expectedRevision
            }

            highlightChunkDidApplyForTesting?(upperBound)
            runIndex = upperBound
            await Task.yield()
        }

        return !Task.isCancelled && document.revision == expectedRevision
    }

    private func restoreBaseFontForSyntaxOverrides(
        in targetRange: NSRange,
        baseFont: NSFont
    ) {
        var restoreRanges: [NSRange] = []

        unsafe textStorage.enumerateAttribute(.font, in: targetRange) { value, range, _ in
            guard let font = value as? NSFont,
                  !font.isEqual(baseFont)
            else {
                return
            }
            restoreRanges.append(range)
        }

        for range in restoreRanges {
            textStorage.addAttribute(.font, value: baseFont, range: range)
        }
    }

    private func recordAppliedHighlight(
        tokens: [SyntaxHighlightToken],
        source: String,
        revision: Int,
        language: SyntaxLanguage
    ) {
        lastHighlightTokens = tokens
        lastHighlightSource = source
        lastHighlightRevision = revision
        lastHighlightLanguage = language
    }

    private func applyPendingHighlightIfSelectionAllows() {
        guard textView.selectedRange().length == 0,
              let pendingHighlightApplication
        else {
            return
        }

        self.pendingHighlightApplication = nil
        applyHighlight(
            pendingHighlightApplication.tokens,
            expectedRevision: pendingHighlightApplication.expectedRevision,
            source: pendingHighlightApplication.source,
            language: pendingHighlightApplication.language,
            refreshRange: pendingHighlightApplication.refreshRange
        )
    }

    private func applyMatchingBracketHighlight(force: Bool = false) {
        let source = textView.string
        let textLength = textStorage.length
        let selection = textView.selectedRange()

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

        textStorage.beginEditing()

        for range in matchedBracketRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            textStorage.removeAttribute(.backgroundColor, range: clamped)
        }

        for range in newRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            textStorage.addAttribute(
                .backgroundColor,
                value: NSColor.syntaxEditorAlpha(resolvedColorTheme().bracketBackground, alpha: 0.24),
                range: clamped
            )
        }

        textStorage.endEditing()
        matchedBracketRanges = newRanges
        invalidateVisibleTextDisplay()
    }

    private func clearMatchingBracketHighlight() {
        guard !matchedBracketRanges.isEmpty else { return }

        let textLength = textStorage.length
        textStorage.beginEditing()
        for range in matchedBracketRanges {
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textLength)
            guard clamped.length > 0 else { continue }
            textStorage.removeAttribute(.backgroundColor, range: clamped)
        }
        textStorage.endEditing()
        matchedBracketRanges = []
        invalidateVisibleTextDisplay()
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let theme = resolvedColorTheme()
        return [
            .font: resolvedBaseFont(for: theme),
            .foregroundColor: theme.baseForeground,
        ]
    }

    private func resolvedBaseFont(for theme: SyntaxEditorResolvedColorTheme? = nil) -> NSFont {
        let fallbackFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let theme = theme ?? resolvedColorTheme()
        return theme.base.font?.platformFont(fallback: fallbackFont) ?? fallbackFont
    }

    private var currentThemeAppearance: SyntaxEditorThemeAppearance {
        effectiveAppearance.syntaxEditorThemeAppearance
    }

    private func resolvedColorTheme() -> SyntaxEditorResolvedColorTheme {
        (lastAppliedColorTheme ?? configuration.colorTheme).resolved(
            for: configuration.language,
            appearance: currentThemeAppearance
        )
    }

    private func updateEditorBackgroundColor() {
        updateEditorBackgroundColor(drawsBackground: configuration.drawsBackground)
    }

    private func updateEditorBackgroundColor(drawsBackground: Bool) {
        let color = resolvedColorTheme().background
        scrollView.drawsBackground = drawsBackground
        scrollView.backgroundColor = color
        textView.backgroundColor = color
    }

    private func applyLineWrappingConfiguration(lineWrappingEnabled: Bool) {
        guard !isApplyingLineWrappingConfiguration else { return }

        isApplyingLineWrappingConfiguration = true
        defer { isApplyingLineWrappingConfiguration = false }

        var layoutGeometryChanged = false

        if scrollView.hasHorizontalScroller == lineWrappingEnabled {
            scrollView.hasHorizontalScroller = !lineWrappingEnabled
            scrollView.tile()
            layoutGeometryChanged = true
        }

        let contentSize = effectiveScrollContentSize

        if textView.minSize.height != contentSize.height {
            textView.minSize = NSSize(width: 0, height: contentSize.height)
        }

        let maxTextViewSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if textView.maxSize != maxTextViewSize {
            textView.maxSize = maxTextViewSize
        }

        if lineWrappingEnabled {
            if textView.isHorizontallyResizable {
                textView.isHorizontallyResizable = false
                layoutGeometryChanged = true
            }
            if textView.autoresizingMask != [.width] {
                textView.autoresizingMask = [.width]
                layoutGeometryChanged = true
            }

            let wrappingWidth = max(0, contentSize.width)
            var frame = textView.frame
            let frameHeight = max(frame.height, contentSize.height)
            if !frame.width.isNearlyEqual(to: wrappingWidth) || !frame.height.isNearlyEqual(to: frameHeight) {
                frame.size = NSSize(width: wrappingWidth, height: frameHeight)
                textView.frame = frame
                layoutGeometryChanged = true
            }

            let containerSize = NSSize(width: wrappingWidth, height: CGFloat.greatestFiniteMagnitude)
            if !textContainer.containerSize.isNearlyEqual(to: containerSize) {
                textContainer.containerSize = containerSize
                layoutGeometryChanged = true
            }
            if !textContainer.widthTracksTextView {
                textContainer.widthTracksTextView = true
                layoutGeometryChanged = true
            }
            if textContainer.lineBreakMode != .byWordWrapping {
                textContainer.lineBreakMode = .byWordWrapping
                layoutGeometryChanged = true
            }

            if resetHorizontalClipOriginForWrapping() {
                layoutGeometryChanged = true
            }
        } else {
            if !textView.isHorizontallyResizable {
                textView.isHorizontallyResizable = true
                layoutGeometryChanged = true
            }
            if !textView.autoresizingMask.isEmpty {
                textView.autoresizingMask = []
                layoutGeometryChanged = true
            }

            let containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            if !textContainer.containerSize.isNearlyEqual(to: containerSize) {
                textContainer.containerSize = containerSize
                layoutGeometryChanged = true
            }
            if textContainer.widthTracksTextView {
                textContainer.widthTracksTextView = false
                layoutGeometryChanged = true
            }
            if textContainer.lineBreakMode != .byClipping {
                textContainer.lineBreakMode = .byClipping
                layoutGeometryChanged = true
            }
        }

        if layoutGeometryChanged {
            invalidateTextLayoutAfterGeometryChange()
        }
    }

    private var effectiveScrollContentSize: NSSize {
        let contentSize = scrollView.contentSize
        let contentInsets = scrollView.contentView.contentInsets
        let width = contentSize.width > 0 ? contentSize.width : bounds.width
        let height = contentSize.height > 0 ? contentSize.height : bounds.height
        return NSSize(
            width: max(0, width - max(0, contentInsets.left) - max(0, contentInsets.right)),
            height: max(0, height - max(0, contentInsets.bottom))
        )
    }

    private func resetHorizontalClipOriginForWrapping() -> Bool {
        let clipView = scrollView.contentView
        let targetOriginX = -max(0, clipView.contentInsets.left)
        guard !clipView.bounds.origin.x.isNearlyEqual(to: targetOriginX) else { return false }

        clipView.scroll(to: NSPoint(x: targetOriginX, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    private func invalidateTextLayoutAfterGeometryChange() {
        layoutManager.textContainerChangedGeometry(textContainer)

        if textStorage.length > 0 {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        }

        layoutManager.ensureLayout(for: textContainer)
        textView.needsDisplay = true
        scrollView.contentView.needsDisplay = true
    }

    private func invalidateVisibleTextDisplay() {
        guard textStorage.length > 0 else { return }

        let visibleRect = textView.visibleRect
        guard !visibleRect.isEmpty else { return }

        let textContainerOrigin = textView.textContainerOrigin
        let visibleContainerRect = visibleRect.offsetBy(
            dx: -textContainerOrigin.x,
            dy: -textContainerOrigin.y
        )
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        guard glyphRange.length > 0 else {
            textView.setNeedsDisplay(visibleRect)
            return
        }

        layoutManager.invalidateDisplay(forGlyphRange: glyphRange)
        textView.setNeedsDisplay(visibleRect)
    }
}

@MainActor
public final class SyntaxEditorViewController: NSViewController, NSTextViewDelegate {
    public private(set) var document: SyntaxEditorDocument
    public private(set) var configuration: SyntaxEditorConfiguration
    public let editorView: SyntaxEditorView

    public var textView: NSTextView {
        editorView.textView
    }

    public var scrollView: NSScrollView {
        editorView
    }

    public init(
        document: SyntaxEditorDocument = SyntaxEditorDocument(),
        configuration: SyntaxEditorConfiguration = SyntaxEditorConfiguration()
    ) {
        self.document = document
        self.configuration = configuration
        self.editorView = SyntaxEditorView(document: document, configuration: configuration)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        view = editorView
    }

    public func update(
        document nextDocument: SyntaxEditorDocument,
        configuration nextConfiguration: SyntaxEditorConfiguration
    ) {
        let documentChanged = document !== nextDocument
        let configurationChanged = configuration !== nextConfiguration
        guard documentChanged || configurationChanged else { return }

        document = nextDocument
        configuration = nextConfiguration
        editorView.update(document: nextDocument, configuration: nextConfiguration)
    }

    internal func synchronizeDocumentForTesting() {
        editorView.synchronizeDocumentForTesting()
    }

    public func textDidChange(_ notification: Notification) {
        editorView.textDidChange(notification)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        editorView.textViewDidChangeSelection(notification)
    }

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        editorView.textView(
            textView,
            shouldChangeTextIn: affectedCharRange,
            replacementString: replacementString
        )
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        editorView.textView(textView, doCommandBy: commandSelector)
    }
}

private extension NSColor {
    static func syntaxEditorAlpha(_ color: NSColor, alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolvedColor = color.withAlphaComponent(alpha)
            appearance.performAsCurrentDrawingAppearance {
                resolvedColor = color.withAlphaComponent(alpha)
            }
            return resolvedColor
        }
    }
}

private extension NSAppearance {
    var syntaxEditorThemeAppearance: SyntaxEditorThemeAppearance {
        let match = bestMatch(from: [
            .darkAqua,
            .accessibilityHighContrastDarkAqua,
            .vibrantDark,
            .accessibilityHighContrastVibrantDark,
            .aqua,
            .accessibilityHighContrastAqua,
            .vibrantLight,
            .accessibilityHighContrastVibrantLight,
        ])
        return match == .darkAqua
            || match == .accessibilityHighContrastDarkAqua
            || match == .vibrantDark
            || match == .accessibilityHighContrastVibrantDark
            ? .dark
            : .light
    }
}

private extension CGFloat {
    func isNearlyEqual(to other: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        abs(self - other) <= tolerance
    }
}

private extension NSSize {
    func isNearlyEqual(to other: NSSize, tolerance: CGFloat = 0.5) -> Bool {
        width.isNearlyEqual(to: other.width, tolerance: tolerance)
            && height.isNearlyEqual(to: other.height, tolerance: tolerance)
    }
}
#endif
