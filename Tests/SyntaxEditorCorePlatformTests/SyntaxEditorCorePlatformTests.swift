import Foundation
import Testing
@testable import SyntaxEditorCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private func syntaxEditorTestColor(hex: UInt32) -> SyntaxEditorColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255.0
    let green = CGFloat((hex >> 8) & 0xFF) / 255.0
    let blue = CGFloat(hex & 0xFF) / 255.0

#if canImport(UIKit)
    return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
#elseif canImport(AppKit)
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
#endif
}

private func customColorTheme() -> SyntaxEditorColorTheme {
    SyntaxEditorColorTheme(
        baseForeground: syntaxEditorTestColor(hex: 0x101112),
        bracketBackground: syntaxEditorTestColor(hex: 0x202122),
        comment: syntaxEditorTestColor(hex: 0x303132),
        string: syntaxEditorTestColor(hex: 0x404142),
        keyword: syntaxEditorTestColor(hex: 0x505152),
        number: syntaxEditorTestColor(hex: 0x606162),
        function: syntaxEditorTestColor(hex: 0x707172),
        type: syntaxEditorTestColor(hex: 0x808182),
        constant: syntaxEditorTestColor(hex: 0x909192),
        variable: syntaxEditorTestColor(hex: 0xA0A1A2),
        punctuation: syntaxEditorTestColor(hex: 0xB0B1B2)
    )
}

private func syntaxEditorColor(_ color: SyntaxEditorColor, matchesLight light: UInt32, dark: UInt32) -> Bool {
#if canImport(UIKit)
    syntaxEditorColor(color, matches: light, style: .light)
        && syntaxEditorColor(color, matches: dark, style: .dark)
#elseif canImport(AppKit)
    syntaxEditorColor(color, matches: light, appearanceName: .aqua)
        && syntaxEditorColor(color, matches: dark, appearanceName: .darkAqua)
#endif
}

#if canImport(UIKit)
private func syntaxEditorColor(
    _ color: SyntaxEditorColor,
    matches hex: UInt32,
    style: UIUserInterfaceStyle
) -> Bool {
    let resolvedColor = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        return false
    }
    return syntaxEditorComponents(red: red, green: green, blue: blue, alpha: alpha, match: hex)
}
#elseif canImport(AppKit)
private func syntaxEditorColor(
    _ color: SyntaxEditorColor,
    matches hex: UInt32,
    appearanceName: NSAppearance.Name
) -> Bool {
    guard let appearance = NSAppearance(named: appearanceName) else {
        return false
    }

    var resolvedColor: NSColor?
    appearance.performAsCurrentDrawingAppearance {
        resolvedColor = color.usingColorSpace(.genericRGB)
    }
    guard let resolvedColor else {
        return false
    }

    return syntaxEditorComponents(
        red: resolvedColor.redComponent,
        green: resolvedColor.greenComponent,
        blue: resolvedColor.blueComponent,
        alpha: resolvedColor.alphaComponent,
        match: hex
    )
}
#endif

private func syntaxEditorComponents(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat,
    match hex: UInt32
) -> Bool {
    let expectedRed = CGFloat((hex >> 16) & 0xFF) / 255.0
    let expectedGreen = CGFloat((hex >> 8) & 0xFF) / 255.0
    let expectedBlue = CGFloat(hex & 0xFF) / 255.0
    return abs(red - expectedRed) < 0.002
        && abs(green - expectedGreen) < 0.002
        && abs(blue - expectedBlue) < 0.002
        && abs(alpha - 1.0) < 0.002
}

@Suite("SyntaxEditorCorePlatform")
struct SyntaxEditorCorePlatformTests {
    @Test("SyntaxEditorConfiguration stores custom color themes")
    @MainActor
    func syntaxEditorConfigurationCustomColorTheme() {
        let theme = customColorTheme()
        let configuration = SyntaxEditorConfiguration(
            language: SyntaxLanguage.swift,
            colorTheme: theme
        )

        #expect(configuration.colorTheme == theme)

        configuration.colorTheme = .default
        #expect(configuration.colorTheme == .default)
    }

    @Test("SyntaxEditorHighlightTheme resolves built-in colors on the current platform")
    func syntaxEditorHighlightThemeResolvesBuiltInColors() {
        let theme = SyntaxEditorColorTheme.default

        #expect(syntaxEditorColor(theme.keyword, matchesLight: 0x9B2393, dark: 0xFC5FA3))
        #expect(syntaxEditorColor(theme.string, matchesLight: 0xC41A16, dark: 0xFC6A5D))
        #expect(syntaxEditorColor(theme.bracketBackground, matchesLight: 0xF5E890, dark: 0x665C2B))
    }

    @Test("SyntaxEditorHighlightTheme uses custom color themes")
    func syntaxEditorHighlightThemeCustomTheme() {
        let theme = customColorTheme()

        #expect(SyntaxEditorHighlightTheme.color(for: "keyword.control", in: theme) == theme.keyword)
        #expect(SyntaxEditorHighlightTheme.color(for: "string.quoted", in: theme) == theme.string)
        #expect(SyntaxEditorHighlightTheme.color(for: "constructor", in: theme) == theme.function)
        #expect(SyntaxEditorHighlightTheme.color(for: "unknown.capture", in: theme) == nil)
    }
}
