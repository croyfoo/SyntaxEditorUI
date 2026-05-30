import Foundation
import SwiftTreeSitter

struct SwiftFileSymbolIndex {
    enum SymbolKind: Hashable {
        case type
        case function
        case variable
        case constant
        case macro
    }

    struct SymbolKindSet: OptionSet {
        let rawValue: UInt8

        static let type = Self(rawValue: 1 << 0)
        static let function = Self(rawValue: 1 << 1)
        static let variable = Self(rawValue: 1 << 2)
        static let constant = Self(rawValue: 1 << 3)
        static let macro = Self(rawValue: 1 << 4)
    }

    enum SymbolRole {
        case file
        case member
        case local
        case genericParameter
    }

    struct SymbolRoleSet: OptionSet {
        let rawValue: UInt8

        static let file = Self(rawValue: 1 << 0)
        static let member = Self(rawValue: 1 << 1)
        static let local = Self(rawValue: 1 << 2)
        static let genericParameter = Self(rawValue: 1 << 3)
        static let any: Self = [.file, .member, .local, .genericParameter]
    }

    struct Entry {
        let name: String
        let kind: SymbolKind
        let role: SymbolRole
        let declarationRange: NSRange
        let scopeRange: NSRange
        let ownerQualifiedName: String?

        init(
            name: String,
            kind: SymbolKind,
            role: SymbolRole,
            declarationRange: NSRange,
            scopeRange: NSRange,
            ownerQualifiedName: String? = nil
        ) {
            self.name = name
            self.kind = kind
            self.role = role
            self.declarationRange = declarationRange
            self.scopeRange = scopeRange
            self.ownerQualifiedName = ownerQualifiedName
        }
    }

    private struct TypeScope {
        let name: String
        let qualifiedName: String
        let kind: String
        let bodyRange: NSRange
    }

    private struct TypeDeclaration {
        let name: String
        let kind: String
        let nameRange: NSRange
        let bodyRange: NSRange?
    }

    private struct FunctionScope {
        let bodyRange: NSRange
        let parameterListRange: NSRange?
    }

    private struct FunctionDeclaration {
        let name: String
        let nameRange: NSRange
    }

    private struct LocalBindingScope {
        let range: NSRange
        let startLocation: Int
    }

    private struct TypedValue {
        let name: String
        let typeName: String
        let scopeRange: NSRange
        let declarationRange: NSRange
    }

    private let source: NSString
    private let maskedSource: NSString
    private(set) var entries: [Entry] = []
    private var typeDeclarations: [TypeDeclaration] = []
    private var functionDeclarations: [FunctionDeclaration] = []
    private var typeScopes: [TypeScope] = []
    private var functionScopes: [FunctionScope] = []
    private var typedValues: [TypedValue] = []
    private var entriesByName: [String: [Entry]] = [:]
    private var typedValuesByName: [String: [TypedValue]] = [:]
    private var enumCasesByName: [String: [Entry]] = [:]
    private var genericParametersByName: [String: [Entry]] = [:]
    private var braceRanges: [NSRange] = []

    init(source: NSString, tokens: [SyntaxHighlightToken], rootNode: Node? = nil) {
        self.source = source
        self.maskedSource = Self.maskedSource(from: source, tokens: tokens)
        self.braceRanges = Self.braceRanges(from: rootNode, in: maskedSource)

        collectTypeDeclarationCandidates()
        collectFunctionLikeDeclarations()
        collectExtensionScopes()
        collectTypeDeclarations()
        collectTypeAliasDeclarations()
        collectFunctionDeclarationEntries()
        collectMacroDeclarations()
        collectPatternBoundLocals()
        collectClosureParameters()
        collectValueDeclarations()
        collectEnumCases()
        collectGenericParameters()
        rebuildLookupTables()
    }

    func entry(
        named name: String,
        at range: NSRange,
        allowedKinds: SymbolKindSet,
        allowedRoles: SymbolRoleSet = .any
    ) -> Entry? {
        guard let candidates = entriesByName[name] else {
            return nil
        }

        let ownerQualifiedName = candidates.contains(where: { $0.role == .member && $0.ownerQualifiedName != nil })
            ? innermostTypeScope(containing: range)?.qualifiedName
            : nil
        var best: Entry?
        for candidate in candidates {
            guard allowedKinds.contains(candidate.kind.kindSet),
                  allowedRoles.contains(candidate.role.roleSet),
                  Self.range(candidate.scopeRange, contains: range),
                  !Self.range(candidate.declarationRange, contains: range),
                  memberOwnerMatches(candidate, currentOwnerQualifiedName: ownerQualifiedName)
            else {
                continue
            }

            if best.map({ Self.entry(candidate, isBetterThan: $0) }) ?? true {
                best = candidate
            }
        }

        return best
    }

    func hasLocalType(named name: String, at range: NSRange) -> Bool {
        entriesByName[name]?.contains {
            $0.kind == .type
                && Self.range($0.scopeRange, contains: range)
                && !Self.range($0.declarationRange, contains: range)
        } ?? false
    }

    func isGenericParameter(named name: String, at range: NSRange) -> Bool {
        genericParametersByName[name]?.contains {
            Self.range($0.scopeRange, contains: range)
                && !Self.range($0.declarationRange, contains: range)
        } ?? false
    }

    func enumCaseEntry(named name: String, at range: NSRange, receiverTypeName: String?) -> Entry? {
        guard let candidates = enumCasesByName[name] else {
            return nil
        }

        var best: Entry?
        if let receiverTypeName {
            for candidate in candidates {
                guard Self.range(candidate.scopeRange, contains: range),
                      !Self.range(candidate.declarationRange, contains: range),
                      candidate.ownerQualifiedName.map(Self.lastQualifiedComponent) == receiverTypeName
                else {
                    continue
                }
                if best.map({ Self.entry(candidate, isBetterThan: $0) }) ?? true {
                    best = candidate
                }
            }
            return best
        }

        var ownerQualifiedName: String?
        var sawOwner = false
        for candidate in candidates {
            guard Self.range(candidate.scopeRange, contains: range),
                  !Self.range(candidate.declarationRange, contains: range)
            else {
                continue
            }

            let owner = candidate.ownerQualifiedName ?? ""
            if !sawOwner {
                ownerQualifiedName = owner
                sawOwner = true
            } else if ownerQualifiedName != owner {
                return nil
            }

            if best.map({ Self.entry(candidate, isBetterThan: $0) }) ?? true {
                best = candidate
            }
        }
        return best
    }

    func declaredTypeName(forValueNamed name: String, at range: NSRange) -> String? {
        guard let candidates = typedValuesByName[name] else {
            return nil
        }

        var best: TypedValue?
        for candidate in candidates {
            guard Self.range(candidate.scopeRange, contains: range),
                  !Self.range(candidate.declarationRange, contains: range)
            else {
                continue
            }

            if best.map({ Self.typedValue(candidate, isBetterThan: $0) }) ?? true {
                best = candidate
            }
        }
        return best?.typeName
    }
}

private extension SwiftFileSymbolIndex {
    mutating func rebuildLookupTables() {
        entriesByName = Dictionary(grouping: entries, by: \.name)
        typedValuesByName = Dictionary(grouping: typedValues, by: \.name)
        enumCasesByName = Dictionary(grouping: entries.lazy.filter { $0.kind == .constant }, by: \.name)
        genericParametersByName = Dictionary(grouping: entries.lazy.filter { $0.role == .genericParameter }, by: \.name)
    }

