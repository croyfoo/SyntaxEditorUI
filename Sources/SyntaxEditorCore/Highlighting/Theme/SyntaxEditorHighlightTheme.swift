import Foundation

#if canImport(UIKit)
import UIKit

public typealias SyntaxEditorColor = UIColor
public typealias SyntaxEditorFont = UIFont
#elseif canImport(AppKit)
import AppKit

public typealias SyntaxEditorColor = NSColor
public typealias SyntaxEditorFont = NSFont
#endif

public struct SyntaxEditorColorTheme: Identifiable, Hashable {
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case bare
        case basic
        case civic
        case classic
        case `default`
        case dusk
        case highContrast
        case lowKey
        case midnight
        case presentation
        case presentationLarge
        case printing
        case spartan
        case sunset

        public var id: String {
            rawValue
        }

        public var displayName: String {
            switch self {
            case .bare: "Bare"
            case .basic: "Basic"
            case .civic: "Civic"
            case .classic: "Classic"
            case .default: "Default"
            case .dusk: "Dusk"
            case .highContrast: "High Contrast"
            case .lowKey: "Low Key"
            case .midnight: "Midnight"
            case .presentation: "Presentation"
            case .presentationLarge: "Presentation Large"
            case .printing: "Printing"
            case .spartan: "Spartan"
            case .sunset: "Sunset"
            }
        }

        var lightResourceID: String {
            switch self {
            case .classic: "classicLight"
            case .default: "defaultLight"
            case .highContrast: "highContrastLight"
            case .presentation: "presentationLight"
            case .presentationLarge: "presentationLargeLight"
            default: rawValue
            }
        }

