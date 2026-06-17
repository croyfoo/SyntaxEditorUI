import Observation
import Foundation

@MainActor
@Observable
public final class SyntaxEditorModel {
    private var textStorage: String
    private var selectedRangeStorage: NSRange

    public var text: String {
        get {
            textStorage
        }
        set {
            replaceText(newValue)
        }
    }

    public var language: SyntaxLanguage
    public var selectedRange: NSRange {
        get {
            selectedRangeStorage
        }
        set {
            selectedRangeStorage = SyntaxEditorRangeUtilities.clampedRange(
                newValue,
                utf16Length: textStorage.utf16.count
            )
        }
    }

    public var isEditable: Bool
    public var lineWrappingEnabled: Bool
    public var theme: SyntaxEditorTheme
    public var drawsBackground: Bool
    public var fontSizeDelta: Int
    public private(set) var textRevision: Int
    public private(set) var latestTextChange: SyntaxEditorTextChange?

    public init(
        text: String = "",
        language: SyntaxLanguage = .javascript,
        selectedRange: NSRange = NSRange(location: 0, length: 0),
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false,
        theme: SyntaxEditorTheme = .default,
        drawsBackground: Bool = true,
        fontSizeDelta: Int = 0
    ) {
        self.textStorage = text
        self.language = language
        self.selectedRangeStorage = SyntaxEditorRangeUtilities.clampedRange(
            selectedRange,
            utf16Length: text.utf16.count
        )
        self.isEditable = isEditable
        self.lineWrappingEnabled = lineWrappingEnabled
        self.theme = theme
        self.drawsBackground = drawsBackground
        self.fontSizeDelta = fontSizeDelta
        self.textRevision = 0
        self.latestTextChange = nil
    }

    @discardableResult
    public func replaceText(
        _ text: String,
        selectedRange: NSRange? = nil
    ) -> SyntaxEditorTextChange? {
        let nextSelectedRange = SyntaxEditorRangeUtilities.clampedRange(
            selectedRange ?? selectedRangeStorage,
            utf16Length: text.utf16.count
        )

        guard textStorage != text else {
            selectedRangeStorage = nextSelectedRange
            return nil
        }

        let replacement = SyntaxEditorTextChange.Replacement(
            range: NSRange(location: 0, length: textStorage.utf16.count),
            replacement: text
        )
        textStorage = text
        selectedRangeStorage = nextSelectedRange
        textRevision += 1
        let change = SyntaxEditorTextChange(
            textRevision: textRevision,
            replacements: [replacement],
            selectedRange: nextSelectedRange,
            kind: .wholeDocumentReplacement
        )
        latestTextChange = change
        return change
    }

    @discardableResult
    public func replaceContents(
        text: String,
        language: SyntaxLanguage,
        selectedRange: NSRange? = nil
    ) -> SyntaxEditorTextChange? {
        self.language = language
        return replaceText(text, selectedRange: selectedRange)
    }

    public func increaseFontSize() {
        fontSizeDelta = SyntaxEditorFontSize.increasedDelta(
            fontSizeDelta,
            forBasePointSize: fontSizeCommandBasePointSize
        )
    }

    public func decreaseFontSize() {
        fontSizeDelta = SyntaxEditorFontSize.decreasedDelta(
            fontSizeDelta,
            forBasePointSize: fontSizeCommandBasePointSize
        )
    }

    public func resetFontSize() {
        fontSizeDelta = 0
    }

    private var fontSizeCommandBasePointSize: CGFloat {
        theme.resolved(for: language).base.font.size
    }

    @discardableResult
    package func commitTextReplacements(
        _ replacements: [SyntaxEditorTextChange.Replacement],
        selectedRange: NSRange
    ) -> SyntaxEditorTextChange? {
        guard !replacements.isEmpty else {
            selectedRangeStorage = SyntaxEditorRangeUtilities.clampedRange(
                selectedRange,
                utf16Length: textStorage.utf16.count
            )
            return nil
        }

        textStorage = Self.applying(replacements, to: textStorage)
        let nextSelectedRange = SyntaxEditorRangeUtilities.clampedRange(
            selectedRange,
            utf16Length: textStorage.utf16.count
        )
        selectedRangeStorage = nextSelectedRange
        textRevision += 1
        let change = SyntaxEditorTextChange(
            textRevision: textRevision,
            replacements: replacements,
            selectedRange: nextSelectedRange,
            kind: .incremental
        )
        latestTextChange = change
        return change
    }

