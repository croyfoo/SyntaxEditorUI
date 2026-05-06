import Foundation

#if canImport(UIKit)
import UIKit

public typealias SyntaxEditorColor = UIColor
#elseif canImport(AppKit)
import AppKit

public typealias SyntaxEditorColor = NSColor
#endif

public struct SyntaxEditorColorTheme: Identifiable, Hashable {
    public let id: UUID
    public let baseForeground: SyntaxEditorColor
    public let bracketBackground: SyntaxEditorColor
    public let comment: SyntaxEditorColor
    public let string: SyntaxEditorColor
    public let keyword: SyntaxEditorColor
    public let number: SyntaxEditorColor
    public let function: SyntaxEditorColor
    public let type: SyntaxEditorColor
    public let constant: SyntaxEditorColor
    public let variable: SyntaxEditorColor
    public let punctuation: SyntaxEditorColor

    public init(
        baseForeground: SyntaxEditorColor,
        bracketBackground: SyntaxEditorColor,
        comment: SyntaxEditorColor,
        string: SyntaxEditorColor,
        keyword: SyntaxEditorColor,
        number: SyntaxEditorColor,
        function: SyntaxEditorColor,
        type: SyntaxEditorColor,
        constant: SyntaxEditorColor,
        variable: SyntaxEditorColor,
        punctuation: SyntaxEditorColor
    ) {
        self.id = UUID()
        self.baseForeground = baseForeground
        self.bracketBackground = bracketBackground
        self.comment = comment
        self.string = string
        self.keyword = keyword
        self.number = number
        self.function = function
        self.type = type
        self.constant = constant
        self.variable = variable
        self.punctuation = punctuation
    }

    private static let xcodeID = UUID()

    private init(
        id: UUID,
        baseForeground: SyntaxEditorColor,
        bracketBackground: SyntaxEditorColor,
        comment: SyntaxEditorColor,
        string: SyntaxEditorColor,
        keyword: SyntaxEditorColor,
        number: SyntaxEditorColor,
        function: SyntaxEditorColor,
        type: SyntaxEditorColor,
        constant: SyntaxEditorColor,
        variable: SyntaxEditorColor,
        punctuation: SyntaxEditorColor
    ) {
        self.id = id
        self.baseForeground = baseForeground
        self.bracketBackground = bracketBackground
        self.comment = comment
        self.string = string
        self.keyword = keyword
        self.number = number
        self.function = function
        self.type = type
        self.constant = constant
        self.variable = variable
        self.punctuation = punctuation
    }

    public static var xcode: SyntaxEditorColorTheme {
        SyntaxEditorColorTheme(
            id: xcodeID,
            baseForeground: .syntaxEditorDynamic(light: 0x1F2328, dark: 0xE6E6E6),
            bracketBackground: .syntaxEditorDynamic(light: 0xF5E890, dark: 0x665C2B),
            comment: .syntaxEditorDynamic(light: 0x6A737D, dark: 0x6C7986),
            string: .syntaxEditorDynamic(light: 0xC41A16, dark: 0xFC6A5D),
            keyword: .syntaxEditorDynamic(light: 0xAD3DA4, dark: 0xFC5FA3),
            number: .syntaxEditorDynamic(light: 0x1C00CF, dark: 0xD0BF69),
            function: .syntaxEditorDynamic(light: 0x326D74, dark: 0x67B7A4),
            type: .syntaxEditorDynamic(light: 0x0B5CAD, dark: 0x5DD8FF),
            constant: .syntaxEditorDynamic(light: 0x643820, dark: 0xD0BF69),
            variable: .syntaxEditorDynamic(light: 0x0E4B9E, dark: 0x9CDCFE),
            punctuation: .syntaxEditorDynamic(light: 0x6E7781, dark: 0xA7A7A7)
        )
    }

