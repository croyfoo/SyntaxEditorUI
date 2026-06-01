import Foundation
import SwiftTreeSitter

protocol SyntaxOverlayState {}

struct SyntaxOverlayResult {
    let tokens: [SyntaxHighlightToken]
    let refreshRangeOverride: NSRange?
    let isCancelled: Bool
}

protocol SyntaxOverlayProvider {
    associatedtype State: SyntaxOverlayState

    static func mergingOverlayResult(
        tokens: [SyntaxHighlightToken],
        source: String,
        rootNode: Node?,
        refreshRange: NSRange?,
        state: inout State?
    ) -> SyntaxOverlayResult
}

struct SyntaxOverlayRangeKey: Hashable {
    let location: Int
    let length: Int

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }
}

struct SyntaxOverlayTokenKey: Hashable {
    let range: SyntaxOverlayRangeKey
    let rawCaptureName: String

    init(_ token: SyntaxHighlightToken) {
        range = SyntaxOverlayRangeKey(token.range)
        rawCaptureName = token.rawCaptureName
    }
}

struct SyntaxOverlaySyntaxIDMask: OptionSet {
    let rawValue: UInt32

    static let identifier = Self(rawValue: 1 << 0)
    static let identifierType = Self(rawValue: 1 << 1)
    static let identifierTypeSystem = Self(rawValue: 1 << 2)
    static let identifierFunction = Self(rawValue: 1 << 3)
    static let identifierFunctionSystem = Self(rawValue: 1 << 4)
    static let declarationType = Self(rawValue: 1 << 5)
    static let declarationOther = Self(rawValue: 1 << 6)
    static let keyword = Self(rawValue: 1 << 7)
    static let plain = Self(rawValue: 1 << 8)

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(syntaxID: EditorSourceSyntaxID) {
        switch syntaxID {
        case .identifier:
            self = .identifier
        case .identifierType:
            self = .identifierType
        case .identifierTypeSystem:
            self = .identifierTypeSystem
        case .identifierFunction:
            self = .identifierFunction
        case .identifierFunctionSystem:
            self = .identifierFunctionSystem
        case .declarationType:
            self = .declarationType
        case .declarationOther:
            self = .declarationOther
        case .keyword:
            self = .keyword
        case .plain:
            self = .plain
        default:
            self = []
        }
    }
}

enum RefreshRangePolicy {
    static func lineEnvelope(containing range: NSRange, in source: NSString) -> NSRange {
        guard source.length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let clampedRange = SyntaxEditorRangeUtilities.clampedRange(range, utf16Length: source.length)
        if clampedRange.length > 0 {
            return source.lineRange(for: clampedRange)
        }

        let location = min(clampedRange.location, source.length - 1)
        return source.lineRange(for: NSRange(location: location, length: 0))
    }
}
