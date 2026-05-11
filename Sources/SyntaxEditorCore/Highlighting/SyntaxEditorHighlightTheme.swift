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
        switch storage {
        case let .custom(theme):
            theme
        case let .preset(preset):
            BuiltInEditorColorThemeStore.resolvedTheme(
                for: preset,
                language: language,
                appearance: appearance
            )
        }
    }

    package func style(
        for captureName: String,
        language: SyntaxLanguage?,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorResolvedTextStyle? {
        switch storage {
        case let .custom(theme):
            theme.style(for: captureName)
        case let .preset(preset):
            BuiltInEditorColorThemeStore.style(
                for: captureName,
                preset: preset,
                language: language,
                appearance: appearance
            )
        }
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

    package func style(for captureName: String) -> SyntaxEditorResolvedTextStyle? {
        switch SyntaxEditorHighlightTheme.tokenCategory(for: captureName) {
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

#if canImport(UIKit)
    package func platformFont(fallback: UIFont) -> UIFont {
        if let family,
           let font = UIFont(name: family, size: size) {
            return font
        }
        return UIFont.monospacedSystemFont(ofSize: size, weight: weight.uiFontWeight)
    }
#elseif canImport(AppKit)
    package func platformFont(fallback: NSFont) -> NSFont {
        if let family,
           let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight.nsFontWeight)
    }
#endif
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

package enum SyntaxEditorHighlightTheme {
    package static func color(
        for captureName: String,
        in theme: SyntaxEditorColorTheme = .default,
        language: SyntaxLanguage? = nil,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorColor? {
        style(
            for: captureName,
            in: theme,
            language: language,
            appearance: appearance
        )?.foreground
    }

    package static func style(
        for captureName: String,
        in theme: SyntaxEditorColorTheme = .default,
        language: SyntaxLanguage? = nil,
        appearance: SyntaxEditorThemeAppearance? = nil
    ) -> SyntaxEditorResolvedTextStyle? {
        theme.style(for: captureName, language: language, appearance: appearance)
    }

    package static func semanticStyleKeys(
        for captureName: String,
        language: SyntaxLanguage? = nil
    ) -> [String]? {
        SyntaxHighlightStyleKeyResolver.styleKeys(for: captureName, language: language)
    }

    fileprivate static func tokenCategory(for captureName: String) -> TokenCategory? {
        let name = captureName.lowercased()
        if name.hasPrefix("comment") {
            return .comment
        }
        if name.hasPrefix("string") || name.contains("regex") {
            return .string
        }
        if name.hasPrefix("declaration.swift.type.name")
            || name.hasPrefix("identifier.swift.project.type")
            || name.hasPrefix("identifier.swift.other.type")
        {
            return .type
        }
        if name.hasPrefix("declaration.swift")
            || name.hasPrefix("identifier.swift.project.function")
            || name.hasPrefix("identifier.swift.other.function")
            || name.hasPrefix("identifier.swift.project.macro")
            || name.hasPrefix("identifier.swift.other.macro")
        {
            return .function
        }
        if name.hasPrefix("identifier.swift.project.constant")
            || name.hasPrefix("identifier.swift.other.constant")
        {
            return .constant
        }
        if name.hasPrefix("identifier.swift.project.property")
            || name.hasPrefix("identifier.swift.other.property")
            || name.hasPrefix("identifier.swift.argument.label")
            || name.hasPrefix("identifier.swift.local")
        {
            return .variable
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
        if name.hasPrefix("type")
            || name.hasPrefix("tag")
            || name.hasPrefix("selector.css.element")
            || name.hasPrefix("selector.css.universal")
            || name.hasPrefix("namespace")
        {
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

    fileprivate enum TokenCategory {
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

private enum SyntaxHighlightStyleKeyResolver {
    static func styleKeys(for captureName: String, language: SyntaxLanguage?) -> [String]? {
        let name = captureName.lowercased()

        if let keys = cssStyleKeys(for: name) {
            return keys
        }
        if let keys = htmlStyleKeys(for: name) {
            return keys
        }
        if shouldResolveSwiftStyleKeys(for: name, language: language),
           let keys = swiftStyleKeys(for: name) {
            return keys
        }

        return commonStyleKeys(for: name, language: language)
    }

    private static func shouldResolveSwiftStyleKeys(for name: String, language: SyntaxLanguage?) -> Bool {
        language == .swift
            || name.hasPrefix("declaration.swift")
            || name.hasPrefix("identifier.swift")
            || name.hasPrefix("type.swift")
            || name.hasPrefix("function.swift")
            || name.hasPrefix("attribute.swift")
            || name.hasPrefix("keyword.swift")
    }

    private static func cssStyleKeys(for name: String) -> [String]? {
        if name.hasPrefix("selector.css.element") || name.hasPrefix("selector.css.universal") {
            return [
                "editor.syntax.css.selector.element",
                "editor.syntax.identifier.type",
                "editor.syntax.identifier.class",
                "editor.syntax.plain",
            ]
        }
        if name.hasPrefix("selector.css.class")
            || name.hasPrefix("selector.css.id")
            || name.hasPrefix("selector.css.nesting")
            || name.hasPrefix("selector.css.pseudoclass")
            || name.hasPrefix("selector.css.pseudoelement")
            || name.hasPrefix("selector.css.namespace")
        {
            return [
                "editor.syntax.css.selector",
                "editor.syntax.identifier.type",
                "editor.syntax.identifier.class",
                "editor.syntax.plain",
            ]
        }
        if name.hasPrefix("property.css.name") || name.hasPrefix("property.css.feature") {
            return [
                "editor.syntax.css.property.name",
                "editor.syntax.attribute",
                "editor.syntax.keyword",
                "editor.syntax.identifier.variable",
            ]
        }
        if name.hasPrefix("attribute.css.name") {
            return [
                "editor.syntax.css.attribute.name",
                "editor.syntax.attribute",
                "editor.syntax.identifier.variable",
            ]
        }
        if name.hasPrefix("variable.css.customproperty") {
            return [
                "editor.syntax.css.customProperty",
                "editor.syntax.identifier.variable",
                "editor.syntax.identifier.constant",
                "editor.syntax.plain",
            ]
        }
        if name.hasPrefix("function.css.name") {
            return [
                "editor.syntax.css.function.name",
                "editor.syntax.identifier.function",
                "editor.syntax.identifier.variable",
            ]
        }
        if name.hasPrefix("keyword.css") {
            return [
                "editor.syntax.css.atRule",
                "editor.syntax.keyword",
                "editor.syntax.preprocessor",
            ]
        }
        if name.hasPrefix("string.css.color") {
            return [
                "editor.syntax.css.color",
                "editor.syntax.string",
                "editor.syntax.number",
            ]
        }
        if name.hasPrefix("string.css") {
            return [
                "editor.syntax.css.string",
                "editor.syntax.string",
                "editor.syntax.character",
            ]
        }
        if name.hasPrefix("number.css") {
            return [
                "editor.syntax.css.number",
                "editor.syntax.number",
            ]
        }
        if name.hasPrefix("type.css.unit") {
            return [
                "editor.syntax.css.unit",
                "editor.syntax.identifier.type",
                "editor.syntax.number",
            ]
        }

        return nil
    }

    private static func htmlStyleKeys(for name: String) -> [String]? {
        if name.hasPrefix("tag.html.error") {
            return [
                "editor.syntax.html.tag.error",
                "editor.syntax.keyword",
                "editor.syntax.identifier.type",
            ]
        }
        if name.hasPrefix("tag.html.name") {
            return [
                "editor.syntax.html.tag.name",
                "editor.syntax.keyword",
                "editor.syntax.identifier.type",
            ]
        }
        if name.hasPrefix("attribute.html.name") {
            return [
                "editor.syntax.html.attribute.name",
                "editor.syntax.attribute",
                "editor.syntax.identifier.variable",
            ]
        }
        if name.hasPrefix("string.html.attributevalue") {
            return [
                "editor.syntax.html.attribute.value",
                "editor.syntax.string",
                "editor.syntax.character",
            ]
        }
        if name.hasPrefix("constant.html.doctype") {
            return [
                "editor.syntax.html.doctype",
                "editor.syntax.keyword",
                "editor.syntax.identifier.constant",
            ]
        }
        if name.hasPrefix("punctuation.html.bracket") {
            return [
                "editor.syntax.html.bracket",
                "editor.syntax.plain",
            ]
        }

        return nil
    }

    private static func swiftStyleKeys(for name: String) -> [String]? {
        if name.hasPrefix("comment.documentation.keyword")
            || name.hasPrefix("comment.doc.keyword")
        {
            return ["editor.syntax.comment.doc.keyword", "editor.syntax.comment.doc", "editor.syntax.comment"]
        }
        if name.hasPrefix("comment.mark") {
            return ["editor.syntax.mark", "editor.syntax.comment"]
        }
        if name.hasPrefix("declaration.swift.type.name") {
            return [
                "editor.syntax.declaration.type",
                "editor.syntax.identifier.type",
            ]
        }
        if name.hasPrefix("declaration.swift.") {
            return [
                "editor.syntax.declaration.other",
                "editor.syntax.identifier.function",
            ]
        }
        if name.hasPrefix("identifier.swift.project.type") {
            return [
                "editor.syntax.identifier.type",
                "editor.syntax.identifier.class",
                "editor.syntax.declaration.type",
            ]
        }
        if name.hasPrefix("identifier.swift.other.type") {
            return [
                "editor.syntax.identifier.type.system",
                "editor.syntax.identifier.class.system",
                "editor.syntax.identifier.type",
            ]
        }
        if name.hasPrefix("identifier.swift.project.function") {
            return [
                "editor.syntax.identifier.function",
                "editor.syntax.declaration.other",
            ]
        }
        if name.hasPrefix("identifier.swift.other.function") {
            return [
                "editor.syntax.identifier.function.system",
                "editor.syntax.identifier.function",
            ]
        }
        if name.hasPrefix("identifier.swift.project.property") {
            return [
                "editor.syntax.identifier.variable",
                "editor.syntax.plain",
            ]
        }
        if name.hasPrefix("identifier.swift.other.property") {
            return [
                "editor.syntax.identifier.variable.system",
                "editor.syntax.identifier.variable",
                "editor.syntax.plain",
            ]
        }
        if name.hasPrefix("identifier.swift.project.constant") {
            return [
                "editor.syntax.identifier.constant",
                "editor.syntax.identifier.variable",
            ]
        }
        if name.hasPrefix("identifier.swift.other.constant") {
            return [
                "editor.syntax.identifier.constant.system",
                "editor.syntax.identifier.constant",
            ]
        }
        if name.hasPrefix("identifier.swift.project.macro") {
            return [
                "editor.syntax.identifier.macro",
                "editor.syntax.identifier.function",
            ]
        }
        if name.hasPrefix("identifier.swift.other.macro") {
            return [
                "editor.syntax.identifier.macro.system",
                "editor.syntax.identifier.macro",
            ]
        }
        if name.hasPrefix("identifier.swift.argument.label") {
            return ["editor.syntax.plain"]
        }
        if name.hasPrefix("identifier.swift.import.name") {
            return ["editor.syntax.plain"]
        }
        if name.hasPrefix("identifier.swift.local") {
            return ["editor.syntax.plain"]
        }
        if name.hasPrefix("type.swift.reference") {
            return [
                "editor.syntax.identifier.type.system",
                "editor.syntax.identifier.type",
            ]
        }
        if name.hasPrefix("function.swift.call") {
            return [
                "editor.syntax.identifier.function.system",
                "editor.syntax.identifier.function",
            ]
        }
        if name.hasPrefix("function.swift.macro") {
            return [
                "editor.syntax.identifier.macro.system",
                "editor.syntax.identifier.macro",
            ]
        }
        if name.hasPrefix("constructor") {
            return ["editor.syntax.keyword"]
        }
        if name.hasPrefix("keyword.directive") {
            return [
                "editor.syntax.preprocessor",
                "editor.syntax.keyword",
            ]
        }
        if name.hasPrefix("keyword.swift.attribute.builtin") {
            return ["editor.syntax.keyword"]
        }
        if name.hasPrefix("keyword.swift.type.builtin") {
            return ["editor.syntax.keyword", "editor.syntax.identifier.type.system"]
        }
        if name.hasPrefix("attribute.swift.punctuation") {
            return [
                "editor.syntax.identifier.type.system",
                "editor.syntax.attribute",
            ]
        }
        if name.hasPrefix("attribute.swift.name") {
            return [
                "editor.syntax.attribute",
                "editor.syntax.identifier.type.system",
            ]
        }
        if name.hasPrefix("boolean") || name.hasPrefix("constant.builtin") {
            return ["editor.syntax.keyword", "editor.syntax.identifier.constant"]
        }
        if name.hasPrefix("constant.macro") {
            return [
                "editor.syntax.identifier.macro.system",
                "editor.syntax.identifier.macro",
                "editor.syntax.preprocessor",
            ]
        }
        if name.hasPrefix("operator")
            || name.hasPrefix("punctuation")
            || name.hasPrefix("delimiter")
        {
            return ["editor.syntax.plain"]
        }
        if name == "variable" || name.hasPrefix("variable.parameter") {
            return ["editor.syntax.plain"]
        }

        return nil
    }

    private static func commonStyleKeys(for name: String, language: SyntaxLanguage?) -> [String]? {
        if name.hasPrefix("comment.documentation.keyword")
            || name.hasPrefix("comment.doc.keyword")
        {
            return ["editor.syntax.comment.doc.keyword", "editor.syntax.comment.doc", "editor.syntax.comment"]
        }
        if name.hasPrefix("comment.mark") {
            return ["editor.syntax.mark", "editor.syntax.comment"]
        }
        if name.hasPrefix("comment.doc") {
            return ["editor.syntax.comment.doc", "editor.syntax.comment"]
        }
        if name.hasPrefix("comment") {
            return ["editor.syntax.comment"]
        }
        if name.hasPrefix("string") || name.contains("regex") {
            return ["editor.syntax.string", "editor.syntax.character"]
        }
        if name.hasPrefix("number") || name.contains("numeric") {
            return ["editor.syntax.number"]
        }
        if name.hasPrefix("text.uri") {
            return ["editor.syntax.url", "editor.syntax.number"]
        }
        if name.hasPrefix("include") || name.hasPrefix("preproc") {
            return ["editor.syntax.preprocessor", "editor.syntax.keyword"]
        }
        if name.hasPrefix("keyword")
            || name.hasPrefix("operator")
            || name.hasPrefix("storageclass")
            || name.hasPrefix("exception")
        {
            return ["editor.syntax.keyword"]
        }
        if name.hasPrefix("function.macro") {
            return ["editor.syntax.identifier.macro", "editor.syntax.identifier.function"]
        }
        if name.hasPrefix("method.call")
            || name.hasPrefix("function.builtin")
            || name.hasPrefix("constructor")
        {
            return language == .objectiveC
                ? ["editor.syntax.identifier.function.system", "editor.syntax.identifier.function"]
                : ["editor.syntax.identifier.function"]
        }
        if name.hasPrefix("method") {
            return language == .objectiveC
                ? ["editor.syntax.declaration.other", "editor.syntax.identifier.function"]
                : ["editor.syntax.identifier.function"]
        }
        if name.hasPrefix("function") {
            return language == .objectiveC
                ? ["editor.syntax.identifier.function.system", "editor.syntax.identifier.function"]
                : ["editor.syntax.identifier.function"]
        }
        if name.hasPrefix("type.builtin") {
            return language == .objectiveC
                ? ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type", "editor.syntax.declaration.type"]
                : ["editor.syntax.identifier.type", "editor.syntax.declaration.type"]
        }
        if name.hasPrefix("type.declaration") || name.hasPrefix("type.definition") {
            return ["editor.syntax.declaration.type", "editor.syntax.identifier.type"]
        }
        if name.hasPrefix("type") || name.hasPrefix("tag") || name.hasPrefix("namespace") {
            return language == .objectiveC
                ? ["editor.syntax.identifier.type.system", "editor.syntax.identifier.type", "editor.syntax.identifier.class.system", "editor.syntax.identifier.class"]
                : ["editor.syntax.identifier.type", "editor.syntax.identifier.class", "editor.syntax.declaration.type"]
        }
        if name.hasPrefix("constant") || name.hasPrefix("boolean") || name.hasPrefix("literal") {
            return ["editor.syntax.identifier.constant", "editor.syntax.identifier.macro"]
        }
        if name.hasPrefix("attribute") {
            return ["editor.syntax.attribute", "editor.syntax.identifier.variable"]
        }
        if name.hasPrefix("parameter")
            || name.hasPrefix("property")
            || name.hasPrefix("selector")
            || name.hasPrefix("variable")
            || name.hasPrefix("name")
        {
            return language == .objectiveC
                ? ["editor.syntax.plain"]
                : ["editor.syntax.identifier.variable", "editor.syntax.identifier.constant", "editor.syntax.plain"]
        }
        if name.hasPrefix("punctuation") || name.hasPrefix("delimiter") {
            return ["editor.syntax.plain"]
        }

        return nil
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
        for captureName: String,
        preset: SyntaxEditorColorTheme.Preset,
        language: SyntaxLanguage?,
        appearance: SyntaxEditorThemeAppearance?
    ) -> SyntaxEditorResolvedTextStyle? {
        let pair = pair(for: preset)
        guard let styleKeys = SyntaxEditorHighlightTheme.semanticStyleKeys(
            for: captureName,
            language: language
        ) else {
            return nil
        }
        return pair.style(
            for: styleKeys,
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

    private func styleKeys(for slot: BuiltInEditorThemeSlot, language: SyntaxLanguage?) -> [String] {
        switch slot {
        case .base:
            ["editor.syntax.plain"]
        case .comment:
            ["editor.syntax.comment"]
        case .string:
            ["editor.syntax.string", "editor.syntax.character"]
        case .keyword:
            ["editor.syntax.keyword", "editor.syntax.preprocessor"]
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
    case number
    case function
    case type
    case constant
    case variable
    case punctuation
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
