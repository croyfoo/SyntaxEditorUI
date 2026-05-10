import Observation
import Foundation

@MainActor
@Observable
public final class SyntaxEditorConfiguration {
    public var language: SyntaxLanguage
    public var isEditable: Bool
    public var lineWrappingEnabled: Bool
    public var colorTheme: SyntaxEditorColorTheme

    public init(
        language: SyntaxLanguage = .javascript,
        isEditable: Bool = true,
        lineWrappingEnabled: Bool = false,
        colorTheme: SyntaxEditorColorTheme = .xcode
    ) {
        self.language = language
        self.isEditable = isEditable
        self.lineWrappingEnabled = lineWrappingEnabled
        self.colorTheme = colorTheme
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

public struct SyntaxEditorDocumentChange: Equatable, Sendable {
    public let revision: Int
    public let edits: [SyntaxEditorTextEdit]
    public let selectedRange: NSRange
    public let isWholeDocumentReplacement: Bool

    public init(
        revision: Int,
        edits: [SyntaxEditorTextEdit],
        selectedRange: NSRange,
        isWholeDocumentReplacement: Bool
    ) {
        self.revision = revision
        self.edits = edits
        self.selectedRange = selectedRange
        self.isWholeDocumentReplacement = isWholeDocumentReplacement
    }
}

@MainActor
@Observable
public final class SyntaxEditorDocument {
    @ObservationIgnored private var storage: String
    public private(set) var revision: Int
    public private(set) var latestChange: SyntaxEditorDocumentChange?

    public init(text: String = "") {
        self.storage = text
        self.revision = 0
        self.latestChange = nil
    }

    public func textSnapshot() -> String {
        storage
    }

    @discardableResult
    public func replaceText(
        _ text: String,
        selectedRange: NSRange = NSRange(location: 0, length: 0)
    ) -> SyntaxEditorDocumentChange {
        let edit = SyntaxEditorTextEdit(
            range: NSRange(location: 0, length: storage.utf16.count),
            replacement: text
        )
        return commitEdits(
            [edit],
            selectedRange: SyntaxEditorRangeUtilities.clampedRange(
                selectedRange,
                utf16Length: text.utf16.count
            ),
            isWholeDocumentReplacement: true
        )
    }

    @discardableResult
    package func commitEdits(
        _ edits: [SyntaxEditorTextEdit],
        selectedRange: NSRange,
        isWholeDocumentReplacement: Bool = false
    ) -> SyntaxEditorDocumentChange {
        guard !edits.isEmpty else {
            let change = SyntaxEditorDocumentChange(
                revision: revision,
                edits: [],
                selectedRange: selectedRange,
                isWholeDocumentReplacement: false
            )
            latestChange = change
            return change
        }

        storage = Self.applying(edits, to: storage)
        revision += 1
        let change = SyntaxEditorDocumentChange(
            revision: revision,
            edits: edits,
            selectedRange: SyntaxEditorRangeUtilities.clampedRange(
                selectedRange,
                utf16Length: storage.utf16.count
            ),
            isWholeDocumentReplacement: isWholeDocumentReplacement
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