        var darkResourceID: String {
            switch self {
            case .classic: "classicDark"
            case .default: "defaultDark"
            case .highContrast: "highContrastDark"
            case .presentation: "presentationDark"
            case .presentationLarge: "presentationLargeDark"
            default: rawValue
            }
        }
    }

    public let id: String
    private let storage: Storage

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
        punctuation: SyntaxEditorColor,
        background: SyntaxEditorColor = .clear
    ) {
        id = "custom.\(UUID().uuidString)"
        storage = .custom(
            SyntaxEditorResolvedColorTheme(
                background: background,
                bracketBackground: bracketBackground,
                base: .init(foreground: baseForeground),
                comment: .init(foreground: comment),
                string: .init(foreground: string),
                keyword: .init(foreground: keyword),
                number: .init(foreground: number),
                function: .init(foreground: function),
                type: .init(foreground: type),
                constant: .init(foreground: constant),
                variable: .init(foreground: variable),
                punctuation: .init(foreground: punctuation)
            )
        )
    }

    private init(id: String, storage: Storage) {
        self.id = id
        self.storage = storage
    }

    public static func preset(_ preset: Preset) -> SyntaxEditorColorTheme {
        SyntaxEditorColorTheme(id: "builtin.\(preset.rawValue)", storage: .preset(preset))
    }

    public static var bare: SyntaxEditorColorTheme { preset(.bare) }
    public static var basic: SyntaxEditorColorTheme { preset(.basic) }
    public static var civic: SyntaxEditorColorTheme { preset(.civic) }
    public static var classic: SyntaxEditorColorTheme { preset(.classic) }
    public static var `default`: SyntaxEditorColorTheme { preset(.default) }
    public static var dusk: SyntaxEditorColorTheme { preset(.dusk) }
    public static var highContrast: SyntaxEditorColorTheme { preset(.highContrast) }
    public static var lowKey: SyntaxEditorColorTheme { preset(.lowKey) }
    public static var midnight: SyntaxEditorColorTheme { preset(.midnight) }
    public static var presentation: SyntaxEditorColorTheme { preset(.presentation) }
    public static var presentationLarge: SyntaxEditorColorTheme { preset(.presentationLarge) }
    public static var printing: SyntaxEditorColorTheme { preset(.printing) }
    public static var spartan: SyntaxEditorColorTheme { preset(.spartan) }
    public static var sunset: SyntaxEditorColorTheme { preset(.sunset) }

    public static var allPresets: [SyntaxEditorColorTheme] {
        Preset.allCases.map(preset)
    }

    public var preset: Preset? {
        guard case let .preset(preset) = storage else { return nil }
        return preset
    }

    public var displayName: String {
        preset?.displayName ?? "Custom"
    }

    public var background: SyntaxEditorColor {
        resolved(for: nil).background
    }

    public var baseForeground: SyntaxEditorColor {
        resolved(for: nil).base.foreground
    }

    public var bracketBackground: SyntaxEditorColor {
        resolved(for: nil).bracketBackground
    }

    public var comment: SyntaxEditorColor {
        resolved(for: nil).comment.foreground
    }

    public var string: SyntaxEditorColor {
        resolved(for: nil).string.foreground
    }

    public var keyword: SyntaxEditorColor {
        resolved(for: nil).keyword.foreground
    }

    public var number: SyntaxEditorColor {
        resolved(for: nil).number.foreground
    }

    public var function: SyntaxEditorColor {
        resolved(for: nil).function.foreground
    }

    public var type: SyntaxEditorColor {
        resolved(for: nil).type.foreground
    }

    public var constant: SyntaxEditorColor {
        resolved(for: nil).constant.foreground
    }

    public var variable: SyntaxEditorColor {
        resolved(for: nil).variable.foreground
    }

    public var punctuation: SyntaxEditorColor {
        resolved(for: nil).punctuation.foreground
    }

    public static func == (lhs: SyntaxEditorColorTheme, rhs: SyntaxEditorColorTheme) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    package func resolved(
        for language: SyntaxLanguage?,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorResolvedColorTheme {
        let theme = switch storage {
        case let .custom(theme):
            theme
        case let .preset(preset):
            BuiltInEditorColorThemeStore.resolvedTheme(
                for: preset,
                language: language,
                appearance: appearance
            )
        }
        return theme.applyingPlatformFontSizeAdjustment()
    }

    package func style(
        for syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage?,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorResolvedTextStyle? {
        let style = switch storage {
        case let .custom(theme):
            theme.style(for: syntaxID)
        case let .preset(preset):
            BuiltInEditorColorThemeStore.style(
                for: syntaxID,
                preset: preset,
                language: language,
                appearance: appearance
            )
        }
        return style?.applyingPlatformFontSizeAdjustment()
    }

    private enum Storage {
        case custom(SyntaxEditorResolvedColorTheme)
        case preset(Preset)
    }
}

package enum SyntaxEditorThemeAppearance {
    case light
    case dark
}

package struct SyntaxEditorResolvedTextStyle {
    package let foreground: SyntaxEditorColor
    package let font: SyntaxEditorFontDescriptor?

    package init(
        foreground: SyntaxEditorColor,
        font: SyntaxEditorFontDescriptor? = nil
    ) {
        self.foreground = foreground
        self.font = font
    }

    package func applyingPlatformFontSizeAdjustment() -> SyntaxEditorResolvedTextStyle {
        SyntaxEditorResolvedTextStyle(
            foreground: foreground,
            font: font?.applyingPointSizeAdjustment(SyntaxEditorFontSize.platformThemePointSizeAdjustment)
        )
    }
}

package struct SyntaxEditorResolvedColorTheme {
    package let background: SyntaxEditorColor
    package let bracketBackground: SyntaxEditorColor
    package let base: SyntaxEditorResolvedTextStyle
    package let comment: SyntaxEditorResolvedTextStyle
    package let string: SyntaxEditorResolvedTextStyle
    package let keyword: SyntaxEditorResolvedTextStyle
    package let number: SyntaxEditorResolvedTextStyle
    package let function: SyntaxEditorResolvedTextStyle
    package let type: SyntaxEditorResolvedTextStyle
    package let constant: SyntaxEditorResolvedTextStyle
    package let variable: SyntaxEditorResolvedTextStyle
    package let punctuation: SyntaxEditorResolvedTextStyle

    package var baseForeground: SyntaxEditorColor { base.foreground }

    package func applyingPlatformFontSizeAdjustment() -> SyntaxEditorResolvedColorTheme {
        SyntaxEditorResolvedColorTheme(
            background: background,
            bracketBackground: bracketBackground,
            base: base.applyingPlatformFontSizeAdjustment(),
            comment: comment.applyingPlatformFontSizeAdjustment(),
            string: string.applyingPlatformFontSizeAdjustment(),
            keyword: keyword.applyingPlatformFontSizeAdjustment(),
            number: number.applyingPlatformFontSizeAdjustment(),
            function: function.applyingPlatformFontSizeAdjustment(),
            type: type.applyingPlatformFontSizeAdjustment(),
            constant: constant.applyingPlatformFontSizeAdjustment(),
            variable: variable.applyingPlatformFontSizeAdjustment(),
            punctuation: punctuation.applyingPlatformFontSizeAdjustment()
        )
    }

    package func style(for syntaxID: EditorSourceSyntaxID) -> SyntaxEditorResolvedTextStyle? {
        switch EditorSourceSyntaxCategory.category(for: syntaxID) {
        case .comment: comment
        case .string: string
        case .keyword: keyword
        case .number: number
        case .function: function
        case .type: type
        case .constant: constant
        case .variable: variable
        case .punctuation: punctuation
        case .none: nil
        }
    }
}

package struct SyntaxEditorFontDescriptor: Hashable, Sendable {
    package let family: String?
    package let size: CGFloat
    package let weight: SyntaxEditorFontWeight

    package init(family: String?, size: CGFloat, weight: SyntaxEditorFontWeight) {
        self.family = family
        self.size = size
        self.weight = weight
    }

    package func applyingPointSizeAdjustment(_ adjustment: CGFloat) -> SyntaxEditorFontDescriptor {
        guard adjustment != 0 else { return self }
        return SyntaxEditorFontDescriptor(family: family, size: size + adjustment, weight: weight)
    }

#if canImport(UIKit)
    package func platformFont(fallback: UIFont, fontSizeDelta: Int = 0) -> UIFont {
        let pointSize = SyntaxEditorFontSize.pointSize(size, applying: fontSizeDelta)
        if let family,
           let font = UIFont(name: family, size: pointSize) {
            return font.applying(weight: weight)
        }
        return UIFont(descriptor: fallback.fontDescriptor, size: pointSize).applying(weight: weight)
    }
#elseif canImport(AppKit)
    package func platformFont(fallback: NSFont, fontSizeDelta: Int = 0) -> NSFont {
        let pointSize = SyntaxEditorFontSize.pointSize(size, applying: fontSizeDelta)
        if let family,
           let font = NSFont(name: family, size: pointSize) {
            return font.applying(weight: weight)
        }
        return NSFont(descriptor: fallback.fontDescriptor, size: pointSize)?.applying(weight: weight)
            ?? fallback.withSize(pointSize).applying(weight: weight)
    }
#endif
}

package enum SyntaxEditorFontSize {
    package static let minimum: CGFloat = 4
    package static let maximum: CGFloat = 64
    #if os(macOS)
    package static let platformThemePointSizeAdjustment: CGFloat = 0
    private static let baseDefaultEditorPointSize: CGFloat = 13
    #else
    package static let platformThemePointSizeAdjustment: CGFloat = 2
    private static let baseDefaultEditorPointSize: CGFloat = 14
    #endif
    package static let defaultEditorPointSize = baseDefaultEditorPointSize + platformThemePointSizeAdjustment

    package static func pointSize(_ basePointSize: CGFloat, applying delta: Int) -> CGFloat {
        min(max(basePointSize + CGFloat(delta), minimum), maximum)
    }

    package static func increasedDelta(_ delta: Int, forBasePointSize basePointSize: CGFloat) -> Int {
        let bounds = deltaBounds(forBasePointSize: basePointSize)
        if delta < bounds.lowerBound {
            return min(bounds.lowerBound + 1, bounds.upperBound)
        }
        return min(delta + 1, bounds.upperBound)
    }

    package static func decreasedDelta(_ delta: Int, forBasePointSize basePointSize: CGFloat) -> Int {
        let bounds = deltaBounds(forBasePointSize: basePointSize)
        if delta > bounds.upperBound {
            return max(bounds.upperBound - 1, bounds.lowerBound)
        }
        return max(delta - 1, bounds.lowerBound)
    }

    private static func deltaBounds(forBasePointSize basePointSize: CGFloat) -> ClosedRange<Int> {
        let lowerBound = Int(ceil(minimum - basePointSize))
        let upperBound = Int(floor(maximum - basePointSize))
        return lowerBound...upperBound
    }
}

package enum SyntaxEditorFontWeight: String, Sendable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

#if canImport(UIKit)
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
#elseif canImport(AppKit)
    var nsFontWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
#endif
}

