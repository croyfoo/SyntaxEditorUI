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
    public var colorTheme: SyntaxEditorColorTheme
    public var drawsBackground: Bool
    public var fontSizeDelta: Int
    public private(set) var revision: Int
    public private(set) var latestChange: SyntaxEditorTextChange?

    public init(
        text: String = "",
        language: SyntaxLanguage = .javascript,
        selectedRange: NSRange = NSRange(location: 0, length: 0),
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false,
        colorTheme: SyntaxEditorColorTheme = .default,
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
        self.colorTheme = colorTheme
        self.drawsBackground = drawsBackground
        self.fontSizeDelta = fontSizeDelta
        self.revision = 0
        self.latestChange = nil
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

        let edit = SyntaxEditorTextEdit(
            range: NSRange(location: 0, length: textStorage.utf16.count),
            replacement: text
        )
        textStorage = text
        selectedRangeStorage = nextSelectedRange
        revision += 1
        let change = SyntaxEditorTextChange(
            revision: revision,
            edits: [edit],
            selectedRange: nextSelectedRange,
            kind: .replacement
        )
        latestChange = change
        return change
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
        colorTheme.resolved(for: language).base.font?.size ?? SyntaxEditorFontSize.defaultEditorPointSize
    }

    @discardableResult
    package func commitEdits(
        _ edits: [SyntaxEditorTextEdit],
        selectedRange: NSRange
    ) -> SyntaxEditorTextChange? {
        guard !edits.isEmpty else {
            selectedRangeStorage = SyntaxEditorRangeUtilities.clampedRange(
                selectedRange,
                utf16Length: textStorage.utf16.count
            )
            return nil
        }

        textStorage = Self.applying(edits, to: textStorage)
        let nextSelectedRange = SyntaxEditorRangeUtilities.clampedRange(
            selectedRange,
            utf16Length: textStorage.utf16.count
        )
        selectedRangeStorage = nextSelectedRange
        revision += 1
        let change = SyntaxEditorTextChange(
            revision: revision,
            edits: edits,
            selectedRange: nextSelectedRange,
            kind: .incremental
        )
        latestChange = change
        return change
    }

    nonisolated package static func applying(_ edits: [SyntaxEditorTextEdit], to source: String) -> String {
        let mutable = NSMutableString(string: source)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return mutable as String
    }

    nonisolated package static func inverseEdits(
        for edits: [SyntaxEditorTextEdit],
        in source: String
    ) -> [SyntaxEditorTextEdit] {
        let nsSource = source as NSString
        var delta = 0
        return edits
            .sorted { $0.range.location < $1.range.location }
            .map { edit in
                let original = nsSource.substring(with: edit.range)
                let inverse = SyntaxEditorTextEdit(
                    range: NSRange(
                        location: edit.range.location + delta,
                        length: edit.replacement.utf16.count
                    ),
                    replacement: original
                )
                delta += edit.replacement.utf16.count - edit.range.length
                return inverse
            }
    }
}

public struct SyntaxEditorTextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

public struct SyntaxEditorTextChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case incremental
        case replacement
    }

    public let revision: Int
    public let edits: [SyntaxEditorTextEdit]
    public let selectedRange: NSRange
    public let kind: Kind

    public init(
        revision: Int,
        edits: [SyntaxEditorTextEdit],
        selectedRange: NSRange,
        kind: Kind
    ) {
        self.revision = revision
        self.edits = edits
        self.selectedRange = selectedRange
        self.kind = kind
    }
}
