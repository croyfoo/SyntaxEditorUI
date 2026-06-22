import Foundation
import SyntaxEditorCoreTypes

package enum SyntaxHighlightMutationLineRange {
    package static func changedLineRange(
        for mutation: SyntaxEditorTextChange.Replacement,
        in source: NSString
    ) -> NSRange {
        source.lineRange(for: changedRange(for: mutation, in: source))
    }

    package static func changedRange(
        for mutation: SyntaxEditorTextChange.Replacement,
        in source: NSString
    ) -> NSRange {
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }
        let replacementLength = mutation.replacement.utf16.count
        let changedLocation = min(max(0, mutation.location), source.length)
        var changedEnd = min(
            source.length,
            max(changedLocation + max(1, replacementLength), changedLocation + 1)
        )
        if changedEnd < source.length,
           LineOffsetTable.endsWithLineBreak(mutation.replacement) {
            changedEnd += 1
        }
        return NSRange(location: changedLocation, length: max(0, changedEnd - changedLocation))
    }
}