    mutating func collectTypeDeclarationCandidates() {
        let sourceString = maskedSource as String
        for match in Self.typeDeclarationRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 2 else { continue }
            let kindRange = match.range(at: 1)
            let nameRange = match.range(at: 2)
            guard kindRange.location != NSNotFound,
                  nameRange.location != NSNotFound
            else {
                continue
            }

            let name = maskedSource.substring(with: nameRange)
            typeDeclarations.append(TypeDeclaration(
                name: name,
                kind: maskedSource.substring(with: kindRange),
                nameRange: nameRange,
                bodyRange: bodyRange(after: match.range.upperBound)
            ))
        }
    }

    mutating func collectTypeDeclarations() {
        for declaration in typeDeclarations {
            let containingTypeScope = innermostTypeScope(containing: declaration.nameRange)
            let containingFunctionScope = innermostFunctionScope(containing: declaration.nameRange)
            let isFunctionLocal = containingFunctionScope.map { functionScope in
                containingTypeScope.map { functionScope.bodyRange.length < $0.bodyRange.length } ?? true
            } ?? false
            let qualifiedName = qualifiedName(
                for: declaration.name,
                in: isFunctionLocal ? nil : containingTypeScope
            )

            if isFunctionLocal, let containingFunctionScope {
                entries.append(Entry(
                    name: declaration.name,
                    kind: .type,
                    role: .local,
                    declarationRange: declaration.nameRange,
                    scopeRange: localDeclarationScope(
                        containing: declaration.nameRange,
                        within: containingFunctionScope
                    )
                ))
            } else if let localExecutableScope = localExecutableBraceRange(
                containing: declaration.nameRange,
                containingTypeScope: containingTypeScope
            ) {
                entries.append(Entry(
                    name: declaration.name,
                    kind: .type,
                    role: .local,
                    declarationRange: declaration.nameRange,
                    scopeRange: localExecutableScope
                ))
            } else if let containingTypeScope {
                appendMemberEntries(
                    name: declaration.name,
                    kind: .type,
                    declarationRange: declaration.nameRange,
                    ownerTypeScope: containingTypeScope
                )
            } else {
                entries.append(Entry(
                    name: declaration.name,
                    kind: .type,
                    role: .file,
                    declarationRange: declaration.nameRange,
                    scopeRange: fullRange
                ))
            }

            if let bodyRange = declaration.bodyRange {
                typeScopes.append(TypeScope(
                    name: declaration.name,
                    qualifiedName: qualifiedName,
                    kind: declaration.kind,
                    bodyRange: bodyRange
                ))
            }
        }
    }

    mutating func collectExtensionScopes() {
        let localTypeNames = localQualifiedTypeNames()
        guard !localTypeNames.isEmpty else { return }

        let sourceString = maskedSource as String
        for match in Self.extensionRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }

            let qualifiedName = maskedSource.substring(with: nameRange)
            guard localTypeNames.contains(qualifiedName),
                  let bodyRange = bodyRange(after: match.range.upperBound)
            else {
                continue
            }
            let name = qualifiedName.split(separator: ".").last.map(String.init) ?? qualifiedName

            typeScopes.append(TypeScope(
                name: name,
                qualifiedName: qualifiedName,
                kind: "extension",
                bodyRange: bodyRange
            ))
        }
    }

    mutating func collectTypeAliasDeclarations() {
        let sourceString = maskedSource as String
        for match in Self.typeAliasRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 2 else { continue }
            let nameRange = match.range(at: 2)
            guard nameRange.location != NSNotFound else { continue }

            let name = maskedSource.substring(with: nameRange)
            if let functionScope = innermostFunctionScope(containing: nameRange) {
                entries.append(Entry(
                    name: name,
                    kind: .type,
                    role: .local,
                    declarationRange: nameRange,
                    scopeRange: localDeclarationScope(
                        containing: nameRange,
                        within: functionScope
                    )
                ))
            } else if let localExecutableScope = localExecutableBraceRange(
                containing: nameRange,
                containingTypeScope: innermostTypeScope(containing: nameRange)
            ) {
                entries.append(Entry(
                    name: name,
                    kind: .type,
                    role: .local,
                    declarationRange: nameRange,
                    scopeRange: localExecutableScope
                ))
            } else if let typeScope = innermostTypeScope(containing: nameRange) {
                appendMemberEntries(
                    name: name,
                    kind: .type,
                    declarationRange: nameRange,
                    ownerTypeScope: typeScope
                )
            } else {
                entries.append(Entry(
                    name: name,
                    kind: .type,
                    role: .file,
                    declarationRange: nameRange,
                    scopeRange: fullRange
                ))
            }
        }
    }

    mutating func collectFunctionLikeDeclarations() {
        let sourceString = maskedSource as String
        collectNamedFunctions(in: sourceString)
        collectOperatorDeclarations(in: sourceString)
        collectInitAndSubscriptScopes(in: sourceString)
        collectFunctionParameters()
    }

    mutating func collectNamedFunctions(in sourceString: String) {
        for match in Self.functionRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }

            functionDeclarations.append(FunctionDeclaration(
                name: maskedSource.substring(with: nameRange),
                nameRange: nameRange
            ))
            appendFunctionScope(after: match.range.upperBound - 1)
        }
    }

    mutating func collectFunctionDeclarationEntries() {
        for declaration in functionDeclarations {
            let containingTypeScope = innermostTypeScope(containing: declaration.nameRange)
            let containingFunctionScope = innermostFunctionScope(containing: declaration.nameRange)
            let isFunctionLocal = containingFunctionScope.map { functionScope in
                containingTypeScope.map { functionScope.bodyRange.length < $0.bodyRange.length } ?? true
            } ?? false

            if isFunctionLocal, let containingFunctionScope {
                entries.append(Entry(
                    name: declaration.name,
                    kind: .function,
                    role: .local,
                    declarationRange: declaration.nameRange,
                    scopeRange: localDeclarationScope(
                        containing: declaration.nameRange,
                        within: containingFunctionScope
                    )
                ))
            } else if let localExecutableScope = localExecutableBraceRange(
                containing: declaration.nameRange,
                containingTypeScope: containingTypeScope
            ) {
                entries.append(Entry(
                    name: declaration.name,
                    kind: .function,
                    role: .local,
                    declarationRange: declaration.nameRange,
                    scopeRange: localExecutableScope
                ))
            } else if let containingTypeScope {
                appendMemberEntries(
                    name: declaration.name,
                    kind: .function,
                    declarationRange: declaration.nameRange,
                    ownerTypeScope: containingTypeScope
                )
            } else {
                entries.append(Entry(
                    name: declaration.name,
                    kind: .function,
                    role: .file,
                    declarationRange: declaration.nameRange,
                    scopeRange: fullRange
                ))
            }
        }
    }

    mutating func collectOperatorDeclarations(in sourceString: String) {
        for match in Self.operatorRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }

            entries.append(Entry(
                name: maskedSource.substring(with: nameRange),
                kind: .function,
                role: .file,
                declarationRange: nameRange,
                scopeRange: fullRange
            ))
        }
    }

    mutating func collectInitAndSubscriptScopes(in sourceString: String) {
        for match in Self.initRegex.matches(in: sourceString, range: fullRange) {
            guard isInitializerDeclaration(at: match.range.location) else {
                continue
            }
            appendFunctionScope(after: match.range.upperBound - 1)
        }

        for match in Self.subscriptRegex.matches(in: sourceString, range: fullRange) {
            appendFunctionScope(after: match.range.upperBound - 1)
        }
    }

    mutating func appendFunctionScope(after location: Int) {
        guard let parameterListRange = balancedRange(
            opening: "(",
            closing: ")",
            after: location - 1
        ),
              let bodyRange = functionBodyRange(after: parameterListRange.upperBound)
        else {
            return
        }

        functionScopes.append(FunctionScope(
            bodyRange: bodyRange,
            parameterListRange: parameterListRange
        ))
    }

    mutating func collectFunctionParameters() {
        for functionScope in functionScopes {
            guard let parameterListRange = functionScope.parameterListRange,
                  parameterListRange.length > 2
            else {
                continue
            }

            let interior = NSRange(
                location: parameterListRange.location + 1,
                length: parameterListRange.length - 2
            )
            for segment in topLevelCommaSeparatedRanges(in: interior) {
                guard let parameter = parameterName(in: segment) else {
                    continue
                }
                appendVariableEntry(
                    name: parameter.name,
                    role: .local,
                    declarationRange: parameter.range,
                    scopeRange: functionScope.bodyRange,
                    typeName: declaredTypeName(in: segment)
                )
            }
        }
    }

    mutating func collectMacroDeclarations() {
        let sourceString = maskedSource as String
        for match in Self.macroRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }

            entries.append(Entry(
                name: maskedSource.substring(with: nameRange),
                kind: .macro,
                role: .file,
                declarationRange: nameRange,
                scopeRange: fullRange
            ))
        }
    }

    mutating func collectValueDeclarations() {
        let sourceString = maskedSource as String
        for match in Self.valueDeclarationRegex.matches(in: sourceString, range: fullRange) {
            guard shouldIndexValueDeclarationKeyword(at: match.range.location) else {
                continue
            }

            let declarationRange = valueDeclarationContentRange(after: match.range.upperBound)
            for segmentRange in topLevelCommaSeparatedRanges(in: declarationRange) {
                for nameRange in valuePatternNameRanges(in: segmentRange) {
                    indexValueDeclarationName(
                        at: nameRange,
                        segmentRange: segmentRange,
                        declarationRange: declarationRange
                    )
                }
            }
        }
    }

    mutating func indexValueDeclarationName(
        at nameRange: NSRange,
        segmentRange: NSRange,
        declarationRange: NSRange
    ) {
        let name = maskedSource.substring(with: nameRange)
        let typeScope = innermostTypeScope(containing: nameRange)
        let functionScope = innermostFunctionScope(containing: nameRange)
        let isFunctionLocal = functionScope.map { functionScope in
            typeScope.map { functionScope.bodyRange.length < $0.bodyRange.length } ?? true
        } ?? false

        if isFunctionLocal, let functionScope {
            let bindingScopes = conditionalBindingScopes(
                for: nameRange,
                within: functionScope.bodyRange
            )
            if !bindingScopes.isEmpty {
                for bindingScope in bindingScopes {
                    appendVariableEntry(
                        name: name,
                        role: .local,
                        declarationRange: nameRange,
                        scopeRange: NSRange(
                            location: bindingScope.startLocation,
                            length: max(0, bindingScope.range.upperBound - bindingScope.startLocation)
                        ),
                        typeName: declaredTypeName(in: segmentRange)
                    )
                }
                return
            }

            let localScope = nestedLocalValueScope(
                containing: nameRange,
                within: functionScope.bodyRange
            ) ?? functionScope.bodyRange
            let scopeStart = valueDeclarationScopeStart(
                for: nameRange,
                segmentRange: segmentRange,
                declarationRange: declarationRange,
                within: localScope
            )
            appendVariableEntry(
                name: name,
                role: .local,
                declarationRange: nameRange,
                scopeRange: NSRange(
                    location: scopeStart,
                    length: max(0, localScope.upperBound - scopeStart)
                ),
                typeName: declaredTypeName(in: segmentRange)
            )
        } else if let typeScope {
            if let localScope = nestedLocalValueScope(containing: nameRange, within: typeScope.bodyRange) {
                appendLocalVariable(
                    nameRange: nameRange,
                    localScope: localScope,
                    startLocation: valueDeclarationScopeStart(
                        for: nameRange,
                        segmentRange: segmentRange,
                        declarationRange: declarationRange,
                        within: localScope
                    )
                )
            } else {
                appendMemberEntries(
                    name: name,
                    kind: .variable,
                    declarationRange: nameRange,
                    ownerTypeScope: typeScope,
                    typeName: declaredTypeName(in: segmentRange)
                )
            }
        } else if let localScope = nestedLocalValueScope(containing: nameRange, within: fullRange) {
            appendLocalVariable(
                nameRange: nameRange,
                localScope: localScope,
                startLocation: valueDeclarationScopeStart(
                    for: nameRange,
                    segmentRange: segmentRange,
                    declarationRange: declarationRange,
                    within: localScope
                )
            )
        } else {
            appendVariableEntry(
                name: name,
                role: .file,
                declarationRange: nameRange,
                scopeRange: fullRange,
                typeName: declaredTypeName(in: segmentRange)
            )
        }
    }

    func shouldIndexValueDeclarationKeyword(at location: Int) -> Bool {
        let lineRange = maskedSource.lineRange(for: NSRange(location: location, length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: location - lineRange.location)
        let prefix = maskedSource.substring(with: prefixRange)
        if Self.caseKeywordRegex.firstMatch(
            in: prefix,
            range: NSRange(location: 0, length: prefixRange.length)
        ) != nil,
           !hasTopLevelCaseTerminator(in: prefix) {
            return false
        }

        guard let previousIdentifier = lastIdentifier(in: prefixRange) else {
            return true
        }
        return previousIdentifier != "case"
            && previousIdentifier != "for"
            && previousIdentifier != "catch"
    }

    func hasTopLevelCaseTerminator(in prefix: String) -> Bool {
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        for character in prefix {
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            case ":" where parenDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                return true
            default:
                break
            }
        }
        return false
    }

    func lastIdentifier(in range: NSRange) -> String? {
        let prefix = maskedSource.substring(with: range) as NSString
        return Self.identifierRegex
            .matches(in: prefix as String, range: NSRange(location: 0, length: prefix.length))
            .last
            .map { prefix.substring(with: $0.range) }
    }

    func valueDeclarationContentRange(after keywordUpperBound: Int) -> NSRange {
        let upperBound = valueDeclarationStatementEnd(after: keywordUpperBound, within: fullRange)
        return NSRange(location: keywordUpperBound, length: upperBound - keywordUpperBound)
    }

    func valuePatternNameRanges(in range: NSRange) -> [NSRange] {
        topLevelCommaSeparatedRanges(in: range).flatMap { segmentRange in
            patternIdentifierRanges(in: declarationPatternRange(in: segmentRange))
        }
    }

    func valueDeclarationScopeStart(
        for nameRange: NSRange,
        segmentRange: NSRange,
        declarationRange: NSRange,
        within localScope: NSRange
    ) -> Int {
        if segmentRange.upperBound < declarationRange.upperBound {
            let start = nextNonWhitespaceLocation(after: segmentRange.upperBound, upTo: declarationRange.upperBound)
                ?? segmentRange.upperBound
            return min(max(start, nameRange.upperBound), localScope.upperBound)
        }

        let statementEnd = valueDeclarationStatementEnd(after: nameRange.upperBound, within: localScope)
        return min(max(statementEnd, nameRange.upperBound), localScope.upperBound)
    }

    func valueDeclarationStatementEnd(after location: Int, within localScope: NSRange) -> Int {
        var angleDepth = 0
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var lastSignificantCharacter: String?
        var scan = location

        while scan < localScope.upperBound {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            switch character {
            case "<" where isGenericAngleOpening(at: scan, before: localScope.upperBound):
                angleDepth += 1
                lastSignificantCharacter = character
            case ">" where angleDepth > 0:
                angleDepth = max(0, angleDepth - 1)
                lastSignificantCharacter = character
            case "(":
                parenDepth += 1
                lastSignificantCharacter = character
            case ")":
                parenDepth = max(0, parenDepth - 1)
                lastSignificantCharacter = character
            case "[":
                bracketDepth += 1
                lastSignificantCharacter = character
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
                lastSignificantCharacter = character
            case "{":
                braceDepth += 1
                lastSignificantCharacter = character
            case "}":
                braceDepth = max(0, braceDepth - 1)
                lastSignificantCharacter = character
            case ";" where angleDepth == 0 && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                return scan + 1
            case "\n", "\r":
                if angleDepth == 0 && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
                    let nextCharacter = nextNonWhitespaceCharacter(after: scan, upTo: localScope.upperBound)
                    if let nextIdentifier = nextIdentifier(after: scan, upTo: localScope.upperBound),
                       Self.valueDeclarationContinuationStoppingKeywords.contains(nextIdentifier) {
                        return scan + 1
                    }
                    if valueDeclarationContinuesAfterLineBreak(
                        previousCharacter: lastSignificantCharacter,
                        nextCharacter: nextCharacter
                    ) {
                        break
                    }
                    return scan + 1
                }
            case " ", "\t":
                break
            default:
                lastSignificantCharacter = character
            }
            scan += 1
        }

        return localScope.upperBound
    }

    func isGenericAngleOpening(at location: Int, before upperBound: Int) -> Bool {
        guard location > 0,
              location + 1 < maskedSource.length
        else {
            return false
        }

        let previousCharacter = maskedSource.substring(with: NSRange(location: location - 1, length: 1))
        let nextCharacter = maskedSource.substring(with: NSRange(location: location + 1, length: 1))
        guard (isIdentifierCharacter(at: location - 1) || previousCharacter == ")" || previousCharacter == "]"),
              nextCharacter != " ",
              nextCharacter != "\t",
              nextCharacter != "\n",
              nextCharacter != "\r"
        else {
            return false
        }

        return hasGenericAngleClose(after: location, before: upperBound)
    }

    func hasGenericAngleClose(after location: Int, before upperBound: Int) -> Bool {
        var depth = 1
        var scan = location + 1
        while scan < upperBound {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            switch character {
            case "<":
                depth += 1
            case ">":
                depth -= 1
                if depth == 0 {
                    return genericAngleCloseCanEnd(at: scan, before: upperBound)
                }
            case ";", "=", "{", "}":
                return false
            default:
                break
            }
            scan += 1
        }

        return false
    }

    func genericAngleCloseCanEnd(at location: Int, before upperBound: Int) -> Bool {
        var scan = location + 1
        while scan < upperBound {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            if character == " " || character == "\t" || character == "\n" || character == "\r" {
                scan += 1
                continue
            }
            return Self.genericAngleCloseFollowingCharacters.contains(character)
        }

        return true
    }

    func nextNonWhitespaceCharacter(after location: Int, upTo upperBound: Int) -> String? {
        var scan = location + 1
        while scan < upperBound {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            if character != " " && character != "\t" && character != "\n" && character != "\r" {
                return character
            }
            scan += 1
        }
        return nil
    }

    func nextNonWhitespaceLocation(after location: Int, upTo upperBound: Int) -> Int? {
        var scan = location + 1
        while scan < upperBound {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            if character != " " && character != "\t" && character != "\n" && character != "\r" {
                return scan
            }
            scan += 1
        }
        return nil
    }

    func nextIdentifier(after location: Int, upTo upperBound: Int) -> String? {
        guard let start = nextNonWhitespaceLocation(after: location, upTo: upperBound),
              isIdentifierCharacter(at: start)
        else {
            return nil
        }

        var end = start + 1
        while end < upperBound && isIdentifierCharacter(at: end) {
            end += 1
        }
        return maskedSource.substring(with: NSRange(location: start, length: end - start))
    }

    func valueDeclarationContinuesAfterLineBreak(
        previousCharacter: String?,
        nextCharacter: String?
    ) -> Bool {
        if let previousCharacter,
           Self.valueDeclarationContinuationPreviousCharacters.contains(previousCharacter)
        {
            return true
        }

        if let nextCharacter,
           Self.valueDeclarationContinuationNextCharacters.contains(nextCharacter)
        {
            return true
        }

        return false
    }

    func declarationPatternRange(in range: NSRange) -> NSRange {
        var location = range.location
        var parenDepth = 0
        var bracketDepth = 0
        var angleDepth = 0

        while location < range.upperBound {
            let character = maskedSource.substring(with: NSRange(location: location, length: 1))
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case ":", "=", "{":
                if parenDepth == 0 && bracketDepth == 0 && angleDepth == 0 {
                    return trimmedRange(NSRange(location: range.location, length: location - range.location))
                }
            default:
                break
            }
            location += 1
        }

        return trimmedRange(range)
    }

    func patternIdentifierRanges(in range: NSRange) -> [NSRange] {
        let pattern = maskedSource.substring(with: range) as NSString
        return Self.identifierRegex
            .matches(in: pattern as String, range: NSRange(location: 0, length: pattern.length))
            .compactMap { match in
                let name = pattern.substring(with: match.range)
                guard name != "_" else {
                    return nil
                }
                return NSRange(
                    location: range.location + match.range.location,
                    length: match.range.length
                )
            }
    }

    mutating func collectPatternBoundLocals() {
        let sourceString = maskedSource as String
        for match in Self.forPatternBindingRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let patternRange = match.range(at: 1)
            guard patternRange.location != NSNotFound else { continue }

            for nameRange in forPatternNameRanges(in: patternRange) {
                let outerRange = innermostFunctionScope(containing: nameRange)?.bodyRange ?? fullRange
                let localScope = bodyRange(after: match.range.upperBound)
                    ?? innermostBraceRange(containing: nameRange, within: outerRange)
                    ?? outerRange
                appendLocalVariable(
                    nameRange: nameRange,
                    localScope: localScope,
                    startLocation: localScope.location
                )
            }
        }

        for match in Self.catchPatternBindingRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }

            let outerRange = innermostFunctionScope(containing: nameRange)?.bodyRange ?? fullRange
            let localScope = bodyRange(after: match.range.upperBound)
                ?? innermostBraceRange(containing: nameRange, within: outerRange)
                ?? outerRange
            appendLocalVariable(
                nameRange: nameRange,
                localScope: localScope,
                startLocation: localScope.location
            )
        }

        for match in Self.caseClauseRegex.matches(in: sourceString, range: fullRange) {
            for nameRange in caseBindingNameRanges(in: match.range) {
                let outerRange = innermostFunctionScope(containing: nameRange)?.bodyRange ?? fullRange
                let localScope = caseClauseRange(for: nameRange, within: outerRange)
                    ?? innermostBraceRange(containing: nameRange, within: outerRange)
                    ?? outerRange
                appendLocalVariable(
                    nameRange: nameRange,
                    localScope: localScope,
                    startLocation: nameRange.upperBound
                )
            }
        }

        for match in Self.conditionalCaseBindingRegex.matches(in: sourceString, range: fullRange) {
            let patternRange = conditionalCasePatternRange(in: match.range)
            for nameRange in caseBindingNameRanges(in: patternRange) {
                let outerRange = innermostFunctionScope(containing: nameRange)?.bodyRange ?? fullRange
                guard let localScope = topLevelBodyRange(after: nameRange.upperBound, within: outerRange) else {
                    continue
                }
                appendLocalVariable(
                    nameRange: nameRange,
                    localScope: localScope,
                    startLocation: localScope.location
                )
            }
        }

        for match in Self.guardCaseBindingRegex.matches(in: sourceString, range: fullRange) {
            let patternRange = conditionalCasePatternRange(in: match.range)
            for nameRange in caseBindingNameRanges(in: patternRange) {
                let outerRange = innermostFunctionScope(containing: nameRange)?.bodyRange ?? fullRange
                for bindingScope in guardBindingScopes(after: nameRange.upperBound, within: outerRange) {
                    appendLocalVariable(
                        nameRange: nameRange,
                        localScope: bindingScope.range,
                        startLocation: bindingScope.startLocation
                    )
                }
            }
        }
    }

    mutating func collectClosureParameters() {
        var location = 0
        while location < maskedSource.length {
            guard let openBrace = firstLocation(of: "{", after: location - 1) else {
                break
            }
            defer { location = openBrace + 1 }

            guard let closeBrace = matchingLocation(opening: "{", closing: "}", at: openBrace),
                  let parameterListRange = closureParameterListRange(openBrace: openBrace, closeBrace: closeBrace)
            else {
                continue
            }

            let closureScope = NSRange(location: openBrace, length: closeBrace - openBrace + 1)
            for nameRange in closureParameterNameRanges(in: parameterListRange) {
                appendLocalVariable(
                    nameRange: nameRange,
                    localScope: closureScope,
                    startLocation: openBrace
                )
            }
        }
    }

    mutating func collectEnumCases() {
        var location = 0
        while location < maskedSource.length {
            let lineRange = maskedSource.lineRange(for: NSRange(location: location, length: 0))
            defer { location = lineRange.upperBound }

            guard let typeScope = innermostTypeScope(containing: lineRange),
                  typeScope.kind == "enum"
            else {
                continue
            }

            let line = maskedSource.substring(with: lineRange)
            guard let caseKeyword = line.range(of: "case") else {
                continue
            }

            let prefix = line[..<caseKeyword.lowerBound]
            guard prefix.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }

            let caseListStart = line.distance(from: line.startIndex, to: caseKeyword.upperBound)
            let absoluteStart = lineRange.location + caseListStart
            let caseListRange = NSRange(
                location: absoluteStart,
                length: max(0, lineRange.upperBound - absoluteStart)
            )
            for nameRange in enumCaseNameRanges(in: caseListRange) {
                entries.append(Entry(
                    name: maskedSource.substring(with: nameRange),
                    kind: .constant,
                    role: .member,
                    declarationRange: nameRange,
                    scopeRange: fullRange,
                    ownerQualifiedName: typeScope.qualifiedName
                ))
            }
        }
    }

    mutating func collectGenericParameters() {
        let sourceString = maskedSource as String
        for match in Self.typeDeclarationRegex.matches(in: sourceString, range: fullRange) {
            guard let genericRange = genericParameterListRange(after: match.range.upperBound) else {
                continue
            }

            let scope = bodyRange(after: genericRange.upperBound) ?? fullRange
            appendGenericParameterEntries(in: genericRange, scope: scope)
        }

        for match in Self.functionRegex.matches(in: sourceString, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound,
                  let genericRange = genericParameterListRange(after: nameRange.upperBound),
                  let parameterListRange = balancedRange(
                    opening: "(",
                    closing: ")",
                    after: match.range.upperBound - 2
                  ),
                  let bodyRange = functionBodyRange(after: parameterListRange.upperBound)
            else {
                continue
            }

            appendGenericParameterEntries(
                in: genericRange,
                scope: NSRange(
                    location: genericRange.location,
                    length: bodyRange.upperBound - genericRange.location
                )
            )
        }
    }

    mutating func appendGenericParameterEntries(in genericRange: NSRange, scope: NSRange) {
        for parameterRange in genericParameterNameRanges(in: genericRange) {
            entries.append(Entry(
                name: maskedSource.substring(with: parameterRange),
                kind: .type,
                role: .genericParameter,
                declarationRange: parameterRange,
                scopeRange: scope
            ))
        }
    }

    private mutating func appendMemberEntries(
        name: String,
        kind: SymbolKind,
        declarationRange: NSRange,
        ownerTypeScope: TypeScope,
        typeName: String? = nil
    ) {
        let ownerScopes = typeScopes.filter { $0.qualifiedName == ownerTypeScope.qualifiedName }
        guard !ownerScopes.isEmpty else {
            entries.append(Entry(
                name: name,
                kind: kind,
                role: .member,
                declarationRange: declarationRange,
                scopeRange: fullRange,
                ownerQualifiedName: nil
            ))
            if kind == .variable, let typeName {
                typedValues.append(TypedValue(
                    name: name,
                    typeName: typeName,
                    scopeRange: fullRange,
                    declarationRange: declarationRange
                ))
            }
            return
        }

        for scope in ownerScopes {
            entries.append(Entry(
                name: name,
                kind: kind,
                role: .member,
                declarationRange: declarationRange,
                scopeRange: scope.bodyRange,
                ownerQualifiedName: scope.qualifiedName
            ))
            if kind == .variable, let typeName {
                typedValues.append(TypedValue(
                    name: name,
                    typeName: typeName,
                    scopeRange: scope.bodyRange,
                    declarationRange: declarationRange
                ))
            }
        }
    }

    private mutating func appendLocalVariable(
        nameRange: NSRange,
        localScope: NSRange,
        startLocation: Int
    ) {
        let scopeStart = min(max(startLocation, localScope.location), localScope.upperBound)
        appendVariableEntry(
            name: maskedSource.substring(with: nameRange),
            role: .local,
            declarationRange: nameRange,
            scopeRange: NSRange(
                location: scopeStart,
                length: max(0, localScope.upperBound - scopeStart)
            ),
            typeName: nil
        )
    }

    private mutating func appendVariableEntry(
        name: String,
        role: SymbolRole,
        declarationRange: NSRange,
        scopeRange: NSRange,
        typeName: String?
    ) {
        entries.append(Entry(
            name: name,
            kind: .variable,
            role: role,
            declarationRange: declarationRange,
            scopeRange: scopeRange
        ))
        if let typeName {
            typedValues.append(TypedValue(
                name: name,
                typeName: typeName,
                scopeRange: scopeRange,
                declarationRange: declarationRange
            ))
        }
    }
}

