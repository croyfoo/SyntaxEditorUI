import CoreGraphics

/// The shape of the editor's insertion caret.
public enum CaretStyle: Equatable, Sendable {
    /// The system-standard thin vertical bar (`NSTextInsertionIndicator`).
    case line
    /// A vertical bar of a custom width, in points.
    case bar(width: CGFloat)
    /// A character-width block (vim-style), drawn translucently so the glyph
    /// beneath stays legible.
    case block
}
