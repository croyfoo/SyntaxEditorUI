#if canImport(AppKit)
import AppKit
import ObservationBridge
import SyntaxEditorCore
import SyntaxEditorUICommon

enum EditorShortcutAction {
    case indent
    case outdent
    case toggleComment
    case toggleLineWrapping
    case increaseFontSize
    case decreaseFontSize
    case resetFontSize
}

extension EditorShortcutAction {
    init?(command: SyntaxEditorMenuCommand) {
        switch command {
        case .shiftRight:
            self = .indent
        case .shiftLeft:
            self = .outdent
        case .commentSelection:
            self = .toggleComment
        case .wrapLines:
            self = .toggleLineWrapping
        case .increaseFontSize:
            self = .increaseFontSize
        case .decreaseFontSize:
            self = .decreaseFontSize
        case .resetFontSize:
            self = .resetFontSize
        }
    }
}

private struct PendingHighlightApplication {
    let tokens: [SyntaxHighlightToken]
    let expectedRevision: Int
    let source: String
    let language: SyntaxLanguage
    let refreshRange: NSRange
    let mutation: SyntaxHighlightMutation?
}

private struct SyntaxHighlightAttributeKey: Hashable {
    let syntaxID: EditorSourceSyntaxID
    let language: SyntaxLanguage
}

private struct SyntaxHighlightStyle {
    let foregroundColor: NSColor
    let font: NSFont?
}

private struct SyntaxHighlightResolvedRun {
    let key: SyntaxHighlightAttributeKey
    var range: NSRange
    let style: SyntaxHighlightStyle
}


private struct SyntaxHighlightAttributeResolver {
    let colorTheme: SyntaxEditorColorTheme
    let defaultLanguage: SyntaxLanguage
    let appearance: SyntaxEditorThemeAppearance
    let baseFont: NSFont
    let fontSizeDelta: Int

    private var styleCache: [SyntaxHighlightAttributeKey: SyntaxHighlightStyle] = [:]
    private var missingAttributeKeys: Set<SyntaxHighlightAttributeKey> = []
    private var fontCache: [SyntaxEditorFontDescriptor: NSFont] = [:]

    init(
        colorTheme: SyntaxEditorColorTheme,
        defaultLanguage: SyntaxLanguage,
        appearance: SyntaxEditorThemeAppearance,
        baseFont: NSFont,
        fontSizeDelta: Int
    ) {
        self.colorTheme = colorTheme
        self.defaultLanguage = defaultLanguage
        self.appearance = appearance
        self.baseFont = baseFont
        self.fontSizeDelta = fontSizeDelta
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
            in: colorTheme,
            language: effectiveLanguage,
            appearance: appearance
        ) else {
            missingAttributeKeys.insert(key)
            return nil
        }