private extension SwiftFileSymbolIndex {
    var fullRange: NSRange {
        NSRange(location: 0, length: maskedSource.length)
    }

    static func range(_ outer: NSRange, contains inner: NSRange) -> Bool {
        inner.location >= outer.location && inner.upperBound <= outer.upperBound
    }

    static func maskedSource(from source: NSString, tokens: [SyntaxHighlightToken]) -> NSString {
        let masked = NSMutableString(string: source as String)
        let ranges = tokens
            .filter {
                let value = $0.syntaxID.rawValue
                return value == "string"
                    || value == "character"
                    || value == "comment"
                    || value.hasPrefix("comment.")
            }
            .map(\.range)
            .sorted { lhs, rhs in lhs.location > rhs.location }

        for range in ranges where range.location != NSNotFound && range.upperBound <= masked.length {
            masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return masked
    }

    static func braceRanges(from rootNode: Node?, in source: NSString) -> [NSRange] {
        guard let rootNode else {
            return braceRanges(in: source)
        }

        var ranges: [NSRange] = []
        var stack: [Int] = []
        ranges.reserveCapacity(128)
        stack.reserveCapacity(64)
        collectBraceRanges(from: rootNode, source: source, stack: &stack, ranges: &ranges)
        return ranges.isEmpty ? braceRanges(in: source) : ranges
    }

    static func collectBraceRanges(
        from node: Node,
        source: NSString,
        stack: inout [Int],
        ranges: inout [NSRange]
    ) {
        let range = node.range
        if range.length == 1, range.upperBound <= source.length {
            let character = source.character(at: range.location)
            if character == openBraceCodeUnit {
                stack.append(range.location)
            } else if character == closeBraceCodeUnit, let openBrace = stack.popLast() {
                ranges.append(NSRange(location: openBrace, length: range.location - openBrace + 1))
            }
        }

        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            collectBraceRanges(from: child, source: source, stack: &stack, ranges: &ranges)
        }
    }

