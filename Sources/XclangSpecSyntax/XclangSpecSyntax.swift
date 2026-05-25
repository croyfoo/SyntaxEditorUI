import Foundation

#if canImport(CoreFoundation)
import CoreFoundation
#endif

package enum XclangSpecParseError: Error, Equatable, CustomStringConvertible {
    case invalidDocumentRoot(String)
    case invalidRuleEntry(String)
    case missingIdentifier
    case invalidSyntax(String)
    case unsupportedValue(String)

    package var description: String {
        switch self {
        case let .invalidDocumentRoot(type):
            "Unsupported xclangspec document root: \(type)"
        case let .invalidRuleEntry(type):
            "Unsupported xclangspec rule entry: \(type)"
        case .missingIdentifier:
            "Xclangspec rule entry is missing an Identifier string"
        case let .invalidSyntax(type):
            "Unsupported xclangspec Syntax value: \(type)"
        case let .unsupportedValue(type):
            "Unsupported xclangspec plist value: \(type)"
        }
    }
}

package enum XclangSpecValue: Equatable, Sendable, Decodable {
    case string(String)
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case array([XclangSpecValue])
    case dictionary([String: XclangSpecValue])

    package init(propertyList value: Any) throws {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            self = Self.numberValue(value)
        case let value as [Any]:
            self = .array(try value.map(XclangSpecValue.init(propertyList:)))
        case let value as [String: Any]:
            self = .dictionary(try value.mapValues(XclangSpecValue.init(propertyList:)))
        default:
            throw XclangSpecParseError.unsupportedValue(String(describing: type(of: value)))
        }
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([XclangSpecValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: XclangSpecValue].self) {
            self = .dictionary(value)
        } else {
            throw XclangSpecParseError.unsupportedValue("Decodable")
        }
    }

    package var string: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    package var bool: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    package var integer: Int? {
        guard case let .integer(value) = self else { return nil }
        return value
    }

    package var dictionary: [String: XclangSpecValue]? {
        guard case let .dictionary(value) = self else { return nil }
        return value
    }

    package var yesNo: Bool? {
        if let bool {
            return bool
        }

        switch string?.uppercased() {
        case "YES":
            return true
        case "NO":
            return false
        default:
            return nil
        }
    }

    package var strings: [String] {
        switch self {
        case let .string(value):
            [value]
        case let .array(values):
            values.flatMap(\.strings)
        default:
            []
        }
    }

    package var recursiveStrings: [String] {
        switch self {
        case let .string(value):
            [value]
        case let .array(values):
            values.flatMap(\.recursiveStrings)
        case let .dictionary(values):
            values.keys.sorted().flatMap { values[$0]?.recursiveStrings ?? [] }
        default:
            []
        }
    }

    private static func numberValue(_ number: NSNumber) -> XclangSpecValue {
#if canImport(CoreFoundation)
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
#endif

        let cfNumber = number as CFNumber
        switch CFNumberGetType(cfNumber) {
        case .charType,
             .shortType,
             .intType,
             .longType,
             .longLongType,
             .cfIndexType,
             .nsIntegerType,
             .sInt8Type,
             .sInt16Type,
             .sInt32Type,
             .sInt64Type:
            return .integer(number.intValue)
        default:
            return .double(number.doubleValue)
        }
    }
}

package struct XclangSpecDocument: Equatable, Sendable {
    package let rules: [XclangSpecRule]

    package init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    package init(data: Data) throws {
        let decoder = PropertyListDecoder()
        if let values = try? decoder.decode([XclangSpecValue].self, from: data) {
            rules = try values.map(XclangSpecRule.init(value:))
            return
        }
        let value = try decoder.decode(XclangSpecValue.self, from: data)
        rules = [try XclangSpecRule(value: value)]
    }

    package init(propertyList: Any) throws {
        if let entries = propertyList as? [Any] {
            rules = try entries.map(XclangSpecRule.init(propertyList:))
            return
        }
        if let entry = propertyList as? [String: Any] {
            rules = [try XclangSpecRule(dictionary: entry)]
            return
        }
        throw XclangSpecParseError.invalidDocumentRoot(String(describing: type(of: propertyList)))
    }
}

