#if canImport(AppKit)
import AppKit
import SyntaxEditorCore

@MainActor
final class MacSyntaxEditorTextInputView: NSView, @preconcurrency NSTextInputClient, @preconcurrency NSTextFinderClient, @preconcurrency NSTextViewportLayoutControllerDelegate {
    let textKit2System: SyntaxEditorTextKit2System
    let textContentView = MacSyntaxEditorTextContentView()
    private let textFinder = NSTextFinder()
    private let insertionIndicator = NSTextInsertionIndicator(frame: .zero)
    private var incrementalMatchRangesObservation: NSKeyValueObservation?
    private var findHighlightRangesOverrideForTesting: [NSRange]?

    var guardedUndoManager: UndoManager?
    var shortcutHandler: ((MacEditorShortcutAction) -> Bool)?
    var shortcutValidator: ((MacEditorShortcutAction) -> Bool)?
    var commandHandler: ((Selector) -> Bool)?
    var lineWrappingStateProvider: (() -> Bool)?
    var didChangeText: (() -> Void)?
    var didChangeSelection: (() -> Void)?
    var shouldChangeText: (([NSRange], [String]) -> Bool)?

    var typingAttributes: [NSAttributedString.Key: Any] = [:]
    var isEditable = true
    var isSelectable = true
    var allowsUndo = true
    var usesFindBar = false {
        didSet {
            guard usesFindBar != oldValue else { return }
            configureTextFinder()
        }
    }
    var usesFindPanel = false
    var isIncrementalSearchingEnabled = false {
        didSet {
            guard isIncrementalSearchingEnabled != oldValue else { return }
            textFinder.isIncrementalSearchingEnabled = isIncrementalSearchingEnabled
        }
    }
    var drawsBackground = false
    var backgroundColor: NSColor = .clear {
        didSet {
            guard backgroundColor != oldValue else { return }
            needsDisplay = true
        }
    }
    var font: NSFont?
    var textColor: NSColor?
    var minSize = NSSize(width: 0, height: 0)
    var maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    var isHorizontallyResizable = true
    var textContainerOrigin: NSPoint { .zero }
    var selectedRangeStorage = NSRange(location: 0, length: 0)
    var markedTextRangeStorage: NSRange?
    var mouseDraggingSelectionAnchors: [NSTextSelection]?
    var fragmentViewMap = NSMapTable<NSTextLayoutFragment, MacSyntaxEditorTextLayoutFragmentView>.weakToWeakObjects()
    var lastUsedFragmentViews: Set<MacSyntaxEditorTextLayoutFragmentView> = []
    var bracketHighlightRanges: [NSRange] = []
    var bracketHighlightColor: NSColor?
    var fragmentDisplayInvalidationCount = 0
    private var viewportOverdraw: CGFloat {
        max(200, bounds.height)
    }
    private var currentViewportBounds: CGRect {
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        return visible.insetBy(dx: 0, dy: -viewportOverdraw)
    }