    static func braceRanges(in source: NSString) -> [NSRange] {
        var stack: [Int] = []
        var ranges: [NSRange] = []
        stack.reserveCapacity(64)

        var location = 0
        while location < source.length {
            let character = source.character(at: location)
            if character == openBraceCodeUnit {
                stack.append(location)
            } else if character == closeBraceCodeUnit, let openBrace = stack.popLast() {
                ranges.append(NSRange(location: openBrace, length: location - openBrace + 1))
            }
            location += 1
        }

        return ranges
    }

    private func innermostTypeScope(containing range: NSRange) -> TypeScope? {
        var best: TypeScope?
        for scope in typeScopes {
            guard Self.range(scope.bodyRange, contains: range) else {
                continue
            }
            if best.map({ scope.bodyRange.length < $0.bodyRange.length }) ?? true {
                best = scope
            }
        }
        return best
    }

    private func memberOwnerMatches(_ entry: Entry, currentOwnerQualifiedName: String?) -> Bool {
        guard entry.role == .member,
              let ownerQualifiedName = entry.ownerQualifiedName
        else {
            return true
        }
        return currentOwnerQualifiedName == ownerQualifiedName
    }

    private func nestedExecutableBraceRange(containing range: NSRange, within typeScope: TypeScope) -> NSRange? {
        guard let braceRange = innermostBraceRange(containing: range, within: typeScope.bodyRange),
              braceRange.length < typeScope.bodyRange.length
        else {
            return nil
        }
        return braceRange
    }