package struct XclangSpecRule: Equatable, Sendable {
    package let identifier: String
    package let name: String?
    package let basedOn: [String]
    package let syntax: XclangSpecRuleSyntax?
    package let fields: [String: XclangSpecValue]

    package init(propertyList: Any) throws {
        guard let dictionary = propertyList as? [String: Any] else {
            throw XclangSpecParseError.invalidRuleEntry(String(describing: type(of: propertyList)))
        }
        try self.init(dictionary: dictionary)
    }

    package init(value: XclangSpecValue) throws {
        guard case let .dictionary(dictionary) = value else {
            throw XclangSpecParseError.invalidRuleEntry(String(describing: value))
        }
        try self.init(fields: dictionary)
    }

    package init(dictionary: [String: Any]) throws {
        let fields = try dictionary.mapValues(XclangSpecValue.init(propertyList:))
        try self.init(fields: fields)
    }

    package init(fields: [String: XclangSpecValue]) throws {
        guard let identifier = fields["Identifier"]?.string else {
            throw XclangSpecParseError.missingIdentifier
        }

        self.identifier = identifier
        self.name = fields["Name"]?.string
        self.basedOn = fields["BasedOn"]?.strings ?? []
        self.fields = fields

        if let syntaxValue = fields["Syntax"] {
            self.syntax = try XclangSpecRuleSyntax(value: syntaxValue)
        } else {
            self.syntax = nil
        }
    }

    package func value(for key: String) -> XclangSpecValue? {
        fields[key]
    }

    package var inheritsNodeType: String? { fields["InheritsNodeType"]?.string }
    package var description: String? { fields["Description"]?.string }
    package var includeInMenu: Bool? { fields["IncludeInMenu"]?.yesNo }
    package var usesCLikeIndentation: Bool? { fields["UsesCLikeIndentation"]?.yesNo }
    package var canSetFont: Bool? { fields["CanSetFont"]?.yesNo }
    package var nameFormat: String? { fields["NameFormat"]?.string }
    package var ignoreToken: Bool? { fields["IgnoreToken"]?.yesNo }
    package var isMark: Bool? { fields["IsMark"]?.yesNo }
}

package struct XclangSpecRuleSyntax: Equatable, Sendable {
    package let fields: [String: XclangSpecValue]

    package init(value: XclangSpecValue) throws {
        guard case let .dictionary(fields) = value else {
            throw XclangSpecParseError.invalidSyntax(String(describing: value))
        }
        self.fields = fields
    }

    package var type: String? { string("Type") }
    package var altType: String? { string("AltType") }
    package var tokenizer: String? { string("Tokenizer") }
    package var start: String? { string("Start") }
    package var end: String? { string("End") }
    package var until: String? { string("Until") }
    package var altEnd: String? { string("AltEnd") }
    package var altUntil: String? { string("AltUntil") }
    package var altToken: String? { string("AltToken") }
    package var sourceScannerClassName: String? { string("SourceScannerClassName") }
    package var startChars: String? { string("StartChars") }
    package var chars: String? { string("Chars") }
    package var escapeChar: String? { string("EscapeChar") }
    package var wordBreak: Bool? { yesNo("WordBreak") }
    package var caseSensitive: Bool? { yesNo("CaseSensitive") }
    package var recursive: Bool? { yesNo("Recursive") }
    package var foldable: Bool? { yesNo("Foldable") }
    package var startAtBOL: Bool? { yesNo("StartAtBOL") }
    package var startAtColumnZero: Bool? { yesNo("StartAtColumnZero") }
    package var shouldTraverse: Bool? { yesNo("ShouldTraverse") }
    package var parseEndBeforeIncludedRules: Bool? { yesNo("ParseEndBeforeIncludedRules") }
    package var ignore: String? { string("Ignore") }
    package var indentWidth: Int? { integer("IndentWidth") }
    package var generateEmptyLine: Bool? { yesNo("GenerateEmptyLine") }
    package var dirtyPreviousRightEdge: Bool? { yesNo("DirtyPreviousRightEdge") }
    package var checkPreprocessorKnownMacros: Bool? { yesNo("CheckPreprocessorKnownMacros") }
    package var volatile: Bool? { yesNo("Volatile") }
    package var includeInMenu: Bool? { yesNo("IncludeInMenu") }
    package var name: String? { string("Name") }
    package var description: String? { string("Description") }
    package var basedOn: [String] { strings("BasedOn") }
    package var includeRules: [String] { strings("IncludeRules") }
    package var rules: [String] { strings("Rules") }
    package var words: [String] { strings("Words") }
    package var match: [String] { strings("Match") }
    package var captureTypes: [String] { strings("CaptureTypes") }

    package var languageEmbeddings: [String: [String]] {
        stringListDictionary("LanguageEmbeddings")
    }

    package var entityNameMap: [String: String] {
        stringDictionary("EntityNameMap")
    }

    package func value(for key: String) -> XclangSpecValue? {
        fields[key]
    }

    package func string(_ key: String) -> String? {
        fields[key]?.string
    }

    package func strings(_ key: String) -> [String] {
        fields[key]?.strings ?? []
    }

    package func yesNo(_ key: String) -> Bool? {
        fields[key]?.yesNo
    }

    package func integer(_ key: String) -> Int? {
        if let integer = fields[key]?.integer {
            return integer
        }
        guard let string = fields[key]?.string else {
            return nil
        }
        return Int(string)
    }

    package func stringDictionary(_ key: String) -> [String: String] {
        guard let dictionary = fields[key]?.dictionary else {
            return [:]
        }
        return dictionary.reduce(into: [:]) { result, element in
            guard let value = element.value.string else { return }
            result[element.key] = value
        }
    }

    package func stringListDictionary(_ key: String) -> [String: [String]] {
        guard let dictionary = fields[key]?.dictionary else {
            return [:]
        }
        return dictionary.reduce(into: [:]) { result, element in
            let values = element.value.strings
            guard !values.isEmpty else { return }
            result[element.key] = values
        }
    }
}