    init(textKit2System: SyntaxEditorTextKit2System) {
        self.textKit2System = textKit2System
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        unsafe textFinder.client = self
        textKit2System.layoutManager.textViewportLayoutController.delegate = self
        textContentView.textInputView = self
        insertionIndicator.displayMode = .hidden
        insertionIndicator.isHidden = true
        addSubview(textContentView)
        addSubview(insertionIndicator)
        incrementalMatchRangesObservation = textFinder.observe(\.incrementalMatchRanges, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateFindHighlightsForVisibleFragments()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class var isCompatibleWithResponsiveScrolling: Bool {
        false
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var isFlipped: Bool { true }
    override var undoManager: UndoManager? { guardedUndoManager ?? super.undoManager }
    var allowsMultipleSelection: Bool { false }
    var selectedRanges: [NSValue] {
        get { [NSValue(range: selectedRangeStorage)] }
        set {
            guard let firstRange = newValue.first?.rangeValue else { return }
            setSelectedRange(firstRange)
        }
    }
    var firstSelectedRange: NSRange { selectedRangeStorage }
    var visibleCharacterRanges: [NSValue] {
        if let range = visibleCharacterRange() {
            return [NSValue(range: range)]
        }
        return [NSValue(range: NSRange(location: 0, length: storage.length))]
    }
    var insertionIndicatorDisplayModeForTesting: NSTextInsertionIndicator.DisplayMode {
        insertionIndicator.displayMode
    }
    var insertionIndicatorFrameForTesting: NSRect {
        insertionIndicator.frame
    }
    var insertionIndicatorIsHiddenForTesting: Bool {
        insertionIndicator.isHidden
    }
    var selectionHighlightRectsForTesting: [CGRect] {
        textContentView.subviews
            .compactMap { $0 as? MacSyntaxEditorTextLayoutFragmentView }
            .flatMap(\.selectionHighlightRects)
    }
    var findHighlightRectsForTesting: [CGRect] {
        textContentView.subviews
            .compactMap { $0 as? MacSyntaxEditorTextLayoutFragmentView }
            .flatMap(\.findHighlightRects)
    }

    var textStorage: NSTextStorage? { storage }
    private var storage: NSTextStorage { textKit2System.textStorage }
    var layoutManager: NSLayoutManager? { nil }
    var textLayoutManager: NSTextLayoutManager { textKit2System.layoutManager }
    var textContentStorage: NSTextContentStorage { textKit2System.textContentStorage }
    var textContainer: NSTextContainer? { textKit2System.container }

    var string: String {
        get { storage.string }
        set {
            textFinder.noteClientStringWillChange()
            textContentStorage.performEditingTransaction {
                storage.setAttributedString(NSAttributedString(string: newValue, attributes: typingAttributes))
            }
            setSelectedRange(NSRange(location: min(selectedRangeStorage.location, storage.length), length: 0))
            invalidateTextLayout()
            didChangeText?()
        }
    }

    func setSelectedRange(_ range: NSRange) {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
        guard clamped != selectedRangeStorage else { return }
        updateSelectedRangeStorage(clamped)
        syncTextLayoutSelection()
        updateSelectionRendering()
        needsDisplay = true
    }

    func shouldChangeText(inRanges affectedRanges: [NSRange], replacementStrings: [String]) -> Bool {
        shouldChangeText?(affectedRanges, replacementStrings) ?? true
    }

    func didChangeTextNotification() {
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: self)
        didChangeText?()
    }

    func breakUndoCoalescing() {}

    @objc func undo(_ sender: Any?) {
        undoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        undoManager?.redo()
    }

    @objc func syntaxEditorShiftRight(_ sender: Any?) {
        _ = shortcutHandler?(.indent)
    }

    @objc func syntaxEditorShiftLeft(_ sender: Any?) {
        _ = shortcutHandler?(.outdent)
    }

    @objc func syntaxEditorCommentSelection(_ sender: Any?) {
        _ = shortcutHandler?(.toggleComment)
    }

    @objc func syntaxEditorToggleLineWrapping(_ sender: Any?) {
        _ = shortcutHandler?(.toggleLineWrapping)
    }

    @objc func syntaxEditorIncreaseFontSize(_ sender: Any?) {
        _ = shortcutHandler?(.increaseFontSize)
    }

    @objc func syntaxEditorDecreaseFontSize(_ sender: Any?) {
        _ = shortcutHandler?(.decreaseFontSize)
    }

    @objc func syntaxEditorResetFontSize(_ sender: Any?) {
        _ = shortcutHandler?(.resetFontSize)
    }

    override func performTextFinderAction(_ sender: Any?) {
        guard usesFindBar else { return }
        configureTextFinder()
        let action = (sender as? NSMenuItem)
            .flatMap { NSTextFinder.Action(rawValue: $0.tag) }
            ?? .showFindInterface
        textFinder.performAction(action)
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) {
            return undoManager?.canUndo ?? false
        }
        if item.action == #selector(redo(_:)) {
            return undoManager?.canRedo ?? false
        }
        if let command = SyntaxEditorMenuCommand(selector: item.action),
           let action = MacEditorShortcutAction(command: command) {
            let canHandle = shortcutValidator?(action) ?? true
            if command == .wrapLines, let menuItem = item as? NSMenuItem {
                menuItem.state = lineWrappingStateProvider?() == true ? .on : .off
            }
            return canHandle
        }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""

        if key.lowercased() == "l",
           modifiers.contains(.command),
           modifiers.contains(.control),
           modifiers.contains(.shift),
           !modifiers.contains(.option),
           shortcutHandler?(.toggleLineWrapping) == true {
            return true
        }

        if key == "0",
           modifiers.contains(.command),
           modifiers.contains(.control),
           !modifiers.contains(.option),
           !modifiers.contains(.shift),
           shortcutHandler?(.resetFontSize) == true {
            return true
        }

        guard modifiers.contains(.command),
              !modifiers.contains(.control),
              !modifiers.contains(.option)
        else {
            return super.performKeyEquivalent(with: event)
        }

        if key == "+" || key == "=" {
            return shortcutHandler?(.increaseFontSize) == true || super.performKeyEquivalent(with: event)
        }
        if key == "-" {
            return shortcutHandler?(.decreaseFontSize) == true || super.performKeyEquivalent(with: event)
        }
        if key == "/" {
            return shortcutHandler?(.toggleComment) == true || super.performKeyEquivalent(with: event)
        }
        if key == "]" {
            return shortcutHandler?(.indent) == true || super.performKeyEquivalent(with: event)
        }
        if key == "[" {
            return shortcutHandler?(.outdent) == true || super.performKeyEquivalent(with: event)
        }

        return super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        if drawsBackground {
            backgroundColor.setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()
        textContentView.frame = bounds
        layoutVisibleViewport()
        updateDecorationRenderingForVisibleFragments()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureTextFinder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            clearTextFinderAttachments()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTextFinder()
        updateSelectionRendering()
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        updateSelectionRendering()
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        updateSelectionRendering()
        return resignedFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        if inputContext?.handleEvent(event) == true {
            return
        }
        interpretKeyEvents([event])
    }

    override func mouseDown(with event: NSEvent) {
        guard inputContext?.handleEvent(event) != true else {
            return
        }
        unsafe window?.makeFirstResponder(self)
        guard isSelectable, event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let extendsSelection = modifiers.contains(.shift)
        let usesVisualSelection = modifiers.contains(.option)

        switch event.clickCount {
        case 1:
            updateTextSelection(
                interactingAt: location,
                anchors: extendsSelection ? textLayoutManager.textSelections : [],
                extending: extendsSelection,
                isDragging: false,
                visual: usesVisualSelection
            )
        case 2:
            updateTextSelection(interactingAt: location)
            selectGranularity(.word)
        case 3:
            updateTextSelection(interactingAt: location)
            selectGranularity(.paragraph)
        default:
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard inputContext?.handleEvent(event) != true else {
            return
        }
        guard isSelectable else {
            super.mouseDragged(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if mouseDraggingSelectionAnchors == nil {
            mouseDraggingSelectionAnchors = textLayoutManager.textSelections
        }
        updateTextSelection(
            interactingAt: location,
            inContainerAt: mouseDraggingSelectionAnchors?.first?.textRanges.first?.location,
            anchors: mouseDraggingSelectionAnchors ?? [],
            extending: true,
            isDragging: true,
            visual: event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
        )
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDraggingSelectionAnchors = nil
        super.mouseUp(with: event)
    }

    override func doCommand(by selector: Selector) {
        if commandHandler?(selector) == true {
            return
        }

        switch selector {
        case #selector(selectAll(_:)):
            selectAll(nil)
        case #selector(insertNewline(_:)):
            insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        case #selector(deleteBackward(_:)):
            deleteBackward()
        case #selector(deleteForward(_:)):
            deleteForward()
        case #selector(moveLeft(_:)):
            moveSelection(direction: .left, destination: .character, extending: false, confined: false)
        case #selector(moveLeftAndModifySelection(_:)):
            moveSelection(direction: .left, destination: .character, extending: true, confined: false)
        case #selector(moveRight(_:)):
            moveSelection(direction: .right, destination: .character, extending: false, confined: false)
        case #selector(moveRightAndModifySelection(_:)):
            moveSelection(direction: .right, destination: .character, extending: true, confined: false)
        case #selector(moveUp(_:)):
            moveSelection(direction: .up, destination: .character, extending: false, confined: false)
        case #selector(moveUpAndModifySelection(_:)):
            moveSelection(direction: .up, destination: .character, extending: true, confined: false)
        case #selector(moveDown(_:)):
            moveSelection(direction: .down, destination: .character, extending: false, confined: false)
        case #selector(moveDownAndModifySelection(_:)):
            moveSelection(direction: .down, destination: .character, extending: true, confined: false)
        case #selector(moveWordLeft(_:)):
            moveSelection(direction: .left, destination: .word, extending: false, confined: false)
        case #selector(moveWordLeftAndModifySelection(_:)):
            moveSelection(direction: .left, destination: .word, extending: true, confined: false)
        case #selector(moveWordRight(_:)):
            moveSelection(direction: .right, destination: .word, extending: false, confined: false)
        case #selector(moveWordRightAndModifySelection(_:)):
            moveSelection(direction: .right, destination: .word, extending: true, confined: false)
        case #selector(moveWordForward(_:)):
            moveSelection(direction: .forward, destination: .word, extending: false, confined: false)
        case #selector(moveWordForwardAndModifySelection(_:)):
            moveSelection(direction: .forward, destination: .word, extending: true, confined: false)
        case #selector(moveWordBackward(_:)):
            moveSelection(direction: .backward, destination: .word, extending: false, confined: false)
        case #selector(moveWordBackwardAndModifySelection(_:)):
            moveSelection(direction: .backward, destination: .word, extending: true, confined: false)
        case #selector(moveToBeginningOfLine(_:)),
             #selector(moveToLeftEndOfLine(_:)):
            moveSelection(direction: .backward, destination: .line, extending: false, confined: true)
        case #selector(moveToBeginningOfLineAndModifySelection(_:)),
             #selector(moveToLeftEndOfLineAndModifySelection(_:)):
            moveSelection(direction: .backward, destination: .line, extending: true, confined: true)
        case #selector(moveToEndOfLine(_:)),
             #selector(moveToRightEndOfLine(_:)):
            moveSelection(direction: .forward, destination: .line, extending: false, confined: true)
        case #selector(moveToEndOfLineAndModifySelection(_:)),
             #selector(moveToRightEndOfLineAndModifySelection(_:)):
            moveSelection(direction: .forward, destination: .line, extending: true, confined: true)
        case #selector(moveToBeginningOfDocument(_:)):
            moveSelection(direction: .backward, destination: .document, extending: false, confined: false)
        case #selector(moveToBeginningOfDocumentAndModifySelection(_:)):
            moveSelection(direction: .backward, destination: .document, extending: true, confined: false)
        case #selector(moveToEndOfDocument(_:)):
            moveSelection(direction: .forward, destination: .document, extending: false, confined: false)
        case #selector(moveToEndOfDocumentAndModifySelection(_:)):
            moveSelection(direction: .forward, destination: .document, extending: true, confined: false)
        default:
            break
        }
    }

    override func selectAll(_ sender: Any?) {
        guard isSelectable else { return }
        setSelectedRange(NSRange(location: 0, length: storage.length))
    }

    override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard isEditable else { return }
        let replacement = (string as? NSAttributedString)?.string ?? "\(string)"
        let range = effectiveReplacementRange(replacementRange)
        replaceText(in: range, with: replacement, selectedRange: NSRange(location: range.location + replacement.utf16.count, length: 0))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard isEditable else { return }
        let replacement = (string as? NSAttributedString)?.string ?? "\(string)"
        let range = markedTextRangeStorage ?? effectiveReplacementRange(replacementRange)
        let markedLength = replacement.utf16.count
        replaceText(
            in: range,
            with: replacement,
            selectedRange: NSRange(
                location: range.location + min(max(0, selectedRange.location), markedLength),
                length: min(max(0, selectedRange.length), markedLength)
            )
        )
        markedTextRangeStorage = replacement.isEmpty ? nil : NSRange(location: range.location, length: markedLength)
    }

    func unmarkText() {
        markedTextRangeStorage = nil
        updateSelectionRendering()
        needsDisplay = true
    }

    func selectedRange() -> NSRange { selectedRangeStorage }
    func markedRange() -> NSRange { markedTextRangeStorage ?? NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { markedTextRangeStorage != nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.underlineStyle, .underlineColor, .foregroundColor] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
        unsafe actualRange?.pointee = clamped
        guard clamped.length > 0 else { return NSAttributedString(string: "") }
        return storage.attributedSubstring(from: clamped)
    }

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        unsafe outRange.pointee = NSRange(location: 0, length: storage.length)
        return textContentView
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        rectsForCharacterRange(range).map { NSValue(rect: $0) }
    }

    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard view === textContentView,
              let targetTextRange = textRange(forUTF16Range: range)
        else {
            return
        }
        textLayoutManager.ensureLayout(for: targetTextRange)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let drawsFindIndicator = view.isDrawingFindIndicator
        textLayoutManager.enumerateTextLayoutFragments(from: targetTextRange.location, options: []) { [self] fragment in
            guard NSIntersectionRange(textRange(for: fragment), range).length > 0 else {
                return true
            }
            SyntaxEditorTextKit2HighlightRenderer.validateRenderingAttributes(
                layoutManager: textLayoutManager,
                textContentStorage: textContentStorage,
                renderStore: textKit2System.renderStore,
                fragment: fragment
            )
            if drawsFindIndicator {
                textLayoutManager.addRenderingAttribute(
                    .foregroundColor,
                    value: NSColor.black,
                    for: targetTextRange
                )
            }
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            if drawsFindIndicator {
                SyntaxEditorTextKit2HighlightRenderer.validateRenderingAttributes(
                    layoutManager: textLayoutManager,
                    textContentStorage: textContentStorage,
                    renderStore: textKit2System.renderStore,
                    fragment: fragment
                )
            }
            return true
        }
    }

    func scrollRangeToVisible(_ range: NSRange) {
        scrollToVisible(rectForCharacterRange(range).insetBy(dx: -4, dy: -4))
    }

    func shouldReplaceCharacters(inRanges ranges: [NSValue], with strings: [String]) -> Bool {
        let affectedRanges = ranges.map(\.rangeValue)
        return shouldChangeText?(affectedRanges, strings) ?? true
    }

    func replaceCharacters(in range: NSRange, with string: String) {
        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
        replaceText(
            in: clampedRange,
            with: string,
            selectedRange: NSRange(location: clampedRange.location + string.utf16.count, length: 0)
        )
    }

    func didReplaceCharacters() {}

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
        unsafe actualRange?.pointee = clamped
        let localRect = rectForCharacterRange(clamped)
        guard let window = unsafe self.window else { return localRect }
        return window.convertToScreen(convert(localRect, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        let windowPoint = unsafe window?.convertPoint(fromScreen: point) ?? point
        let localPoint = convert(windowPoint, from: nil)
        return characterIndex(at: localPoint)
    }

    func baselineDeltaForCharacter(at index: Int) -> CGFloat { 0 }
    func fractionOfDistanceThroughGlyph(for point: NSPoint) -> CGFloat { 0 }
    func windowLevel() -> Int { unsafe window?.level.rawValue ?? 0 }
    func drawsVerticallyForCharacter(at charIndex: Int) -> Bool { false }

    func textLocation(forUTF16Offset offset: Int) -> NSTextLocation? {
        textKit2System.textLocation(forUTF16Offset: offset)
    }

    func utf16Offset(for textLocation: NSTextLocation) -> Int {
        textKit2System.utf16Offset(for: textLocation)
    }

    func textRange(forUTF16Range range: NSRange) -> NSTextRange? {
        textKit2System.textRange(forUTF16Range: range)
    }

    func utf16Range(for textRange: NSTextRange) -> NSRange {
        textKit2System.utf16Range(for: textRange)
    }

    func textRange(for layoutFragment: NSTextLayoutFragment) -> NSRange {
        NSRange(
            location: utf16Offset(for: layoutFragment.rangeInElement.location),
            length: utf16Offset(for: layoutFragment.rangeInElement.endLocation)
                - utf16Offset(for: layoutFragment.rangeInElement.location)
        )
    }

    func invalidateTextLayout() {
        textLayoutManager.invalidateLayout(for: textContentStorage.documentRange)
        textLayoutManager.textSelectionNavigation.flushLayoutCache()
        layoutVisibleViewport()
        updateDecorationRenderingForVisibleFragments()
        setNeedsDisplayForVisibleTextFragments()
    }

    func layoutVisibleViewport() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        textLayoutManager.ensureLayout(for: currentViewportBounds)
        textLayoutManager.textViewportLayoutController.layoutViewport()
    }

    func invalidateRenderingAttributes(for range: NSRange) {
        textKit2System.invalidateRenderingAttributes(for: range)
        setNeedsDisplayForTextRanges([range])
    }

    func setNeedsDisplayForTextRanges(_ ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }

        layoutVisibleViewport()
        var didInvalidateFragment = false
        for case let fragmentView as MacSyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            let fragmentRange = textRange(for: fragmentView.layoutFragment)
            guard ranges.contains(where: { NSIntersectionRange($0, fragmentRange).length > 0 }) else {
                continue
            }
            fragmentView.needsDisplay = true
            fragmentDisplayInvalidationCount += 1
            didInvalidateFragment = true
        }
        guard !didInvalidateFragment else { return }

