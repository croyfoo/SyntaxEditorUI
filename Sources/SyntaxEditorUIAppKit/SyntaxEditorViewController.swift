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
    let recordsCache: Bool
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
    public private(set) var model: SyntaxEditorModel
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
    private let modelObservations = ObservationScope()
    var modelDeliveryForTesting: ObservationDelivery?
    var modelConfigurationDeliveryForTesting: ObservationDelivery?

    private var scrollView: NSScrollView { self }

    public var text: String {
        get { textView.string }
        set {
            guard let change = model.replaceText(newValue, selectedRange: selectedRange) else {
                updateTypingAttributes()
                return
            }
            applyObservedModelChange(forceTextUpdate: true, observedRevision: change.revision)
        }
    }

    public var selectedRange: NSRange {
        get { textView.selectedRange() }
        set {
            textView.setSelectedRange(newValue)
            model.selectedRange = textView.selectedRange()
        }
    }

    public var isEditable: Bool {
        get { model.isEditable }
        set {
            guard model.isEditable != newValue else { return }
            model.isEditable = newValue
        }
    }

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
        self.lastAppliedDocumentRevision = model.revision

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
        self.lastAppliedFontSizeDelta = model.fontSizeDelta

        super.init(frame: .zero)

        nativeTextView.guardedUndoManager = guardedUndoManager
        guardedUndoManager.allowsMutation = { [weak self] in
            self?.model.isEditable ?? true
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
            self?.model.lineWrappingEnabled ?? false
        }

        configureScrollView()
        configureTextView()
        startModelObservation(schedulesInitialHighlight: false)
    }

    public func update(model nextModel: SyntaxEditorModel) {
        guard model !== nextModel else { return }

        modelObservations.cancelAll()
        activeUndoManager?.removeAllActions()
        commandEngine.invalidateTransientState()
        clearHighlightCache()
        model = nextModel
        startModelObservation()
    }

    internal func synchronizeDocumentForTesting() {
        applyObservedConfiguration(
            language: model.language,
            isEditable: model.isEditable,
            lineWrappingEnabled: model.lineWrappingEnabled,
            colorTheme: model.colorTheme,
            drawsBackground: model.drawsBackground,
            fontSizeDelta: model.fontSizeDelta
        )
        applyObservedModelChange()
        applyObservedSelection(model.selectedRange)
    }

    internal func waitForPendingHighlightForTesting() async {
        await highlightTask?.value
    }

    internal func setApplyingHighlightForTesting(_ isApplying: Bool) {
        isApplyingHighlight = isApplying
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

    internal var lineMetricsFullRebuildCountForTesting: Int {
        textView.lineMetrics.fullRebuildCount
    }

    internal func materializeSyntaxForegroundForTesting(in range: NSRange) {
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
        modelObservations.cancelAll()
    }

    public override func layout() {
        super.layout()
        applyLineWrappingConfiguration(lineWrappingEnabled: model.lineWrappingEnabled)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateEditorBackgroundColor()
        applyBaseForegroundColorChange(from: lastAppliedColorTheme, to: lastAppliedColorTheme ?? model.colorTheme)
        updateTextViewFontAndTypingAttributes()
        reapplyCachedHighlight()
        applyMatchingBracketHighlight(force: true)
    }

    public override func tile() {
        super.tile()
        guard isScrollViewConfigured, !isApplyingLineWrappingConfiguration else { return }

        applyLineWrappingConfiguration(lineWrappingEnabled: model.lineWrappingEnabled)
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
        guard !isApplyingModel else {
            pendingEditStartUTF16 = nil
            pendingUndoSelection = nil
            pendingHighlightMutation = nil
            return
        }

        let previousText = model.text
        let nextText = textView.string
        if isApplyingHighlight, nextText == previousText {
            pendingEditStartUTF16 = nil
            pendingUndoSelection = nil
            pendingHighlightMutation = nil
            return
        }

        let mutation = pendingHighlightMutation ??
            TextMutation.diff(from: previousText, to: nextText).map(SyntaxHighlightMutation.init)
        let change: SyntaxEditorTextChange?
        if let mutation {
            change = model.commitEdits(
                [
                    SyntaxEditorTextEdit(
                        range: NSRange(location: mutation.location, length: mutation.length),
                        replacement: mutation.replacement
                    ),
                ],
                selectedRange: textView.selectedRange()
            )
        } else {
            change = model.replaceText(nextText, selectedRange: textView.selectedRange())
        }
        guard let change else {
            model.selectedRange = textView.selectedRange()
            return
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
            language: model.language,
            revision: change.revision,
            mutation: mutation,
            refreshStartUTF16: refreshStartUTF16
        )
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        textSelectionDidChange()
    }

    private func textSelectionDidChange() {
        if !isApplyingModel {
            model.selectedRange = textView.selectedRange()
        }
        if !isApplyingCommandSelection {
            commandEngine.invalidateTransientState()
        }
        applyMatchingBracketHighlight()
        applyPendingHighlightIfSelectionAllows()
    }

    private func textShouldChange(inRanges affectedRanges: [NSRange], replacementStrings: [String]) -> Bool {
        guard let affectedCharRange = affectedRanges.first else { return true }
        let usesSingleReplacement = affectedRanges.count == 1 && replacementStrings.count == 1
        guard !isApplyingModel else {
            pendingUndoSelection = nil
            return true
        }

        guard model.isEditable else {
            pendingEditStartUTF16 = nil
            pendingUndoSelection = nil
            pendingHighlightMutation = nil
            return false
        }

        pendingEditStartUTF16 = affectedCharRange.location
        pendingUndoSelection = affectedCharRange
        guard usesSingleReplacement, let replacementString = replacementStrings.first else {
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
            language: model.language
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
        guard model.isEditable else {
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
                language: model.language
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
                language: model.language,
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
        scrollView.drawsBackground = model.drawsBackground
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !model.lineWrappingEnabled
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        isScrollViewConfigured = true
    }

    private func configureTextView() {
        textView.drawsBackground = false
        updateEditorBackgroundColor()
        textView.isEditable = model.isEditable
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

        applyLineWrappingConfiguration(lineWrappingEnabled: model.lineWrappingEnabled)
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

    private func startModelObservation(schedulesInitialHighlight: Bool = true) {
        modelConfigurationDeliveryForTesting = modelObservations.observe(model, tracking: { model in
            _ = model.language
            _ = model.isEditable
            _ = model.lineWrappingEnabled
            _ = model.colorTheme
            _ = model.drawsBackground
            _ = model.fontSizeDelta
        }) { [weak self] event, model in
            guard let self else { return }
            self.applyObservedConfiguration(
                language: model.language,
                isEditable: model.isEditable,
                lineWrappingEnabled: model.lineWrappingEnabled,
                colorTheme: model.colorTheme,
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
            self.applyObservedModelChange(
                forceTextUpdate: event.kind == .initial,
                observedRevision: model.revision
            )
            self.applyObservedSelection(model.selectedRange)
        }
    }

    private func applyObservedModelChange(forceTextUpdate: Bool = false, observedRevision: Int? = nil) {
        let revision = observedRevision ?? model.revision
        guard forceTextUpdate || revision != lastAppliedDocumentRevision else { return }

        isApplyingModel = true
        defer {
            isApplyingModel = false
        }

        let text = model.text
        let textNeedsUpdate = forceTextUpdate || textView.string != text
        var highlightMutation: SyntaxHighlightMutation?
        if textNeedsUpdate {
            commandEngine.invalidateTransientState()
            let change = model.latestChange
            if change?.kind == .replacement {
                activeUndoManager?.removeAllActions()
            }
            let canApplyIncrementally = change.map {
                $0.revision == revision
                    && $0.kind == .incremental
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
               !(change.kind == .replacement && change.selectedRange == NSRange(location: 0, length: 0)) {
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
                language: model.language,
                revision: revision,
                mutation: highlightMutation,
                refreshStartUTF16: 0
            )
        }
        lastAppliedDocumentRevision = revision
    }

    private func applyObservedSelection(_ range: NSRange) {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: textStorage.length)
        guard textView.selectedRange() != clamped else { return }

        isApplyingModel = true
        defer {
            isApplyingModel = false
        }
        textView.setSelectedRange(clamped)
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
                revision: model.revision,
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
            .resolved(for: model.language, appearance: currentThemeAppearance)
            .baseForeground
        textSystem.styleStore.updateBaseForeground(nextBaseForeground, textLength: textStorage.length)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        if fullRange.length > 0 {
            TextEditingTransaction.perform(on: textSystem.textContentStorage) { textStorage in
                textStorage.addAttribute(.foregroundColor, value: nextBaseForeground, range: fullRange)
            }
        }
        invalidateVisibleTextDisplay()
    }

    private func applyCommandResult(_ result: EditorCommandResult) {
        guard model.isEditable else {
            return
        }

        let previousText = textView.string
        let previousSelection = textView.selectedRange()
        let textChanged = !result.edits.isEmpty
        let nextText = textChanged
            ? SyntaxEditorModel.applying(result.edits, to: previousText)
            : previousText

        let undoState: (restore: EditorUndoState, counterpart: EditorUndoState)? =
            if textChanged, !isApplyingUndoRedo {
                (
                    EditorUndoState(
                        edits: SyntaxEditorModel.inverseEdits(for: result.edits, in: previousText),
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
        if !textChanged {
            model.selectedRange = textView.selectedRange()
        }

        pendingEditStartUTF16 = nil
        pendingHighlightMutation = nil

        if let undoState {
            registerUndoAction(restore: undoState.restore, counterpart: undoState.counterpart)
        }

        var change: SyntaxEditorTextChange?
        if textChanged {
            change = model.commitEdits(result.edits, selectedRange: result.selectedRange)
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
                language: model.language,
                revision: change?.revision ?? model.revision,
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
            restoreEdits = SyntaxEditorModel.inverseEdits(for: edits, in: previousText)
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
            model.isEditable && model.language.supportsCodeEditingCommands
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
            model.increaseFontSize()
            return true
        case .decreaseFontSize:
            model.decreaseFontSize()
            return true
        case .resetFontSize:
            model.resetFontSize()
            return true
        }
    }

    private func runInsertTabCommand() -> Bool {
        guard model.isEditable, model.language.supportsCodeEditingCommands else {
            return false
        }

        let source = textView.string
        guard let result = commandEngine.insertTab(
            source: source,
            selection: textView.selectedRange(),
            language: model.language
        ) else {
            return false
        }
        applyCommandResult(result)
        return true
    }

    private func runIndentCommand() -> Bool {
        guard model.isEditable, model.language.supportsCodeEditingCommands else {
            return false
        }

        let source = textView.string
        guard let result = commandEngine.indentSelection(
            source: source,
            selection: textView.selectedRange(),
            language: model.language
        ) else {
            return false
        }
        applyCommandResult(result)
        return true
    }

    private func runOutdentCommand() -> Bool {
        guard model.isEditable, model.language.supportsCodeEditingCommands else {
            return false
        }

        let source = textView.string
        guard let result = commandEngine.outdentSelection(
            source: source,
            selection: textView.selectedRange(),
            language: model.language
        ) else {
            return false
        }
        applyCommandResult(result)
        return true
    }

    private func runToggleCommentCommand() -> Bool {
        guard model.isEditable, model.language.supportsCodeEditingCommands else {
            return false
        }

        let source = textView.string
        guard let result = commandEngine.toggleComment(
            source: source,
            selection: textView.selectedRange(),
            language: model.language
        ) else {
            return false
        }
        applyCommandResult(result)
        return true
    }

    private func runToggleLineWrappingCommand() -> Bool {
        model.lineWrappingEnabled.toggle()
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

    private func applyHighlightResultFromScheduledTask(
        _ result: SyntaxHighlightResult,
        mutation: SyntaxHighlightMutation?
    ) async {
        guard !Task.isCancelled else { return }
        guard model.revision == result.revision else { return }
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
            mutation: mutation,
            recordsCache: result.phase == .complete
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
        guard lastHighlightRevision == model.revision,
              lastHighlightLanguage == model.language,
              lastHighlightSource == source
        else {
            scheduleHighlight(source: source, language: model.language, revision: model.revision)
            return
        }

        applyHighlight(
            lastHighlightTokens,
            expectedRevision: model.revision,
            source: source,
            language: model.language,
            refreshRange: NSRange(location: 0, length: source.utf16.count),
            mutation: nil,
            forceOperations: true
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
        textView.lineMetrics.reset(source: nextText)
        TextEditingTransaction.perform(on: textSystem.textContentStorage) { textStorage in
            textStorage.setAttributedString(NSAttributedString(string: nextText, attributes: storageBaseAttributes()))
        }
        textView.setSelectedRange(textView.selectedRange())
        textView.invalidateTextLayout()
    }

    private func applyStorageTextEdits(_ edits: [SyntaxEditorTextEdit]) -> Bool {
        guard editsAreValid(edits) else { return false }

        let base = storageBaseAttributes()
        let previousSource = textStorage.string
        TextEditingTransaction.perform(on: textSystem.textContentStorage) { textStorage in
            for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
                let replacement = NSAttributedString(string: edit.replacement, attributes: base)
                textStorage.replaceCharacters(in: edit.range, with: replacement)
            }
        }
        textView.lineMetrics.apply(edits: edits, previousSource: previousSource)
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
        if lastHighlightRevision == model.revision,
           lastHighlightLanguage == model.language,
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

    private static func highlightMutation(_ change: SyntaxEditorTextChange) -> SyntaxHighlightMutation? {
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
        mutation: SyntaxHighlightMutation?,
        recordsCache: Bool = true,
        forceOperations: Bool = false
    ) -> Bool {
        guard model.revision == expectedRevision else { return false }
        guard model.language == expectedLanguage,
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
            mutation: mutation,
            recordsCache: recordsCache
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
            if recordsCache {
                recordAppliedHighlight(
                    tokens: tokens,
                    source: expectedSource,
                    revision: expectedRevision,
                    language: expectedLanguage
                )
            }
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
            mutation: mutation,
            forceOperations: forceOperations
        )
        textView.applyMarkedTextAttributes()
        textView.typingAttributes = base
        applyMatchingBracketHighlight(force: true)
        invalidateSyntaxHighlightDisplay(for: targetRange)
        if recordsCache {
            recordAppliedHighlight(
                tokens: tokens,
                source: expectedSource,
                revision: expectedRevision,
                language: expectedLanguage
            )
        }
        return true
    }

    @discardableResult
    private func applyHighlightFromScheduledTask(
        _ tokens: [SyntaxHighlightToken],
        expectedRevision: Int,
        source expectedSource: String,
        language expectedLanguage: SyntaxLanguage,
        refreshRange: NSRange,
        mutation: SyntaxHighlightMutation?,
        recordsCache: Bool = true
    ) async -> Bool {
        guard model.revision == expectedRevision else { return false }
        guard model.language == expectedLanguage,
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
            mutation: mutation,
            recordsCache: recordsCache
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
            if recordsCache {
                recordAppliedHighlight(
                    tokens: tokens,
                    source: expectedSource,
                    revision: expectedRevision,
                    language: expectedLanguage
                )
            }
            applyMatchingBracketHighlight(force: true)
            return true
        }
        let base = baseAttributes()
        guard !Task.isCancelled else { return false }
        isApplyingHighlight = true
        defer { isApplyingHighlight = false }
        guard await installSyntaxHighlightRenderingIncrementally(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            baseAttributes: base,
            mutation: mutation,
            expectedRevision: expectedRevision
        ) else { return false }
        guard !Task.isCancelled, model.revision == expectedRevision else { return false }

        textView.applyMarkedTextAttributes()
        textView.typingAttributes = base
        applyMatchingBracketHighlight(force: true)
        invalidateSyntaxHighlightDisplay(for: targetRange)
        if recordsCache {
            recordAppliedHighlight(
                tokens: tokens,
                source: expectedSource,
                revision: expectedRevision,
                language: expectedLanguage
            )
        }
        return true
    }

    private func makeSyntaxHighlightAttributeResolver(
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> SyntaxHighlightAttributeResolver {
        SyntaxHighlightAttributeResolver(
            colorTheme: model.colorTheme,
            defaultLanguage: model.language,
            appearance: currentThemeAppearance,
            baseFont: (baseAttributes[.font] as? NSFont) ?? resolvedBaseFont(),
            fontSizeDelta: model.fontSizeDelta
        )
    }

    private func installSyntaxHighlightRendering(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        baseAttributes: [NSAttributedString.Key: Any],
        mutation: SyntaxHighlightMutation?,
        forceOperations: Bool = false
    ) {
        guard let transaction = syntaxHighlightTransaction(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            baseAttributes: baseAttributes,
            mutation: mutation,
            forceOperations: forceOperations
        ) else {
            return
        }
        TextEditingTransaction.apply(transaction.operations, to: textSystem.textContentStorage)
        textSystem.styleStore.commit(transaction)
    }

    private func installSyntaxHighlightRenderingIncrementally(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        baseAttributes: [NSAttributedString.Key: Any],
        mutation: SyntaxHighlightMutation?,
        expectedRevision: Int
    ) async -> Bool {
        guard let transaction = syntaxHighlightTransaction(
            for: tokens,
            targetRange: targetRange,
            textLength: textLength,
            baseAttributes: baseAttributes,
            mutation: mutation
        ) else {
            return false
        }
        let didApply = await TextEditingTransaction.applyIncrementally(
            transaction.operations,
            to: textSystem.textContentStorage,
            shouldContinue: { model.revision == expectedRevision }
        )
        guard didApply else { return false }
        textSystem.styleStore.commit(transaction)
        return true
    }

    private func syntaxHighlightTransaction(
        for tokens: [SyntaxHighlightToken],
        targetRange: NSRange,
        textLength: Int,
        baseAttributes: [NSAttributedString.Key: Any],
        mutation _: SyntaxHighlightMutation?,
        forceOperations: Bool = false
    ) -> HighlightStyleTransaction? {
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
        return textSystem.styleStore.prepareApply(
            runSet,
            refreshedRange: targetRange,
            mutation: nil,
            textLength: textLength,
            baseForeground: baseForeground,
            baseFont: baseAttributes[.font] as? NSFont,
            foregroundSuppressionRanges: foregroundSuppressionRanges(textLength: textLength),
            forceOperations: forceOperations
        )
    }

    private func foregroundSuppressionRanges(textLength: Int) -> [NSRange] {
        let markedRange = textView.markedRange()
        guard markedRange.location != NSNotFound else { return [] }
        let clamped = SyntaxEditorRangeUtilities.clampedRange(markedRange, utf16Length: textLength)
        return clamped.length > 0 ? [clamped] : []
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

        let tokenRangeIndex = HighlightTokenRangeIndex(tokens: tokens)
        let tokenStartIndex = tokenRangeIndex.firstTokenIndex(intersecting: targetRange)
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
            mutation: pendingHighlightApplication.mutation,
            recordsCache: pendingHighlightApplication.recordsCache
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
        baseAttributes()
    }

    private func resolvedBaseFont(for theme: SyntaxEditorResolvedColorTheme? = nil) -> NSFont {
        let fallbackFont = NSFont.monospacedSystemFont(
            ofSize: SyntaxEditorFontSize.defaultEditorPointSize,
            weight: .regular
        )
        let theme = theme ?? resolvedColorTheme()
        return theme.base.font?.platformFont(
            fallback: fallbackFont,
            fontSizeDelta: model.fontSizeDelta
        ) ?? fallbackFont.syntaxEditorFontSizeAdjusted(by: model.fontSizeDelta)
    }

    private var currentThemeAppearance: SyntaxEditorThemeAppearance {
        effectiveAppearance.syntaxEditorThemeAppearance
    }

    func resolvedColorTheme() -> SyntaxEditorResolvedColorTheme {
        (lastAppliedColorTheme ?? model.colorTheme).resolved(
            for: model.language,
            appearance: currentThemeAppearance
        )
    }

    private func updateEditorBackgroundColor() {
        updateEditorBackgroundColor(drawsBackground: model.drawsBackground)
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

        var contentSize = effectiveScrollContentSize
        var estimatedDocumentSize = estimatedTextViewDocumentSize(
            minimumContentSize: contentSize,
            lineWrappingEnabled: lineWrappingEnabled
        )

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

            layoutGeometryChanged = applyWrappedTextGeometry(
                contentSize: contentSize,
                estimatedDocumentSize: estimatedDocumentSize
            ) || layoutGeometryChanged
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

            scrollView.tile()
            let settledContentSize = effectiveScrollContentSize
            if !settledContentSize.isNearlyEqual(to: contentSize) {
                contentSize = settledContentSize
                estimatedDocumentSize = estimatedTextViewDocumentSize(
                    minimumContentSize: contentSize,
                    lineWrappingEnabled: true
                )
                layoutGeometryChanged = applyWrappedTextGeometry(
                    contentSize: contentSize,
                    estimatedDocumentSize: estimatedDocumentSize
                ) || layoutGeometryChanged
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

    private func applyWrappedTextGeometry(
        contentSize: NSSize,
        estimatedDocumentSize: NSSize
    ) -> Bool {
        var didChange = false
        let wrappingWidth = max(0, contentSize.width)
        var frame = textView.frame
        let frameHeight = estimatedDocumentSize.height
        if !frame.width.isNearlyEqual(to: wrappingWidth) || !frame.height.isNearlyEqual(to: frameHeight) {
            frame.size = NSSize(width: wrappingWidth, height: frameHeight)
            textView.frame = frame
            didChange = true
        }

        let containerSize = NSSize(width: wrappingWidth, height: CGFloat.greatestFiniteMagnitude)
        if !textContainer.containerSize.isNearlyEqual(to: containerSize) {
            textContainer.containerSize = containerSize
            didChange = true
        }
        return didChange
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

    private func estimatedTextViewDocumentSize(
        minimumContentSize: NSSize,
        lineWrappingEnabled: Bool
    ) -> NSSize {
        let baseFont = textView.font ?? resolvedBaseFont()
        let lineHeight = max(1, ceil(baseFont.ascender - baseFont.descender + baseFont.leading))
        let estimatedColumnWidth = max(1, baseFont.pointSize * 0.65)
        return textView.lineMetrics.estimatedDocumentSize(
            minimumSize: minimumContentSize,
            lineWrappingEnabled: lineWrappingEnabled,
            lineHeight: lineHeight,
            columnWidth: estimatedColumnWidth,
            lineFragmentPadding: textContainer.lineFragmentPadding
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
    public private(set) var model: SyntaxEditorModel
    public let editorView: SyntaxEditorView

    var textView: SyntaxEditorTextInputView {
        editorView.textView
    }

    public var scrollView: NSScrollView {
        editorView
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

    public func update(model nextModel: SyntaxEditorModel) {
        guard model !== nextModel else { return }

        model = nextModel
        editorView.update(model: nextModel)
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
