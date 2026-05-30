#if canImport(AppKit)
import AppKit
import SyntaxEditorCore

@MainActor
final class MacSyntaxEditorTextInputView: NSView, @preconcurrency NSTextInputClient, @preconcurrency NSTextViewportLayoutControllerDelegate {
    let textKit2System: SyntaxEditorTextKit2System
    let textContentView = MacSyntaxEditorTextContentView()

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
    var usesFindBar = false
    var usesFindPanel = false
    var isIncrementalSearchingEnabled = false
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
        textKit2System.layoutManager.textViewportLayoutController.delegate = self
        addSubview(textContentView)
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

    var textStorage: NSTextStorage? { storage }
    private var storage: NSTextStorage { textKit2System.textStorage }
    var layoutManager: NSLayoutManager? { nil }
    var textLayoutManager: NSTextLayoutManager { textKit2System.layoutManager }
    var textContentStorage: NSTextContentStorage { textKit2System.textContentStorage }
    var textContainer: NSTextContainer? { textKit2System.container }

    var string: String {
        get { storage.string }
        set {
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
        selectedRangeStorage = clamped
        syncTextLayoutSelection()
        didChangeSelection?()
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
        guard let item = sender as? NSMenuItem else {
            enclosingScrollView?.isFindBarVisible = true
            return
        }

        if item.tag == NSTextFinder.Action.showFindInterface.rawValue {
            enclosingScrollView?.isFindBarVisible = true
        }
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
    }

    override func keyDown(with event: NSEvent) {
        if inputContext?.handleEvent(event) == true {
            return
        }
        interpretKeyEvents([event])
    }

    override func mouseDown(with event: NSEvent) {
        unsafe window?.makeFirstResponder(self)
        guard isSelectable else { return }

        let location = convert(event.locationInWindow, from: nil)
        setSelectedRange(NSRange(location: characterIndex(at: location), length: 0))
    }

    override func doCommand(by selector: Selector) {
        if commandHandler?(selector) == true {
            return
        }

        switch selector {
        case #selector(insertNewline(_:)):
            insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        case #selector(deleteBackward(_:)):
            deleteBackward()
        case #selector(moveLeft(_:)):
            moveSelection(offset: -1, extending: false)
        case #selector(moveRight(_:)):
            moveSelection(offset: 1, extending: false)
        default:
            break
        }
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

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
        unsafe actualRange?.pointee = clamped
        let localRect = rectForCharacterRange(clamped)
        guard let window = unsafe self.window else { return localRect }
        return window.convertToScreen(convert(localRect, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        let localPoint = convert(point, from: nil)
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

        configureBracketHighlights(for: fragmentView)
        if fragmentView.frame != layoutFragmentFrame {
            fragmentView.frame = layoutFragmentFrame
            fragmentView.needsDisplay = true
        }
        if unsafe fragmentView.superview != textContentView {
            textContentView.addSubview(fragmentView)
        }
    }

    func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        for staleView in lastUsedFragmentViews {
            staleView.removeFromSuperview()
        }
        lastUsedFragmentViews.removeAll()
    }

    private func replaceText(in range: NSRange, with replacement: String, selectedRange: NSRange) {
        guard shouldChangeText(inRanges: [range], replacementStrings: [replacement]) else { return }
        textContentStorage.performEditingTransaction {
            storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: typingAttributes))
        }
        setSelectedRange(selectedRange)
        invalidateTextLayout()
        didChangeTextNotification()
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

    private func moveSelection(offset: Int, extending: Bool) {
        let nextLocation = min(max(0, selectedRangeStorage.location + offset), storage.length)
        setSelectedRange(NSRange(location: nextLocation, length: 0))
    }

    private func effectiveReplacementRange(_ range: NSRange) -> NSRange {
        if range.location == NSNotFound {
            return selectedRangeStorage
        }
        return SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: storage.length)
    }

    private func syncTextLayoutSelection() {
        guard let textRange = textRange(forUTF16Range: selectedRangeStorage) else { return }
        textLayoutManager.textSelections = [NSTextSelection(range: textRange, affinity: .downstream, granularity: .character)]
    }

    private func characterIndex(at point: NSPoint) -> Int {
        guard let fragment = textLayoutManager.textLayoutFragment(for: point) else {
            return storage.length
        }
        let fragmentRange = textRange(for: fragment)
        return SyntaxEditorRangeUtilities.clampedRange(
            NSRange(location: fragmentRange.location, length: 0),
            utf16Length: storage.length
        ).location
    }

    private func rectForCharacterRange(_ range: NSRange) -> NSRect {
        guard let textRange = textRange(forUTF16Range: range) else { return .zero }
        textLayoutManager.ensureLayout(for: textRange)
        var rect = NSRect.zero
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { _, segmentRect, _, _ in
            rect = rect == .zero ? segmentRect : rect.union(segmentRect)
            return true
        }
        return rect == .zero ? bounds : rect
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
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class MacSyntaxEditorTextLayoutFragmentView: NSView {
    let layoutFragment: NSTextLayoutFragment
    weak var textKit2System: SyntaxEditorTextKit2System?
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

    override func draw(_ dirtyRect: NSRect) {
        if let textKit2System {
            SyntaxEditorTextKit2HighlightRenderer.validateRenderingAttributes(
                layoutManager: textKit2System.layoutManager,
                textContentStorage: textKit2System.textContentStorage,
                renderStore: textKit2System.renderStore,
                fragment: layoutFragment
            )
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
}
#endif