        for range in ranges {
            setNeedsDisplay(rectForCharacterRange(range))
        }
    }

    func setNeedsDisplayForVisibleTextFragments() {
        layoutVisibleViewport()
        for case let fragmentView as MacSyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            guard fragmentView.frame.intersects(currentViewportBounds) else { continue }
            fragmentView.needsDisplay = true
            fragmentDisplayInvalidationCount += 1
        }
    }

    func visibleCharacterRange() -> NSRange? {
        layoutVisibleViewport()
        var visibleRange: NSRange?
        for case let fragmentView as MacSyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            guard fragmentView.frame.intersects(currentViewportBounds) else { continue }
            let fragmentRange = textRange(for: fragmentView.layoutFragment)
            if let current = visibleRange {
                let lowerBound = min(current.location, fragmentRange.location)
                let upperBound = max(current.upperBound, fragmentRange.upperBound)
                visibleRange = NSRange(location: lowerBound, length: upperBound - lowerBound)
            } else {
                visibleRange = fragmentRange
            }
        }
        return visibleRange
    }

    func updateBracketHighlights(ranges: [NSRange], color: NSColor?) {
        bracketHighlightRanges = ranges
        bracketHighlightColor = color
        for case let fragmentView as MacSyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            configureBracketHighlights(for: fragmentView)
        }
    }

    func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        currentViewportBounds
    }

    func textViewportLayoutControllerWillLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        lastUsedFragmentViews = Set(
            fragmentViewMap.objectEnumerator()?.allObjects as? [MacSyntaxEditorTextLayoutFragmentView] ?? []
        )
    }

    func textViewportLayoutController(
        _ textViewportLayoutController: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
    ) {
        let layoutFragmentFrame = textLayoutFragment.layoutFragmentFrame
        let fragmentView: MacSyntaxEditorTextLayoutFragmentView
        if let cached = fragmentViewMap.object(forKey: textLayoutFragment) {
            fragmentView = cached
            lastUsedFragmentViews.remove(cached)
        } else {
            fragmentView = MacSyntaxEditorTextLayoutFragmentView(
                layoutFragment: textLayoutFragment,
                frame: layoutFragmentFrame
            )
            fragmentView.textKit2System = textKit2System
            fragmentViewMap.setObject(fragmentView, forKey: textLayoutFragment)
        }

        if fragmentView.frame != layoutFragmentFrame {
            fragmentView.frame = layoutFragmentFrame
            fragmentView.needsDisplay = true
        }
        if unsafe fragmentView.superview != textContentView {
            textContentView.addSubview(fragmentView)
        }
        configureFindHighlights(for: fragmentView)
        configureSelectionHighlights(for: fragmentView)
        configureBracketHighlights(for: fragmentView)
    }

    func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        for staleView in lastUsedFragmentViews {
            staleView.removeFromSuperview()
        }
        lastUsedFragmentViews.removeAll()
        updateInsertionIndicator()
    }

    private func replaceText(in range: NSRange, with replacement: String, selectedRange: NSRange) {
        guard shouldChangeText(inRanges: [range], replacementStrings: [replacement]) else { return }
        textFinder.noteClientStringWillChange()
        textContentStorage.performEditingTransaction {
            storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: typingAttributes))
        }
        setSelectedRange(selectedRange)
        invalidateTextLayout()
        didChangeTextNotification()
    }

    private func configureTextFinder() {
        if !usesFindBar {
            textFinder.cancelFindIndicator()
        }
        unsafe textFinder.findBarContainer = usesFindBar ? enclosingScrollView : nil
        textFinder.isIncrementalSearchingEnabled = isIncrementalSearchingEnabled
        updateFindHighlightsForVisibleFragments()
    }

    private func clearTextFinderAttachments() {
        textFinder.cancelFindIndicator()
        unsafe textFinder.findBarContainer = nil
        updateFindHighlightsForVisibleFragments()
    }

    private func deleteBackward() {
        if selectedRangeStorage.length > 0 {
            replaceText(in: selectedRangeStorage, with: "", selectedRange: NSRange(location: selectedRangeStorage.location, length: 0))
        } else if selectedRangeStorage.location > 0 {
            let source = string as NSString
            let range = source.rangeOfComposedCharacterSequence(at: selectedRangeStorage.location - 1)
            replaceText(in: range, with: "", selectedRange: NSRange(location: range.location, length: 0))
        }
    }

    private func deleteForward() {
        if selectedRangeStorage.length > 0 {
            replaceText(in: selectedRangeStorage, with: "", selectedRange: NSRange(location: selectedRangeStorage.location, length: 0))
        } else if selectedRangeStorage.location < storage.length {
            let source = string as NSString
            let range = source.rangeOfComposedCharacterSequence(at: selectedRangeStorage.location)
            replaceText(in: range, with: "", selectedRange: NSRange(location: range.location, length: 0))
        }
    }

    private func moveSelection(
        direction: NSTextSelectionNavigation.Direction,
        destination: NSTextSelectionNavigation.Destination,
        extending: Bool,
        confined: Bool
    ) {
        guard isSelectable else { return }

        let currentSelections = textLayoutManager.textSelections.isEmpty
            ? textSelections(for: selectedRangeStorage)
            : textLayoutManager.textSelections
        let nextSelections = currentSelections.compactMap { selection in
            textLayoutManager.textSelectionNavigation.destinationSelection(
                for: selection,
                direction: direction,
                destination: destination,
                extending: extending,
                confined: confined
            )
        }
        guard !nextSelections.isEmpty else { return }

        applyTextSelections(nextSelections)
    }

    private func updateTextSelection(
        interactingAt point: NSPoint,
        inContainerAt location: NSTextLocation? = nil,
        anchors: [NSTextSelection] = [],
        extending: Bool = false,
        isDragging: Bool = false,
        visual: Bool = false
    ) {
        guard isSelectable else { return }

        var modifiers: NSTextSelectionNavigation.Modifier = []
        if extending {
            modifiers.insert(.extend)
        }
        if visual {
            modifiers.insert(.visual)
        }

        let selections = textLayoutManager.textSelectionNavigation.textSelections(
            interactingAt: point,
            inContainerAt: location ?? textContentStorage.documentRange.location,
            anchors: anchors,
            modifiers: modifiers,
            selecting: isDragging,
            bounds: textLayoutManager.usageBoundsForTextContainer
        )
        guard !selections.isEmpty else { return }

        applyTextSelections(selections)
    }

    private func selectGranularity(_ granularity: NSTextSelection.Granularity) {
        guard isSelectable,
              let selection = textLayoutManager.textSelections.last
        else {
            return
        }

        applyTextSelections([
            textLayoutManager.textSelectionNavigation.textSelection(
                for: granularity,
                enclosing: selection
            ),
        ])
    }

    private func effectiveReplacementRange(_ range: NSRange) -> NSRange {
        if range.location == NSNotFound {
            return selectedRangeStorage
        }
        return SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
    }

    private func syncTextLayoutSelection() {
        guard let textRange = textRange(forUTF16Range: selectedRangeStorage) else { return }
        let affinity: NSTextSelection.Affinity = selectedRangeStorage.length == 0
            && isHardLineBreakCaretLocation(selectedRangeStorage.location)
            ? .upstream
            : .downstream
        textLayoutManager.textSelections = [NSTextSelection(range: textRange, affinity: affinity, granularity: .character)]
    }

    private func characterIndex(at point: NSPoint) -> Int {
        if let location = caretTextLocation(interactingAt: point) {
            return utf16Offset(for: location)
        }

        let selections = textLayoutManager.textSelectionNavigation.textSelections(
            interactingAt: point,
            inContainerAt: textContentStorage.documentRange.location,
            anchors: [],
            modifiers: [],
            selecting: false,
            bounds: textLayoutManager.usageBoundsForTextContainer
        )
        if let location = selections.first?.textRanges.first?.location {
            return utf16Offset(for: location)
        }

        return point.y >= bounds.maxY ? storage.length : 0
    }

    private func caretTextLocation(interactingAt point: NSPoint) -> NSTextLocation? {
        guard let lineFragmentRange = textLayoutManager.lineFragmentRange(
            for: point,
            inContainerAt: textContentStorage.documentRange.location
        ) else {
            return nil
        }

        if let layoutFragment = textLayoutManager.textLayoutFragment(for: point) {
            let frame = layoutFragment.layoutFragmentFrame
            if point.y < frame.minY || point.y > frame.maxY {
                return nil
            }
        }

        var closestDistance = CGFloat.greatestFiniteMagnitude
        var closestLocation: NSTextLocation?
        var maximumCaretOffset = -CGFloat.greatestFiniteMagnitude
        let lineEndLocation = caretLineEndLocation(for: lineFragmentRange)
        let lineEndOffset = utf16Offset(for: lineEndLocation)
        unsafe textLayoutManager.enumerateCaretOffsetsInLineFragment(at: lineFragmentRange.location) { caretOffset, location, leadingEdge, stop in
            maximumCaretOffset = max(maximumCaretOffset, caretOffset)
            let distance = abs(caretOffset - point.x)
            let locationOffset = utf16Offset(for: location)
            let isLineEndTrailingEdge = !leadingEdge && isTrailingCaretOffsetAtLineEnd(
                locationOffset,
                lineEndOffset: lineEndOffset
            )
            guard leadingEdge || isLineEndTrailingEdge else { return }

            if distance < closestDistance {
                closestDistance = distance
                closestLocation = isLineEndTrailingEdge ? lineEndLocation : location
            } else if distance > closestDistance {
                unsafe stop.pointee = true
            }
        }

        if point.x > maximumCaretOffset {
            return lineEndLocation
        }

        return closestLocation
    }

    private func caretLineEndLocation(for lineFragmentRange: NSTextRange) -> NSTextLocation {
        let endOffset = utf16Offset(for: lineFragmentRange.endLocation)
        if let lineBreakOffset = lineBreakCaretOffset(endingAt: endOffset),
           let lineBreakLocation = textLocation(forUTF16Offset: lineBreakOffset) {
            return lineBreakLocation
        }
        return lineFragmentRange.endLocation
    }

    private func lineBreakCaretOffset(endingAt endOffset: Int) -> Int? {
        let lineBreakOffset = endOffset - 1
        guard isHardLineBreakCaretLocation(lineBreakOffset) else { return nil }

        let source = string as NSString
        let character = source.character(at: lineBreakOffset)
        if character == 0x0A, lineBreakOffset > 0 {
            let previousCharacter = source.character(at: lineBreakOffset - 1)
            if previousCharacter == 0x0D {
                return lineBreakOffset - 1
            }
        }

        return lineBreakOffset
    }

    private func isHardLineBreakCaretLocation(_ location: Int) -> Bool {
        guard location >= 0, location < storage.length else { return false }
        let character = (string as NSString).character(at: location)
        return character == 0x0A || character == 0x0D
    }

    private func isTrailingCaretOffsetAtLineEnd(_ locationOffset: Int, lineEndOffset: Int) -> Bool {
        if locationOffset == lineEndOffset {
            return true
        }

        guard locationOffset >= 0,
              locationOffset < lineEndOffset,
              lineEndOffset <= storage.length
        else {
            return false
        }

        let characterRange = (string as NSString).rangeOfComposedCharacterSequence(at: locationOffset)
        return characterRange.upperBound == lineEndOffset
    }

    private func textSelections(for range: NSRange) -> [NSTextSelection] {
        guard let textRange = textRange(forUTF16Range: range) else { return [] }
        return [NSTextSelection(range: textRange, affinity: .downstream, granularity: .character)]
    }

    private func applyTextSelections(_ selections: [NSTextSelection]) {
        guard !selections.isEmpty else { return }

        textLayoutManager.textSelections = selections
        guard let range = nsRange(for: selections.first) else { return }
        updateSelectedRangeStorage(range)
        updateSelectionRendering()
        needsDisplay = true
    }

    private func nsRange(for selection: NSTextSelection?) -> NSRange? {
        guard let selection,
              let firstRange = selection.textRanges.first
        else {
            return nil
        }

        var lowerBound = utf16Offset(for: firstRange.location)
        var upperBound = utf16Offset(for: firstRange.endLocation)
        for textRange in selection.textRanges.dropFirst() {
            lowerBound = min(lowerBound, utf16Offset(for: textRange.location))
            upperBound = max(upperBound, utf16Offset(for: textRange.endLocation))
        }
        return SyntaxEditorRangeUtilities.clampedRange(
            NSRange(location: lowerBound, length: max(0, upperBound - lowerBound)),
            utf16Length: storage.length
        )
    }

    private func updateSelectedRangeStorage(_ range: NSRange) {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
        guard clamped != selectedRangeStorage else { return }

        selectedRangeStorage = clamped
        didChangeSelection?()
    }

    private func rectForCharacterRange(_ range: NSRange) -> NSRect {
        let rects = rectsForCharacterRange(range)
        guard !rects.isEmpty else { return bounds }
        return rects.reduce(NSRect.zero) { partialResult, rect in
            partialResult == .zero ? rect : partialResult.union(rect)
        }
    }

    private func rectsForCharacterRange(_ range: NSRange) -> [NSRect] {
        guard let textRange = textRange(forUTF16Range: range) else { return [] }
        textLayoutManager.ensureLayout(for: textRange)
        var rects: [NSRect] = []
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { _, segmentRect, _, _ in
            rects.append(segmentRect)
            return true
        }
        return rects
    }

    private func updateSelectionRendering() {
        layoutVisibleViewport()
        updateDecorationRenderingForVisibleFragments()
    }

    private func updateDecorationRenderingForVisibleFragments() {
        for case let fragmentView as MacSyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            configureFindHighlights(for: fragmentView)
            configureSelectionHighlights(for: fragmentView)
        }
        updateInsertionIndicator()
    }

    private func updateFindHighlightsForVisibleFragments() {
        layoutVisibleViewport()
        for case let fragmentView as MacSyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            configureFindHighlights(for: fragmentView)
        }
    }

    func setNeedsDisplayForContentRect(_ rect: NSRect) {
        guard !rect.isEmpty else { return }

        for case let fragmentView as MacSyntaxEditorTextLayoutFragmentView in textContentView.subviews {
            guard fragmentView.frame.intersects(rect) else { continue }
            fragmentView.setNeedsDisplay(rect.offsetBy(dx: -fragmentView.frame.minX, dy: -fragmentView.frame.minY))
            fragmentDisplayInvalidationCount += 1
        }
    }

    private func updateInsertionIndicator() {
        guard unsafe window?.firstResponder === self,
              isEditable,
              selectedRangeStorage.length == 0,
              let caretRect = caretRect(forUTF16Location: selectedRangeStorage.location)
        else {
            insertionIndicator.displayMode = .hidden
            insertionIndicator.isHidden = true
            return
        }

        insertionIndicator.frame = caretRect
        insertionIndicator.isHidden = false
        insertionIndicator.displayMode = .automatic
    }

    private func caretRect(forUTF16Location location: Int) -> CGRect? {
        guard let textLocation = textLocation(forUTF16Offset: location) else { return nil }
        let textRange = NSTextRange(location: textLocation)

        textLayoutManager.ensureLayout(for: textRange)
        let lineLookupOffset = textLineFragmentLookupUTF16Location(forUTF16Location: location)
        let lineLookupLocation = self.textLocation(forUTF16Offset: lineLookupOffset) ?? textLocation
        if let caretRect = textLayoutLineCaretRect(
            forUTF16Location: location,
            lineLookupUTF16Location: lineLookupOffset,
            textLocation: lineLookupLocation
        ) {
            return caretRect
        }

        var options: NSTextLayoutManager.SegmentOptions = [.rangeNotRequired]
        if isHardLineBreakCaretLocation(location) {
            options.insert(.upstreamAffinity)
        }
        var caretRect: CGRect?
        textLayoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: options
        ) { _, rect, _, _ in
            caretRect = rect
            return false
        }
        return caretRect
    }

    private func textLineFragmentLookupUTF16Location(forUTF16Location location: Int) -> Int {
        let textLength = storage.length
        let clampedLocation = min(max(0, location), textLength)

        if isHardLineBreakCaretLocation(clampedLocation),
           clampedLocation > 0,
           !isHardLineBreakCaretLocation(clampedLocation - 1) {
            return clampedLocation - 1
        }

        if clampedLocation == textLength,
           textLength > 0,
           !isHardLineBreakCaretLocation(textLength - 1) {
            return textLength - 1
        }

        return clampedLocation
    }

    private func textLayoutLineCaretRect(
        forUTF16Location location: Int,
        lineLookupUTF16Location: Int,
        textLocation: NSTextLocation
    ) -> CGRect? {
        guard let (layoutFragment, lineFragment) = textLayoutLineFragment(
                containingUTF16Offset: lineLookupUTF16Location,
                preferredTextLocation: textLocation
              ),
              let lineStartLocation = textContentStorage.location(
                layoutFragment.rangeInElement.location,
                offsetBy: lineFragment.characterRange.location
              )
        else {
            return nil
        }

        let clampedLocation = min(max(0, location), storage.length)
        var lineEndCaretX: CGFloat?
        var exactCaretX: CGFloat?
        var resolvedCaretX: CGFloat?
        var closestDistance = Int.max
        unsafe textLayoutManager.enumerateCaretOffsetsInLineFragment(at: lineStartLocation) { caretOffset, caretLocation, _, stop in
            lineEndCaretX = max(lineEndCaretX ?? caretOffset, caretOffset)
            let caretUTF16Offset = utf16Offset(for: caretLocation)
            let distance = abs(caretUTF16Offset - clampedLocation)
            if distance < closestDistance {
                closestDistance = distance
                resolvedCaretX = caretOffset
            }

            if caretUTF16Offset == clampedLocation {
                exactCaretX = caretOffset
                if !usesLineEndCaretX(forUTF16Location: clampedLocation) {
                    unsafe stop.pointee = true
                }
            }
        }

        let caretX = usesLineEndCaretX(forUTF16Location: clampedLocation)
            ? lineEndCaretX
            : exactCaretX ?? resolvedCaretX
        guard let caretX,
              caretX.isFinite
        else {
            return nil
        }
        let lineFrame = lineFragment.typographicBounds.offsetBy(
            dx: layoutFragment.layoutFragmentFrame.minX,
            dy: layoutFragment.layoutFragmentFrame.minY
        )
        let lineHeight = font.map { max(1, ceil($0.ascender - $0.descender + $0.leading)) } ?? lineFrame.height
        let indicatorWidth = max(2, 1 / max(unsafe window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1))
        return CGRect(
            x: caretX,
            y: lineFrame.minY,
            width: indicatorWidth,
            height: max(lineHeight, lineFrame.height)
        )
    }

    private func textLayoutLineFragment(
        containingUTF16Offset offset: Int,
        preferredTextLocation: NSTextLocation
    ) -> (NSTextLayoutFragment, NSTextLineFragment)? {
        if let layoutFragment = textLayoutManager.textLayoutFragment(for: preferredTextLocation),
           let lineFragment = textLineFragment(containingUTF16Offset: offset, in: layoutFragment) {
            return (layoutFragment, lineFragment)
        }

        var result: (NSTextLayoutFragment, NSTextLineFragment)?
        textLayoutManager.enumerateTextLayoutFragments(
            from: textContentStorage.documentRange.location,
            options: [.ensuresLayout]
        ) { layoutFragment in
            let fragmentStart = utf16Offset(for: layoutFragment.rangeInElement.location)
            guard fragmentStart <= offset else {
                return false
            }

            let fragmentEnd = utf16Offset(for: layoutFragment.rangeInElement.endLocation)
            guard offset <= fragmentEnd else {
                return true
            }

            if let lineFragment = textLineFragment(containingUTF16Offset: offset, in: layoutFragment) {
                result = (layoutFragment, lineFragment)
                return false
            }
            return true
        }

        return result
    }

    private func usesLineEndCaretX(forUTF16Location location: Int) -> Bool {
        if isHardLineBreakCaretLocation(location) {
            return true
        }

        let textLength = storage.length
        return location == textLength
            && textLength > 0
            && !isHardLineBreakCaretLocation(textLength - 1)
    }

    private func textLineFragment(
        containingUTF16Offset offset: Int,
        in layoutFragment: NSTextLayoutFragment
    ) -> NSTextLineFragment? {
        let fragmentStart = utf16Offset(for: layoutFragment.rangeInElement.location)
        let textLength = storage.length
        let clampedOffset = min(max(0, offset), textLength)
        var documentEndLineFragment: NSTextLineFragment?

        for lineFragment in layoutFragment.textLineFragments {
            let lineStart = fragmentStart + lineFragment.characterRange.location
            let lineEnd = lineStart + lineFragment.characterRange.length

            if lineFragment.characterRange.length == 0 {
                if clampedOffset == lineStart {
                    return lineFragment
                }
                continue
            }

            if clampedOffset >= lineStart && clampedOffset < lineEnd {
                return lineFragment
            }

            if clampedOffset == lineEnd {
                if clampedOffset < textLength && isHardLineBreakCaretLocation(clampedOffset) {
                    return lineFragment
                }
                if clampedOffset == textLength {
                    documentEndLineFragment = lineFragment
                }
            }
        }

        return documentEndLineFragment
    }

    func setFindHighlightRangesForTesting(_ ranges: [NSRange]?) {
        findHighlightRangesOverrideForTesting = ranges
        updateFindHighlightsForVisibleFragments()
    }

    private func configureFindHighlights(for fragmentView: MacSyntaxEditorTextLayoutFragmentView) {
        let matchRanges = findHighlightRangesOverrideForTesting
            ?? (usesFindBar && textFinder.isIncrementalSearchingEnabled
                ? textFinder.incrementalMatchRanges.map(\.rangeValue)
                : [])
        guard !matchRanges.isEmpty else {
            fragmentView.setFindHighlights(rects: [])
            return
        }

        let fragmentRange = textRange(for: fragmentView.layoutFragment)
        let ranges = matchRanges.compactMap { range -> NSRange? in
            let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
            let intersection = NSIntersectionRange(clamped, fragmentRange)
            return intersection.length > 0 ? intersection : nil
        }
        guard !ranges.isEmpty else {
            fragmentView.setFindHighlights(rects: [])
            return
        }

        var rects: [CGRect] = []
        for range in ranges {
            guard let textRange = textRange(forUTF16Range: range) else { continue }
            textLayoutManager.ensureLayout(for: textRange)
            textLayoutManager.enumerateTextSegments(
                in: textRange,
                type: .standard,
                options: [.rangeNotRequired]
            ) { _, rect, _, _ in
                rects.append(rect.offsetBy(dx: -fragmentView.frame.minX, dy: -fragmentView.frame.minY))
                return true
            }
        }
        fragmentView.setFindHighlights(rects: rects)
    }

    private func configureSelectionHighlights(for fragmentView: MacSyntaxEditorTextLayoutFragmentView) {
        guard selectedRangeStorage.length > 0 else {
            fragmentView.setSelectionHighlights(rects: [], color: nil)
            return
        }

        let fragmentRange = textRange(for: fragmentView.layoutFragment)
        let intersection = NSIntersectionRange(selectedRangeStorage, fragmentRange)
        guard intersection.length > 0,
              let textRange = textRange(forUTF16Range: intersection)
        else {
            fragmentView.setSelectionHighlights(rects: [], color: nil)
            return
        }

        textLayoutManager.ensureLayout(for: textRange)
        var rects: [CGRect] = []
        textLayoutManager.enumerateTextSegments(
            in: textRange,
            type: .selection,
            options: [.upstreamAffinity]
        ) { _, rect, _, _ in
            rects.append(rect.offsetBy(dx: -fragmentView.frame.minX, dy: -fragmentView.frame.minY))
            return true
        }

        fragmentView.setSelectionHighlights(rects: rects, color: .selectedTextBackgroundColor)
    }

    private func configureBracketHighlights(for fragmentView: MacSyntaxEditorTextLayoutFragmentView) {
        guard !bracketHighlightRanges.isEmpty,
              let bracketHighlightColor
        else {
            fragmentView.bracketHighlightRects = []
            fragmentView.bracketHighlightColor = nil
            fragmentView.needsDisplay = true
            return
        }

        let fragmentRange = textRange(for: fragmentView.layoutFragment)
        let ranges = bracketHighlightRanges.compactMap { range -> NSRange? in
            let intersection = NSIntersectionRange(range, fragmentRange)
            return intersection.length > 0 ? intersection : nil
        }
        let rects = ranges.map(rectForCharacterRange)
        fragmentView.bracketHighlightRects = rects.map {
            $0.offsetBy(dx: -fragmentView.frame.minX, dy: -fragmentView.frame.minY)
        }
        fragmentView.bracketHighlightColor = bracketHighlightColor
        fragmentView.needsDisplay = true
    }
}

