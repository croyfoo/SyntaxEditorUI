import Observation
import Foundation
import SyntaxEditorCoreTypes
import SyntaxEditorTheme

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
    /// The shape of the insertion caret.
    public var caretStyle: CaretStyle
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
        fontSizeDelta: Int = 0,
        caretStyle: CaretStyle = .line
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
        self.caretStyle = caretStyle
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
        fontSizeDelta = SyntaxEditorTheme.FontSize.increasedDelta(
            fontSizeDelta,
            forBasePointSize: fontSizeCommandBasePointSize
        )
    }

    public func decreaseFontSize() {
        fontSizeDelta = SyntaxEditorTheme.FontSize.decreasedDelta(
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
        SyntaxEditorTextChange.applying(replacements, to: source)
    }

    nonisolated package static func inverseReplacements(
        for replacements: [SyntaxEditorTextChange.Replacement],
        in source: String
    ) -> [SyntaxEditorTextChange.Replacement] {
        SyntaxEditorTextChange.inverseReplacements(for: replacements, in: source)
    }
}
