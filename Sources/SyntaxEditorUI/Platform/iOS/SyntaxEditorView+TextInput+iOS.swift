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
        applyUserReplacement(in: selectedRange, replacement: text, deletionIntent: .unspecified)
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
            setSelectedRange(
                NSRange(location: location, length: length),
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

        let replacement = markedText ?? ""
        let replacementRange = markedRange ?? self.selectedRange
        applyUserReplacement(
            in: replacementRange,
            replacement: replacement,
            deletionIntent: .unspecified,
            allowsCommandTransform: false
        )

        guard !replacement.isEmpty else {
            markedRange = nil
            return
        }

        let nextMarkedRange = NSRange(location: replacementRange.location, length: replacement.utf16.count)
        markedRange = nextMarkedRange
        setSelectedRange(
            NSRange(
                location: nextMarkedRange.location + selectedRange.location,
                length: selectedRange.length
            ),
            preservesCommandState: false,
            schedulesSelectionScroll: false
        )
    }

    public func unmarkText() {
        markedRange = nil
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

    public func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let currentOffset = self.offset(for: position) else { return nil }
        let nextOffset = currentOffset + offset
        guard nextOffset >= 0, nextOffset <= text.utf16.count else { return nil }
        return SyntaxEditorTextPosition(offset: nextOffset)
    }

    public func position(
        from position: UITextPosition,
        in direction: UITextLayoutDirection,
        offset: Int
    ) -> UITextPosition? {
        switch direction {
        case .left, .up:
            return self.position(from: position, offset: -offset)
        case .right, .down:
            return self.position(from: position, offset: offset)
        @unknown default:
            return nil
        }
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

        switch direction {
        case .left, .up:
            guard currentOffset > 0 else { return nil }
            return SyntaxEditorTextRange(nsRange: NSRange(location: currentOffset - 1, length: 1))
        case .right, .down:
            guard currentOffset < text.utf16.count else { return nil }
            return SyntaxEditorTextRange(nsRange: NSRange(location: currentOffset, length: 1))
        @unknown default:
            return nil
        }
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
        guard let textLocation = textLocation(forUTF16Offset: location)
        else {
            return defaultCaretRect()
        }
        let textRange = NSTextRange(location: textLocation)

        layoutManager.ensureLayout(for: textRange)
        var caretRect: CGRect?
        layoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: [.upstreamAffinity]
        ) { _, rect, _, _ in
            caretRect = rect
            return false
        }

        guard let caretRect else { return defaultCaretRect() }
        return CGRect(
            x: caretRect.minX + textContentView.frame.minX - 1,
            y: caretRect.minY + textContentView.frame.minY,
            width: max(2, caretRect.width),
            height: max(font.lineHeight, caretRect.height)
        )
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

        guard length > 0 else {
            return closestTextPosition(to: point, constrainedTo: nil)
        }

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

        let length = start < text.utf16.count ? 1 : 0
        return SyntaxEditorTextRange(nsRange: NSRange(location: start, length: length))
    }

    public func position(within range: UITextRange, atCharacterOffset offset: Int) -> UITextPosition? {
        let startOffset = self.offset(from: beginningOfDocument, to: range.start)
        guard startOffset >= 0 else { return nil }
        return SyntaxEditorTextPosition(offset: min(max(0, startOffset + offset), text.utf16.count))
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
           !layoutFragmentFrame.contains(point) {
            return nil
        }

        var closestDistance = CGFloat.greatestFiniteMagnitude
        var closestLocation: NSTextLocation?
        unsafe layoutManager.enumerateCaretOffsetsInLineFragment(at: lineFragmentRange.location) { caretOffset, location, leadingEdge, stop in
            guard leadingEdge else { return }

            let distance = abs(caretOffset - point.x)
            if distance < closestDistance {
                closestDistance = distance
                closestLocation = location
            } else if distance > closestDistance {
                unsafe stop.pointee = true
            }
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
}
#endif