    nonisolated package static func applying(
        _ replacements: [SyntaxEditorTextChange.Replacement],
        to source: String
    ) -> String {
        let mutable = NSMutableString(string: source)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: replacement.range, with: replacement.replacement)
        }
        return mutable as String
    }

    nonisolated package static func inverseReplacements(
        for replacements: [SyntaxEditorTextChange.Replacement],
        in source: String
    ) -> [SyntaxEditorTextChange.Replacement] {
        let nsSource = source as NSString
        var delta = 0
        return replacements
            .sorted { $0.range.location < $1.range.location }
            .map { replacement in
                let original = nsSource.substring(with: replacement.range)
                let inverse = SyntaxEditorTextChange.Replacement(
                    range: NSRange(
                        location: replacement.range.location + delta,
                        length: replacement.replacement.utf16.count
                    ),
                    replacement: original
                )
                delta += replacement.replacement.utf16.count - replacement.range.length
                return inverse
            }
    }
}

public struct SyntaxEditorTextChange: Equatable, Sendable {
    public struct Replacement: Equatable, Sendable {
        public let range: NSRange
        public let replacement: String

        public var location: Int {
            range.location
        }

        public var length: Int {
            range.length
        }

        public init(range: NSRange, replacement: String) {
            self.range = range
            self.replacement = replacement
        }

        public init(location: Int, length: Int, replacement: String) {
            self.init(
                range: NSRange(location: location, length: length),
                replacement: replacement
            )
        }

        package static func singleReplacement(from oldText: String, to newText: String) -> Replacement? {
            guard oldText != newText else { return nil }

            let oldUTF16 = Array(oldText.utf16)
            let newUTF16 = Array(newText.utf16)
            let prefixLength = commonPrefixLength(oldUTF16, newUTF16)
            let suffixLength = commonSuffixLength(
                oldUTF16,
                newUTF16,
                prefixLength: prefixLength
            )

            let oldChangeEnd = oldUTF16.count - suffixLength
            let newChangeEnd = newUTF16.count - suffixLength
            let replacementUTF16 = Array(newUTF16[prefixLength..<newChangeEnd])

            return Replacement(
                range: NSRange(
                    location: prefixLength,
                    length: oldChangeEnd - prefixLength
                ),
                replacement: String(decoding: replacementUTF16, as: UTF16.self)
            )
        }
    }

    public enum Kind: Equatable, Sendable {
        case incremental
        case wholeDocumentReplacement
    }

    public let textRevision: Int
    public let replacements: [Replacement]
    public let selectedRange: NSRange
    public let kind: Kind

    public init(
        textRevision: Int,
        replacements: [Replacement],
        selectedRange: NSRange,
        kind: Kind
    ) {
        self.textRevision = textRevision
        self.replacements = replacements
        self.selectedRange = selectedRange
        self.kind = kind
    }
}

private extension SyntaxEditorTextChange.Replacement {
    static func commonPrefixLength(_ lhs: [UInt16], _ rhs: [UInt16]) -> Int {
        let count = min(lhs.count, rhs.count)
        var index = 0
        while index < count, lhs[index] == rhs[index] {
            index += 1
        }
        return index
    }

    static func commonSuffixLength(
        _ lhs: [UInt16],
        _ rhs: [UInt16],
        prefixLength: Int
    ) -> Int {
        var lhsIndex = lhs.count
        var rhsIndex = rhs.count
        var matched = 0

        while lhsIndex > prefixLength,
              rhsIndex > prefixLength,
              lhs[lhsIndex - 1] == rhs[rhsIndex - 1]
        {
            lhsIndex -= 1
            rhsIndex -= 1
            matched += 1
        }

        return matched
    }
}
