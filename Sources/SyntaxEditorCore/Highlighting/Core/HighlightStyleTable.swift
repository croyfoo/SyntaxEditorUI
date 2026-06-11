import Foundation

/// Session-owned, append-only interning table for token styles.
///
/// Hot paths reference styles by `UInt16` id; the display-order rank used for
/// token sorting is precomputed once per style, eliminating per-comparison
/// string work (the old comparator split `syntaxID.rawValue` on every call).
package final class HighlightStyleTable {
    package struct Style: Hashable {
        package let syntaxID: EditorSourceSyntaxID
        package let language: SyntaxLanguage?
        package let rawCaptureName: String
        package let isSemanticOverlay: Bool

        package init(
            syntaxID: EditorSourceSyntaxID,
            language: SyntaxLanguage?,
            rawCaptureName: String,
            isSemanticOverlay: Bool
        ) {
            self.syntaxID = syntaxID
            self.language = language
            self.rawCaptureName = rawCaptureName
            self.isSemanticOverlay = isSemanticOverlay
        }
    }

    package private(set) var styles: ContiguousArray<Style> = []
    /// Sorting rank packing (renderPriority << 24) | (dot-component count << 16)
    /// | name ordinal — equal-position ties resolve identically to the legacy
    /// display order (priority, specificity, capture-name lexicographic).
    package private(set) var displayRank: ContiguousArray<UInt32> = []
    private var lookup: [Style: UInt16] = [:]
    /// Lexicographically ordered capture names get stable ordinals lazily; the
    /// ordinal preserves `rawCaptureName` ascending order among styles that tie
    /// on priority and specificity.
    private var nameOrdinals: [String: UInt16] = [:]
    private var orderedNames: [String] = []

    package init() {}

    package var count: Int { styles.count }

    package subscript(_ id: UInt16) -> Style {
        styles[Int(id)]
    }

    package func intern(_ token: SyntaxHighlightToken) -> UInt16 {
        intern(Style(
            syntaxID: token.syntaxID,
            language: token.language,
            rawCaptureName: token.rawCaptureName,
            isSemanticOverlay: token.isSemanticOverlay
        ))
    }

    package func intern(_ style: Style) -> UInt16 {
        if let existing = lookup[style] {
            return existing
        }
        precondition(styles.count < Int(UInt16.max), "style table overflow")
        let id = UInt16(styles.count)
        styles.append(style)
        displayRank.append(Self.rank(for: style, ordinal: nameOrdinal(for: style.rawCaptureName)))
        lookup[style] = id
        return id
    }

    /// Re-ranks every style after new capture names changed ordinal assignments.
    /// Name ordinals are assigned in first-seen order, which breaks lexicographic
    /// tie-breaking when names arrive out of order — callers compare with
    /// `displayOrder(of:before:)` below, which falls back to string comparison
    /// only when two distinct names share priority and specificity.
    private func nameOrdinal(for name: String) -> UInt16 {
        if let existing = nameOrdinals[name] {
            return existing
        }
        let ordinal = UInt16(min(orderedNames.count, Int(UInt16.max - 1)))
        orderedNames.append(name)
        nameOrdinals[name] = ordinal
        return ordinal
    }

    /// True when style `lhs` orders before `rhs` at the same location+length.
    /// Mirrors `SyntaxHighlightTokenOrdering.displayOrder`'s tail comparisons.
    package func displayOrder(of lhs: UInt16, before rhs: UInt16) -> Bool {
        let lhsRank = displayRank[Int(lhs)]
        let rhsRank = displayRank[Int(rhs)]
        let lhsHead = lhsRank >> 16
        let rhsHead = rhsRank >> 16
        if lhsHead != rhsHead {
            return lhsHead < rhsHead
        }
        // Same priority and specificity: lexicographic capture-name order.
        let lhsName = styles[Int(lhs)].rawCaptureName
        let rhsName = styles[Int(rhs)].rawCaptureName
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return false
    }

    private static func rank(for style: Style, ordinal: UInt16) -> UInt32 {
        let priority = UInt32(renderPriority(for: style.syntaxID))
        // Specificity = `rawValue.split(separator: ".").count` in the legacy
        // comparator; split drops empty components, so count non-empty runs.
        var dotComponents = 0
        var inComponent = false
        for character in style.syntaxID.rawValue {
            if character == "." {
                inComponent = false
            } else if !inComponent {
                inComponent = true
                dotComponents += 1
            }
        }
        return (priority << 24) | (UInt32(min(255, dotComponents)) << 16) | UInt32(ordinal)
    }

    /// Legacy render priority, ported verbatim from
    /// `SyntaxHighlightTokenOrdering.renderPriority` — branch order matters
    /// (e.g. "comment.doc" wins over the ".doc"-less comparisons, and
    /// "identifier.macro.system" falls through to the `.macro` branch = 3).
    package static func renderPriority(for syntaxID: EditorSourceSyntaxID) -> Int {
        let value = syntaxID.rawValue
        if value == "plain" {
            return 0
        }
        if value == "comment" || value == "string" {
            return 1
        }
        if value.hasPrefix("comment.doc") || value == "mark" || value == "url" {
            return 7
        }
        if value.hasPrefix("declaration.") || value == "identifier.macro" {
            return 6
        }
        if value == "keyword" || value == "preprocessor" {
            return 5
        }
        if value.contains(".type") || value.contains(".class") {
            return 4
        }
        if value.contains(".function") || value.contains(".macro") {
            return 3
        }
        return 2
    }
}