    private func nestedLocalValueScope(containing range: NSRange, within outerRange: NSRange) -> NSRange? {
        var candidates: [NSRange] = []
        if let caseClauseRange = switchCaseClauseRange(containing: range, within: outerRange) {
            candidates.append(caseClauseRange)
        }

        if let braceRange = innermostBraceRange(containing: range, within: outerRange),
           braceRange.length < outerRange.length {
            candidates.append(braceRange)
        }

        var best: NSRange?
        for candidate in candidates {
            if best.map({ candidate.length < $0.length }) ?? true {
                best = candidate
            }
        }
        return best
    }

    private func localExecutableBraceRange(
        containing range: NSRange,
        containingTypeScope: TypeScope?
    ) -> NSRange? {
        if let containingTypeScope {
            return nestedExecutableBraceRange(containing: range, within: containingTypeScope)
        }

        if extensionScopeCandidates().contains(where: { Self.range($0.bodyRange, contains: range) }) {
            return nil
        }

        return innermostBraceRange(containing: range, within: fullRange)
    }

    private func localDeclarationScope(containing range: NSRange, within functionScope: FunctionScope) -> NSRange {
        innermostBraceRange(containing: range, within: functionScope.bodyRange) ?? functionScope.bodyRange
    }

    private func localQualifiedTypeNames() -> Set<String> {
        let extensionCandidates = extensionScopeCandidates()
        var knownNames: Set<String> = []

        while true {
            var discoveredScopes: [(qualifiedName: String, bodyRange: NSRange)] = []
            var nextNames: Set<String> = []

            for declaration in typeDeclarations {
                let activeExtensionScopes = extensionCandidates.filter {
                    (knownNames.contains($0.qualifiedName) || nextNames.contains($0.qualifiedName))
                        && Self.range($0.bodyRange, contains: declaration.nameRange)
                }
                let containingScope = (discoveredScopes + activeExtensionScopes)
                    .filter { Self.range($0.bodyRange, contains: declaration.nameRange) }
                    .sorted { $0.bodyRange.length < $1.bodyRange.length }
                    .first
                let qualifiedName: String
                if let containingScope {
                    qualifiedName = "\(containingScope.qualifiedName).\(declaration.name)"
                } else {
                    qualifiedName = declaration.name
                }
                nextNames.insert(qualifiedName)

                if let bodyRange = declaration.bodyRange {
                    discoveredScopes.append((qualifiedName: qualifiedName, bodyRange: bodyRange))
                }
            }

            if nextNames == knownNames {
                return nextNames
            }
            knownNames = nextNames
        }
    }

    private func extensionScopeCandidates() -> [(qualifiedName: String, bodyRange: NSRange)] {
        let sourceString = maskedSource as String
        return Self.extensionRegex.matches(in: sourceString, range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound,
                  let bodyRange = bodyRange(after: match.range.upperBound)
            else {
                return nil
            }
            return (qualifiedName: maskedSource.substring(with: nameRange), bodyRange: bodyRange)
        }
    }

    private func qualifiedName(for name: String, in containingTypeScope: TypeScope?) -> String {
        guard let containingTypeScope else {
            return name
        }
        return "\(containingTypeScope.qualifiedName).\(name)"
    }

    private func innermostFunctionScope(containing range: NSRange) -> FunctionScope? {
        var best: FunctionScope?
        for scope in functionScopes {
            guard Self.range(scope.bodyRange, contains: range) else {
                continue
            }
            if best.map({ scope.bodyRange.length < $0.bodyRange.length }) ?? true {
                best = scope
            }
        }
        return best
    }

    private func innermostBraceRange(containing range: NSRange, within outerRange: NSRange) -> NSRange? {
        var best: NSRange?
        for braceRange in braceRanges {
            guard Self.range(outerRange, contains: braceRange),
                  Self.range(braceRange, contains: range)
            else {
                continue
            }
            if best.map({ braceRange.length < $0.length }) ?? true {
                best = braceRange
            }
        }
        return best
    }

    private func conditionalBindingScopes(for range: NSRange, within outerRange: NSRange) -> [LocalBindingScope] {
        let prefixRange = conditionalHeaderPrefixRange(endingAt: range.location, within: outerRange)
        let prefix = maskedSource.substring(with: prefixRange)
        guard let match = Self.conditionalBindingPrefixRegex.firstMatch(
            in: prefix,
            range: NSRange(location: 0, length: (prefix as NSString).length)
        ),
              match.numberOfRanges > 1
        else {
            return []
        }
        let keyword = (prefix as NSString).substring(with: match.range(at: 1))

        if keyword == "guard" {
            return guardBindingScopes(after: range.upperBound, within: outerRange)
        }

        guard let bodyRange = topLevelBodyRange(after: range.upperBound, within: outerRange)
        else {
            return []
        }

        return [LocalBindingScope(
            range: NSRange(location: range.upperBound, length: bodyRange.upperBound - range.upperBound),
            startLocation: conditionalBindingStartLocation(after: range.upperBound, beforeBodyAt: bodyRange.location)
        )]
    }

    private func conditionalBindingStartLocation(after location: Int, beforeBodyAt bodyLocation: Int) -> Int {
        var scan = location
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while scan < bodyLocation {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            case "," where parenDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                return scan + 1
            default:
                break
            }
            scan += 1
        }

