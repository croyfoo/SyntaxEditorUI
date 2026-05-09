#if canImport(UIKit)
import UIKit

@MainActor
final class SyntaxEditorFindCoordinator: NSObject, @MainActor UIFindInteractionDelegate, @MainActor UITextSearching {
    typealias DocumentIdentifier = Int

    private let documentIdentifier = 0
    weak var editorView: SyntaxEditorView?
    lazy var findInteraction = UIFindInteraction(sessionDelegate: self)
    private var activeResultAggregator: UITextSearchAggregator<Int>?

    init(editorView: SyntaxEditorView) {
        self.editorView = editorView
        super.init()
    }

    var selectedTextRange: UITextRange? {
        editorView?.selectedTextRange
    }

    var selectedTextSearchDocument: Int? {
        documentIdentifier
    }

    var supportsTextReplacement: Bool {
        editorView?.model.isEditable ?? false
    }

    func findInteraction(_ interaction: UIFindInteraction, sessionFor view: UIView) -> UIFindSession? {
        guard editorView != nil else { return nil }
        return UITextSearchingFindSession(searchableObject: self)
    }

    func findInteraction(_ interaction: UIFindInteraction, didEnd session: UIFindSession) {
        activeResultAggregator?.invalidate()
        activeResultAggregator = nil
        editorView?.clearFindDecorations()
    }

    func compare(
        _ foundRange: UITextRange,
        toRange: UITextRange,
        document: Int?
    ) -> ComparisonResult {
        guard let lhs = nsRange(for: foundRange),
              let rhs = nsRange(for: toRange)
        else {
            return .orderedSame
        }

        if lhs.location < rhs.location { return .orderedAscending }
        if lhs.location > rhs.location { return .orderedDescending }
        if lhs.length < rhs.length { return .orderedAscending }
        if lhs.length > rhs.length { return .orderedDescending }
        return .orderedSame
    }

    func compare(document: Int, toDocument: Int) -> ComparisonResult {
        if document < toDocument { return .orderedAscending }
        if document > toDocument { return .orderedDescending }
        return .orderedSame
    }

    func performTextSearch(
        queryString: String,
        options: UITextSearchOptions,
        resultAggregator: UITextSearchAggregator<Int>
    ) {
        guard let editorView else {
            resultAggregator.finishedSearching()
            return
        }

        activeResultAggregator = resultAggregator
        editorView.beginFindDecorationBatch()
        defer {
            editorView.endFindDecorationBatch()
        }
        editorView.clearFindDecorations()

        let ranges = Self.searchRanges(
            in: editorView.text,
            queryString: queryString,
            compareOptions: sanitizedCompareOptions(options.stringCompareOptions),
            wordMatchMethod: options.wordMatchMethod
        )
        for range in ranges {
            resultAggregator.foundRange(
                SyntaxEditorTextRange(nsRange: range),
                searchString: queryString,
                document: documentIdentifier
            )
        }
        resultAggregator.finishedSearching()
    }

    func decorate(
        foundTextRange: UITextRange,
        document: Int?,
        usingStyle: UITextSearchFoundTextStyle
    ) {
        guard let range = nsRange(for: foundTextRange) else { return }
        editorView?.decorateFindTextRange(range, style: usingStyle)
    }

    func clearAllDecoratedFoundText() {
        editorView?.clearFindDecorations()
    }

    func invalidateResultsAfterTextChange() {
        activeResultAggregator?.invalidate()
        activeResultAggregator = nil
        findInteraction.updateResultCount()
    }

    func willHighlight(foundTextRange: UITextRange, document: Int?) {
        scrollRangeToVisible(foundTextRange, inDocument: document)
    }

    func scrollRangeToVisible(_ range: UITextRange, inDocument: Int?) {
        guard let range = nsRange(for: range) else { return }
        editorView?.scrollRangeToVisible(range)
    }

    func shouldReplace(foundTextRange: UITextRange, document: Int?, withText: String) -> Bool {
        guard editorView?.model.isEditable == true,
              let range = nsRange(for: foundTextRange)
        else {
            return false
        }
        return range.length > 0
    }