package struct XclangSpecRuleIndex: Equatable, Sendable {
    package static let syntaxReferenceKeys = [
        "BasedOn",
        "Tokenizer",
        "IncludeRules",
        "Rules",
        "Start",
        "End",
        "Until",
        "AltUntil",
        "AltEnd",
        "AltToken",
        "EntityNameMap",
    ]

    package let rulesByIdentifier: [String: XclangSpecRule]
    package let duplicateIdentifiers: [String: [String]]

    package init(documents: [XclangSpecDocument]) {
        var rulesByIdentifier: [String: XclangSpecRule] = [:]
        var duplicateIdentifiers: [String: [String]] = [:]

        for document in documents {
            for rule in document.rules {
                if let existing = rulesByIdentifier[rule.identifier] {
                    duplicateIdentifiers[rule.identifier, default: [existing.identifier]].append(rule.identifier)
                }
                rulesByIdentifier[rule.identifier] = rule
            }
        }

        self.rulesByIdentifier = rulesByIdentifier
        self.duplicateIdentifiers = duplicateIdentifiers
    }

    package init(document: XclangSpecDocument) {
        self.init(documents: [document])
    }

    package func rule(identifier: String) -> XclangSpecRule? {
        rulesByIdentifier[identifier]
    }

    package func directRuleReferences(for identifier: String) -> [String] {
        guard let rule = rulesByIdentifier[identifier] else { return [] }

        var references: [String] = []
        appendKnownReferences(
            from: rule.fields["BasedOn"],
            to: &references
        )

        guard let syntax = rule.syntax else {
            return references
        }

        for key in Self.syntaxReferenceKeys {
            appendKnownReferences(
                from: syntax.fields[key],
                to: &references
            )
        }
        appendKnownReferences(
            fromExpressions: syntax.languageEmbeddings.keys.sorted(),
            to: &references
        )

        return references
    }

    package func ruleClosure(rootIdentifier: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        var stack = [rootIdentifier]

        while let identifier = stack.popLast() {
            guard seen.insert(identifier).inserted,
                  rulesByIdentifier[identifier] != nil
            else {
                continue
            }
            ordered.append(identifier)

            let references = directRuleReferences(for: identifier)
            for reference in references.reversed() where !seen.contains(reference) {
                stack.append(reference)
            }
        }

        return ordered
    }

    package func syntaxTypes(in ruleIdentifiers: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for identifier in ruleIdentifiers {
            guard let syntax = rulesByIdentifier[identifier]?.syntax else {
                continue
            }
            appendSyntaxType(syntax.type, seen: &seen, ordered: &ordered)
            appendSyntaxType(syntax.altType, seen: &seen, ordered: &ordered)
            for value in syntax.captureTypes {
                appendSyntaxType(value, seen: &seen, ordered: &ordered)
            }
        }

        return ordered.sorted()
    }

    private func appendSyntaxType(
        _ value: String?,
        seen: inout Set<String>,
        ordered: inout [String]
    ) {
        guard let value,
              value.hasPrefix("xcode.syntax."),
              seen.insert(value).inserted
        else {
            return
        }
        ordered.append(value)
    }

    private func appendKnownReferences(
        from value: XclangSpecValue?,
        to references: inout [String]
    ) {
        guard let value else { return }
        appendKnownReferences(
            fromExpressions: value.recursiveStrings,
            to: &references
        )
    }

    private func appendKnownReferences(
        fromExpressions expressions: [String],
        to references: inout [String]
    ) {
        var seen = Set(references)
        let knownIdentifiers = Set(rulesByIdentifier.keys)

        for expression in expressions {
            for identifier in identifiers(inRuleExpression: expression, knownIdentifiers: knownIdentifiers) {
                guard seen.insert(identifier).inserted else { continue }
                references.append(identifier)
            }
        }
    }

    private func identifiers(
        inRuleExpression expression: String,
        knownIdentifiers: Set<String>
    ) -> [String] {
        if knownIdentifiers.contains(expression) {
            return [expression]
        }

        var identifiers: [String] = []
        var seen = Set<String>()
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            defer { current.removeAll(keepingCapacity: true) }
            guard knownIdentifiers.contains(current),
                  seen.insert(current).inserted
            else {
                return
            }
            identifiers.append(current)
        }

        for scalar in expression.unicodeScalars {
            if Self.isRuleIdentifierScalar(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()

        return identifiers
    }

    private static func isRuleIdentifierScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        case 45, 46, 95:
            return true
        default:
            return false
        }
    }
}