        return bodyLocation
    }

    private func guardBindingScopes(after location: Int, within outerRange: NSRange) -> [LocalBindingScope] {
        var scan = max(location, outerRange.location)
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while scan < outerRange.upperBound {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                if parenDepth == 0,
                   bracketDepth == 0,
                   braceDepth == 0,
                   isKeyword("else", at: scan)
                {
                    let elseLocation = scan
                    let elseUpperBound = scan + "else".utf16.count
                    guard let elseBodyRange = topLevelBodyRange(after: elseUpperBound, within: outerRange) else {
                        return []
                    }
                    var scopes: [LocalBindingScope] = []
                    let headerStart = conditionalBindingStartLocation(after: location, beforeBodyAt: elseLocation)
                    if headerStart < elseLocation {
                        scopes.append(LocalBindingScope(
                            range: NSRange(location: headerStart, length: elseLocation - headerStart),
                            startLocation: headerStart
                        ))
                    }
                    let start = elseBodyRange.upperBound
                    scopes.append(LocalBindingScope(
                        range: NSRange(location: start, length: max(0, outerRange.upperBound - start)),
                        startLocation: start
                    ))
                    return scopes
                }
            }
            scan += 1
        }

        return []
    }

    private func topLevelBodyRange(after location: Int, within outerRange: NSRange) -> NSRange? {
        var scan = max(location, outerRange.location)
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while scan < outerRange.upperBound {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
                    guard let closeBrace = matchingLocation(opening: "{", closing: "}", at: scan) else {
                        return nil
                    }
                    return NSRange(location: scan, length: closeBrace - scan + 1)
                }
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }
            scan += 1
        }

        return nil
    }

    private func conditionalHeaderPrefixRange(endingAt location: Int, within outerRange: NSRange) -> NSRange {
        var scan = location - 1
        while scan >= outerRange.location {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            if character == "{" || character == "}" || character == ";" {
                let start = scan + 1
                return NSRange(location: start, length: max(0, location - start))
            }
            scan -= 1
        }

        return NSRange(location: outerRange.location, length: max(0, location - outerRange.location))
    }

    private func caseClauseRange(for range: NSRange, within outerRange: NSRange) -> NSRange? {
        switchCaseClauseRange(containing: range, within: outerRange) ?? bodyRange(after: range.upperBound)
    }

    private func switchCaseClauseRange(containing range: NSRange, within outerRange: NSRange) -> NSRange? {
        var candidateLineRange = maskedSource.lineRange(for: NSRange(location: range.location, length: 0))

        while candidateLineRange.location >= outerRange.location {
            let candidateLine = maskedSource.substring(with: candidateLineRange)
            let trimmed = candidateLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if isSwitchCaseLine(trimmed),
               let switchBodyRange = switchBodyRange(containing: candidateLineRange, within: outerRange),
               let candidateRange = switchCaseClauseRange(
                startingAt: candidateLineRange,
                within: switchBodyRange
               ),
               Self.range(candidateRange, contains: range) {
                return candidateRange
            }

            guard candidateLineRange.location > outerRange.location else {
                return nil
            }
            candidateLineRange = maskedSource.lineRange(for: NSRange(location: candidateLineRange.location - 1, length: 0))
        }

        return nil
    }

    private func switchCaseClauseRange(startingAt currentLineRange: NSRange, within outerRange: NSRange) -> NSRange? {
        let currentIndent = leadingWhitespaceCount(in: maskedSource.substring(with: currentLineRange))
        var location = currentLineRange.upperBound

        while location < outerRange.upperBound {
            let lineRange = maskedSource.lineRange(for: NSRange(location: location, length: 0))
            let line = maskedSource.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if leadingWhitespaceCount(in: line) <= currentIndent,
               isSwitchCaseLine(trimmed)
            {
                return NSRange(location: currentLineRange.location, length: lineRange.location - currentLineRange.location)
            }
            location = lineRange.upperBound
        }

        return NSRange(
            location: currentLineRange.location,
            length: outerRange.upperBound - currentLineRange.location
        )
    }

    private func switchBodyRange(containing range: NSRange, within outerRange: NSRange) -> NSRange? {
        guard let braceRange = innermostBraceRange(containing: range, within: outerRange),
              isSwitchBodyRange(braceRange)
        else {
            return nil
        }
        return braceRange
    }

    private func isSwitchBodyRange(_ range: NSRange) -> Bool {
        let prefixRange = statementPrefixRange(endingAt: range.location)
        let prefix = maskedSource.substring(with: prefixRange)
        return Self.switchKeywordRegex.firstMatch(
            in: prefix,
            range: NSRange(location: 0, length: (prefix as NSString).length)
        ) != nil
    }

    private func isSwitchCaseLine(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("case ") || trimmedLine.hasPrefix("default")
    }

    private func leadingWhitespaceCount(in line: String) -> Int {
        var count = 0
        for character in line {
            guard character == " " || character == "\t" else {
                break
            }
            count += 1
        }
        return count
    }

    func bodyRange(after location: Int) -> NSRange? {
        guard let openBrace = firstLocation(of: "{", after: location),
              let closeBrace = matchingLocation(
                opening: "{",
                closing: "}",
                at: openBrace
              )
        else {
            return nil
        }

        return NSRange(location: openBrace, length: closeBrace - openBrace + 1)
    }

    func functionBodyRange(after location: Int) -> NSRange? {
        guard let openBrace = firstLocation(of: "{", after: location) else {
            return nil
        }

        let signatureTailRange = NSRange(
            location: max(0, min(location, maskedSource.length)),
            length: max(0, openBrace - max(0, min(location, maskedSource.length)))
        )
        let signatureTail = maskedSource.substring(with: signatureTailRange)
        guard signatureTail.contains("}") == false,
              signatureTail.contains(";") == false,
              Self.declarationKeywordRegex.firstMatch(
                in: signatureTail,
                range: NSRange(location: 0, length: (signatureTail as NSString).length)
              ) == nil,
              let closeBrace = matchingLocation(opening: "{", closing: "}", at: openBrace)
        else {
            return nil
        }

        return NSRange(location: openBrace, length: closeBrace - openBrace + 1)
    }

    func isInitializerDeclaration(at location: Int) -> Bool {
        if let previousLocation = previousNonWhitespaceLocation(before: location),
           maskedSource.substring(with: NSRange(location: previousLocation, length: 1)) == "."
        {
            return false
        }

        let prefixRange = statementPrefixRange(endingAt: location)
        let prefix = maskedSource.substring(with: prefixRange)
        return prefix.contains("=") == false
    }

    func previousNonWhitespaceLocation(before location: Int) -> Int? {
        var scan = location - 1
        while scan >= 0 {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            if character != " " && character != "\t" && character != "\n" && character != "\r" {
                return scan
            }
            scan -= 1
        }
        return nil
    }

    func statementPrefixRange(endingAt location: Int) -> NSRange {
        var scan = location - 1
        while scan >= 0 {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            if character == "{" || character == "}" || character == ";" || character == "\n" {
                let start = scan + 1
                return NSRange(location: start, length: max(0, location - start))
            }
            scan -= 1
        }

        return NSRange(location: 0, length: max(0, location))
    }

    func balancedRange(opening: Character, closing: Character, after location: Int) -> NSRange? {
        guard let openLocation = firstLocation(of: opening, after: location),
              let closeLocation = matchingLocation(opening: opening, closing: closing, at: openLocation)
        else {
            return nil
        }
        return NSRange(location: openLocation, length: closeLocation - openLocation + 1)
    }

    func firstLocation(of character: Character, after location: Int) -> Int? {
        let start = max(0, min(maskedSource.length, location + 1))
        guard start < maskedSource.length else { return nil }

        let range = maskedSource.range(
            of: String(character),
            options: [],
            range: NSRange(location: start, length: maskedSource.length - start)
        )
        return range.location == NSNotFound ? nil : range.location
    }

    func matchingLocation(opening: Character, closing: Character, at openLocation: Int) -> Int? {
        var depth = 0
        var location = openLocation
        while location < maskedSource.length {
            let character = maskedSource.substring(with: NSRange(location: location, length: 1))
            if character == String(opening) {
                depth += 1
            } else if character == String(closing) {
                depth -= 1
                if depth == 0 {
                    return location
                }
            }
            location += 1
        }
        return nil
    }

    func topLevelCommaSeparatedRanges(in range: NSRange) -> [NSRange] {
        var ranges: [NSRange] = []
        var start = range.location
        var angleDepth = 0
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var location = range.location

        while location < range.upperBound {
            let character = maskedSource.substring(with: NSRange(location: location, length: 1))
            switch character {
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            case "," where angleDepth == 0 && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                ranges.append(NSRange(location: start, length: location - start))
                start = location + 1
            default:
                break
            }
            location += 1
        }

        ranges.append(NSRange(location: start, length: range.upperBound - start))
        return ranges
    }

    func parameterName(in range: NSRange) -> (name: String, range: NSRange)? {
        let segment = maskedSource.substring(with: range) as NSString
        let colonRange = segment.range(of: ":")
        guard colonRange.location != NSNotFound else {
            return nil
        }

        let headRange = NSRange(location: 0, length: colonRange.location)
        let matches = Self.identifierRegex.matches(in: segment as String, range: headRange)
        guard !matches.isEmpty else {
            return nil
        }

        let selectedMatch: NSTextCheckingResult
        if matches.count >= 2 {
            selectedMatch = matches[1]
        } else {
            selectedMatch = matches[0]
        }

        let name = segment.substring(with: selectedMatch.range)
        guard name != "_" else {
            return nil
        }

        return (
            name,
            NSRange(
                location: range.location + selectedMatch.range.location,
                length: selectedMatch.range.length
            )
        )
    }

    func declaredTypeName(in range: NSRange) -> String? {
        guard let colonLocation = topLevelColonLocation(in: range) else {
            return nil
        }
        let typeRange = NSRange(
            location: colonLocation + 1,
            length: max(0, range.upperBound - colonLocation - 1)
        )
        let typeTextRange = declarationTypeHeadRange(in: typeRange)
        guard typeTextRange.length > 0 else {
            return nil
        }

        let typeText = maskedSource.substring(with: typeTextRange) as NSString
        guard let match = Self.identifierRegex.firstMatch(
            in: typeText as String,
            range: NSRange(location: 0, length: typeText.length)
        ) else {
            return nil
        }
        return typeText.substring(with: match.range)
    }

    func topLevelColonLocation(in range: NSRange) -> Int? {
        var parenDepth = 0
        var bracketDepth = 0
        var angleDepth = 0
        var location = range.location
        while location < range.upperBound {
            let character = maskedSource.substring(with: NSRange(location: location, length: 1))
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case ":" where parenDepth == 0 && bracketDepth == 0 && angleDepth == 0:
                return location
            case "=", "{":
                if parenDepth == 0 && bracketDepth == 0 && angleDepth == 0 {
                    return nil
                }
            default:
                break
            }
            location += 1
        }
        return nil
    }

    func declarationTypeHeadRange(in range: NSRange) -> NSRange {
        var lowerBound = range.location
        var upperBound = range.upperBound
        while lowerBound < upperBound,
              maskedSource.substring(with: NSRange(location: lowerBound, length: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty {
            lowerBound += 1
        }

        var scan = lowerBound
        var angleDepth = 0
        var parenDepth = 0
        var bracketDepth = 0
        while scan < upperBound {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            switch character {
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "=", ",", "{", "\n", "\r":
                if angleDepth == 0 && parenDepth == 0 && bracketDepth == 0 {
                    upperBound = scan
                    scan = range.upperBound
                    continue
                }
            default:
                break
            }
            scan += 1
        }

        return trimmedRange(NSRange(location: lowerBound, length: max(0, upperBound - lowerBound)))
    }

    func closureParameterListRange(openBrace: Int, closeBrace: Int) -> NSRange? {
        let scanRange = NSRange(location: openBrace + 1, length: max(0, closeBrace - openBrace - 1))
        var location = scanRange.location
        var parenDepth = 0
        var bracketDepth = 0
        var angleDepth = 0
        var braceDepth = 0

        while location < scanRange.upperBound {
            let character = maskedSource.substring(with: NSRange(location: location, length: 1))
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                if parenDepth == 0,
                   bracketDepth == 0,
                   angleDepth == 0,
                   braceDepth == 0,
                   isKeyword("in", at: location)
                {
                    let parameterRange = trimmedRange(NSRange(
                        location: openBrace + 1,
                        length: location - openBrace - 1
                    ))
                    guard isClosureParameterHeader(parameterRange) else {
                        return nil
                    }
                    return parameterRange
                }
            }

            location += 1
        }

        return nil
    }

    func caseBindingNameRanges(in range: NSRange) -> [NSRange] {
        var ranges: [NSRange] = []
        let clause = maskedSource.substring(with: range) as NSString
        for match in Self.inlineCaseBindingRegex.matches(
            in: clause as String,
            range: NSRange(location: 0, length: clause.length)
        ) {
            guard match.numberOfRanges > 1 else { continue }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }
            ranges.append(NSRange(
                location: range.location + nameRange.location,
                length: nameRange.length
            ))
        }

        guard let leadingMatch = Self.leadingCaseBindingRegex.firstMatch(
            in: clause as String,
            range: NSRange(location: 0, length: clause.length)
        ) else {
            return uniqueRanges(ranges)
        }

        let patternStart = range.location + leadingMatch.range.upperBound
        let patternEnd = casePatternUpperBound(in: range)
        guard patternStart < patternEnd else {
            return uniqueRanges(ranges)
        }

        ranges.append(contentsOf: caseLeadingPatternNameRanges(in: NSRange(
            location: patternStart,
            length: patternEnd - patternStart
        )))
        return uniqueRanges(ranges)
    }

    func conditionalCasePatternRange(in range: NSRange) -> NSRange {
        var location = range.location
        var parenDepth = 0
        var bracketDepth = 0

        while location < range.upperBound {
            let character = maskedSource.substring(with: NSRange(location: location, length: 1))
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "=" where parenDepth == 0 && bracketDepth == 0:
                return trimmedRange(NSRange(location: range.location, length: location - range.location))
            default:
                break
            }
            location += 1
        }

        return range
    }

    func forPatternNameRanges(in range: NSRange) -> [NSRange] {
        let pattern = maskedSource.substring(with: range).trimmingCharacters(in: .whitespaces)
        if pattern.hasPrefix("case ") {
            return caseBindingNameRanges(in: range)
        }

        return patternIdentifierRanges(in: range).filter { nameRange in
            let name = maskedSource.substring(with: nameRange)
            return !Self.nonBindingPatternKeywords.contains(name)
        }
    }

    func casePatternUpperBound(in range: NSRange) -> Int {
        let clause = maskedSource.substring(with: range) as NSString
        let whereRange = clause.range(of: " where ")
        if whereRange.location != NSNotFound {
            return range.location + whereRange.location
        }
        return range.upperBound
    }

    func caseLeadingPatternNameRanges(in range: NSRange) -> [NSRange] {
        patternIdentifierRanges(in: range).filter { nameRange in
            nameRange.location == range.location
                || maskedSource.substring(with: NSRange(location: nameRange.location - 1, length: 1)) != "."
        }
    }

    func uniqueRanges(_ ranges: [NSRange]) -> [NSRange] {
        var seen: Set<String> = []
        return ranges.filter { range in
            seen.insert("\(range.location):\(range.length)").inserted
        }
    }

    func closureParameterNameRanges(in range: NSRange) -> [NSRange] {
        var parameterRange = range
        if parameterRange.length > 0,
           maskedSource.substring(with: NSRange(location: parameterRange.location, length: 1)) == "[",
           let captureListEnd = matchingLocation(opening: "[", closing: "]", at: parameterRange.location),
           captureListEnd < parameterRange.upperBound
        {
            parameterRange = trimmedRange(NSRange(
                location: captureListEnd + 1,
                length: parameterRange.upperBound - captureListEnd - 1
            ))
        }

        if parameterRange.length > 0,
           maskedSource.substring(with: NSRange(location: parameterRange.location, length: 1)) == "(",
           let parameterListEnd = matchingLocation(opening: "(", closing: ")", at: parameterRange.location),
           parameterListEnd < parameterRange.upperBound
        {
            parameterRange = NSRange(
                location: parameterRange.location + 1,
                length: parameterListEnd - parameterRange.location - 1
            )
        }

        return topLevelCommaSeparatedRanges(in: parameterRange).compactMap { segmentRange in
            let segmentRange = trimmedRange(segmentRange)
            guard segmentRange.length > 0 else {
                return nil
            }

            if let typedParameter = parameterName(in: segmentRange) {
                return typedParameter.range
            }

            let segment = maskedSource.substring(with: segmentRange) as NSString
            guard let match = Self.identifierRegex.firstMatch(
                in: segment as String,
                range: NSRange(location: 0, length: segment.length)
            ) else {
                return nil
            }

            let name = segment.substring(with: match.range)
            guard name != "_" else {
                return nil
            }
            return NSRange(
                location: segmentRange.location + match.range.location,
                length: match.range.length
            )
        }
    }

    func isClosureParameterHeader(_ range: NSRange) -> Bool {
        guard range.length > 0 else {
            return false
        }

        let header = maskedSource.substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !header.isEmpty else {
            return false
        }

        return Self.closureHeaderRejectedKeywordRegex.firstMatch(
            in: header,
            range: NSRange(location: 0, length: (header as NSString).length)
        ) == nil
    }

    func trimmedRange(_ range: NSRange) -> NSRange {
        var lowerBound = range.location
        var upperBound = range.upperBound

        while lowerBound < upperBound,
              maskedSource.substring(with: NSRange(location: lowerBound, length: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        {
            lowerBound += 1
        }

        while upperBound > lowerBound,
              maskedSource.substring(with: NSRange(location: upperBound - 1, length: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        {
            upperBound -= 1
        }

        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    func isKeyword(_ keyword: String, at location: Int) -> Bool {
        let range = NSRange(location: location, length: (keyword as NSString).length)
        guard range.upperBound <= maskedSource.length,
              maskedSource.substring(with: range) == keyword
        else {
            return false
        }

        let beforeIsIdentifier = location > 0 && isIdentifierCharacter(at: location - 1)
        let afterLocation = range.upperBound
        let afterIsIdentifier = afterLocation < maskedSource.length && isIdentifierCharacter(at: afterLocation)
        return beforeIsIdentifier == false && afterIsIdentifier == false
    }

    func isIdentifierCharacter(at location: Int) -> Bool {
        guard location >= 0 && location < maskedSource.length else {
            return false
        }
        return Self.isSwiftIdentifierContinueCodeUnit(maskedSource.character(at: location))
    }

    func enumCaseNameRanges(in range: NSRange) -> [NSRange] {
        topLevelCommaSeparatedRanges(in: range).compactMap { segmentRange in
            let segment = maskedSource.substring(with: segmentRange) as NSString
            let match = Self.identifierRegex.firstMatch(
                in: segment as String,
                range: NSRange(location: 0, length: segment.length)
            )
            guard let match else { return nil }
            return NSRange(
                location: segmentRange.location + match.range.location,
                length: match.range.length
            )
        }
    }

    func genericParameterListRange(after location: Int) -> NSRange? {
        var scan = min(max(0, location), maskedSource.length)
        while scan < maskedSource.length {
            let character = maskedSource.substring(with: NSRange(location: scan, length: 1))
            if character == "<" {
                return balancedRange(opening: "<", closing: ">", after: scan - 1)
            }
            if character == "{" || character == "(" || character == "\n" {
                return nil
            }
            if character.trimmingCharacters(in: .whitespaces).isEmpty == false {
                return nil
            }
            scan += 1
        }
        return nil
    }

    func genericParameterNameRanges(in range: NSRange) -> [NSRange] {
        guard range.length > 2 else { return [] }
        let interior = NSRange(location: range.location + 1, length: range.length - 2)
        return topLevelCommaSeparatedRanges(in: interior).compactMap { segmentRange in
            let segment = maskedSource.substring(with: segmentRange) as NSString
            guard let match = Self.identifierRegex.firstMatch(
                in: segment as String,
                range: NSRange(location: 0, length: segment.length)
            ) else {
                return nil
            }
            return NSRange(
                location: segmentRange.location + match.range.location,
                length: match.range.length
            )
        }
    }
}

private extension SwiftFileSymbolIndex {
    static func entry(_ lhs: Entry, isBetterThan rhs: Entry) -> Bool {
        if lhs.scopeRange.length != rhs.scopeRange.length {
            return lhs.scopeRange.length < rhs.scopeRange.length
        }
        if lhs.declarationRange.location != rhs.declarationRange.location {
            return lhs.declarationRange.location > rhs.declarationRange.location
        }
        return lhs.name < rhs.name
    }

    private static func typedValue(_ lhs: TypedValue, isBetterThan rhs: TypedValue) -> Bool {
        if lhs.scopeRange.length != rhs.scopeRange.length {
            return lhs.scopeRange.length < rhs.scopeRange.length
        }
        return lhs.declarationRange.location > rhs.declarationRange.location
    }

    static func lastQualifiedComponent(_ name: String) -> String {
        guard let dotIndex = name.lastIndex(of: ".") else {
            return name
        }
        return String(name[name.index(after: dotIndex)...])
    }

    static let identifierPattern = #"[A-Za-z_][A-Za-z0-9_]*"#
    static let qualifiedIdentifierPattern = #"\#(identifierPattern)(?:\.\#(identifierPattern))*"#

    static let identifierRegex = try! NSRegularExpression(pattern: identifierPattern)

    static let typeDeclarationRegex = try! NSRegularExpression(
        pattern: #"\b(class|struct|enum|actor|protocol|precedencegroup)\s+(\#(identifierPattern))"#
    )

    static let typeAliasRegex = try! NSRegularExpression(
        pattern: #"\b(typealias|associatedtype)\s+(\#(identifierPattern))"#
    )

    static let extensionRegex = try! NSRegularExpression(
        pattern: #"\bextension\s+(\#(qualifiedIdentifierPattern))"#
    )

    static let functionRegex = try! NSRegularExpression(
        pattern: #"\bfunc\s+(`[^`]+`|\#(identifierPattern)|[!%&*+\-./<=>?^|~]+)\s*(?:<[^{}\n()]+>)?\s*\("#
    )

    static let initRegex = try! NSRegularExpression(
        pattern: #"\binit\s*[?!]?\s*\("#
    )

    static let subscriptRegex = try! NSRegularExpression(
        pattern: #"\bsubscript\s*\("#
    )

    static let operatorRegex = try! NSRegularExpression(
        pattern: #"\b(?:prefix|infix|postfix)\s+operator\s+([^\s:]+)"#
    )

    static let macroRegex = try! NSRegularExpression(
        pattern: #"\bmacro\s+(\#(identifierPattern))\s*\("#
    )

    static let valueDeclarationRegex = try! NSRegularExpression(
        pattern: #"\b(?:let|var)\b"#
    )

    static let forPatternBindingRegex = try! NSRegularExpression(
        pattern: #"\bfor\s+([^\n]+?)\s+in\b"#
    )

    static let catchPatternBindingRegex = try! NSRegularExpression(
        pattern: #"\bcatch\s+(?:let\s+|var\s+)?(\#(identifierPattern))\b"#
    )

    static let caseClauseRegex = try! NSRegularExpression(
        pattern: #"\bcase\b[^\n]*:"#
    )

    static let conditionalCaseBindingRegex = try! NSRegularExpression(
        pattern: #"\b(?:if|while)\s+case\b[^\n{]*\{"#
    )

    static let guardCaseBindingRegex = try! NSRegularExpression(
        pattern: #"\bguard\s+case\b[^\n{]*\belse\s*\{"#
    )

    static let switchKeywordRegex = try! NSRegularExpression(
        pattern: #"\bswitch\b"#
    )

    static let caseKeywordRegex = try! NSRegularExpression(
        pattern: #"\bcase\b"#
    )

    static let inlineCaseBindingRegex = try! NSRegularExpression(
        pattern: #"\b(?:let|var)\s+(\#(identifierPattern))\b"#
    )

    static let leadingCaseBindingRegex = try! NSRegularExpression(
        pattern: #"\bcase\s+(?:let|var)\b\s*"#
    )

    static let declarationKeywordRegex = try! NSRegularExpression(
        pattern: #"\b(?:class|struct|enum|actor|protocol|extension|func|init|subscript|let|var|case|macro)\b"#
    )

    static let conditionalBindingPrefixRegex = try! NSRegularExpression(
        pattern: #"\b(if|while|guard)\b[\s\S]*\b(?:let|var)\s*$"#
    )

    static let closureHeaderRejectedKeywordRegex = try! NSRegularExpression(
        pattern: #"\b(?:for|if|while|switch|case|guard|return|let|var|do|catch|throw|defer)\b"#
    )

    static let valueDeclarationContinuationPreviousCharacters: Set<String> = [
        "=", ",", "(", "[", "{", ".", "?", "!", ":",
    ]
    static let valueDeclarationContinuationNextCharacters: Set<String> = [
        ".", "?", "!", "+", "-", "*", "/", "%", "&", "|", "^", "=", "<", ">",
    ]
    static let valueDeclarationContinuationStoppingKeywords: Set<String> = [
        "actor", "case", "class", "default", "enum", "extension", "func", "import", "let", "protocol",
        "struct", "typealias", "var",
    ]

    static let genericAngleCloseFollowingCharacters: Set<String> = [
        "(", ")", "[", "]", ".", ",", "?", "!", ":", "=",
    ]

    static let nonBindingPatternKeywords: Set<String> = ["await", "case", "let", "try", "var"]

    static let openBraceCodeUnit: unichar = 123
    static let closeBraceCodeUnit: unichar = 125

    static func isSwiftIdentifierContinueCodeUnit(_ codeUnit: unichar) -> Bool {
        codeUnit == 95
            || (codeUnit >= 48 && codeUnit <= 57)
            || (codeUnit >= 65 && codeUnit <= 90)
            || (codeUnit >= 97 && codeUnit <= 122)
    }
}

private extension SwiftFileSymbolIndex.SymbolKind {
    var kindSet: SwiftFileSymbolIndex.SymbolKindSet {
        switch self {
        case .type:
            return .type
        case .function:
            return .function
        case .variable:
            return .variable
        case .constant:
            return .constant
        case .macro:
            return .macro
        }
    }
}

private extension SwiftFileSymbolIndex.SymbolRole {
    var roleSet: SwiftFileSymbolIndex.SymbolRoleSet {
        switch self {
        case .file:
            return .file
        case .member:
            return .member
        case .local:
            return .local
        case .genericParameter:
            return .genericParameter
        }
    }
}