    public static func == (lhs: SyntaxEditorColorTheme, rhs: SyntaxEditorColorTheme) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

package enum SyntaxEditorHighlightTheme {
    package static func color(
        for captureName: String,
        in theme: SyntaxEditorColorTheme = .xcode
    ) -> SyntaxEditorColor? {
        return switch tokenCategory(for: captureName.lowercased()) {
        case .comment: theme.comment
        case .string: theme.string
        case .keyword: theme.keyword
        case .number: theme.number
        case .function: theme.function
        case .type: theme.type
        case .constant: theme.constant
        case .variable: theme.variable
        case .punctuation: theme.punctuation
        case .none: nil
        }
    }

    private static func tokenCategory(for name: String) -> TokenCategory? {
        if name.hasPrefix("comment") {
            return .comment
        }
        if name.hasPrefix("string") || name.contains("regex") {
            return .string
        }
        if name.hasPrefix("keyword")
            || name.hasPrefix("operator")
            || name.hasPrefix("preproc")
            || name.hasPrefix("include")
            || name.hasPrefix("storageclass")
            || name.hasPrefix("exception")
        {
            return .keyword
        }
        if name.hasPrefix("number") || name.contains("numeric") || name.hasPrefix("text.uri") {
            return .number
        }
        if name.hasPrefix("function") || name.hasPrefix("method") || name.hasPrefix("constructor") {
            return .function
        }
        if name.hasPrefix("type") || name.hasPrefix("tag") || name.hasPrefix("namespace") {
            return .type
        }
        if name.hasPrefix("constant") || name.hasPrefix("boolean") || name.hasPrefix("literal") {
            return .constant
        }
        if name.hasPrefix("attribute")
            || name.hasPrefix("parameter")
            || name.hasPrefix("property")
            || name.hasPrefix("selector")
            || name.hasPrefix("variable")
            || name.hasPrefix("name")
        {
            return .variable
        }
        if name.hasPrefix("punctuation") || name.hasPrefix("delimiter") {
            return .punctuation
        }

        return nil
    }

    private enum TokenCategory {
        case comment
        case string
        case keyword
        case number
        case function
        case type
        case constant
        case variable
        case punctuation
    }
}

#if canImport(UIKit)
private extension UIColor {
    static func syntaxEditorDynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traitCollection in
            syntaxEditor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        }
    }

    static func syntaxEditor(hex: UInt32) -> UIColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    static func syntaxEditorDynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .darkAqua,
                .accessibilityHighContrastDarkAqua,
                .vibrantDark,
                .accessibilityHighContrastVibrantDark,
                .aqua,
                .accessibilityHighContrastAqua,
                .vibrantLight,
                .accessibilityHighContrastVibrantLight,
            ])
            let isDark = match == .darkAqua
                || match == .accessibilityHighContrastDarkAqua
                || match == .vibrantDark
                || match == .accessibilityHighContrastVibrantDark
            return syntaxEditor(hex: isDark ? dark : light)
        }
    }

    static func syntaxEditor(hex: UInt32) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }
}
#endif

package enum SyntaxEditorRangeUtilities {
    package static func clampedRange(_ range: NSRange, utf16Length: Int) -> NSRange {
        let location = min(max(0, range.location), utf16Length)
        let available = max(0, utf16Length - location)
        let length = min(max(0, range.length), available)
        return NSRange(location: location, length: length)
    }

    package static func intersection(of lhs: NSRange, and rhs: NSRange) -> NSRange {
        let start = max(lhs.location, rhs.location)
        let end = min(lhs.location + lhs.length, rhs.location + rhs.length)
        let length = max(0, end - start)
        return NSRange(location: start, length: length)
    }

    package static func lineStartUTF16Offset(in source: String, around offset: Int) -> Int {
        let nsString = source as NSString
        let clampedOffset = min(max(0, offset), nsString.length)
        return nsString.lineRange(for: NSRange(location: clampedOffset, length: 0)).location
    }
}