        var font: NSFont?
        if let fontDescriptor = style.font {
            font = platformFont(for: fontDescriptor)
        }
        let resolvedStyle = SyntaxHighlightStyle(foregroundColor: style.foreground, font: font)
        styleCache[key] = resolvedStyle
        return (key, resolvedStyle)
    }

    private mutating func platformFont(for descriptor: SyntaxEditorFontDescriptor) -> NSFont {
        if let cached = fontCache[descriptor] {
            return cached
        }
        let font = descriptor.platformFont(fallback: baseFont, fontSizeDelta: fontSizeDelta)
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

@MainActor
public final class SyntaxEditorView: NSScrollView {
    public private(set) var document: SyntaxEditorDocument
    public private(set) var configuration: SyntaxEditorConfiguration
    public var isFindInteractionEnabled = true {
        didSet {
            guard isFindInteractionEnabled != oldValue else { return }
            applyFindInteractionConfiguration()
        }
    }

    private let fallbackUndoManager = UndoManager()
    private let guardedUndoManager = SyntaxEditorReadOnlyGuardedUndoManager()
    let textSystem: EditorTextSystem
    let textView: SyntaxEditorTextInputView
    let textStorage: NSTextStorage
    let layoutManager: NSTextLayoutManager
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
    private var pendingUndoSelection: NSRange?
    private var pendingHighlightMutation: SyntaxHighlightMutation?
    private var pendingHighlightApplication: PendingHighlightApplication?
    var matchedBracketRanges: [NSRange] = []
    private var visibleTextDisplayInvalidationCount = 0
    private var fullTextDisplayInvalidationCount = 0
    private var isApplyingUndoRedo = false
    private var isApplyingCommandSelection = false
    private var isApplyingLineWrappingConfiguration = false
    private var isScrollViewConfigured = false
    private var lastAppliedColorTheme: SyntaxEditorColorTheme?
    private var lastAppliedFontSizeDelta: Int
    private var lastAppliedDocumentRevision = 0
    private let documentObservations = ObservationScope()
    private let configurationObservations = ObservationScope()
    var documentDeliveryForTesting: ObservationDelivery?
    var configurationDeliveryForTesting: ObservationDelivery?

    private var scrollView: NSScrollView { self }

    public var text: String {
        get { textView.string }
        set {
            document.replaceText(newValue, selectedRange: selectedRange)
            applyObservedDocumentChange(forceTextUpdate: true)
        }
    }

    public var selectedRange: NSRange {
        get { textView.selectedRange() }
        set { textView.setSelectedRange(newValue) }
    }

    public var isEditable: Bool {
        get { configuration.isEditable }
        set {
            guard configuration.isEditable != newValue else { return }
            configuration.isEditable = newValue
        }
    }

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

        let textSystem = EditorTextSystem(
            container: NSTextContainer(
                size: NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
            )
        )
        let nativeTextView = SyntaxEditorTextInputView(textSystem: textSystem)
        self.textSystem = textSystem
        self.textStorage = textSystem.textStorage
        self.layoutManager = textSystem.layoutManager
        self.textContainer = textSystem.container
        self.textView = nativeTextView
        self.lastAppliedFontSizeDelta = configuration.fontSizeDelta

        super.init(frame: .zero)

        nativeTextView.guardedUndoManager = guardedUndoManager
        guardedUndoManager.allowsMutation = { [weak self] in
            self?.configuration.isEditable ?? true
        }
        nativeTextView.shortcutHandler = { [weak self] action in
            guard let self else { return false }
            return self.handleShortcut(action)
        }
        nativeTextView.shortcutValidator = { [weak self] action in
            guard let self else { return false }
            return self.canHandleShortcut(action)
        }
        nativeTextView.commandHandler = { [weak self] selector in
            guard let self else { return false }
            return self.textView(self.textView, doCommandBy: selector)
        }
        nativeTextView.lineWrappingStateProvider = { [weak self] in
            self?.configuration.lineWrappingEnabled ?? false
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
            drawsBackground: configuration.drawsBackground,
            fontSizeDelta: configuration.fontSizeDelta
        )
        applyObservedDocumentChange()
    }

    internal func waitForPendingHighlightForTesting() async {
        await highlightTask?.value
    }

    internal var bracketHighlightRangesForTesting: [NSRange] {
        matchedBracketRanges
    }

    internal var visibleTextDisplayInvalidationCountForTesting: Int {
        visibleTextDisplayInvalidationCount
    }

    internal var fullTextDisplayInvalidationCountForTesting: Int {
        fullTextDisplayInvalidationCount
    }

    internal var fragmentDisplayInvalidationCountForTesting: Int {
        textView.fragmentDisplayInvalidationCount
    }

    internal var syntaxForegroundMaterializationCountForTesting: Int {
        textSystem.styleStore.epoch
    }

    internal var syntaxRenderingAttributeApplicationCountForTesting: Int {
        textView.syntaxRenderingAttributeApplicationCountForTesting
    }

    internal var syntaxColorRunCountForTesting: Int {
        textSystem.styleStore.appliedColorRunsForTesting.count
    }

    internal func materializeSyntaxForegroundForTesting(in range: NSRange) {
        textSystem.invalidateRenderingAttributes(for: range)
        textView.setNeedsDisplayForTextRanges([range])
    }

    internal func syntaxForegroundColorForTesting(at location: Int) -> NSColor? {
        guard location >= 0,
              location < textStorage.length
        else {
            return nil
        }
        return textSystem.styleStore.foregroundColor(at: location)
    }

    internal func baseForegroundColorForTesting() -> NSColor? {
        textSystem.styleStore.baseForeground
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

        textView.layoutVisibleViewportIfNeeded()
    }

    public override var acceptsFirstResponder: Bool {
        true
    }

    public override func becomeFirstResponder() -> Bool {
        guard let window = unsafe self.window else {
            return textView.becomeFirstResponder()
        }
        if window.firstResponder === textView {
            return true
        }
        return window.makeFirstResponder(textView)
    }

    public func textDidChange(_ notification: Notification) {
        textDidChange()
    }

    private func textDidChange() {
        guard !isApplyingModel, !isApplyingHighlight else {
            pendingEditStartUTF16 = nil
            pendingUndoSelection = nil
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
        let previousSelection = pendingUndoSelection
        pendingEditStartUTF16 = nil
        pendingUndoSelection = nil
        pendingHighlightMutation = nil
        let refreshStartUTF16 = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
            in: nextText,
            around: editStartUTF16
        )
        if !isApplyingUndoRedo {
            registerUndoForTextInput(
                previousText: previousText,
                nextText: nextText,
                previousSelection: previousSelection,
                nextSelection: textView.selectedRange(),
                mutation: mutation,
                refreshStartUTF16: refreshStartUTF16
            )
        }
        prepareSyntaxHighlightRenderingForPendingTextChange(
            mutation: mutation,
            source: nextText,
            refreshStartUTF16: refreshStartUTF16
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
        textSelectionDidChange()
    }

    private func textSelectionDidChange() {
        if !isApplyingCommandSelection {
            commandEngine.invalidateTransientState()
        }
        applyMatchingBracketHighlight()
        applyPendingHighlightIfSelectionAllows()
    }

    private func textShouldChange(inRanges affectedRanges: [NSRange], replacementStrings: [String]) -> Bool {
        guard let affectedCharRange = affectedRanges.first else { return true }
        let replacementString = replacementStrings.first
        guard !isApplyingModel, !isApplyingHighlight else {
            pendingUndoSelection = nil
            return true
        }

        guard configuration.isEditable else {
            pendingEditStartUTF16 = nil
            pendingUndoSelection = nil
            pendingHighlightMutation = nil
            return false
        }

        pendingEditStartUTF16 = affectedCharRange.location
        pendingUndoSelection = affectedCharRange
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

    func textView(
        _ textView: SyntaxEditorTextInputView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        textShouldChange(
            inRanges: [affectedCharRange],
            replacementStrings: replacementString.map { [$0] } ?? []
        )
    }

    func textView(_ textView: SyntaxEditorTextInputView, doCommandBy commandSelector: Selector) -> Bool {
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
        textView.drawsBackground = false
        updateEditorBackgroundColor()
        textView.isEditable = configuration.isEditable
        textView.guardedUndoManager = guardedUndoManager
        textView.didChangeText = { [weak self] in
            self?.textDidChange()
        }
        textView.didChangeSelection = { [weak self] in
            self?.textSelectionDidChange()
        }
        textView.shouldChangeText = { [weak self] ranges, replacements in
            self?.textShouldChange(inRanges: ranges, replacementStrings: replacements) ?? true
        }
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
            textView.usesFindBar = false
            textView.isIncrementalSearchingEnabled = false
            textView.usesFindPanel = false
        }
    }

    private var activeUndoManager: UndoManager? {
        textView.undoManager ?? fallbackUndoManager
    }

    private func configureBaseTextViewAppearance() {
        let base = baseAttributes()
        updateRenderingBaseForeground(from: base)
        textView.font = base[.font] as? NSFont ?? textView.font
        textView.textColor = base[.foregroundColor] as? NSColor ?? textView.textColor
        textView.typingAttributes = base
    }

    private func updateTextViewFontAndTypingAttributes() {
        let base = baseAttributes()
        updateRenderingBaseForeground(from: base)
        textView.font = base[.font] as? NSFont ?? textView.font
        textView.typingAttributes = base
    }

    private func updateTypingAttributes() {
        let base = baseAttributes()
        updateRenderingBaseForeground(from: base)
        textView.typingAttributes = base
    }

    private func updateRenderingBaseForeground(from base: [NSAttributedString.Key: Any]) {
        textSystem.styleStore.updateBaseForeground(
            base[.foregroundColor] as? NSColor,
            textLength: textStorage.length
        )
    }

    private func startConfigurationObservation(schedulesInitialHighlight: Bool = true) {
        configurationDeliveryForTesting = configurationObservations.observe(configuration, tracking: { configuration in
            _ = configuration.language
            _ = configuration.isEditable
            _ = configuration.lineWrappingEnabled
            _ = configuration.colorTheme
            _ = configuration.drawsBackground
            _ = configuration.fontSizeDelta
        }) { [weak self] event, configuration in
            guard let self else { return }
            self.applyObservedConfiguration(
                language: configuration.language,
                isEditable: configuration.isEditable,
                lineWrappingEnabled: configuration.lineWrappingEnabled,
                colorTheme: configuration.colorTheme,
                drawsBackground: configuration.drawsBackground,
                fontSizeDelta: configuration.fontSizeDelta,
                forceLanguageRefresh: event.kind == .initial,
                schedulesHighlight: event.kind != .initial || schedulesInitialHighlight
            )
        }
    }

    private func startDocumentObservation() {
        documentDeliveryForTesting = documentObservations.observe(document, tracking: { document in
            _ = document.revision
        }) { [weak self] event, document in
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
            prepareSyntaxHighlightRenderingForPendingTextChange(
                mutation: highlightMutation,
                source: text,
                refreshStartUTF16: 0
            )
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
        fontSizeDelta: Int,
        forceLanguageRefresh: Bool = false,
        schedulesHighlight: Bool = true
    ) {
        let previousColorTheme = lastAppliedColorTheme
        let colorThemeChanged = previousColorTheme.map { $0 != colorTheme } ?? true
        let fontSizeDeltaChanged = lastAppliedFontSizeDelta != fontSizeDelta
        if colorThemeChanged {
            applyBaseForegroundColorChange(from: previousColorTheme, to: colorTheme)
        }
        lastAppliedColorTheme = colorTheme
        lastAppliedFontSizeDelta = fontSizeDelta
        updateTextViewFontAndTypingAttributes()
        if fontSizeDeltaChanged {
            applyResolvedFontsToExistingText()
        }
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
        } else if (colorThemeChanged || fontSizeDeltaChanged) && schedulesHighlight {
            reapplyCachedHighlight()
        }
    }

    private func applyBaseForegroundColorChange(
        from _: SyntaxEditorColorTheme?,
        to colorTheme: SyntaxEditorColorTheme
    ) {
        let nextBaseForeground = colorTheme
            .resolved(for: configuration.language, appearance: currentThemeAppearance)
            .baseForeground
        textSystem.styleStore.updateBaseForeground(nextBaseForeground, textLength: textStorage.length)
        invalidateVisibleTextDisplay()
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
            let mutation = change.flatMap(Self.highlightMutation)
            prepareSyntaxHighlightRenderingForPendingTextChange(
                mutation: mutation,
                source: nextText,
                refreshStartUTF16: result.refreshStartUTF16
            )
            scheduleHighlight(
                source: nextText,
                language: configuration.language,
                revision: change?.revision ?? document.revision,
                mutation: mutation,
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

    private func registerUndoForTextInput(
        previousText: String,
        nextText: String,
        previousSelection: NSRange?,
        nextSelection: NSRange,
        mutation: SyntaxHighlightMutation?,
        refreshStartUTF16: Int
    ) {
        let edits: [SyntaxEditorTextEdit]
        let restoreEdits: [SyntaxEditorTextEdit]
        if let mutation {
            edits = [
                SyntaxEditorTextEdit(
                    range: NSRange(location: mutation.location, length: mutation.length),
                    replacement: mutation.replacement
                ),
            ]
            restoreEdits = SyntaxEditorDocument.inverseEdits(for: edits, in: previousText)
        } else {
            edits = [
                SyntaxEditorTextEdit(
                    range: NSRange(location: 0, length: previousText.utf16.count),
                    replacement: nextText
                ),
            ]
            restoreEdits = [
                SyntaxEditorTextEdit(
                    range: NSRange(location: 0, length: nextText.utf16.count),
                    replacement: previousText
                ),
            ]
        }

        registerUndoAction(
            restore: EditorUndoState(
                edits: restoreEdits,
                selectedRange: previousSelection ?? NSRange(location: 0, length: 0),
                refreshStartUTF16: refreshStartUTF16
            ),
            counterpart: EditorUndoState(
                edits: edits,
                selectedRange: nextSelection,
                refreshStartUTF16: refreshStartUTF16
            )
        )
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

        let affectedRanges = validationEdits.map(\.range)
        let replacementStrings = validationEdits.map(\.replacement)
        guard textView.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings) else {
            return false
        }

        guard applyStorageTextEdits(edits) else { return false }
        textView.didChangeTextNotification()
        return true
    }

    private func canHandleShortcut(_ action: EditorShortcutAction) -> Bool {
        switch action {
        case .indent, .outdent, .toggleComment:
            configuration.isEditable
        case .toggleLineWrapping, .increaseFontSize, .decreaseFontSize, .resetFontSize:
            true
        }
    }

    private func handleShortcut(_ action: EditorShortcutAction) -> Bool {
        switch action {
        case .indent:
            return runIndentCommand()
        case .outdent:
            return runOutdentCommand()
        case .toggleComment:
            return runToggleCommentCommand()
        case .toggleLineWrapping:
            return runToggleLineWrappingCommand()
        case .increaseFontSize:
            configuration.increaseFontSize()
            return true
        case .decreaseFontSize:
            configuration.decreaseFontSize()
            return true
        case .resetFontSize:
            configuration.resetFontSize()
            return true
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
        highlightTask = Task(priority: .utility) { [weak self, highlighter, expectedSource, language, revision, mutation] in
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
            await self?.applyHighlightResultFromScheduledTask(result, mutation: mutation)
        }
    }

    private func applyHighlightResultFromScheduledTask(
        _ result: SyntaxHighlightResult,
        mutation: SyntaxHighlightMutation?
    ) async {
        guard !Task.isCancelled else { return }
        guard document.revision == result.revision else { return }
        let refreshRange = highlightApplicationRefreshRange(
            for: result,
            mutation: mutation
        )
        await applyHighlightFromScheduledTask(
            result.tokens,
            expectedRevision: result.revision,
            source: result.source,
            language: result.language,
            refreshRange: refreshRange,
            mutation: mutation
        )
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
            refreshRange: NSRange(location: 0, length: source.utf16.count),
            mutation: nil
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
        resetSyntaxHighlightRenderingState(textLength: textStorage.length)
    }

    private func replaceEntireStorageText(_ nextText: String) {
        resetSyntaxHighlightRenderingState(textLength: nextText.utf16.count)
        TextEditingTransaction.perform(on: textSystem.textContentStorage) { textStorage in
            textStorage.setAttributedString(NSAttributedString(string: nextText, attributes: storageBaseAttributes()))
        }
        textView.invalidateTextLayout()
    }

    private func applyStorageTextEdits(_ edits: [SyntaxEditorTextEdit]) -> Bool {
        guard editsAreValid(edits) else { return false }

        let base = storageBaseAttributes()
        TextEditingTransaction.perform(on: textSystem.textContentStorage) { textStorage in
            for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
                let replacement = NSAttributedString(string: edit.replacement, attributes: base)
                textStorage.replaceCharacters(in: edit.range, with: replacement)
            }
        }
        textView.invalidateTextLayout()
        return true
    }

    private func applyResolvedFontsToExistingText() {
        let textRange = NSRange(location: 0, length: textStorage.length)
        guard textRange.length > 0,
              let baseFont = baseAttributes()[.font] as? NSFont
        else {
            return
        }

        var updates: [(range: NSRange, font: NSFont)] = []
        let source = textView.string
        if lastHighlightRevision == document.revision,
           lastHighlightLanguage == configuration.language,
           lastHighlightSource == source {
            var resolver = makeSyntaxHighlightAttributeResolver(baseAttributes: baseAttributes())
            let runSet = syntaxHighlightRunSet(
                for: lastHighlightTokens,
                targetRange: textRange,
                textLength: textStorage.length,
                resolver: &resolver,
                baseFont: baseFont
            )
            for run in runSet.fontRuns {
                updates.append((run.range, run.font))
            }
        }

        TextEditingTransaction.perform(on: textSystem.textContentStorage) { textStorage in
            textStorage.addAttribute(.font, value: baseFont, range: textRange)
            for update in updates {
                textStorage.addAttribute(.font, value: update.font, range: update.range)
            }
        }
        clearMaterializedSyntaxHighlightRendering()
        invalidateVisibleTextDisplay()
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
        refreshRange: NSRange,
        mutation: SyntaxHighlightMutation?
    ) -> Bool {
        guard document.revision == expectedRevision else { return false }
        guard configuration.language == expectedLanguage,
              textView.string == expectedSource
        else {
            pendingHighlightApplication = nil
            return false
        }
        let pendingApplication = PendingHighlightApplication(
            tokens: tokens,
            expectedRevision: expectedRevision,
            source: expectedSource,
            language: expectedLanguage,
            refreshRange: refreshRange,
            mutation: mutation
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

        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        installSyntaxHighlightRendering(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            baseAttributes: base,
            mutation: mutation
        )
        textView.typingAttributes = base
        applyMatchingBracketHighlight(force: true)
        invalidateSyntaxHighlightDisplay(for: targetRange)
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
        refreshRange: NSRange,
        mutation: SyntaxHighlightMutation?
    ) async -> Bool {
        guard document.revision == expectedRevision else { return false }
        guard configuration.language == expectedLanguage,
              textView.string == expectedSource
        else {
            pendingHighlightApplication = nil
            return false
        }
        let pendingApplication = PendingHighlightApplication(
            tokens: tokens,
            expectedRevision: expectedRevision,
            source: expectedSource,
            language: expectedLanguage,
            refreshRange: refreshRange,
            mutation: mutation
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
        guard !Task.isCancelled else { return false }
        isApplyingHighlight = true
        defer { isApplyingHighlight = false }
        await installSyntaxHighlightRenderingIncrementally(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            baseAttributes: base,
            mutation: mutation
        )
        guard !Task.isCancelled, document.revision == expectedRevision else { return false }

        textView.typingAttributes = base
        applyMatchingBracketHighlight(force: true)
        invalidateSyntaxHighlightDisplay(for: targetRange)
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
    ) -> SyntaxHighlightAttributeResolver {
        SyntaxHighlightAttributeResolver(
            colorTheme: configuration.colorTheme,
            defaultLanguage: configuration.language,
            appearance: currentThemeAppearance,
            baseFont: (baseAttributes[.font] as? NSFont) ?? resolvedBaseFont(),
            fontSizeDelta: configuration.fontSizeDelta
        )
    }

    private func installSyntaxHighlightRendering(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        baseAttributes: [NSAttributedString.Key: Any],
        mutation: SyntaxHighlightMutation?
    ) {
        guard let operations = syntaxHighlightOperations(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            baseAttributes: baseAttributes,
            mutation: mutation
        ) else {
            return
        }
        TextEditingTransaction.apply(operations, to: textSystem.textContentStorage)
        textSystem.invalidateRenderingAttributes(for: targetRange)
    }

    private func installSyntaxHighlightRenderingIncrementally(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        baseAttributes: [NSAttributedString.Key: Any],
        mutation: SyntaxHighlightMutation?
    ) async {
        guard let operations = syntaxHighlightOperations(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            baseAttributes: baseAttributes,
            mutation: mutation
        ) else {
            return
        }
        await TextEditingTransaction.applyIncrementally(operations, to: textSystem.textContentStorage)
        textSystem.invalidateRenderingAttributes(for: targetRange)
    }

    private func syntaxHighlightOperations(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        baseAttributes: [NSAttributedString.Key: Any],
        mutation _: SyntaxHighlightMutation?
    ) -> HighlightStyleOperations? {
        var resolver = makeSyntaxHighlightAttributeResolver(baseAttributes: baseAttributes)
        let runSet = syntaxHighlightRunSet(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            resolver: &resolver,
            baseFont: baseAttributes[.font] as? NSFont
        )
        guard let baseForeground = baseAttributes[.foregroundColor] as? NSColor else {
            return nil
        }
        return textSystem.styleStore.apply(
            runSet,
            refreshedRange: targetRange,
            mutation: nil,
            textLength: textLength,
            baseForeground: baseForeground,
            baseFont: baseAttributes[.font] as? NSFont
        )
    }

    private func syntaxHighlightRunSet(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        resolver: inout SyntaxHighlightAttributeResolver,
        baseFont: NSFont?
    ) -> HighlightRunSet {
        let resolvedRuns = syntaxHighlightResolvedRuns(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            resolver: &resolver
        )
        var colorRuns: [HighlightColorRun] = []
        colorRuns.reserveCapacity(resolvedRuns.count)
        var fontRuns: [HighlightFontRun] = []
        fontRuns.reserveCapacity(resolvedRuns.count)

        for run in resolvedRuns {
            if var last = colorRuns.last,
               last.color.isEqual(run.style.foregroundColor),
               last.range.upperBound >= run.range.location,
               run.range.upperBound >= last.range.location {
                let lowerBound = min(last.range.location, run.range.location)
                let upperBound = max(last.range.upperBound, run.range.upperBound)
                last.range = NSRange(location: lowerBound, length: upperBound - lowerBound)
                colorRuns[colorRuns.count - 1] = last
            } else {
                colorRuns.append(HighlightColorRun(range: run.range, color: run.style.foregroundColor))
            }
            guard let font = run.style.font,
                  baseFont.map({ !font.isEqual($0) }) ?? true
            else {
                continue
            }
            fontRuns.append(HighlightFontRun(range: run.range, font: font))
        }

        return HighlightRunSet(colorRuns: colorRuns, fontRuns: fontRuns)
    }

    private func syntaxHighlightResolvedRuns(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        resolver: inout SyntaxHighlightAttributeResolver
    ) -> [SyntaxHighlightResolvedRun] {
        var runs: [SyntaxHighlightResolvedRun] = []
        runs.reserveCapacity(min(tokens.count, 1024))

        let tokenStartIndex = firstTokenIndex(intersecting: targetRange, in: tokens)
        for token in tokens[tokenStartIndex...] {
            guard token.range.location < targetRange.upperBound else { break }
            let clamped = SyntaxEditorRangeUtilities.clampedRange(token.range, utf16Length: textLength)
            let intersection = SyntaxEditorRangeUtilities.intersection(of: clamped, and: targetRange)
            guard intersection.length > 0 else {
                continue
            }
            guard let resolved = resolver.style(for: token.syntaxID, language: token.language) else {
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
                    SyntaxHighlightResolvedRun(
                        key: resolved.key,
                        range: intersection,
                        style: resolved.style
                    )
                )
            }
        }

        return runs
    }

    private func firstTokenIndex(
        intersecting range: NSRange,
        in tokens: [SyntaxHighlightToken]
    ) -> Int {
        var lowerBound = 0
        var upperBound = tokens.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if tokens[midIndex].range.upperBound <= range.location {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return lowerBound
    }

    private func subtractSyntaxHighlightRange(
        _ range: NSRange,
        from runs: inout [SyntaxHighlightResolvedRun]
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
                let trailingRun = SyntaxHighlightResolvedRun(
                    key: run.key,
                    range: NSRange(location: resetEnd, length: runEnd - resetEnd),
                    style: run.style
                )
                runs[index].range = NSRange(location: runStart, length: resetStart - runStart)
                runs.insert(trailingRun, at: index + 1)
            }
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
            refreshRange: pendingHighlightApplication.refreshRange,
            mutation: pendingHighlightApplication.mutation
        )
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let theme = resolvedColorTheme()
        return [
            .font: resolvedBaseFont(for: theme),
            .foregroundColor: theme.baseForeground,
        ]
    }

    private func storageBaseAttributes() -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes()
        attributes.removeValue(forKey: .foregroundColor)
        return attributes
    }

    private func resolvedBaseFont(for theme: SyntaxEditorResolvedColorTheme? = nil) -> NSFont {
        let fallbackFont = NSFont.monospacedSystemFont(
            ofSize: SyntaxEditorFontSize.defaultEditorPointSize,
            weight: .regular
        )
        let theme = theme ?? resolvedColorTheme()
        return theme.base.font?.platformFont(
            fallback: fallbackFont,
            fontSizeDelta: configuration.fontSizeDelta
        ) ?? fallbackFont.syntaxEditorFontSizeAdjusted(by: configuration.fontSizeDelta)
    }

    private var currentThemeAppearance: SyntaxEditorThemeAppearance {
        effectiveAppearance.syntaxEditorThemeAppearance
    }

    func resolvedColorTheme() -> SyntaxEditorResolvedColorTheme {
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
        let estimatedDocumentSize = estimatedTextViewDocumentSize(minimumContentSize: contentSize)

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
            let frameHeight = estimatedDocumentSize.height
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

            var frame = textView.frame
            if !frame.width.isNearlyEqual(to: estimatedDocumentSize.width)
                || !frame.height.isNearlyEqual(to: estimatedDocumentSize.height)
            {
                frame.size = estimatedDocumentSize
                textView.frame = frame
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

    private func estimatedTextViewDocumentSize(minimumContentSize: NSSize) -> NSSize {
        let source = textView.string
        let baseFont = textView.font ?? resolvedBaseFont()
        let lineHeight = max(1, ceil(baseFont.ascender - baseFont.descender + baseFont.leading))
        var lineCount = 1
        var currentLineLength = 0
        var maximumLineLength = 0

        for codeUnit in source.utf16 {
            if codeUnit == 10 || codeUnit == 13 {
                maximumLineLength = max(maximumLineLength, currentLineLength)
                currentLineLength = 0
                lineCount += 1
            } else {
                currentLineLength += 1
            }
        }
        maximumLineLength = max(maximumLineLength, currentLineLength)

        let estimatedColumnWidth = max(1, baseFont.pointSize * 0.65)
        let horizontalPadding = textContainer.lineFragmentPadding * 2
        let estimatedWidth = ceil(CGFloat(maximumLineLength) * estimatedColumnWidth + horizontalPadding)
        let estimatedHeight = ceil(CGFloat(lineCount) * lineHeight)

        return NSSize(
            width: max(minimumContentSize.width, estimatedWidth),
            height: max(minimumContentSize.height, estimatedHeight)
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
        layoutManager.invalidateLayout(for: textSystem.textContentStorage.documentRange)
        textView.layoutVisibleViewport()
        textView.setNeedsDisplayForVisibleTextFragments()
    }

    private func invalidateTextDisplay(forCharacterRanges ranges: [NSRange]) {
        textView.setNeedsDisplayForTextRanges(ranges)
    }

    private func invalidateSyntaxHighlightDisplay(for refreshRange: NSRange) {
        guard let visibleRange = visibleTextCharacterRange() else { return }
        let intersection = SyntaxEditorRangeUtilities.intersection(of: refreshRange, and: visibleRange)
        guard intersection.length > 0 else { return }
        invalidateTextDisplay(forCharacterRanges: [intersection])
    }

    private func clearSyntaxHighlightRendering() {
        let base = baseAttributes()
        if let baseForeground = base[.foregroundColor] as? NSColor {
            let operations = textSystem.styleStore.clear(
                textLength: textStorage.length,
                baseForeground: baseForeground,
                baseFont: base[.font] as? NSFont
            )
            TextEditingTransaction.apply(operations, to: textSystem.textContentStorage)
        }
        invalidateVisibleTextDisplay()
    }

    private func resetSyntaxHighlightRenderingState(textLength: Int) {
        textSystem.styleStore.reset(textLength: textLength)
    }

    private func prepareSyntaxHighlightRenderingForPendingTextChange(
        mutation: SyntaxHighlightMutation?,
        source: String,
        refreshStartUTF16 _: Int
    ) {
        guard let mutation else {
            suspendSyntaxHighlightMaterialization()
            return
        }
        let invalidatedRange = pendingTextMutationReplacementRange(in: source, mutation: mutation)
        let base = baseAttributes()
        if let baseForeground = base[.foregroundColor] as? NSColor {
            let mutationOperations = textSystem.styleStore.apply(
                HighlightRunSet(colorRuns: [], fontRuns: []),
                refreshedRange: invalidatedRange,
                mutation: mutation,
                textLength: source.utf16.count,
                baseForeground: baseForeground,
                baseFont: base[.font] as? NSFont
            )
            TextEditingTransaction.apply(mutationOperations, to: textSystem.textContentStorage)
        }
        textView.setNeedsDisplayForTextRanges([invalidatedRange])
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

    private func suspendSyntaxHighlightMaterialization() {
        invalidateVisibleTextDisplay()
    }

    private func clearMaterializedSyntaxHighlightRendering() {
        invalidateVisibleTextDisplay()
    }

    private func invalidateVisibleTextDisplay() {
        guard textStorage.length > 0 else { return }
        visibleTextDisplayInvalidationCount += 1

        guard let visibleRange = visibleTextCharacterRange() else {
            textView.setNeedsDisplayForVisibleTextFragments()
            return
        }
        textView.setNeedsDisplayForTextRanges([visibleRange])
    }

    private func visibleTextCharacterRange() -> NSRange? {
        guard textStorage.length > 0 else { return nil }
        textView.layoutVisibleViewport()
        return textView.visibleCharacterRange()
    }
}

@MainActor
public final class SyntaxEditorViewController: NSViewController {
    public private(set) var document: SyntaxEditorDocument
    public private(set) var configuration: SyntaxEditorConfiguration
    public let editorView: SyntaxEditorView

    var textView: SyntaxEditorTextInputView {
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

    func textView(
        _ textView: SyntaxEditorTextInputView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        editorView.textView(
            textView,
            shouldChangeTextIn: affectedCharRange,
            replacementString: replacementString
        )
    }

    func textView(_ textView: SyntaxEditorTextInputView, doCommandBy commandSelector: Selector) -> Bool {
        editorView.textView(textView, doCommandBy: commandSelector)
    }
}

extension NSColor {
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

private extension NSFont {
    func syntaxEditorFontSizeAdjusted(by delta: Int) -> NSFont {
        withSize(SyntaxEditorFontSize.pointSize(pointSize, applying: delta))
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
