import Foundation

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

extension SyntaxEditorTextChange {
    package static func applying(
        _ replacements: [SyntaxEditorTextChange.Replacement],
        to source: String
    ) -> String {
        let mutable = NSMutableString(string: source)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: replacement.range, with: replacement.replacement)
        }
        return mutable as String
    }

    package static func inverseReplacements(
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