final class MacSyntaxEditorTextContentView: NSView {
    weak var textInputView: MacSyntaxEditorTextInputView?

    override var isFlipped: Bool { true }

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            super.needsDisplay = newValue
            if newValue {
                textInputView?.setNeedsDisplayForVisibleTextFragments()
            }
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        textInputView?.setNeedsDisplayForContentRect(invalidRect)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class MacSyntaxEditorTextLayoutFragmentView: NSView {
    let layoutFragment: NSTextLayoutFragment
    weak var textKit2System: SyntaxEditorTextKit2System?
    var findHighlightRects: [CGRect] = []
    var selectionHighlightRects: [CGRect] = []
    var selectionHighlightColor: NSColor?
    var bracketHighlightRects: [CGRect] = []
    var bracketHighlightColor: NSColor?

    init(layoutFragment: NSTextLayoutFragment, frame: CGRect) {
        self.layoutFragment = layoutFragment
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setFindHighlights(rects: [CGRect]) {
        guard findHighlightRects != rects else { return }

        findHighlightRects = rects
        needsDisplay = true
    }

    func setSelectionHighlights(rects: [CGRect], color: NSColor?) {
        guard selectionHighlightRects != rects
            || !colorsEqual(selectionHighlightColor, color)
        else {
            return
        }
        selectionHighlightRects = rects
        selectionHighlightColor = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let textKit2System {
            SyntaxEditorTextKit2HighlightRenderer.validateRenderingAttributes(
                layoutManager: textKit2System.layoutManager,
                textContentStorage: textKit2System.textContentStorage,
                renderStore: textKit2System.renderStore,
                fragment: layoutFragment
            )
        }
        for rect in findHighlightRects where rect.intersects(dirtyRect) {
            NSTextFinder.drawIncrementalMatchHighlight(in: rect)
        }
        if let selectionHighlightColor {
            selectionHighlightColor.setFill()
            for rect in selectionHighlightRects where rect.intersects(dirtyRect) {
                rect.fill()
            }
        }
        if let bracketHighlightColor {
            bracketHighlightColor.setFill()
            for rect in bracketHighlightRects where rect.intersects(dirtyRect) {
                rect.fill()
            }
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        layoutFragment.draw(at: .zero, in: context)
    }

    private func colorsEqual(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.isEqual(rhs)
        default:
            return false
        }
    }
}
#endif
