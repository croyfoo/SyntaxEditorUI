#if canImport(UIKit)
import SyntaxEditorCore
import UIKit

extension SyntaxEditorView {
    @objc public var textInputView: UIView {
        self
    }

    public var hasText: Bool {
        !text.isEmpty
    }

    public func insertText(_ text: String) {
        guard model.isEditable else { return }

        if markedRange != nil {
            replaceCommittedMarkedText(with: text)
            return
        }

        applyUserReplacement(in: selectedRange, replacement: text, deletionIntent: .unspecified)
    }

    @objc(insertText:alternatives:style:)
    public func insertText(_ text: String, alternatives: [String], style: UITextAlternativeStyle) {
        insertText(text)
    }

    public func deleteBackward() {
        guard model.isEditable else { return }

        let deletionRange: NSRange
        let deletionIntent: EditorCommandEngine.DeletionIntent
        if selectedRange.length > 0 {
            deletionRange = selectedRange
            deletionIntent = .unspecified
        } else {
            guard selectedRange.location > 0 else { return }
            deletionRange = (text as NSString).rangeOfComposedCharacterSequence(
                at: selectedRange.location - 1
            )
            deletionIntent = .backward
        }

        applyUserReplacement(in: deletionRange, replacement: "", deletionIntent: deletionIntent)
    }

    public var selectedTextRange: UITextRange? {
        get {
            SyntaxEditorTextRange(nsRange: selectedRange)
        }
        set {
            preserveTextInteractionHorizontalOffsetForCurrentTurn()
            guard let newValue else {
                setSelectedRange(
                    NSRange(location: 0, length: 0),
                    preservesCommandState: false,
                    schedulesSelectionScroll: false
                )
                return
            }
            let location = offset(from: beginningOfDocument, to: newValue.start)
            let length = offset(from: newValue.start, to: newValue.end)
            guard location >= 0, length >= 0 else { return }
            let nextRange = NSRange(location: location, length: length)
            clearMarkedTextIfSelectionLeavesComposition(nextRange)
            setSelectedRange(
                nextRange,
                preservesCommandState: false,
                schedulesSelectionScroll: false
            )
        }
    }

    public var markedTextRange: UITextRange? {
        guard let markedRange else { return nil }
        return SyntaxEditorTextRange(nsRange: markedRange)
    }

    public func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        guard model.isEditable else { return }
        guard let markedText else {
            unmarkText()
            return
        }

