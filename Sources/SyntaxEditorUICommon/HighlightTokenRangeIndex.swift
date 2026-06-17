#if canImport(UIKit) || canImport(AppKit)
import Foundation
import SyntaxEditorCore

package struct HighlightTokenRangeIndex {
    private let prefixMaxUpperBounds: [Int]

    package init(tokens: [SyntaxEditorHighlighting.Token]) {
        var maxUpperBound = 0
        prefixMaxUpperBounds = tokens.map { token in
            maxUpperBound = max(maxUpperBound, token.range.upperBound)
            return maxUpperBound
        }
    }

    package func firstTokenIndex(intersecting range: NSRange) -> Int {
        guard range.length > 0 else { return 0 }

        var lowerBound = 0
        var upperBound = prefixMaxUpperBounds.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if prefixMaxUpperBounds[midIndex] <= range.location {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return lowerBound
    }
}
#endif