    func replace(foundTextRange: UITextRange, document: Int?, withText text: String) {
        guard shouldReplace(foundTextRange: foundTextRange, document: document, withText: text),
              let range = nsRange(for: foundTextRange)
        else {
            return
        }
        editorView?.replaceFindText(in: range, with: text)
    }

    func replaceAll(queryString: String, options: UITextSearchOptions, withText text: String) {
        editorView?.replaceAllFindMatches(
            queryString: queryString,
            compareOptions: sanitizedCompareOptions(options.stringCompareOptions),
            wordMatchMethod: options.wordMatchMethod,
            with: text
        )
    }

    func nsRange(for textRange: UITextRange) -> NSRange? {
        guard let editorView,
              let start = editorView.offset(for: textRange.start),
              let end = editorView.offset(for: textRange.end)
        else {
            return nil
        }

        let lower = min(start, end)
        let upper = max(start, end)
        return editorView.clampedTextRange(NSRange(location: lower, length: upper - lower))
    }

    func sanitizedCompareOptions(_ options: NSString.CompareOptions) -> NSString.CompareOptions {
        var sanitized = options
        sanitized.remove(.backwards)
        sanitized.remove(.anchored)
        return sanitized
    }

    static func searchRanges(
        in source: String,
        queryString: String,
        compareOptions: NSString.CompareOptions = [],
        wordMatchMethod: UITextSearchOptions.WordMatchMethod = .contains
    ) -> [NSRange] {
        guard !source.isEmpty, !queryString.isEmpty else { return [] }

        let sourceString = source as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: sourceString.length)
        var options = compareOptions
        options.remove(.backwards)
        options.remove(.anchored)

        while searchRange.length > 0 {
            let foundRange = sourceString.range(
                of: queryString,
                options: options,
                range: searchRange
            )
            guard foundRange.location != NSNotFound, foundRange.length > 0 else { break }

            let alignedRange = composedCharacterAlignedRange(foundRange, in: sourceString)
            if accepts(range: alignedRange, in: sourceString, wordMatchMethod: wordMatchMethod) {
                ranges.append(alignedRange)
            }

            let nextLocation = foundRange.location + max(foundRange.length, 1)
            guard nextLocation <= sourceString.length else { break }
            searchRange = NSRange(location: nextLocation, length: sourceString.length - nextLocation)
        }

        return ranges
    }

    private static func composedCharacterAlignedRange(_ range: NSRange, in source: NSString) -> NSRange {
        guard range.length > 0, source.length > 0 else { return range }

        let startRange = source.rangeOfComposedCharacterSequence(at: range.location)
        let endRange = source.rangeOfComposedCharacterSequence(at: range.location + range.length - 1)
        let lower = min(startRange.location, range.location)
        let upper = max(endRange.location + endRange.length, range.location + range.length)
        return NSRange(location: lower, length: upper - lower)
    }

    private static func accepts(
        range: NSRange,
        in source: NSString,
        wordMatchMethod: UITextSearchOptions.WordMatchMethod
    ) -> Bool {
        switch wordMatchMethod {
        case .contains:
            true
        case .startsWith:
            isIdentifierBoundary(at: range.location, in: source)
        case .fullWord:
            isIdentifierBoundary(at: range.location, in: source)
                && isIdentifierBoundary(at: range.location + range.length, in: source)
        @unknown default:
            true
        }
    }

    private static func isIdentifierBoundary(at offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        let source = source as String
        guard let index = stringIndex(forUTF16Offset: offset, in: source) else {
            return false
        }

        let previousIndex = source.index(before: index)
        return !isIdentifierCharacter(source[previousIndex])
            || !isIdentifierCharacter(source[index])
    }

    private static func stringIndex(forUTF16Offset offset: Int, in source: String) -> String.Index? {
        let utf16Index = source.utf16.index(source.utf16.startIndex, offsetBy: offset)
        return String.Index(utf16Index, within: source)
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        if character == "_" { return true }
        return character.unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }
}
#endif