        let replacementRange = markedRange ?? self.selectedRange
        let clampedReplacementRange = clampedTextRange(replacementRange)
        replaceMarkedText(in: clampedReplacementRange, replacement: markedText, selectedRange: selectedRange)
    }

    func replaceMarkedText(in range: NSRange, replacement: String, selectedRange: NSRange) {
        let source = text
        let clampedRange = clampedTextRange(range, in: source)
        let replacementUTF16Length = replacement.utf16.count
        let nextText = (source as NSString).replacingCharacters(in: clampedRange, with: replacement)
        let nextMarkedRange = replacement.isEmpty
            ? nil
            : NSRange(location: clampedRange.location, length: replacementUTF16Length)
        let selectedRangeInMarkedText = SyntaxEditorRangeUtilities.clampedRange(
            selectedRange,
            utf16Length: replacementUTF16Length
        )
        let nextSelection = NSRange(
            location: clampedRange.location + selectedRangeInMarkedText.location,
            length: selectedRangeInMarkedText.length
        )

        if nextMarkedRange != nil {
            beginMarkedTextUndoSessionIfNeeded(
                source: source,
                selectedRange: self.selectedRange,
                editStartUTF16: clampedRange.location
            )
        }

        inputDelegate?.textWillChange(self)
        inputDelegate?.selectionWillChange(self)

        performRawReplacement(in: clampedRange, replacement: replacement, preservesMarkedTextSession: true)
        markedRange = nextMarkedRange
        applyMarkedTextAttributes()
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
        if nextMarkedRange == nil {
            finishMarkedTextUndoSessionIfNeeded(
                finalText: nextText,
                selectedRange: currentSelectedRange,
                editStartUTF16: clampedRange.location
            )
        }

        inputDelegate?.selectionDidChange(self)
        inputDelegate?.textDidChange(self)
    }

    func clearMarkedTextIfSelectionLeavesComposition(_ selection: NSRange) {
        guard let markedRange else { return }

        let markedEnd = markedRange.location + markedRange.length
        let selectionEnd = selection.location + selection.length
        guard selection.location < markedRange.location || selectionEnd > markedEnd else { return }

        unmarkText()
    }

    func replaceCommittedMarkedText(with replacement: String) {
        guard let markedRange else {
            applyUserReplacement(in: selectedRange, replacement: replacement, deletionIntent: .unspecified)
            return
        }

        let source = text
        let clampedRange = clampedTextRange(markedRange, in: source)
        guard model.isEditable else { return }
        beginMarkedTextCommitUndoSessionIfNeeded(source: source, markedRange: clampedRange)

        let nextText = (source as NSString).replacingCharacters(in: clampedRange, with: replacement)
        let nextSelection = NSRange(location: clampedRange.location + replacement.utf16.count, length: 0)

        inputDelegate?.textWillChange(self)
        inputDelegate?.selectionWillChange(self)

        performRawReplacement(in: clampedRange, replacement: replacement, preservesMarkedTextSession: true)
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
        finishMarkedTextUndoSessionIfNeeded(
            finalText: nextText,
            selectedRange: currentSelectedRange,
            editStartUTF16: clampedRange.location
        )

        inputDelegate?.selectionDidChange(self)
        inputDelegate?.textDidChange(self)
    }

    public func unmarkText() {
        let previousMarkedRange = markedRange
        markedRange = nil
        if let previousMarkedRange {
            reapplyTextAttributes(in: previousMarkedRange)
            finishMarkedTextUndoSessionIfNeeded(
                finalText: text,
                selectedRange: selectedRange,
                editStartUTF16: previousMarkedRange.location
            )
        }
    }

    public var beginningOfDocument: UITextPosition {
        SyntaxEditorTextPosition(offset: 0)
    }

    public var endOfDocument: UITextPosition {
        SyntaxEditorTextPosition(offset: text.utf16.count)
    }

    public func text(in range: UITextRange) -> String? {
        let location = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        guard location >= 0, length >= 0 else { return nil }
        return string(in: NSRange(location: location, length: length))
    }

    public func replace(_ range: UITextRange, withText text: String) {
        let location = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        guard location >= 0, length >= 0 else { return }
        applyUserReplacement(
            in: NSRange(location: location, length: length),
            replacement: text,
            deletionIntent: .unspecified
        )
    }

    public func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let fromOffset = offset(for: fromPosition),
              let toOffset = offset(for: toPosition)
        else {
            return nil
        }

        let lower = min(fromOffset, toOffset)
        let upper = max(fromOffset, toOffset)
        return SyntaxEditorTextRange(nsRange: NSRange(location: lower, length: upper - lower))
    }

    func isValidTextPositionOffset(_ offset: Int, in source: NSString) -> Bool {
        let textLength = source.length
        guard offset >= 0, offset <= textLength else { return false }
        guard offset > 0, offset < textLength else { return true }
        return source.rangeOfComposedCharacterSequence(at: offset).location == offset
    }

    func composedCharacterRange(extendingFrom offset: Int, in direction: UITextLayoutDirection) -> NSRange? {
        let source = text as NSString
        let textLength = source.length

        switch direction {
        case .left, .up:
            guard offset > 0, offset <= textLength else { return nil }
            return source.rangeOfComposedCharacterSequence(at: offset - 1)
        case .right, .down:
            guard offset >= 0, offset < textLength else { return nil }
            return source.rangeOfComposedCharacterSequence(at: offset)
        @unknown default:
            return nil
        }
    }

    public func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let currentOffset = self.offset(for: position) else { return nil }
        let source = text as NSString
        let nextOffsetResult = currentOffset.addingReportingOverflow(offset)
        guard !nextOffsetResult.overflow else { return nil }
        let nextOffset = nextOffsetResult.partialValue
        guard isValidTextPositionOffset(currentOffset, in: source),
              isValidTextPositionOffset(nextOffset, in: source)
        else {
            return nil
        }
        return SyntaxEditorTextPosition(offset: nextOffset)
    }

    public func position(
        from position: UITextPosition,
        in direction: UITextLayoutDirection,
        offset: Int
    ) -> UITextPosition? {
        guard offset != 0 else { return position }
        guard let currentOffset = self.offset(for: position),
              let currentLocation = textLocation(forUTF16Offset: currentOffset)
        else {
            return nil
        }

        layoutTextIfNeeded()
        let initialSelection = isHardLineBreakCaretLocation(currentOffset)
            ? NSTextSelection(currentLocation, affinity: .upstream)
            : NSTextSelection(currentLocation, affinity: .downstream)
        if let caretRect = textLayoutCaretRect(forUTF16Location: currentOffset) {
            initialSelection.anchorPositionOffset = caretRect.midX
        }
        var destinationSelection: NSTextSelection? = initialSelection
        let navigationDirection = direction.textSelectionNavigationDirection
        for _ in 0..<abs(offset) {
            guard let selection = destinationSelection else { return nil }
            destinationSelection = layoutManager.textSelectionNavigation.destinationSelection(
                for: selection,
                direction: offset > 0 ? navigationDirection : navigationDirection.reversed,
                destination: .character,
                extending: false,
                confined: false
            )
        }

        guard let location = destinationSelection?.textRanges.first?.location else { return nil }
        return SyntaxEditorTextPosition(offset: utf16Offset(for: location))
    }

    public func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard let lhs = offset(for: position),
              let rhs = offset(for: other)
        else {
            return .orderedSame
        }

        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    public func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard let source = offset(for: from),
              let target = offset(for: toPosition)
        else {
            return 0
        }
        return target - source
    }

    public func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        switch direction {
        case .left, .up:
            return range.start
        case .right, .down:
            return range.end
        @unknown default:
            return nil
        }
    }

    public func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let currentOffset = offset(for: position) else { return nil }

        guard let characterRange = composedCharacterRange(extendingFrom: currentOffset, in: direction) else { return nil }
        return SyntaxEditorTextRange(nsRange: characterRange)
    }

    public func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .leftToRight
    }

    public func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    public func firstRect(for range: UITextRange) -> CGRect {
        preserveTextInteractionHorizontalOffsetForCurrentTurn()
        let location = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        guard location >= 0, length >= 0 else { return .zero }

        guard length > 0 else {
            return caretRect(for: range.start)
        }

        guard let textRange = textRange(forUTF16Range: NSRange(location: location, length: length)) else {
            return caretRect(for: range.start)
        }

        layoutManager.ensureLayout(for: textRange)
        var firstRect: CGRect?
        layoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: [.middleFragmentsExcluded]
        ) { _, rect, _, _ in
            firstRect = rect
            return false
        }

        return firstRect?
            .offsetBy(dx: textContentView.frame.minX, dy: textContentView.frame.minY)
            ?? caretRect(for: range.start)
    }

    public func caretRect(for position: UITextPosition) -> CGRect {
        preserveTextInteractionHorizontalOffsetForCurrentTurn()
        guard let location = offset(for: position) else {
            return defaultCaretRect()
        }

        return caretRect(forUTF16Location: location)
    }

    func caretRect(forUTF16Location location: Int) -> CGRect {
        guard let caretRect = textLayoutCaretRect(forUTF16Location: location) else { return defaultCaretRect() }
        return CGRect(
            x: caretRect.minX + textContentView.frame.minX - 1,
            y: caretRect.minY + textContentView.frame.minY,
            width: max(2, caretRect.width),
            height: max(font.lineHeight, caretRect.height)
        )
    }

    func textLayoutCaretRect(forUTF16Location location: Int) -> CGRect? {
        if !isLayingOutText {
            layoutTextIfNeeded()
        }

        guard let textLocation = textLocation(forUTF16Offset: location)
        else {
            return nil
        }
        if let trailingWhitespaceCaretRect = trailingWhitespaceLineEndCaretRect(forUTF16Location: location) {
            return trailingWhitespaceCaretRect
        }
        let textRange = NSTextRange(location: textLocation)

        layoutManager.ensureLayout(for: textRange)
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
        layoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: options
        ) { _, rect, _, _ in
            caretRect = rect
            return false
        }

        return caretRect
    }

    func trailingWhitespaceLineEndCaretRect(forUTF16Location location: Int) -> CGRect? {
        guard isHardLineBreakCaretLocation(location), location > 0 else { return nil }

        let source = text as NSString
        var whitespaceStart = location
        while whitespaceStart > 0 {
            let previousOffset = whitespaceStart - 1
            let character = source.character(at: previousOffset)
            guard character == 0x20 || character == 0x09 else { break }
            whitespaceStart = previousOffset
        }

        guard whitespaceStart < location,
              let anchorRect = textLayoutCaretRect(forUTF16Location: whitespaceStart)
        else {
            return nil
        }

        let whitespace = source.substring(
            with: NSRange(location: whitespaceStart, length: location - whitespaceStart)
        )
        let whitespaceWidth = (whitespace as NSString).size(withAttributes: [.font: font]).width
        return CGRect(
            x: anchorRect.minX + whitespaceWidth,
            y: anchorRect.minY,
            width: anchorRect.width,
            height: anchorRect.height
        )
    }

    func textLineFragmentLookupUTF16Location(forUTF16Location location: Int) -> Int {
        let textLength = text.utf16.count
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

    func textLayoutLineCaretRect(
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

        let clampedLocation = min(max(0, location), text.utf16.count)
        var lineEndCaretX: CGFloat?
        var exactCaretX: CGFloat?
        var resolvedCaretX: CGFloat?
        var closestDistance = Int.max
        unsafe layoutManager.enumerateCaretOffsetsInLineFragment(at: lineStartLocation) { caretOffset, caretLocation, _, stop in
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
        return CGRect(
            x: caretX,
            y: lineFrame.minY,
            width: 2,
            height: max(font.lineHeight, lineFrame.height)
        )
    }

    func textLayoutLineFragment(
        containingUTF16Offset offset: Int,
        preferredTextLocation: NSTextLocation
    ) -> (NSTextLayoutFragment, NSTextLineFragment)? {
        if let layoutFragment = layoutManager.textLayoutFragment(for: preferredTextLocation),
           let lineFragment = textLineFragment(containingUTF16Offset: offset, in: layoutFragment) {
            return (layoutFragment, lineFragment)
        }

        var result: (NSTextLayoutFragment, NSTextLineFragment)?
        layoutManager.enumerateTextLayoutFragments(
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

    func usesLineEndCaretX(forUTF16Location location: Int) -> Bool {
        if isHardLineBreakCaretLocation(location) {
            return true
        }

        let textLength = text.utf16.count
        return location == textLength
            && textLength > 0
            && !isHardLineBreakCaretLocation(textLength - 1)
    }

    func textLineFragment(
        containingUTF16Offset offset: Int,
        in layoutFragment: NSTextLayoutFragment
    ) -> NSTextLineFragment? {
        let fragmentStart = utf16Offset(for: layoutFragment.rangeInElement.location)
        let textLength = text.utf16.count
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

    func defaultCaretRect() -> CGRect {
        CGRect(
            x: textContainerInset.left + container.lineFragmentPadding,
            y: textContainerInset.top,
            width: 2,
            height: font.lineHeight
        )
    }

    public func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        preserveTextInteractionHorizontalOffsetForCurrentTurn()
        let location = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        guard location >= 0, length >= 0 else { return [] }

        if length == 0 {
            return [
                SyntaxEditorSelectionRect(
                    rect: caretRect(for: range.start),
                    containsStart: true,
                    containsEnd: true
                ),
            ]
        }

        guard let textRange = textRange(forUTF16Range: NSRange(location: location, length: length)) else { return [] }

        var result: [UITextSelectionRect] = []
        layoutManager.ensureLayout(for: textRange)
        layoutManager.enumerateTextSegments(
            in: textRange,
            type: .selection,
            options: [.upstreamAffinity]
        ) { textSegmentRange, rect, _, _ in
            let isFirst = result.isEmpty
            result.append(
                SyntaxEditorSelectionRect(
                    rect: rect.offsetBy(dx: self.textContentView.frame.minX, dy: self.textContentView.frame.minY),
                    containsStart: isFirst,
                    containsEnd: textSegmentRange?.endLocation.compare(textRange.endLocation) == .orderedSame
                )
            )
            return true
        }
        return result
    }

    public func closestPosition(to point: CGPoint) -> UITextPosition? {
        preserveTextInteractionHorizontalOffsetForCurrentTurn()
        return closestTextPosition(to: point, constrainedTo: nil)
    }

    public func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        preserveTextInteractionHorizontalOffsetForCurrentTurn()
        let location = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        guard location >= 0, length >= 0 else { return nil }

        return closestTextPosition(
            to: point,
            constrainedTo: NSRange(location: location, length: length)
        )
    }

    public func characterRange(at point: CGPoint) -> UITextRange? {
        guard let position = closestPosition(to: point),
              let start = offset(for: position)
        else {
            return nil
        }

        guard let characterRange = composedCharacterRange(extendingFrom: start, in: .right) else {
            return SyntaxEditorTextRange(nsRange: NSRange(location: start, length: 0))
        }
        return SyntaxEditorTextRange(nsRange: characterRange)
    }

    public func position(within range: UITextRange, atCharacterOffset offset: Int) -> UITextPosition? {
        let startOffset = self.offset(from: beginningOfDocument, to: range.start)
        let length = self.offset(from: range.start, to: range.end)
        guard startOffset >= 0, length >= 0 else { return nil }
        let endOffset = min(startOffset + length, text.utf16.count)
        let targetOffset = min(max(startOffset + offset, startOffset), endOffset)
        return SyntaxEditorTextPosition(offset: targetOffset)
    }

    public func characterOffset(of position: UITextPosition, within range: UITextRange) -> Int {
        let rangeStart = offset(from: beginningOfDocument, to: range.start)
        guard let positionOffset = offset(for: position),
              rangeStart >= 0
        else {
            return 0
        }
        return positionOffset - rangeStart
    }

    func closestTextPosition(to point: CGPoint, constrainedTo range: NSRange?) -> UITextPosition? {
        layoutTextIfNeeded()
        let pointInTextContainer = CGPoint(
            x: point.x - textContentView.frame.minX,
            y: point.y - textContentView.frame.minY
        )
        let containerLocation = textContentStorage.documentRange.location

        if let location = caretTextLocation(
            interactingAt: pointInTextContainer,
            inContainerAt: containerLocation
        ) {
            return SyntaxEditorTextPosition(
                offset: clampedHitOffset(utf16Offset(for: location), constrainedTo: range)
            )
        }

        let fallbackSelections = layoutManager.textSelectionNavigation.textSelections(
            interactingAt: pointInTextContainer,
            inContainerAt: containerLocation,
            anchors: [],
            modifiers: [],
            selecting: false,
            bounds: layoutManager.usageBoundsForTextContainer
        )
        if let location = fallbackSelections.first?.textRanges.first?.location {
            return SyntaxEditorTextPosition(
                offset: clampedHitOffset(utf16Offset(for: location), constrainedTo: range)
            )
        }

        return SyntaxEditorTextPosition(offset: clampedHitOffset(text.utf16.count, constrainedTo: range))
    }

    func caretTextLocation(
        interactingAt point: CGPoint,
        inContainerAt containerLocation: NSTextLocation
    ) -> NSTextLocation? {
        guard let lineFragmentRange = layoutManager.lineFragmentRange(
            for: point,
            inContainerAt: containerLocation
        ) else {
            return nil
        }

        if let layoutFragmentFrame = layoutManager.textLayoutFragment(for: point)?.layoutFragmentFrame,
           (point.y < layoutFragmentFrame.minY || point.y > layoutFragmentFrame.maxY) {
            return nil
        }

        var closestDistance = CGFloat.greatestFiniteMagnitude
        var closestLocation: NSTextLocation?
        var maximumCaretOffset = -CGFloat.greatestFiniteMagnitude
        unsafe layoutManager.enumerateCaretOffsetsInLineFragment(at: lineFragmentRange.location) { caretOffset, location, leadingEdge, stop in
            maximumCaretOffset = max(maximumCaretOffset, caretOffset)
            let distance = abs(caretOffset - point.x)
            if distance < closestDistance || shouldPreferTrailingCaretLocation(
                location,
                over: closestLocation,
                distance: distance,
                closestDistance: closestDistance
            ) {
                closestDistance = distance
                closestLocation = location
            } else if leadingEdge && caretOffset > point.x && distance > closestDistance {
                unsafe stop.pointee = true
            }
        }

        if point.x > maximumCaretOffset {
            return caretLineEndLocation(for: lineFragmentRange)
        }

        return closestLocation
    }

    func clampedHitOffset(_ offset: Int, constrainedTo range: NSRange?) -> Int {
        let textLength = text.utf16.count
        guard let range else {
            return min(max(0, offset), textLength)
        }

        let lowerBound = min(max(0, range.location), textLength)
        let upperBound = min(max(lowerBound, range.location + range.length), textLength)
        return min(max(offset, lowerBound), upperBound)
    }

    func isHardLineBreakCaretLocation(_ location: Int) -> Bool {
        guard location >= 0, location < text.utf16.count else { return false }
        let character = (text as NSString).character(at: location)
        return character == 0x0A || character == 0x0D
    }

    func caretLineEndLocation(for lineFragmentRange: NSTextRange) -> NSTextLocation {
        let endOffset = utf16Offset(for: lineFragmentRange.endLocation)
        if let lineBreakOffset = lineBreakCaretOffset(endingAt: endOffset),
           let lineBreakLocation = textLocation(forUTF16Offset: lineBreakOffset) {
            return lineBreakLocation
        }
        return lineFragmentRange.endLocation
    }

    func lineBreakCaretOffset(endingAt endOffset: Int) -> Int? {
        let lineBreakOffset = endOffset - 1
        guard isHardLineBreakCaretLocation(lineBreakOffset) else { return nil }

        let character = (text as NSString).character(at: lineBreakOffset)
        if character == 0x0A, lineBreakOffset > 0 {
            let previousCharacter = (text as NSString).character(at: lineBreakOffset - 1)
            if previousCharacter == 0x0D {
                return lineBreakOffset - 1
            }
        }

        return lineBreakOffset
    }

    func shouldPreferTrailingCaretLocation(
        _ location: NSTextLocation,
        over closestLocation: NSTextLocation?,
        distance: CGFloat,
        closestDistance: CGFloat
    ) -> Bool {
        guard distance.isNearlyEqual(to: closestDistance),
              let closestLocation else {
            return false
        }

        return utf16Offset(for: location) > utf16Offset(for: closestLocation)
    }

    func beginMarkedTextCommitUndoSessionIfNeeded(source: String, markedRange: NSRange) {
        guard markedTextUndoAnchor == nil else { return }

        let restoreText = (source as NSString).replacingCharacters(in: markedRange, with: "")
        let restoreLocation = min(markedRange.location, restoreText.utf16.count)
        markedTextUndoAnchor = EditorUndoState(
            text: restoreText,
            selectedRange: NSRange(location: restoreLocation, length: 0),
            refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                in: restoreText,
                around: restoreLocation
            )
        )
    }

    func beginMarkedTextUndoSessionIfNeeded(
        source: String,
        selectedRange: NSRange,
        editStartUTF16: Int
    ) {
        guard markedTextUndoAnchor == nil else { return }
        markedTextUndoAnchor = EditorUndoState(
            text: source,
            selectedRange: selectedRange,
            refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                in: source,
                around: editStartUTF16
            )
        )
    }

    func finishMarkedTextUndoSessionIfNeeded(
        finalText: String,
        selectedRange: NSRange,
        editStartUTF16: Int
    ) {
        guard let restore = markedTextUndoAnchor else { return }
        markedTextUndoAnchor = nil
        guard !isApplyingUndoRedo else { return }

        registerUndoAction(
            restore: restore,
            counterpart: EditorUndoState(
                text: finalText,
                selectedRange: selectedRange,
                refreshStartUTF16: SyntaxEditorRangeUtilities.lineStartUTF16Offset(
                    in: finalText,
                    around: editStartUTF16
                )
            )
        )
    }
}

private extension UITextLayoutDirection {
    var textSelectionNavigationDirection: NSTextSelectionNavigation.Direction {
        switch self {
        case .up:
            .up
        case .down:
            .down
        case .left:
            .left
        case .right:
            .right
        @unknown default:
            NSTextSelectionNavigation.Direction(rawValue: rawValue)!
        }
    }
}

private extension NSTextSelectionNavigation.Direction {
    var reversed: NSTextSelectionNavigation.Direction {
        switch self {
        case .forward:
            .backward
        case .backward:
            .forward
        case .right:
            .left
        case .left:
            .right
        case .up:
            .down
        case .down:
            .up
        @unknown default:
            self
        }
    }
}
#endif
