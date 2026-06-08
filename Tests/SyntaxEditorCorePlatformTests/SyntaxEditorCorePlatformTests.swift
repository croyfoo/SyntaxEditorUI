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

private func customTheme() -> SyntaxEditorTheme {
    SyntaxEditorTheme(
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
        punctuation: syntaxEditorTestColor(hex: 0xB0B1B2),
        font: SyntaxEditorFont.monospacedSystemFont(ofSize: 12, weight: .regular)
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
    @Test("SyntaxEditorModel stores custom themes")
    @MainActor
    func syntaxEditorModelCustomTheme() {
        let theme = customTheme()
        let model = SyntaxEditorModel(
            language: SyntaxLanguage.swift,
            theme: theme
        )

        #expect(model.theme == theme)

        model.theme = .default
        #expect(model.theme == .default)
    }

    @Test("SyntaxEditorHighlightTheme resolves built-in colors on the current platform")
    func syntaxEditorHighlightThemeResolvesBuiltInColors() {
        let theme = SyntaxEditorTheme.default

        #expect(syntaxEditorColor(theme.keyword, matchesLight: 0x9B2393, dark: 0xFC5FA3))
        #expect(syntaxEditorColor(theme.string, matchesLight: 0xC41A16, dark: 0xFC6A5D))
        #expect(syntaxEditorColor(theme.bracketBackground, matchesLight: 0xF5E890, dark: 0x665C2B))
    }

    @Test("SyntaxEditorHighlightTheme resolves platform font sizes")
    func syntaxEditorHighlightThemeResolvesPlatformFontSizes() throws {
        let theme = SyntaxEditorTheme.presentationLarge
        let resolved = theme.resolved(for: .swift, appearance: .light)
        let baseFont = resolved.base.font
        let keywordFont = resolved.keyword.font

#if canImport(UIKit)
        #expect(abs(baseFont.size - 30) < 0.01)
        #expect(abs(keywordFont.size - 30) < 0.01)
#elseif canImport(AppKit)
        #expect(abs(baseFont.size - 28) < 0.01)
        #expect(abs(keywordFont.size - 28) < 0.01)
#endif
    }

    @Test("SyntaxEditorHighlightTheme preserves custom font sizes")
    func syntaxEditorHighlightThemePreservesCustomFontSizes() throws {
        let theme = customTheme()
        let resolved = theme.resolved(for: .swift, appearance: .light)
        let keywordStyle = try #require(theme.style(for: .keyword, language: .swift, appearance: .light))

        #expect(abs(resolved.base.font.size - 12) < 0.01)
        #expect(abs(resolved.keyword.font.size - 12) < 0.01)
        #expect(abs(keywordStyle.font.size - 12) < 0.01)
    }

    @Test("SyntaxEditorHighlightTheme uses custom themes")
    func syntaxEditorHighlightThemeCustomTheme() {
        let theme = customTheme()

        #expect(SyntaxEditorHighlightTheme.color(for: .keyword, in: theme) == theme.keyword)
        #expect(SyntaxEditorHighlightTheme.color(for: .string, in: theme) == theme.string)
        #expect(SyntaxEditorHighlightTheme.color(for: .identifierFunction, in: theme) == theme.function)
        #expect(SyntaxEditorHighlightTheme.color(for: .plain, in: theme) == nil)
    }

    @Test("SyntaxEditorFontDescriptor resolves system monospaced font when family is absent")
    func syntaxEditorFontDescriptorResolvesSystemMonospacedFontWhenFamilyIsAbsent() {
        let descriptor = SyntaxEditorFontDescriptor(family: nil, size: 13, weight: .bold)

        let font = descriptor.platformFont()

        #expect(abs(font.pointSize - 13) < 0.01)
    }

    @Test("SyntaxEditorFontDescriptor applies font size delta with clamp")
    func syntaxEditorFontDescriptorAppliesFontSizeDeltaWithClamp() {
        let descriptor = SyntaxEditorFontDescriptor(family: nil, size: 13, weight: .regular)

        let increasedFont = descriptor.platformFont(fontSizeDelta: 4)
        let minimumFont = descriptor.platformFont(fontSizeDelta: -20)
        let maximumFont = descriptor.platformFont(fontSizeDelta: 100)

        #expect(abs(increasedFont.pointSize - 17) < 0.01)
        #expect(abs(minimumFont.pointSize - 4) < 0.01)
        #expect(abs(maximumFont.pointSize - 64) < 0.01)
    }
}