#if canImport(UIKit)
private extension UIFont {
    func applying(weight: SyntaxEditorFontWeight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [
                UIFontDescriptor.TraitKey.weight: weight.uiFontWeight.rawValue,
            ],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#elseif canImport(AppKit)
private extension NSFont {
    func applying(weight: SyntaxEditorFontWeight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [
                NSFontDescriptor.TraitKey.weight: weight.nsFontWeight.rawValue,
            ],
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
#endif

package enum SyntaxEditorHighlightTheme {
    package static func color(
        for syntaxID: EditorSourceSyntaxID,
        in theme: SyntaxEditorColorTheme = .default,
        language: SyntaxLanguage? = nil,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorColor? {
        style(
            for: syntaxID,
            in: theme,
            language: language,
            appearance: appearance
        )?.foreground
    }

    package static func style(
        for syntaxID: EditorSourceSyntaxID,
        in theme: SyntaxEditorColorTheme = .default,
        language: SyntaxLanguage? = nil,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorResolvedTextStyle? {
        guard isKnownSemanticSyntaxID(syntaxID, language: language) else {
            return nil
        }
        return theme.style(for: syntaxID, language: language, appearance: appearance)
    }

    package static func color(
        for sourceSyntaxID: String,
        in theme: SyntaxEditorColorTheme = .default,
        language: SyntaxLanguage? = nil,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorColor? {
        color(
            for: EditorSourceSyntaxID(sourceSyntaxID),
            in: theme,
            language: language,
            appearance: appearance
        )
    }

    package static func style(
        for sourceSyntaxID: String,
        in theme: SyntaxEditorColorTheme = .default,
        language: SyntaxLanguage? = nil,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorResolvedTextStyle? {
        style(
            for: EditorSourceSyntaxID(sourceSyntaxID),
            in: theme,
            language: language,
            appearance: appearance
        )
    }

    package static func semanticStyleKeys(
        for syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage? = nil
    ) -> [String]? {
        guard isKnownSemanticSyntaxID(syntaxID, language: language) else {
            return nil
        }
        return [syntaxID.styleKey]
    }

    package static func semanticStyleKeys(
        for sourceSyntaxID: String,
        language: SyntaxLanguage? = nil
    ) -> [String]? {
        semanticStyleKeys(for: EditorSourceSyntaxID(sourceSyntaxID), language: language)
    }

    private static func isKnownSemanticSyntaxID(
        _ syntaxID: EditorSourceSyntaxID,
        language: SyntaxLanguage?
    ) -> Bool {
        EditorSourceSyntaxCategory.category(for: syntaxID) != nil
            || syntaxID == .plain
            || syntaxID == .identifier
            || BuiltInEditorColorThemeDefinitions.containsStyle(for: syntaxID)
    }
}

private extension BuiltInEditorColorThemeDefinitions {
    static let allStyleKeys: Set<String> = Set(all.values.flatMap { $0.styles.keys })

    static func containsStyle(for syntaxID: EditorSourceSyntaxID) -> Bool {
        allStyleKeys.contains(syntaxID.styleKey)
    }
}

enum BuiltInEditorColorThemeStore {
    static func resolvedTheme(
        for preset: SyntaxEditorColorTheme.Preset,
        language: SyntaxLanguage?,
        appearance: SyntaxEditorThemeAppearance?
    ) -> SyntaxEditorResolvedColorTheme {
        let pair = pair(for: preset)
        return SyntaxEditorResolvedColorTheme(
            background: pair.backgroundColor(appearance: appearance),
            bracketBackground: fallbackBracketBackground(appearance: appearance),
            base: pair.style(for: .base, language: language, appearance: appearance),
            comment: pair.style(for: .comment, language: language, appearance: appearance),
            string: pair.style(for: .string, language: language, appearance: appearance),
            keyword: pair.style(for: .keyword, language: language, appearance: appearance),
            number: pair.style(for: .number, language: language, appearance: appearance),
            function: pair.style(for: .function, language: language, appearance: appearance),
            type: pair.style(for: .type, language: language, appearance: appearance),
            constant: pair.style(for: .constant, language: language, appearance: appearance),
            variable: pair.style(for: .variable, language: language, appearance: appearance),
            punctuation: pair.style(for: .punctuation, language: language, appearance: appearance)
        )
    }

    static func style(
        for syntaxID: EditorSourceSyntaxID,
        preset: SyntaxEditorColorTheme.Preset,
        language: SyntaxLanguage?,
        appearance: SyntaxEditorThemeAppearance?
    ) -> SyntaxEditorResolvedTextStyle? {
        let pair = pair(for: preset)
        if let exactStyle = pair.styleIfPresent(for: [syntaxID.styleKey], appearance: appearance) {
            return exactStyle
        }
        return pair.style(
            for: BuiltInEditorThemeSlot(syntaxID: syntaxID),
            language: language,
            appearance: appearance
        )
    }

    private static func pair(for preset: SyntaxEditorColorTheme.Preset) -> BuiltInEditorColorThemePair {
        BuiltInEditorColorThemePair(
            light: definition(for: preset.lightResourceID),
            dark: definition(for: preset.darkResourceID)
        )
    }

    private static func definition(for id: String) -> BuiltInEditorColorThemeDefinition {
        BuiltInEditorColorThemeDefinitions.all[id] ?? BuiltInEditorColorThemeDefinitions.all["defaultLight"]!
    }

    private static func fallbackBracketBackground(
        appearance: SyntaxEditorThemeAppearance?
    ) -> SyntaxEditorColor {
        color(light: .init(red: 245, green: 232, blue: 144, alpha: 1),
              dark: .init(red: 102, green: 92, blue: 43, alpha: 1),
              appearance: appearance)
    }

    fileprivate static func color(
        light: SyntaxEditorColorComponents,
        dark: SyntaxEditorColorComponents,
        appearance: SyntaxEditorThemeAppearance?
    ) -> SyntaxEditorColor {
        switch appearance {
        case .light:
            SyntaxEditorColor.syntaxEditorColor(light)
        case .dark:
            SyntaxEditorColor.syntaxEditorColor(dark)
        case .none:
            SyntaxEditorColor.syntaxEditorDynamic(light: light, dark: dark)
        }
    }
}

private struct BuiltInEditorColorThemePair {
    let light: BuiltInEditorColorThemeDefinition
    let dark: BuiltInEditorColorThemeDefinition

    func backgroundColor(appearance: SyntaxEditorThemeAppearance?) -> SyntaxEditorColor {
        BuiltInEditorColorThemeStore.color(
            light: light.backgroundColor,
            dark: dark.backgroundColor,
            appearance: appearance
        )
    }

    func style(
        for slot: BuiltInEditorThemeSlot,
        language: SyntaxLanguage?,
        appearance: SyntaxEditorThemeAppearance?
    ) -> SyntaxEditorResolvedTextStyle {
        style(for: styleKeys(for: slot, language: language), appearance: appearance)
    }

    func style(
        for styleKeys: [String],
        appearance: SyntaxEditorThemeAppearance?
    ) -> SyntaxEditorResolvedTextStyle {
        switch appearance {
        case .light:
            return light.style(for: styleKeys).resolvedStyle()
        case .dark:
            return dark.style(for: styleKeys).resolvedStyle()
        case .none:
            let lightStyle = light.style(for: styleKeys)
            let darkStyle = dark.style(for: styleKeys)
            return SyntaxEditorResolvedTextStyle(
                foreground: BuiltInEditorColorThemeStore.color(
                    light: lightStyle.color,
                    dark: darkStyle.color,
                    appearance: nil
                ),
                font: lightStyle.font
            )
        }
    }

    func styleIfPresent(
        for styleKeys: [String],
        appearance: SyntaxEditorThemeAppearance?
    ) -> SyntaxEditorResolvedTextStyle? {
        switch appearance {
        case .light:
            return light.styleIfPresent(for: styleKeys)?.resolvedStyle()
        case .dark:
            return dark.styleIfPresent(for: styleKeys)?.resolvedStyle()
        case .none:
            guard let lightStyle = light.styleIfPresent(for: styleKeys),
                  let darkStyle = dark.styleIfPresent(for: styleKeys)
            else {
                return nil
            }
            return SyntaxEditorResolvedTextStyle(
                foreground: BuiltInEditorColorThemeStore.color(
                    light: lightStyle.color,
                    dark: darkStyle.color,
                    appearance: nil
                ),
                font: lightStyle.font
            )
        }
    }

    private func styleKeys(for slot: BuiltInEditorThemeSlot, language: SyntaxLanguage?) -> [String] {
        switch slot {
        case .base:
            ["editor.syntax.plain"]
        case .comment:
            ["editor.syntax.comment"]
        case .string:
            ["editor.syntax.string", "editor.syntax.character"]
        case .keyword:
            ["editor.syntax.keyword"]
        case .preprocessor:
            ["editor.syntax.preprocessor", "editor.syntax.keyword"]
        case .number:
            ["editor.syntax.number"]
        case .function:
            language == .objectiveC
                ? ["editor.syntax.identifier.function.system", "editor.syntax.identifier.function"]
                : ["editor.syntax.identifier.function"]
        case .type:
            language == .objectiveC
                ? ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type", "editor.syntax.identifier.class.system", "editor.syntax.identifier.class"]
                : ["editor.syntax.identifier.type", "editor.syntax.identifier.class", "editor.syntax.declaration.type"]
        case .constant:
            ["editor.syntax.identifier.constant", "editor.syntax.identifier.macro"]
        case .variable:
            language == .objectiveC
                ? ["editor.syntax.plain"]
                : ["editor.syntax.identifier.variable", "editor.syntax.identifier.constant", "editor.syntax.plain"]
        case .punctuation:
            ["editor.syntax.plain"]
        }
    }
}

private enum BuiltInEditorThemeSlot {
    case base
    case comment
    case string
    case keyword
    case preprocessor
    case number
    case function
    case type
    case constant
    case variable
    case punctuation

    init(syntaxID: EditorSourceSyntaxID) {
        let value = syntaxID.rawValue
        if value == "preprocessor" || value.hasPrefix("preprocessor.") {
            self = .preprocessor
            return
        }

        switch EditorSourceSyntaxCategory.category(for: syntaxID) {
        case .comment:
            self = .comment
        case .string:
            self = .string
        case .keyword:
            self = .keyword
        case .number:
            self = .number
        case .function:
            self = .function
        case .type:
            self = .type
        case .constant:
            self = .constant
        case .variable:
            self = .variable
        case .punctuation:
            self = .punctuation
        case .none:
            self = .base
        }
    }
}

struct BuiltInEditorColorThemeDefinition {
    let id: String
    let displayName: String
    let backgroundColor: SyntaxEditorColorComponents
    let styles: [String: BuiltInEditorTextStyleDefinition]

    func style(for keys: [String]) -> BuiltInEditorTextStyleDefinition {
        for key in keys {
            if let style = styles[key] {
                return style
            }
        }
        return styles["editor.syntax.plain"] ?? BuiltInEditorTextStyleDefinition(
            color: backgroundColor,
            font: nil
        )
    }

    func styleIfPresent(for keys: [String]) -> BuiltInEditorTextStyleDefinition? {
        for key in keys {
            if let style = styles[key] {
                return style
            }
        }
        return nil
    }
}

struct BuiltInEditorTextStyleDefinition {
    let color: SyntaxEditorColorComponents
    let font: SyntaxEditorFontDescriptor?

    func resolvedStyle() -> SyntaxEditorResolvedTextStyle {
        SyntaxEditorResolvedTextStyle(foreground: SyntaxEditorColor.syntaxEditorColor(color), font: font)
    }
}

struct SyntaxEditorColorComponents {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

#if canImport(UIKit)
extension UIColor {
    static func syntaxEditorDynamic(
        light: SyntaxEditorColorComponents,
        dark: SyntaxEditorColorComponents
    ) -> UIColor {
        UIColor { traitCollection in
            syntaxEditorColor(traitCollection.userInterfaceStyle == .dark ? dark : light)
        }
    }

    static func syntaxEditorColor(_ components: SyntaxEditorColorComponents) -> UIColor {
        UIColor(
            red: components.red / 255.0,
            green: components.green / 255.0,
            blue: components.blue / 255.0,
            alpha: components.alpha
        )
    }
}
#elseif canImport(AppKit)
extension NSColor {
    static func syntaxEditorDynamic(
        light: SyntaxEditorColorComponents,
        dark: SyntaxEditorColorComponents
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            syntaxEditorColor(appearance.syntaxEditorIsDark ? dark : light)
        }
    }

    static func syntaxEditorColor(_ components: SyntaxEditorColorComponents) -> NSColor {
        NSColor(
            calibratedRed: components.red / 255.0,
            green: components.green / 255.0,
            blue: components.blue / 255.0,
            alpha: components.alpha
        )
    }
}

private extension NSAppearance {
    var syntaxEditorIsDark: Bool {
        let match = bestMatch(from: [
            .darkAqua,
            .accessibilityHighContrastDarkAqua,
            .vibrantDark,
            .accessibilityHighContrastVibrantDark,
            .aqua,
            .accessibilityHighContrastAqua,
            .vibrantLight,
            .accessibilityHighContrastVibrantLight,
        ])
        return match == .darkAqua
            || match == .accessibilityHighContrastDarkAqua
            || match == .vibrantDark
            || match == .accessibilityHighContrastVibrantDark
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
