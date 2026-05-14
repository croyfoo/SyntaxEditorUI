import Foundation
import Observation
import Testing
@testable import SyntaxEditorCore

private func requireObservable<T: Observable>(_ value: T) {}

private func applying(_ result: EditorCommandResult?, to source: String) -> String? {
    guard let result else { return nil }
    return applyingIfValid(result.edits, to: source)
}

private func applying(_ result: EditorCommandResult, to source: String) -> String {
    SyntaxEditorDocument.applying(result.edits, to: source)
}

private func applying(_ edit: SyntaxLanguageEdit?, to source: String) -> String? {
    guard let edit else { return nil }
    return applyingIfValid(edit.edits, to: source)
}

private func applying(_ edit: SyntaxLanguageEdit, to source: String) -> String {
    SyntaxEditorDocument.applying(edit.edits, to: source)
}

private func applyingIfValid(_ edits: [SyntaxEditorTextEdit], to source: String) -> String? {
    let length = source.utf16.count
    guard edits.allSatisfy({ edit in
        edit.range.location >= 0
            && edit.range.length >= 0
            && edit.range.location + edit.range.length <= length
    }) else {
        return nil
    }
    return SyntaxEditorDocument.applying(edits, to: source)
}

private func highlightTokensMatch(_ lhs: [SyntaxHighlightToken], _ rhs: [SyntaxHighlightToken]) -> Bool {
    sortHighlightTokens(lhs) == sortHighlightTokens(rhs)
}

private func sortHighlightTokens(_ tokens: [SyntaxHighlightToken]) -> [SyntaxHighlightToken] {
    tokens.sorted {
        if $0.range.location != $1.range.location {
            return $0.range.location < $1.range.location
        }
        if $0.range.length != $1.range.length {
            return $0.range.length < $1.range.length
        }
        return $0.rawCaptureName < $1.rawCaptureName
    }
}

private func tokenIntersects(
    _ token: SyntaxHighlightToken,
    range: NSRange,
    syntaxID: EditorSourceSyntaxID? = nil,
    language: SyntaxLanguage? = nil
) -> Bool {
    if let syntaxID, token.syntaxID != syntaxID {
        return false
    }
    if let language, token.language != language {
        return false
    }
    return SyntaxEditorRangeUtilities.intersection(of: token.range, and: range).length > 0
}

private func tokenIsInjectedKeyword(_ token: SyntaxHighlightToken, in range: NSRange) -> Bool {
    (token.language == .javascript || token.language == .json)
        && token.syntaxID == .keyword
        && SyntaxEditorRangeUtilities.intersection(of: token.range, and: range).length > 0
}

private struct HighlightSemanticSnapshot {
    let text: String
    let rawCaptureName: String
    let syntaxID: EditorSourceSyntaxID
    let styleKeys: [String]
    let resolvedStyle: SyntaxEditorResolvedTextStyle
}

private func referenceSampleText(named filename: String) throws -> String {
    let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sampleURL = repositoryRootURL
        .appendingPathComponent("Tools/Mini/Mini/ReferenceSamples", isDirectory: true)
        .appendingPathComponent(filename)
    return try String(contentsOf: sampleURL, encoding: .utf8)
}

private func repositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func highlightQueryURL(language: SyntaxLanguage) -> URL {
    let directoryName = switch language {
    case .css:
        "CSSQueries"
    case .html:
        "HTMLQueries"
    case .javascript:
        "JavaScriptQueries"
    case .json:
        "JSONQueries"
    case .objectiveC:
        "ObjectiveCQueries"
    case .swift:
        "SwiftQueries"
    case .toml:
        "TOMLQueries"
    case .xml:
        "XMLQueries"
    }
    return repositoryRootURL()
        .appendingPathComponent("Sources/SyntaxEditorCore/Resources", isDirectory: true)
        .appendingPathComponent(directoryName, isDirectory: true)
        .appendingPathComponent("highlights.scm")
}

private func canonicalCaptureLanguageName(for language: SyntaxLanguage) -> String {
    switch language {
    case .css:
        "css"
    case .html:
        "html"
    case .javascript:
        "javascript"
    case .json:
        "json"
    case .objectiveC:
        "objectivec"
    case .swift:
        "swift"
    case .toml:
        "toml"
    case .xml:
        "xml"
    }
}

private func languageImplementationDirectoryName(for language: SyntaxLanguage) -> String {
    switch language {
    case .css:
        "CSS"
    case .html:
        "HTML"
    case .javascript:
        "JavaScript"
    case .json:
        "JSON"
    case .objectiveC:
        "ObjectiveC"
    case .swift:
        "Swift"
    case .toml:
        "TOML"
    case .xml:
        "XML"
    }
}

private func captureNames(inQuerySource source: String) -> [String] {
    var captures: [String] = []
    var index = source.startIndex
    var isInString = false
    var isEscaped = false
    var isInLineComment = false

    while index < source.endIndex {
        let character = source[index]

        if isInLineComment {
            if character == "\n" {
                isInLineComment = false
            }
            index = source.index(after: index)
            continue
        }

        if isInString {
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isInString = false
            }
            index = source.index(after: index)
            continue
        }

        if character == ";" {
            isInLineComment = true
            index = source.index(after: index)
            continue
        }
        if character == "\"" {
            isInString = true
            index = source.index(after: index)
            continue
        }
        guard character == "@" else {
            index = source.index(after: index)
            continue
        }

        var end = source.index(after: index)
        while end < source.endIndex {
            let next = source[end]
            guard next.isLetter || next.isNumber || next == "." || next == "_" || next == "-" else {
                break
            }
            end = source.index(after: end)
        }
        if end > source.index(after: index) {
            captures.append(String(source[source.index(after: index)..<end]))
        }
        index = end
    }

    return captures
}

private func generatedQueryBlock(named name: String, language: SyntaxLanguage) throws -> String {
    let source = try String(contentsOf: highlightQueryURL(language: language), encoding: .utf8)
    let begin = "; BEGIN GENERATED EDITOR SYNTAX WORDS: \(name)"
    let end = "; END GENERATED EDITOR SYNTAX WORDS: \(name)"
    let beginRange = try #require(source.range(of: begin))
    let contentStart = try #require(source[beginRange.upperBound...].firstIndex(of: "\n"))
    let endRange = try #require(source.range(of: end, range: contentStart..<source.endIndex))
    return String(source[source.index(after: contentStart)..<endRange.lowerBound])
}

private func quotedStrings(in source: String) -> [String] {
    var strings: [String] = []
    var index = source.startIndex

    while index < source.endIndex {
        guard source[index] == "\"" else {
            index = source.index(after: index)
            continue
        }

        index = source.index(after: index)
        var value = ""
        var isEscaped = false
        while index < source.endIndex {
            let character = source[index]
            if isEscaped {
                value.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                break
            } else {
                value.append(character)
            }
            index = source.index(after: index)
        }
        strings.append(value)
        if index < source.endIndex {
            index = source.index(after: index)
        }
    }

    return strings
}

private func semanticSnapshot(
    in tokens: [SyntaxHighlightToken],
    source: String,
    text: String,
    syntaxID: EditorSourceSyntaxID,
    language: SyntaxLanguage,
    inOccurrenceOf containingText: String? = nil
) throws -> HighlightSemanticSnapshot {
    let nsSource = source as NSString
    let searchRange: NSRange
    if let containingText {
        searchRange = nsSource.range(of: containingText)
        #expect(searchRange.location != NSNotFound)
    } else {
        searchRange = NSRange(location: 0, length: nsSource.length)
    }
    let expectedRange = nsSource.range(of: text, options: [], range: searchRange)
    #expect(expectedRange.location != NSNotFound)
    let matchedToken = tokens.first {
        $0.syntaxID == syntaxID
            && SyntaxEditorRangeUtilities.intersection(of: $0.range, and: expectedRange).length > 0
    }
    if matchedToken == nil {
        let nearby = tokens
            .filter { SyntaxEditorRangeUtilities.intersection(of: $0.range, and: searchRange).length > 0 }
            .map { token in
                "\(nsSource.substring(with: token.range)):\(token.rawCaptureName)"
            }
            .joined(separator: ", ")
        Issue.record("Could not find \(syntaxID.rawValue) for \(text) in \(containingText ?? source). Nearby: \(nearby)")
    }
    let token = try #require(matchedToken)
    let tokenText = nsSource.substring(with: token.range)
    let styleKeys = try #require(SyntaxEditorHighlightTheme.semanticStyleKeys(
        for: token.syntaxID,
        language: language
    ))
    let style = try #require(SyntaxEditorHighlightTheme.style(
        for: token.syntaxID,
        in: .default,
        language: language,
        appearance: .dark
    ))
    return HighlightSemanticSnapshot(
        text: tokenText,
        rawCaptureName: token.rawCaptureName,
        syntaxID: token.syntaxID,
        styleKeys: styleKeys,
        resolvedStyle: style
    )
}

private func syntaxIDs(
    in tokens: [SyntaxHighlightToken],
    source: String,
    text: String,
    inOccurrenceOf containingText: String
) -> [EditorSourceSyntaxID] {
    let nsSource = source as NSString
    let searchRange = nsSource.range(of: containingText)
    #expect(searchRange.location != NSNotFound)
    let expectedRange = nsSource.range(of: text, options: [], range: searchRange)
    #expect(expectedRange.location != NSNotFound)

    return tokens
        .filter { SyntaxEditorRangeUtilities.intersection(of: $0.range, and: expectedRange).length > 0 }
        .map(\.syntaxID)
}

private func effectiveSemanticSnapshot(
    in tokens: [SyntaxHighlightToken],
    source: String,
    text: String,
    syntaxID: EditorSourceSyntaxID,
    language: SyntaxLanguage,
    inOccurrenceOf containingText: String
) throws -> HighlightSemanticSnapshot {
    let nsSource = source as NSString
    let searchRange = nsSource.range(of: containingText)
    #expect(searchRange.location != NSNotFound)
    let expectedRange = nsSource.range(of: text, options: [], range: searchRange)
    #expect(expectedRange.location != NSNotFound)

    let matchedToken = tokens.last {
        $0.syntaxID == syntaxID
            && SyntaxEditorRangeUtilities.intersection(of: $0.range, and: expectedRange).length > 0
    }
    if matchedToken == nil {
        let nearby = tokens
            .filter { SyntaxEditorRangeUtilities.intersection(of: $0.range, and: searchRange).length > 0 }
            .map { token in
                "\(nsSource.substring(with: token.range)):\(token.rawCaptureName)"
            }
            .joined(separator: ", ")
        Issue.record("Could not find effective \(syntaxID.rawValue) token for \(text) in \(containingText). Nearby: \(nearby)")
    }

    let token = try #require(matchedToken)
    let tokenText = nsSource.substring(with: token.range)
    let styleKeys = try #require(SyntaxEditorHighlightTheme.semanticStyleKeys(
        for: token.syntaxID,
        language: language
    ))
    let style = try #require(SyntaxEditorHighlightTheme.style(
        for: token.syntaxID,
        in: .default,
        language: language,
        appearance: .dark
    ))
    return HighlightSemanticSnapshot(
        text: tokenText,
        rawCaptureName: token.rawCaptureName,
        syntaxID: token.syntaxID,
        styleKeys: styleKeys,
        resolvedStyle: style
    )
}

private extension SyntaxHighlighterEngine {
    func reset(source: String, language: SyntaxLanguage) async -> SyntaxHighlightResult {
        await reset(source: source, language: language, revision: 0)
    }

    func update(
        previousSource: String,
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation
    ) async -> SyntaxHighlightResult {
        _ = previousSource
        return await update(source: source, language: language, mutation: mutation, revision: 1)
    }
}

@Suite("SyntaxEditorCore")
struct SyntaxEditorCoreTests {
    @Test("SyntaxLanguage.named maps supported values")
    func builtinSyntaxLanguagesNamed() {
        #expect(SyntaxLanguage.named("css")?.identifier == SyntaxLanguage.css.identifier)
        #expect(SyntaxLanguage.named("html")?.identifier == SyntaxLanguage.html.identifier)
        #expect(SyntaxLanguage.named("HTM")?.identifier == SyntaxLanguage.html.identifier)
        #expect(SyntaxLanguage.named(" javascript ")?.identifier == SyntaxLanguage.javascript.identifier)
        #expect(SyntaxLanguage.named("JS")?.identifier == SyntaxLanguage.javascript.identifier)
        #expect(SyntaxLanguage.named("JSON")?.identifier == SyntaxLanguage.json.identifier)
        #expect(SyntaxLanguage.named("objective-c")?.identifier == SyntaxLanguage.objectiveC.identifier)
        #expect(SyntaxLanguage.named("objectivec")?.identifier == SyntaxLanguage.objectiveC.identifier)
        #expect(SyntaxLanguage.named("objc")?.identifier == SyntaxLanguage.objectiveC.identifier)
        #expect(SyntaxLanguage.named("Swift")?.identifier == SyntaxLanguage.swift.identifier)
        #expect(SyntaxLanguage.named("toml")?.identifier == SyntaxLanguage.toml.identifier)
        #expect(SyntaxLanguage.named("xml")?.identifier == SyntaxLanguage.xml.identifier)
    }

    @Test("SyntaxLanguage.named rejects unsupported values")
    func builtinSyntaxLanguagesRejectUnsupportedValue() {
        #expect(SyntaxLanguage.named("yaml") == nil)
    }

    @Test("SyntaxEditorDocument and SyntaxEditorConfiguration store and mutate state on MainActor")
    @MainActor
    func syntaxEditorDocumentConfigurationState() {
        let document = SyntaxEditorDocument(text: "{}")
        let configuration = SyntaxEditorConfiguration(language: SyntaxLanguage.json)

        #expect(document.textSnapshot() == "{}")
        #expect(configuration.language.identifier == SyntaxLanguage.json.identifier)
        #expect(configuration.isEditable == true)
        #expect(configuration.lineWrappingEnabled == false)
        #expect(configuration.colorTheme == .default)

        document.replaceText("body { color: red; }")
        configuration.language = SyntaxLanguage.css
        configuration.isEditable = false
        configuration.lineWrappingEnabled = true

        #expect(document.textSnapshot() == "body { color: red; }")
        #expect(document.revision == 1)
        #expect(configuration.language.identifier == SyntaxLanguage.css.identifier)
        #expect(configuration.isEditable == false)
        #expect(configuration.lineWrappingEnabled == true)
        #expect(configuration.colorTheme == .default)
    }

    @Test("SyntaxEditorDocument text snapshots participate in observation")
    @MainActor
    func syntaxEditorDocumentTextSnapshotObservation() {
        let document = SyntaxEditorDocument(text: "let value = 1")
        var observedText = ""
        let didChange = DispatchSemaphore(value: 0)

        withObservationTracking {
            observedText = document.textSnapshot()
        } onChange: {
            didChange.signal()
        }

        document.replaceText("let value = 2")

        #expect(observedText == "let value = 1")
        #expect(didChange.wait(timeout: .now()) == .success)
    }

    @Test("SyntaxEditorHighlightTheme maps representative captures to theme slots")
    func syntaxEditorHighlightThemeMapping() {
        let theme = SyntaxEditorColorTheme.default
        let resolved = theme.resolved(for: .swift, appearance: .light)
        let custom = SyntaxEditorColorTheme(
            baseForeground: .syntaxEditorColor(.init(red: 1, green: 1, blue: 1, alpha: 1)),
            bracketBackground: .syntaxEditorColor(.init(red: 0, green: 0, blue: 0, alpha: 1)),
            comment: .syntaxEditorColor(.init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)),
            string: .syntaxEditorColor(.init(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)),
            keyword: .syntaxEditorColor(.init(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)),
            number: .syntaxEditorColor(.init(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)),
            function: .syntaxEditorColor(.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)),
            type: .syntaxEditorColor(.init(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)),
            constant: .syntaxEditorColor(.init(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)),
            variable: .syntaxEditorColor(.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)),
            punctuation: .syntaxEditorColor(.init(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        )
        let customResolved = custom.resolved(for: .swift, appearance: .light)

        #expect(SyntaxEditorHighlightTheme.color(for: .keyword, in: theme, language: .swift, appearance: .light) == resolved.keyword.foreground)
        #expect(SyntaxEditorHighlightTheme.color(for: .string, in: theme, language: .swift, appearance: .light) == resolved.string.foreground)
        #expect(SyntaxEditorHighlightTheme.color(for: .plain, in: theme, language: .swift, appearance: .light) == resolved.base.foreground)
        #expect(SyntaxEditorHighlightTheme.semanticStyleKeys(for: .identifierTypeSystem, language: .swift)?.first == "editor.syntax.identifier.type.system")
        #expect(SyntaxEditorHighlightTheme.color(for: .number, in: theme, language: .swift, appearance: .light) == resolved.number.foreground)
        #expect(SyntaxEditorHighlightTheme.color(for: .declarationType, in: custom, language: .swift, appearance: .light) == customResolved.type.foreground)
        #expect(SyntaxEditorHighlightTheme.color(for: .declarationOther, in: custom, language: .swift, appearance: .light) == customResolved.function.foreground)
        #expect(SyntaxEditorHighlightTheme.color(for: .identifierFunctionSystem, in: custom, language: .swift, appearance: .light) == customResolved.function.foreground)
        #expect(SyntaxEditorHighlightTheme.color(for: .identifierConstantSystem, in: custom, language: .swift, appearance: .light) == customResolved.constant.foreground)
        #expect(SyntaxEditorHighlightTheme.color(for: .identifierVariableSystem, in: custom, language: .swift, appearance: .light) == customResolved.variable.foreground)
        #expect(SyntaxEditorHighlightTheme.color(for: .plain, in: custom, language: .swift, appearance: .light) == nil)
        #expect(SyntaxEditorHighlightTheme.color(for: "unknown.capture", in: theme, language: .swift, appearance: .light) == resolved.base.foreground)
    }

    @Test("SyntaxEditorHighlightTheme resolves language-specific built-in styles")
    func syntaxEditorHighlightThemeLanguageSpecificStyles() {
        let theme = SyntaxEditorColorTheme.default
        let swiftStyle = SyntaxEditorHighlightTheme.style(
            for: .plain,
            in: theme,
            language: .swift,
            appearance: .light
        )
        let swiftResolved = theme.resolved(for: .swift, appearance: .light)
        #expect(swiftStyle?.foreground == swiftResolved.baseForeground)

        let objectiveCStyle = SyntaxEditorHighlightTheme.style(
            for: .plain,
            in: theme,
            language: .objectiveC,
            appearance: .light
        )
        let objectiveCResolved = theme.resolved(for: .objectiveC, appearance: .light)
        #expect(objectiveCStyle?.foreground == objectiveCResolved.baseForeground)
    }

    @Test("EditorSyntaxCapture parses canonical captures and falls back for non-canonical names")
    func editorSyntaxCaptureParser() {
        let swiftKeyword = EditorSyntaxCapture.parse(
            rawCaptureName: "editor.syntax.swift.keyword",
            rootLanguage: .html
        )
        #expect(swiftKeyword.syntaxID == .keyword)
        #expect(swiftKeyword.language == .swift)

        let objectiveCType = EditorSyntaxCapture.parse(
            rawCaptureName: "@editor.syntax.objectivec.identifier.type.system",
            rootLanguage: .swift
        )
        #expect(objectiveCType.syntaxID == .identifierTypeSystem)
        #expect(objectiveCType.language == .objectiveC)

        let fallback = EditorSyntaxCapture.parse(rawCaptureName: "keyword", rootLanguage: .swift)
        #expect(fallback.syntaxID == .plain)
        #expect(fallback.language == .swift)
    }

    @Test("Built-in highlight queries use canonical editor syntax captures")
    func builtInHighlightQueriesUseCanonicalCaptures() throws {
        for language in SyntaxLanguage.allCases {
            let source = try String(contentsOf: highlightQueryURL(language: language), encoding: .utf8)
            let captures = captureNames(inQuerySource: source)
            let prefix = "editor.syntax.\(canonicalCaptureLanguageName(for: language))."
            #expect(captures.isEmpty == false, "No captures found for \(language.rawValue)")

            for capture in captures {
                #expect(capture.hasPrefix(prefix), "Non-canonical capture @\(capture) in \(language.rawValue)")
                let classification = EditorSyntaxCapture.parse(
                    rawCaptureName: capture,
                    rootLanguage: language
                )
                #expect(classification.language == language)
                #expect(SyntaxEditorHighlightTheme.semanticStyleKeys(
                    for: classification.syntaxID,
                    language: classification.language
                )?.isEmpty == false)
                #expect(SyntaxEditorHighlightTheme.style(
                    for: classification.syntaxID,
                    in: .default,
                    language: classification.language,
                    appearance: .dark
                ) != nil)
            }
        }
    }

    @Test("Generated language syntax vocabularies cover supported languages")
    func generatedLanguageSyntaxVocabulariesCoverSupportedLanguages() throws {
        let vocabulariesByLanguage = Dictionary(
            uniqueKeysWithValues: SyntaxLanguage.allCases.map {
                ($0, $0.syntaxVocabulary)
            }
        )
        #expect(Set(vocabulariesByLanguage.keys) == Set(SyntaxLanguage.allCases))

        let swift = try #require(vocabulariesByLanguage[.swift])
        #expect(swift.fileExtensions.contains("swift"))
        #expect(swift.rootRuleIdentifier == "swift")
        #expect(swift.syntaxTypes.contains("declaration.precedencegroup"))
        #expect(swift.keywordWords.contains("defer"))
        #expect(swift.keywordWords.contains("isolated"))
        #expect(swift.attributeWords.contains("@available"))
        #expect(swift.attributeWords.contains("#sourceLocation"))

        let html = try #require(vocabulariesByLanguage[.html])
        #expect(html.rootRuleIdentifier == "html")
        #expect(html.syntaxTypes.contains("definition.entity"))
        #expect(html.keywordWords.isEmpty == false)

        let css = try #require(vocabulariesByLanguage[.css])
        #expect(css.syntaxTypes.contains("definition.style"))
        #expect(css.attributeWords.contains("@media"))

        let objectiveC = try #require(vocabulariesByLanguage[.objectiveC])
        #expect(objectiveC.attributeWords.contains("@interface"))
        #expect(objectiveC.keywordWords.contains("typedef"))

        #expect(SyntaxEditorHighlightTheme.semanticStyleKeys(for: "attribute", language: .toml)?.first == "editor.syntax.attribute")
        #expect(SyntaxEditorHighlightTheme.semanticStyleKeys(for: "plain", language: .toml)?.first == "editor.syntax.plain")
        #expect(SyntaxEditorHighlightTheme.semanticStyleKeys(for: "keyword", language: .css)?.first == "editor.syntax.keyword")
        #expect(SyntaxEditorHighlightTheme.semanticStyleKeys(for: "keyword", language: .html)?.first == "editor.syntax.keyword")
    }

    @Test("Language source files live in language-specific directories")
    func languageSourceFilesLiveInLanguageSpecificDirectories() {
        let languagesURL = repositoryRootURL()
            .appendingPathComponent("Sources/SyntaxEditorCore/Languages", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: languagesURL.appendingPathComponent("Builtin").path))
        #expect(!FileManager.default.fileExists(atPath: languagesURL.appendingPathComponent("Generated").path))
        #expect(!FileManager.default.fileExists(atPath: languagesURL.appendingPathComponent("Support").path))

        for language in SyntaxLanguage.allCases {
            let directoryName = languageImplementationDirectoryName(for: language)
            let typeName = switch language {
            case .css:
                "CSSLanguage"
            case .html:
                "HTMLLanguage"
            case .javascript:
                "JavaScriptLanguage"
            case .json:
                "JSONLanguage"
            case .objectiveC:
                "ObjectiveCLanguage"
            case .swift:
                "SwiftLanguage"
            case .toml:
                "TOMLLanguage"
            case .xml:
                "XMLLanguage"
            }
            let languageDirectory = languagesURL.appendingPathComponent(directoryName, isDirectory: true)
            #expect(FileManager.default.fileExists(atPath: languageDirectory.appendingPathComponent("\(typeName).swift").path))
            #expect(FileManager.default.fileExists(atPath: languageDirectory.appendingPathComponent("\(typeName)+Generated.swift").path))
        }
    }

    @Test("Generated query word blocks stay in sync with generated vocabulary")
    func generatedQueryWordBlocksStayInSyncWithGeneratedVocabulary() throws {
        let swift = SyntaxLanguage.swift.syntaxVocabulary
        let swiftAttributes = Set(swift.attributeWords.compactMap { word -> String? in
            guard word.hasPrefix("@") else { return nil }
            return String(word.dropFirst())
        })
        let generatedSwiftAttributeWords = Set(
            quotedStrings(in: try generatedQueryBlock(named: "swift-attributes", language: .swift))
                .filter { $0 != "@" }
        )
        #expect(generatedSwiftAttributeWords == swiftAttributes)

        let objectiveC = SyntaxLanguage.objectiveC.syntaxVocabulary
        let stableObjectiveCAttributes: Set<String> = [
            "@autoreleasepool",
            "@catch",
            "@compatibility_alias",
            "@defs",
            "@dynamic",
            "@end",
            "@finally",
            "@implementation",
            "@interface",
            "@optional",
            "@property",
            "@protocol",
            "@required",
            "@selector",
            "@synchronized",
            "@synthesize",
            "@throw",
            "@try",
        ]
        let objectiveCAttributes = Set(objectiveC.attributeWords).intersection(stableObjectiveCAttributes)
        #expect(Set(quotedStrings(in: try generatedQueryBlock(named: "objectivec-attributes", language: .objectiveC))) == objectiveCAttributes)

        let css = SyntaxLanguage.css.syntaxVocabulary
        let stableCSSAtRules: Set<String> = ["@keyframes", "@supports"]
        let cssAtRules = Set(css.attributeWords).union(["@keyframes", "@supports"]).intersection(stableCSSAtRules)
        #expect(Set(quotedStrings(in: try generatedQueryBlock(named: "css-at-rules", language: .css))) == cssAtRules)

        let json = SyntaxLanguage.json.syntaxVocabulary
        let jsonBlock = try generatedQueryBlock(named: "json-literals", language: .json)
        for word in json.keywordWords {
            #expect(jsonBlock.contains("(\(word))"))
        }

        let tomlBlock = try generatedQueryBlock(named: "toml-literals", language: .toml)
        #expect(tomlBlock.contains("(boolean) @editor.syntax.toml.keyword"))
    }

    @Test("Theme style fallbacks map syntax vocabulary IDs")
    func themeStyleFallbacksMapSyntaxVocabularyIDs() throws {
        #expect(
            SyntaxEditorThemeStyleFallbacks.styleKeys(
                for: "xcode.syntax.keyword"
            )?.first == "editor.syntax.keyword"
        )
        #expect(
            SyntaxEditorThemeStyleFallbacks.styleKeys(
                for: "xcode.syntax.preprocessor"
            )?.first == "editor.syntax.preprocessor"
        )
        #expect(
            SyntaxEditorThemeStyleFallbacks.styleKeys(
                for: "xcode.syntax.declaration.precedencegroup"
            )?.first == "editor.syntax.declaration.type"
        )
        #expect(
            SyntaxEditorThemeStyleFallbacks.styleKeys(
                for: "xcode.syntax.definition.style"
            )?.first == "editor.syntax.identifier.type"
        )
        #expect(
            SyntaxEditorThemeStyleFallbacks.styleKeys(
                for: "xcode.syntax.entity"
            )?.first == "editor.syntax.identifier.type"
        )
        #expect(
            SyntaxEditorThemeStyleFallbacks.styleKeys(
                for: "xcode.syntax.definition.property"
            )?.first == "editor.syntax.identifier.variable"
        )
        #expect(
            SyntaxEditorHighlightTheme.semanticStyleKeys(
                for: "xcode.syntax.definition.macro",
                language: .swift
            )?.first == "editor.syntax.identifier.macro"
        )
    }

    @Test("SyntaxEditorHighlightTheme resolves built-in fonts")
    func syntaxEditorHighlightThemeFonts() {
        let theme = SyntaxEditorColorTheme.default
        let lightComment = SyntaxEditorHighlightTheme.style(
            for: "comment.doc",
            in: theme,
            language: .swift,
            appearance: .light
        )
        #expect(lightComment?.font?.family == "HelveticaNeue")
        #expect(lightComment?.font?.size == 12)

        let darkKeyword = SyntaxEditorHighlightTheme.style(
            for: "keyword.control",
            in: theme,
            language: .swift,
            appearance: .dark
        )
        #expect(darkKeyword?.font?.weight == .bold)
    }

    @Test("SyntaxEditorRangeUtilities clamps and intersects UTF-16 ranges")
    func syntaxEditorRangeUtilities() {
        let clamped = SyntaxEditorRangeUtilities.clampedRange(NSRange(location: -4, length: 20), utf16Length: 10)
        #expect(clamped == NSRange(location: 0, length: 10))

        let intersection = SyntaxEditorRangeUtilities.intersection(
            of: NSRange(location: 4, length: 6),
            and: NSRange(location: 0, length: 5)
        )
        #expect(intersection == NSRange(location: 4, length: 1))

        let lineStart = SyntaxEditorRangeUtilities.lineStartUTF16Offset(in: "a\nbc\ndef", around: 4)
        #expect(lineStart == 2)
    }

    @Test("TextMutation returns nil when text does not change")
    func textMutationNoChange() {
        #expect(TextMutation.diff(from: "body {}", to: "body {}") == nil)
    }

    @Test("TextMutation computes insertion range for newline")
    func textMutationInsertionRange() {
        let mutation = TextMutation.diff(from: "a\nb", to: "a\n\nb")
        #expect(mutation?.range == NSRange(location: 2, length: 0))
        #expect(mutation?.replacement == "\n")
    }

    @Test("TextMutation computes replacement range for comment toggle")
    func textMutationReplacementRange() {
        let mutation = TextMutation.diff(
            from: "let value = 1;\n",
            to: "// let value = 1;\n"
        )
        #expect(mutation?.range == NSRange(location: 0, length: 0))
        #expect(mutation?.replacement == "// ")
    }

    @Test("TextMutation keeps prefix attributes when applying mutation")
    func textMutationPreservesPrefixAttributes() {
        let oldText = "/* comment */\nbody {\n}"
        let newText = "/* comment */\nbody {\n    \n}"
        guard let mutation = TextMutation.diff(from: oldText, to: newText) else {
            Issue.record("Mutation should exist for changed text")
            return
        }

        let key = NSAttributedString.Key("token")
        let attributed = NSMutableAttributedString(string: oldText)
        attributed.addAttribute(key, value: "comment", range: NSRange(location: 0, length: 12))
        attributed.replaceCharacters(in: mutation.range, with: mutation.replacement)

        #expect(attributed.string == newText)
        #expect((attributed.attribute(key, at: 2, effectiveRange: nil) as? String) == "comment")
    }

    @Test("LineMetricsIndex indexes long offscreen lines")
    func lineMetricsIndexInitialLongLineWidth() {
        let source = "short\n\(String(repeating: "x", count: 120))\nmid"
        let index = LineMetricsIndex(source: source, tabWidth: 4)

        #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 120)
        #expect(index.horizontalDocumentWidth(columnWidth: 2, textContainerInset: 10, lineFragmentPadding: 5) == 260)
    }

    @Test("LineMetricsIndex updates edited line ranges without full rebuild")
    func lineMetricsIndexIncrementalEdits() {
        var source = "abc\nabcdef"
        let index = LineMetricsIndex(source: source, tabWidth: 4)
        let initialRebuildCount = index.fullRebuildCount

        func apply(_ edit: SyntaxEditorTextEdit) {
            index.apply(edits: [edit], previousSource: source)
            source = SyntaxEditorDocument.applying([edit], to: source)
        }

        #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 6)

        apply(SyntaxEditorTextEdit(range: NSRange(location: 1, length: 0), replacement: "Z"))
        #expect(source == "aZbc\nabcdef")
        #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 6)

        apply(SyntaxEditorTextEdit(range: NSRange(location: 4, length: 0), replacement: "\nwide-line"))
        #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 9)

        let maxLineRange = (source as NSString).range(of: "wide-line")
        apply(SyntaxEditorTextEdit(range: maxLineRange, replacement: "w"))
        #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 6)

        let pasteLocation = source.utf16.count
        apply(SyntaxEditorTextEdit(range: NSRange(location: pasteLocation, length: 0), replacement: "\n1234567890"))
        #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 10)
        #expect(index.fullRebuildCount == initialRebuildCount)
    }

    @Test("LineMetricsIndex does not accumulate heap entries for repeated same-width edits")
    func lineMetricsIndexKeepsMaxColumnCacheBounded() {
        var source = "a"
        let index = LineMetricsIndex(source: source, tabWidth: 4)

        for iteration in 0..<100 {
            let replacement = iteration.isMultiple(of: 2) ? "b" : "a"
            let edit = SyntaxEditorTextEdit(
                range: NSRange(location: 0, length: 1),
                replacement: replacement
            )
            index.apply(edits: [edit], previousSource: source)
            source = SyntaxEditorDocument.applying([edit], to: source)
            #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 1)
        }

        #expect(index.cachedMaxColumnEntryCountForTesting == 1)
    }

    @Test("LineMetricsIndex prunes stale heap entries below the maximum")
    func lineMetricsIndexPrunesStaleHeapEntriesBelowMaximum() {
        var source = "\(String(repeating: "x", count: 200))\nshort"
        let index = LineMetricsIndex(source: source, tabWidth: 4)

        for width in 1...80 {
            let lineBreakRange = (source as NSString).range(of: "\n")
            let lineStart = lineBreakRange.location + lineBreakRange.length
            let edit = SyntaxEditorTextEdit(
                range: NSRange(location: lineStart, length: source.utf16.count - lineStart),
                replacement: String(repeating: "y", count: width)
            )
            index.apply(edits: [edit], previousSource: source)
            source = SyntaxEditorDocument.applying([edit], to: source)

            #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 200)
        }

        #expect(index.cachedMaxColumnEntryCountForTesting == 2)
    }

    @Test("LineMetricsIndex removes trailing empty line after deleting final newline")
    func lineMetricsIndexHandlesFinalNewlineDeletion() {
        var source = "abc\n"
        let index = LineMetricsIndex(source: source, tabWidth: 4)
        let edit = SyntaxEditorTextEdit(
            range: NSRange(location: source.utf16.count - 1, length: 1),
            replacement: ""
        )

        index.apply(edits: [edit], previousSource: source)
        source = SyntaxEditorDocument.applying([edit], to: source)

        #expect(source == "abc")
        #expect(index.lineCountForTesting == 1)
        #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == 3)
    }

    @Test("LineMetricsIndex matches display column rules for tabs and Unicode")
    func lineMetricsIndexMatchesDisplayColumnRules() {
        let source = "a\tあ\u{200D}b\nplain"
        let index = LineMetricsIndex(source: source, tabWidth: 4)
        let expected = SyntaxEditorDisplayColumnUtilities.maximumColumnCount(in: source, tabWidth: 4)

        #expect(index.horizontalDocumentWidth(columnWidth: 1, textContainerInset: 0, lineFragmentPadding: 0) == CGFloat(expected))
    }

    @Test("EditorCommandEngine auto-pairs opening braces")
    func editorCommandEngineAutoPair() {
        let engine = EditorCommandEngine()
        let source = ""
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: 0, length: 0),
            replacementText: "{",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == "{}")
        #expect(result?.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("EditorCommandEngine wraps selected text with quote")
    func editorCommandEngineWrapSelection() {
        let engine = EditorCommandEngine()
        let source = "value"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: 0, length: 5),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == "\"value\"")
        #expect(result?.selectedRange == NSRange(location: 7, length: 0))
    }

    @Test("EditorCommandEngine suppresses quote auto-pair for selected text inside literals")
    func editorCommandEngineSuppressesQuoteAutoPairForSelectedTextInsideLiteral() {
        let engine = EditorCommandEngine()
        let source = "const message = \"hello\";"
        let selection = (source as NSString).range(of: "hello")
        let result = engine.transformInput(
            source: source,
            range: selection,
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine skips duplicate closing brace")
    func editorCommandEngineSkipClosingBrace() {
        let engine = EditorCommandEngine()
        let source = "{}"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: 1, length: 0),
            replacementText: "}",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == "{}")
        #expect(result?.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test("EditorCommandEngine skips existing closing brace after whitespace")
    func editorCommandEngineSkipClosingBraceAfterWhitespace() {
        let engine = EditorCommandEngine()
        let source = "{\n    \n}"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: 6, length: 0),
            replacementText: "}",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source)
        #expect(result?.selectedRange == NSRange(location: 8, length: 0))
    }

    @Test("EditorCommandEngine inserts smart newline in brace block")
    func editorCommandEngineSmartNewline() {
        let engine = EditorCommandEngine()
        let source = "{}"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: 1, length: 0),
            replacementText: "\n",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == "{\n    \n}")
        #expect(result?.selectedRange == NSRange(location: 6, length: 0))
    }

    @Test("EditorCommandEngine supports repeated smart newline transforms")
    func editorCommandEngineRepeatedSmartNewline() {
        let engine = EditorCommandEngine()
        var source = "{}"
        var selection = NSRange(location: 1, length: 0)

        for _ in 0..<3 {
            guard let result = engine.transformInput(
                source: source,
                range: selection,
                replacementText: "\n",
                language: SyntaxLanguage.javascript
            ) else {
                Issue.record("Smart newline unexpectedly returned nil")
                return
            }
            source = applying(result, to: source)
            selection = result.selectedRange
        }

        #expect(source.contains("\n"))
    }

    @Test("EditorCommandEngine outdents closing brace at line start")
    func editorCommandEngineClosingBraceOutdent() {
        let engine = EditorCommandEngine()
        let source = "    "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: 4, length: 0),
            replacementText: "}",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == "}")
        #expect(result?.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("EditorCommandEngine outdents closing brace by one tab width")
    func editorCommandEngineClosingBraceOutdentWithTabs() {
        let engine = EditorCommandEngine()
        let source = "\t\t"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: 2, length: 0),
            replacementText: "}",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == "\t}")
        #expect(result?.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test("EditorCommandEngine deletes paired symbols together")
    func editorCommandEnginePairBackspace() {
        let engine = EditorCommandEngine()
        let source = "()"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: 0, length: 1),
            replacementText: "",
            language: SyntaxLanguage.javascript,
            deletionIntent: .backward
        )

        #expect(applying(result, to: source) == "")
        #expect(result?.selectedRange == NSRange(location: 0, length: 0))
    }

    @Test("EditorCommandEngine does not pair-delete one-character selections")
    func editorCommandEngineSelectionDeleteDoesNotPairBackspace() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "{}",
            range: NSRange(location: 0, length: 1),
            replacementText: "",
            language: SyntaxLanguage.javascript
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine indents selected lines")
    func editorCommandEngineIndentSelection() {
        let engine = EditorCommandEngine()
        let source = "a\nb\n"
        let result = engine.indentSelection(
            source: source,
            selection: NSRange(location: 0, length: 3)
        )

        #expect(applying(result, to: source) == "    a\n    b\n")
    }

    @Test("EditorCommandEngine inserts tab spaces at the caret")
    func editorCommandEngineInsertTabAtCaret() {
        let engine = EditorCommandEngine()
        let source = "abcde"
        let result = engine.insertTab(
            source: source,
            selection: NSRange(location: 2, length: 0)
        )

        #expect(applying(result, to: source) == "ab  cde")
        #expect(result?.selectedRange == NSRange(location: 4, length: 0))
    }

    @Test("EditorCommandEngine inserts tab spaces after wide Unicode")
    func editorCommandEngineInsertTabAfterWideUnicode() {
        let engine = EditorCommandEngine()
        let source = "あbc"
        let result = engine.insertTab(
            source: source,
            selection: NSRange(location: "あ".utf16.count, length: 0)
        )

        #expect(applying(result, to: source) == "あ  bc")
        #expect(result?.selectedRange == NSRange(location: "あ  ".utf16.count, length: 0))
    }

    @Test("EditorCommandEngine inserts tab spaces after zero-width Unicode")
    func editorCommandEngineInsertTabAfterZeroWidthUnicode() {
        let engine = EditorCommandEngine()
        let prefix = "e\u{301}"
        let source = "\(prefix)bc"
        let result = engine.insertTab(
            source: source,
            selection: NSRange(location: prefix.utf16.count, length: 0)
        )

        #expect(applying(result, to: source) == "\(prefix)   bc")
        #expect(result?.selectedRange == NSRange(location: "\(prefix)   ".utf16.count, length: 0))
    }

    @Test("EditorCommandEngine inserts tab spaces after a ZWJ emoji cluster")
    func editorCommandEngineInsertTabAfterEmojiCluster() {
        let engine = EditorCommandEngine()
        let prefix = "👩‍💻"
        let source = "\(prefix)bc"
        let result = engine.insertTab(
            source: source,
            selection: NSRange(location: prefix.utf16.count, length: 0)
        )

        #expect(applying(result, to: source) == "\(prefix)  bc")
        #expect(result?.selectedRange == NSRange(location: "\(prefix)  ".utf16.count, length: 0))
    }

    @Test("EditorCommandEngine indents selected lines for tab range input")
    func editorCommandEngineInsertTabIndentsSelectedLines() {
        let engine = EditorCommandEngine()
        let source = "a\nb\n"
        let result = engine.insertTab(
            source: source,
            selection: NSRange(location: 0, length: 3)
        )

        #expect(applying(result, to: source) == "    a\n    b\n")
    }

    @Test("EditorCommandEngine indents trailing empty line at document end")
    func editorCommandEngineIndentTrailingEmptyLine() {
        let engine = EditorCommandEngine()
        let source = "a\n"
        let result = engine.indentSelection(
            source: source,
            selection: NSRange(location: source.utf16.count, length: 0)
        )

        #expect(applying(result, to: source) == "a\n    ")
    }

    @Test("EditorCommandEngine outdents selected lines")
    func editorCommandEngineOutdentSelection() {
        let engine = EditorCommandEngine()
        let source = "    a\n    b\n"
        let result = engine.outdentSelection(
            source: source,
            selection: NSRange(location: 0, length: 11)
        )

        #expect(applying(result, to: source) == "a\nb\n")
    }

    @Test("EditorCommandEngine keeps caret on current line when outdenting overlapping indent")
    func editorCommandEngineOutdentSelectionClampsCaretInsideRemovedIndent() {
        let engine = EditorCommandEngine()
        let source = "x\n    y"
        let result = engine.outdentSelection(
            source: source,
            selection: NSRange(location: 4, length: 0)
        )

        #expect(applying(result, to: source) == "x\ny")
        #expect(result?.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test("EditorCommandEngine toggles JavaScript line comments")
    func editorCommandEngineToggleJavaScriptComments() {
        let engine = EditorCommandEngine()
        let source = "let a = 1;\nlet b = 2;\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.javascript
        )

        #expect(applying(first, to: source) == "// let a = 1;\n// let b = 2;\n")
        let firstText = applying(first, to: source) ?? ""

        let second = engine.toggleComment(
            source: firstText,
            selection: NSRange(location: 0, length: firstText.utf16.count),
            language: SyntaxLanguage.javascript
        )

        #expect(applying(second, to: firstText) == source)
    }

    @Test("EditorCommandEngine toggles Swift line comments")
    func editorCommandEngineToggleSwiftComments() {
        let engine = EditorCommandEngine()
        let source = "let a = 1\nlet b = 2\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.swift
        )

        #expect(applying(first, to: source) == "// let a = 1\n// let b = 2\n")
        let firstText = applying(first, to: source) ?? ""

        let second = engine.toggleComment(
            source: firstText,
            selection: NSRange(location: 0, length: firstText.utf16.count),
            language: SyntaxLanguage.swift
        )

        #expect(applying(second, to: firstText) == source)
    }

    @Test("EditorCommandEngine toggles Objective-C line comments")
    func editorCommandEngineToggleObjectiveCComments() {
        let engine = EditorCommandEngine()
        let source = "NSString *name = @\"Editor\";\nreturn name;\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.objectiveC
        )

        #expect(applying(first, to: source) == "// NSString *name = @\"Editor\";\n// return name;\n")
        let firstText = applying(first, to: source) ?? ""

        let second = engine.toggleComment(
            source: firstText,
            selection: NSRange(location: 0, length: firstText.utf16.count),
            language: SyntaxLanguage.objectiveC
        )

        #expect(applying(second, to: firstText) == source)
    }

    @Test("EditorCommandEngine toggles TOML line comments")
    func editorCommandEngineToggleTOMLComments() {
        let engine = EditorCommandEngine()
        let source = "title = \"SyntaxEditorUI\"\nenabled = true\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.toml
        )

        #expect(applying(first, to: source) == "# title = \"SyntaxEditorUI\"\n# enabled = true\n")
        let firstText = applying(first, to: source) ?? ""

        let second = engine.toggleComment(
            source: firstText,
            selection: NSRange(location: 0, length: firstText.utf16.count),
            language: SyntaxLanguage.toml
        )

        #expect(applying(second, to: firstText) == source)
    }

    @Test("EditorCommandEngine toggles TOML comments without touching blank lines")
    func editorCommandEngineToggleTOMLCommentsPreservingBlankLines() {
        let engine = EditorCommandEngine()
        let source = "title = \"SyntaxEditorUI\"\n\nenabled = true\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == "# title = \"SyntaxEditorUI\"\n\n# enabled = true\n")
    }

    @Test("EditorCommandEngine toggles TOML comment for caret line")
    func editorCommandEngineToggleTOMLCommentAtCaretLine() {
        let engine = EditorCommandEngine()
        let source = "title = \"SyntaxEditorUI\"\nenabled = true\n"
        let caret = (source as NSString).range(of: "enabled").location

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: caret, length: 0),
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == "title = \"SyntaxEditorUI\"\n# enabled = true\n")
    }

    @Test("EditorCommandEngine toggles CSS block comment")
    func editorCommandEngineToggleCSSComment() {
        let engine = EditorCommandEngine()
        let source = "color: red;\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.css
        )

        #expect(applying(first, to: source)?.contains("/*") == true)
        #expect(applying(first, to: source)?.contains("*/") == true)
        let firstText = applying(first, to: source) ?? ""

        let second = engine.toggleComment(
            source: firstText,
            selection: NSRange(location: 0, length: firstText.utf16.count),
            language: SyntaxLanguage.css
        )

        #expect(applying(second, to: firstText) == source)
    }

    @Test("EditorCommandEngine does not unwrap multiple CSS comments as one block")
    func editorCommandEngineCssCommentToggleNoopForMultipleIndependentBlocks() {
        let engine = EditorCommandEngine()
        let source = "/* a */\n/* b */\n"
        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.css
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap CSS selection containing block markers")
    func editorCommandEngineCssCommentToggleNoopWhenSelectionContainsBlockMarkers() {
        let engine = EditorCommandEngine()
        let source = "color: red; /* note */\n"
        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.css
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine toggles HTML comment")
    func editorCommandEngineToggleHTMLComment() {
        let engine = EditorCommandEngine()
        let source = "<div>hello</div>\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.html
        )

        #expect(applying(first, to: source) == "<!-- <div>hello</div>\n -->")
        let firstText = applying(first, to: source) ?? ""

        let second = engine.toggleComment(
            source: firstText,
            selection: NSRange(location: 0, length: firstText.utf16.count),
            language: SyntaxLanguage.html
        )

        #expect(applying(second, to: firstText) == source)
    }

    @Test("EditorCommandEngine does not wrap HTML comments around double hyphen text")
    func editorCommandEngineDoesNotWrapHTMLCommentAroundDoubleHyphenText() {
        let engine = EditorCommandEngine()
        let source = "alpha -- beta\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap HTML comments around text ending with hyphen")
    func editorCommandEngineDoesNotWrapHTMLCommentAroundTrailingHyphenText() {
        let engine = EditorCommandEngine()
        let source = "alpha-\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine returns no-op for malformed HTML comment wrapper")
    func editorCommandEngineHTMLCommentToggleNoopForMalformedComment() {
        let engine = EditorCommandEngine()
        let source = "<!-- <div>hello</div>\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine toggles XML comment")
    func editorCommandEngineToggleXMLComment() {
        let engine = EditorCommandEngine()
        let source = "<note>hello</note>\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.xml
        )

        #expect(applying(first, to: source) == "<!-- <note>hello</note>\n -->")
        let firstText = applying(first, to: source) ?? ""

        let second = engine.toggleComment(
            source: firstText,
            selection: NSRange(location: 0, length: firstText.utf16.count),
            language: SyntaxLanguage.xml
        )

        #expect(applying(second, to: firstText) == source)
    }

    @Test("EditorCommandEngine toggles XML comment from a caret inside an element line")
    func editorCommandEngineToggleXMLCommentFromCaretInsideElementLine() {
        let engine = EditorCommandEngine()
        let source = "<note priority=\"high\">hello</note>\n"
        let caret = (source as NSString).range(of: "priority").location

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: caret, length: 0),
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<!-- <note priority=\"high\">hello</note>\n -->")
    }

    @Test("EditorCommandEngine does not wrap XML comments around double hyphen text")
    func editorCommandEngineDoesNotWrapXMLCommentAroundDoubleHyphenText() {
        let engine = EditorCommandEngine()
        let source = "alpha -- beta\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap XML comments around text ending with hyphen")
    func editorCommandEngineDoesNotWrapXMLCommentAroundTrailingHyphenText() {
        let engine = EditorCommandEngine()
        let source = "alpha-\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not toggle XML comments inside CDATA content")
    func editorCommandEngineDoesNotToggleXMLCommentInsideCDATAContent() {
        let engine = EditorCommandEngine()
        let source = """
        <![CDATA[
        alpha
        ]]>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "alpha").location,
            length: 0
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not toggle XML comments inside processing instruction payload")
    func editorCommandEngineDoesNotToggleXMLCommentInsideProcessingInstructionPayload() {
        let engine = EditorCommandEngine()
        let source = """
        <?xml-stylesheet
        href="style.xsl"
        type="text/xsl"?>
        <root/>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "href").location,
            length: 0
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not toggle XML comments inside multiline comment content")
    func editorCommandEngineDoesNotToggleXMLCommentInsideMultilineCommentContent() {
        let engine = EditorCommandEngine()
        let source = """
        <!--
        alpha
        -->
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "alpha").location,
            length: 0
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine toggles XML comments inside DTD internal subsets")
    func editorCommandEngineToggleXMLCommentInsideDTDInternalSubset() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note [
        <!ELEMENT note (#PCDATA)>
        ]>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "<!ELEMENT note (#PCDATA)>\n").location,
            length: "<!ELEMENT note (#PCDATA)>\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == """
        <!DOCTYPE note [
        <!-- <!ELEMENT note (#PCDATA)>
         -->]>
        """)
    }

    @Test("EditorCommandEngine toggles XML comments from a caret inside DTD internal subset lines")
    func editorCommandEngineToggleXMLCommentFromCaretInsideDTDInternalSubsetLine() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note [
        <!ELEMENT note (#PCDATA)>
        ]>
        """
        let caret = (source as NSString).range(of: "note (#PCDATA)").location

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: caret, length: 0),
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == """
        <!DOCTYPE note [
        <!-- <!ELEMENT note (#PCDATA)>
         -->]>
        """)
    }

    @Test("EditorCommandEngine toggles XML comments for DTD declarations containing closing text literals")
    func editorCommandEngineToggleXMLCommentForDTDDeclarationsContainingClosingTextLiterals() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note [
        <!ENTITY marker "value ]> tail">
        ]>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "<!ENTITY marker \"value ]> tail\">\n").location,
            length: "<!ENTITY marker \"value ]> tail\">\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == """
        <!DOCTYPE note [
        <!-- <!ENTITY marker "value ]> tail">
         -->]>
        """)
    }

    @Test("EditorCommandEngine does not toggle XML comments on doctype opener lines")
    func editorCommandEngineDoesNotToggleXMLCommentOnDoctypeOpenerLines() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note [
        <!ELEMENT note (#PCDATA)>
        ]>
        """

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: 0),
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine toggles standalone XML doctype lines")
    func editorCommandEngineToggleStandaloneXMLDoctypeLines() {
        let engine = EditorCommandEngine()
        let source = "<!DOCTYPE note>\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<!-- <!DOCTYPE note>\n -->")
    }

    @Test("EditorCommandEngine toggles standalone XML doctype lines with bracket characters in literals")
    func editorCommandEngineToggleStandaloneXMLDoctypeLinesWithBracketCharactersInLiterals() {
        let engine = EditorCommandEngine()
        let source = "<!DOCTYPE note SYSTEM \"foo[bar].dtd\">\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<!-- <!DOCTYPE note SYSTEM \"foo[bar].dtd\">\n -->")
    }

    @Test("EditorCommandEngine toggles standalone XML doctype lines with multiline bracket literals")
    func editorCommandEngineToggleStandaloneXMLDoctypeLinesWithMultilineBracketLiterals() {
        let engine = EditorCommandEngine()
        let source = "<!DOCTYPE note SYSTEM \"foo\n[bar].dtd\">\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<!-- <!DOCTYPE note SYSTEM \"foo\n[bar].dtd\">\n -->")
    }

    @Test("EditorCommandEngine does not toggle XML comments on doctype closing lines")
    func editorCommandEngineDoesNotToggleXMLCommentOnDoctypeClosingLines() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note [
        <!ELEMENT note (#PCDATA)>
        ]>
        """
        let closingLineLocation = (source as NSString).range(of: "]>").location

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: closingLineLocation, length: 0),
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not toggle XML comments across doctype closing delimiters")
    func editorCommandEngineDoesNotToggleXMLCommentAcrossDoctypeClosingDelimiters() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note [
        <!ELEMENT note (#PCDATA)>
        ]>
        <note/>
        """
        let start = (source as NSString).range(of: "<!ELEMENT note (#PCDATA)>\n").location
        let end = (source as NSString).range(of: "<note/>").location

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: start, length: end - start),
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not toggle XML comments across multiline doctype opener delimiters")
    func editorCommandEngineDoesNotToggleXMLCommentAcrossMultilineDoctypeOpenerDelimiters() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note SYSTEM
        "foo.dtd"
        [
        <!ELEMENT note (#PCDATA)>
        ]>
        """
        let end = (source as NSString).range(of: "<!ELEMENT note (#PCDATA)>").location

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: end),
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not toggle XML comments across conditional section opener delimiters")
    func editorCommandEngineDoesNotToggleXMLCommentAcrossConditionalSectionOpenerDelimiters() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note [
        <![
        IGNORE
        [
        <!ENTITY hidden "value">
        ]]>
        ]>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "<![\n").location,
            length: "<![\nIGNORE\n[\n<!ENTITY hidden \"value\">\n]]>\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not toggle XML comments on lines containing closing delimiters with trailing content")
    func editorCommandEngineDoesNotToggleXMLCommentOnLinesContainingClosingDelimitersWithTrailingContent() {
        let engine = EditorCommandEngine()
        let source = "<!DOCTYPE note [ <!ELEMENT note (#PCDATA)> ]> <note/>\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine toggles XML comments for multiline DTD declarations containing closing text literals")
    func editorCommandEngineToggleXMLCommentForMultilineDTDDeclarationsContainingClosingTextLiterals() {
        let engine = EditorCommandEngine()
        let source = """
        <!DOCTYPE note [
        <!ENTITY marker "value
        ]> tail">
        ]>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "<!ENTITY marker \"value\n").location,
            length: "<!ENTITY marker \"value\n]> tail\">\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == """
        <!DOCTYPE note [
        <!-- <!ENTITY marker "value
        ]> tail">
         -->]>
        """)
    }

    @Test("EditorCommandEngine delegates HTML comment toggle inside script raw text")
    func editorCommandEngineDelegatesHTMLCommentToggleInsideScriptRawText() {
        let engine = EditorCommandEngine()
        let startTag = "<script data=\"x>y\" type=\"text/javascript\">"
        let source = "\(startTag)const answer = 42;\n</script>"
        let selection = NSRange(location: startTag.utf16.count, length: "const answer = 42;\n".utf16.count)

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == "\(startTag)// const answer = 42;\n</script>")
    }

    @Test("EditorCommandEngine delegates HTML comment toggle inside self-closing script raw text")
    func editorCommandEngineDelegatesHTMLCommentToggleInsideSelfClosingScriptRawText() {
        let engine = EditorCommandEngine()
        let source = "<script/>const answer = 42;\n</script>"
        let selection = NSRange(
            location: "<script/>".utf16.count,
            length: "const answer = 42;\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == "<script/>// const answer = 42;\n</script>")
    }

    @Test("EditorCommandEngine keeps script raw text active for unquoted attribute values ending with slash")
    func editorCommandEngineKeepsScriptRawTextActiveForUnquotedAttributeValuesEndingWithSlash() {
        let engine = EditorCommandEngine()
        let startTag = "<script src=/assets/>"
        let source = "\(startTag)const answer = 42;\n</script>"
        let selection = NSRange(location: startTag.utf16.count, length: "const answer = 42;\n".utf16.count)

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == "\(startTag)// const answer = 42;\n</script>")
    }

    @Test("EditorCommandEngine keeps script raw text active for general unquoted attribute values with slash")
    func editorCommandEngineKeepsScriptRawTextActiveForGeneralUnquotedAttributeValuesWithSlash() {
        let engine = EditorCommandEngine()
        let startTag = "<script src=https://example.com/assets/>"
        let source = "\(startTag)const answer = 42;\n</script>"
        let selection = NSRange(location: startTag.utf16.count, length: "const answer = 42;\n".utf16.count)

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == "\(startTag)// const answer = 42;\n</script>")
    }

    @Test("EditorCommandEngine does not delegate unsupported script types to JavaScript rules")
    func editorCommandEngineDoesNotDelegateUnsupportedScriptTypesToJavaScriptRules() {
        let engine = EditorCommandEngine()
        let source = """
        <script type="application/json">{"enabled": true}
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "{\"enabled\": true}\n").location,
            length: "{\"enabled\": true}\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap EOF caret inside unterminated unsupported script raw text")
    func editorCommandEngineDoesNotWrapEOFCaretInsideUnterminatedUnsupportedScriptRawText() {
        let engine = EditorCommandEngine()
        let source = #"<script type="application/json">{"enabled": true}"#

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: source.utf16.count, length: 0),
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not delegate unsupported script types when other attributes contain angle brackets")
    func editorCommandEngineDoesNotDelegateUnsupportedScriptTypesWithAngleBracketAttributeText() {
        let engine = EditorCommandEngine()
        let source = """
        <script data="<" type="application/json">{"enabled": true}
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "{\"enabled\": true}\n").location,
            length: "{\"enabled\": true}\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine ignores raw-text-like attribute text when toggling HTML comments")
    func editorCommandEngineIgnoresRawTextLikeAttributeTextWhenTogglingHTMLComments() {
        let engine = EditorCommandEngine()
        let source = """
        <div data='<script type="application/json">'>Container</div>
        <span>Hello</span>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "<span>Hello</span>\n").location,
            length: "<span>Hello</span>\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source)?.contains("<!-- <span>Hello</span>") == true)
    }

    @Test("EditorCommandEngine does not delegate non-CSS style types to CSS rules")
    func editorCommandEngineDoesNotDelegateNonCSSTypesToCSSRules() {
        let engine = EditorCommandEngine()
        let source = """
        <style type="text/plain">body { color: red; }
        </style>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "body { color: red; }\n").location,
            length: "body { color: red; }\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap long selections that cross unsupported script raw text")
    func editorCommandEngineDoesNotWrapLongSelectionsCrossingUnsupportedScriptRawText() {
        let engine = EditorCommandEngine()
        let prefix = String(repeating: "A", count: 80)
        let suffix = String(repeating: "B", count: 240)
        let source = """
        <div>\(prefix)</div>
        <script type="application/json">{"enabled": true}</script>
        <div>\(suffix)</div>
        """

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: (source as NSString).length),
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap partial script closing tags with HTML comments")
    func editorCommandEngineDoesNotWrapPartialScriptClosingTagsWithHTMLComments() {
        let engine = EditorCommandEngine()
        let source = "<script>const answer = 42;\n</scr"
        let selection = NSRange(
            location: (source as NSString).range(of: "</scr").location,
            length: "</scr".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap completed script closing tag names without terminator")
    func editorCommandEngineDoesNotWrapCompletedScriptClosingTagNamesWithoutTerminator() {
        let engine = EditorCommandEngine()
        let source = "<script>const answer = 42;\n</script"
        let selection = NSRange(
            location: (source as NSString).range(of: "</script").location,
            length: "</script".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap full script closing tags with HTML comments")
    func editorCommandEngineDoesNotWrapFullScriptClosingTagsWithHTMLComments() {
        let engine = EditorCommandEngine()
        let source = "<script>const answer = 42;\n</script>"
        let selection = NSRange(
            location: (source as NSString).range(of: "</script>").location,
            length: "</script>".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap mixed selections that cross into script raw text")
    func editorCommandEngineDoesNotWrapMixedSelectionsCrossingIntoScriptRawText() {
        let engine = EditorCommandEngine()
        let source = """
        <div>before</div>
        <script>const answer = 42;
        </script>
        """
        let selectionEnd = (source as NSString).range(of: "const answer").location + "const answer".utf16.count
        let selection = NSRange(location: 0, length: selectionEnd)

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine delegates HTML comment toggle inside style raw text")
    func editorCommandEngineDelegatesHTMLCommentToggleInsideStyleRawText() {
        let engine = EditorCommandEngine()
        let source = "<style>body { color: red; }\n</style>"
        let selection = NSRange(location: 7, length: "body { color: red; }\n".utf16.count)

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == "<style>/* body { color: red; }\n */</style>")
    }

    @Test("EditorCommandEngine keeps style raw text open past repeated literal closing tag text")
    func editorCommandEngineKeepsStyleRawTextOpenPastRepeatedLiteralClosingTagText() {
        let engine = EditorCommandEngine()
        let source = """
        <style>body::before { content: "</style> </style>"; }
        body { color: red; }
        </style>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "body { color: red; }\n").location,
            length: "body { color: red; }\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <style>body::before { content: "</style> </style>"; }
        /* body { color: red; }
         */</style>
        """)
    }

    @Test("EditorCommandEngine keeps style raw text open past repeated literal closing tag text inside comments")
    func editorCommandEngineKeepsStyleRawTextOpenPastRepeatedLiteralClosingTagTextInsideComments() {
        let engine = EditorCommandEngine()
        let source = """
        <style>/* </style> </style> */
        body { color: red; }
        </style>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "body { color: red; }\n").location,
            length: "body { color: red; }\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <style>/* </style> </style> */
        /* body { color: red; }
         */</style>
        """)
    }

    @Test("EditorCommandEngine keeps style raw text open past malformed closing tag syntax")
    func editorCommandEngineKeepsStyleRawTextOpenPastMalformedClosingTagSyntax() {
        let engine = EditorCommandEngine()
        let source = """
        <style>body::before { content: none; }
        </style foo>
        body { color: red; }
        </style>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "body { color: red; }\n").location,
            length: "body { color: red; }\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <style>body::before { content: none; }
        </style foo>
        /* body { color: red; }
         */</style>
        """)
    }

    @Test("EditorCommandEngine does not fall back to HTML comments for blank script lines")
    func editorCommandEngineDoesNotFallbackToHTMLCommentsForBlankScriptLines() {
        let engine = EditorCommandEngine()
        let source = "<script>\n</script>"
        let selection = NSRange(location: 8, length: 0)

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not fall back to HTML comments for invalid CSS raw text selections")
    func editorCommandEngineDoesNotFallbackToHTMLCommentsForInvalidCSSRawTextSelections() {
        let engine = EditorCommandEngine()
        let source = "<style>body { color: red; /* note */ }\n</style>"
        let selection = NSRange(location: 7, length: "body { color: red; /* note */ }\n".utf16.count)

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine keeps script raw text open past scripted suffix text")
    func editorCommandEngineKeepsScriptRawTextOpenPastScriptedSuffixText() {
        let engine = EditorCommandEngine()
        let source = """
        <script>const marker = \"</scripted>\";
        const answer = 42;
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "const answer = 42;\n").location,
            length: "const answer = 42;\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <script>const marker = \"</scripted>\";
        // const answer = 42;
        </script>
        """)
    }

    @Test("EditorCommandEngine keeps script raw text open past literal closing tag text")
    func editorCommandEngineKeepsScriptRawTextOpenPastLiteralClosingTagText() {
        let engine = EditorCommandEngine()
        let source = """
        <script>const marker = \"</script>\";
        const answer = 42;
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "const answer = 42;\n").location,
            length: "const answer = 42;\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <script>const marker = \"</script>\";
        // const answer = 42;
        </script>
        """)
    }

    @Test("EditorCommandEngine keeps script raw text open past malformed closing tag syntax")
    func editorCommandEngineKeepsScriptRawTextOpenPastMalformedClosingTagSyntax() {
        let engine = EditorCommandEngine()
        let source = """
        <script>const marker = 1;
        </script foo>
        const answer = 42;
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "const answer = 42;\n").location,
            length: "const answer = 42;\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <script>const marker = 1;
        </script foo>
        // const answer = 42;
        </script>
        """)
    }

    @Test("EditorCommandEngine keeps script raw text open inside legacy HTML wrapper")
    func editorCommandEngineKeepsScriptRawTextOpenInsideLegacyHTMLWrapper() {
        let engine = EditorCommandEngine()
        let source = """
        <script><!--
        </script>
        const answer = 42;
        //-->
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "const answer = 42;\n").location,
            length: "const answer = 42;\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <script><!--
        </script>
        // const answer = 42;
        //-->
        </script>
        """)
    }

    @Test("EditorCommandEngine does not rewrite legacy HTML wrapper selections")
    func editorCommandEngineDoesNotRewriteLegacyHTMLWrapperSelections() {
        let engine = EditorCommandEngine()
        let source = """
        <script><!--
        const answer = 42;
        //-->
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "<!--").location,
            length: "<!--\nconst answer = 42;\n//-->".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not rewrite legacy HTML wrapper carets")
    func editorCommandEngineDoesNotRewriteLegacyHTMLWrapperCarets() {
        let engine = EditorCommandEngine()
        let source = """
        <script><!--
        const answer = 42;
        //-->
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "<!--").location,
            length: 0
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not wrap long selections that cross legacy script wrapper lines")
    func editorCommandEngineDoesNotWrapLongSelectionsCrossingLegacyScriptWrapperLines() {
        let engine = EditorCommandEngine()
        let prefix = String(repeating: "A", count: 80)
        let suffix = String(repeating: "B", count: 240)
        let source = """
        <div>\(prefix)</div>
        <script>
        <!--
        const answer = 42;
        //-->
        </script>
        <div>\(suffix)</div>
        """

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: (source as NSString).length),
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine keeps script raw text open past commented wrapper-like markers")
    func editorCommandEngineKeepsScriptRawTextOpenPastCommentedWrapperLikeMarkers() {
        let engine = EditorCommandEngine()
        let source = """
        <script>/*
        <!--
        */
        const answer = 42;
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "const answer = 42;\n").location,
            length: "const answer = 42;\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <script>/*
        <!--
        */
        // const answer = 42;
        </script>
        """)
    }

    @Test("EditorCommandEngine does not treat wrapper-like lines inside comments as legacy wrappers")
    func editorCommandEngineDoesNotTreatWrapperLikeCommentLinesAsLegacyWrappers() {
        let engine = EditorCommandEngine()
        let source = """
        <script>const html = `
        <!--
        `;
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "<!--").location,
            length: 0
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <script>const html = `
        // <!--
        `;
        </script>
        """)
    }

    @Test("EditorCommandEngine ignores commented-out raw text tags when toggling HTML comments")
    func editorCommandEngineIgnoresCommentedOutRawTextTagsWhenTogglingHTMLComments() {
        let engine = EditorCommandEngine()
        let source = """
        <!-- <script type="application/json"> -->
        <div>hello</div>
        """

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(
                location: (source as NSString).range(of: "<div>").location,
                length: "<div>hello</div>\n".utf16.count
            ),
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <!-- <script type="application/json"> -->
        <!-- <div>hello</div> -->
        """)
    }

    @Test("EditorCommandEngine keeps script raw text open past literal comment marker text")
    func editorCommandEngineKeepsScriptRawTextOpenPastLiteralCommentMarkerText() {
        let engine = EditorCommandEngine()
        let source = """
        <script>const marker = "<!--";
        const answer = 42;
        </script>
        """
        let selection = NSRange(
            location: (source as NSString).range(of: "const answer = 42;\n").location,
            length: "const answer = 42;\n".utf16.count
        )

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == """
        <script>const marker = "<!--";
        // const answer = 42;
        </script>
        """)
    }

    @Test("EditorCommandEngine restores HTML attribute pairing after literal comment marker text")
    func editorCommandEngineRestoresHTMLAttributePairingAfterLiteralCommentMarkerText() {
        let engine = EditorCommandEngine()
        let source = """
        <script>const marker = "<!--";
        </script>
        <div class=
        """
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine returns no-op for JSON comments")
    func editorCommandEngineJsonCommentNoop() {
        let engine = EditorCommandEngine()
        let result = engine.toggleComment(
            source: "{\"a\":1}",
            selection: NSRange(location: 0, length: 7),
            language: SyntaxLanguage.json
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs quote after URL literal prefix")
    func editorCommandEngineAutoPairQuoteAfterURLLiteral() {
        let engine = EditorCommandEngine()
        let source = "const url = \"https://a\"; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses Swift quote auto-pair inside line comment")
    func editorCommandEngineSuppressSwiftQuoteAutoPairInsideLineComment() {
        let engine = EditorCommandEngine()
        let source = "// note: "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.swift
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs Objective-C quote in code")
    func editorCommandEngineAutoPairObjectiveCQuoteInCode() {
        let engine = EditorCommandEngine()
        let source = "NSString *value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.objectiveC
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses Objective-C quote auto-pair inside line comment")
    func editorCommandEngineSuppressObjectiveCQuoteAutoPairInsideLineComment() {
        let engine = EditorCommandEngine()
        let source = "// note: "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.objectiveC
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses Objective-C quote auto-pair inside block comment")
    func editorCommandEngineSuppressObjectiveCQuoteAutoPairInsideBlockComment() {
        let engine = EditorCommandEngine()
        let source = "/* note: "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.objectiveC
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses Objective-C quote auto-pair inside Objective-C string literal")
    func editorCommandEngineSuppressObjectiveCQuoteAutoPairInsideNSStringLiteral() {
        let engine = EditorCommandEngine()
        let source = "NSString *value = @\"hello"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.objectiveC
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses Objective-C quote auto-pair inside character literal")
    func editorCommandEngineSuppressObjectiveCQuoteAutoPairInsideCharacterLiteral() {
        let engine = EditorCommandEngine()
        let source = "char marker = 'x"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.objectiveC
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs TOML quote in code")
    func editorCommandEngineAutoPairTOMLQuoteInCode() {
        let engine = EditorCommandEngine()
        let source = "name = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses TOML quote auto-pair inside comment")
    func editorCommandEngineSuppressTOMLQuoteAutoPairInsideComment() {
        let engine = EditorCommandEngine()
        let source = "# note: "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses TOML quote auto-pair inside basic string")
    func editorCommandEngineSuppressTOMLQuoteAutoPairInsideBasicString() {
        let engine = EditorCommandEngine()
        let source = "name = \"Syntax"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses TOML apostrophe auto-pair inside literal string")
    func editorCommandEngineSuppressTOMLApostropheAutoPairInsideLiteralString() {
        let engine = EditorCommandEngine()
        let source = "path = 'Sources"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "'",
            language: SyntaxLanguage.toml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses TOML quote auto-pair inside multiline basic string")
    func editorCommandEngineSuppressTOMLQuoteAutoPairInsideMultilineBasicString() {
        let engine = EditorCommandEngine()
        let source = "description = \"\"\"\nhello\n"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses TOML apostrophe auto-pair inside multiline literal string")
    func editorCommandEngineSuppressTOMLApostropheAutoPairInsideMultilineLiteralString() {
        let engine = EditorCommandEngine()
        let source = "description = '''\nhello\n"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "'",
            language: SyntaxLanguage.toml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine does not treat hash inside TOML string as comment")
    func editorCommandEngineDoesNotTreatHashInsideTOMLStringAsComment() {
        let engine = EditorCommandEngine()
        let source = "name = \"value # still string\"\nnext = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine recognizes closed TOML multiline basic strings ending with quote")
    func editorCommandEngineRecognizesClosedTOMLMultilineBasicStringEndingWithQuote() {
        let engine = EditorCommandEngine()
        let source = "description = \"\"\"\nvalue\"\"\"\"\nnext = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine recognizes closed TOML multiline literal strings ending with apostrophe")
    func editorCommandEngineRecognizesClosedTOMLMultilineLiteralStringEndingWithApostrophe() {
        let engine = EditorCommandEngine()
        let source = "description = '''\nvalue''''\nnext = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "'",
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == source + "''")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine supports typing TOML multiline basic string delimiters")
    func editorCommandEngineSupportsTypingTOMLMultilineBasicStringDelimiters() {
        let engine = EditorCommandEngine()
        let source = "description = "

        let first = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )
        let second = engine.transformInput(
            source: applying(first, to: source) ?? "",
            range: first?.selectedRange ?? NSRange(location: 0, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )
        let firstText = applying(first, to: source) ?? ""
        let secondText = applying(second, to: firstText) ?? ""
        let third = engine.transformInput(
            source: secondText,
            range: second?.selectedRange ?? NSRange(location: 0, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(applying(first, to: source) == source + "\"\"")
        #expect(secondText == source + "\"\"")
        #expect(applying(third, to: secondText) == source + "\"\"\"")
        #expect(third?.selectedRange == NSRange(location: source.utf16.count + 3, length: 0))
    }

    @Test("EditorCommandEngine supports typing TOML multiline literal string delimiters")
    func editorCommandEngineSupportsTypingTOMLMultilineLiteralStringDelimiters() {
        let engine = EditorCommandEngine()
        let source = "description = "

        let first = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "'",
            language: SyntaxLanguage.toml
        )
        let second = engine.transformInput(
            source: applying(first, to: source) ?? "",
            range: first?.selectedRange ?? NSRange(location: 0, length: 0),
            replacementText: "'",
            language: SyntaxLanguage.toml
        )
        let firstText = applying(first, to: source) ?? ""
        let secondText = applying(second, to: firstText) ?? ""
        let third = engine.transformInput(
            source: secondText,
            range: second?.selectedRange ?? NSRange(location: 0, length: 0),
            replacementText: "'",
            language: SyntaxLanguage.toml
        )

        #expect(applying(first, to: source) == source + "''")
        #expect(secondText == source + "''")
        #expect(applying(third, to: secondText) == source + "'''")
        #expect(third?.selectedRange == NSRange(location: source.utf16.count + 3, length: 0))
    }

    @Test("EditorCommandEngine invalidates pending TOML multiline delimiter after unrelated command")
    func editorCommandEngineInvalidatesPendingTOMLMultilineDelimiterAfterUnrelatedCommand() {
        let engine = EditorCommandEngine()
        let source = "description = "

        let first = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )
        let second = engine.transformInput(
            source: applying(first, to: source) ?? "",
            range: first?.selectedRange ?? NSRange(location: 0, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )
        let firstText = applying(first, to: source) ?? ""
        let secondText = applying(second, to: firstText) ?? ""

        _ = engine.indentSelection(
            source: "value\n",
            selection: NSRange(location: 0, length: 0)
        )

        let third = engine.transformInput(
            source: secondText,
            range: second?.selectedRange ?? NSRange(location: 0, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(applying(third, to: secondText) == source + "\"\"\"\"")
        #expect(third?.selectedRange == NSRange(location: source.utf16.count + 3, length: 0))
    }

    @Test("EditorCommandEngine invalidates pending TOML multiline delimiter on explicit reset")
    func editorCommandEngineInvalidatesPendingTOMLMultilineDelimiterOnExplicitReset() {
        let engine = EditorCommandEngine()
        let source = "description = "

        let first = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )
        let second = engine.transformInput(
            source: applying(first, to: source) ?? "",
            range: first?.selectedRange ?? NSRange(location: 0, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )
        let firstText = applying(first, to: source) ?? ""
        let secondText = applying(second, to: firstText) ?? ""

        engine.invalidateTransientState()

        let third = engine.transformInput(
            source: secondText,
            range: second?.selectedRange ?? NSRange(location: 0, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(applying(third, to: secondText) == source + "\"\"\"\"")
        #expect(third?.selectedRange == NSRange(location: source.utf16.count + 3, length: 0))
    }

    @Test("EditorCommandEngine does not keep TOML basic strings open across line breaks")
    func editorCommandEngineDoesNotKeepTOMLBasicStringsOpenAcrossLineBreaks() {
        let engine = EditorCommandEngine()
        let source = "name = \"foo\nnext = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine does not keep TOML escaped basic strings open across line breaks")
    func editorCommandEngineDoesNotKeepTOMLEscapedBasicStringsOpenAcrossLineBreaks() {
        let engine = EditorCommandEngine()
        let source = "name = \"foo\\\nnext = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine does not keep TOML literal strings open across line breaks")
    func editorCommandEngineDoesNotKeepTOMLLiteralStringsOpenAcrossLineBreaks() {
        let engine = EditorCommandEngine()
        let source = "name = 'foo\nnext = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "'",
            language: SyntaxLanguage.toml
        )

        #expect(applying(result, to: source) == source + "''")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs HTML quote in attribute assignment")
    func editorCommandEngineAutoPairHTMLQuoteInAttributeAssignment() {
        let engine = EditorCommandEngine()
        let source = "<div class="
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == "<div class=\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses HTML quote auto-pair in comment")
    func editorCommandEngineSuppressHTMLQuoteAutoPairInComment() {
        let engine = EditorCommandEngine()
        let source = "<!-- note "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses HTML quote auto-pair in comment text containing equals")
    func editorCommandEngineSuppressHTMLQuoteAutoPairInCommentWithEquals() {
        let engine = EditorCommandEngine()
        let source = "<!-- data=foo "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses HTML quote auto-pair in attribute value")
    func editorCommandEngineSuppressHTMLQuoteAutoPairInAttributeValue() {
        let engine = EditorCommandEngine()
        let source = "<div class=\"hero"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses HTML quote auto-pair in text node")
    func editorCommandEngineSuppressHTMLQuoteAutoPairInTextNode() {
        let engine = EditorCommandEngine()
        let source = "<div>Hello "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs HTML quote inside script raw text")
    func editorCommandEngineAutoPairHTMLQuoteInScriptRawText() {
        let engine = EditorCommandEngine()
        let prefix = "<script>const message = "
        let source = prefix + "</script>"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: prefix.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == prefix + "\"\"" + "</script>")
        #expect(result?.selectedRange == NSRange(location: prefix.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses HTML quote auto-pair inside script string")
    func editorCommandEngineSuppressHTMLQuoteAutoPairInsideScriptString() {
        let engine = EditorCommandEngine()
        let prefix = "<script>const message = \"hello"
        let source = prefix + "</script>"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: prefix.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs HTML quote inside style raw text")
    func editorCommandEngineAutoPairHTMLQuoteInStyleRawText() {
        let engine = EditorCommandEngine()
        let prefix = "<style>body::before { content: "
        let source = prefix + "</style>"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: prefix.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(applying(result, to: source) == prefix + "\"\"" + "</style>")
        #expect(result?.selectedRange == NSRange(location: prefix.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses HTML quote auto-pair inside style string")
    func editorCommandEngineSuppressHTMLQuoteAutoPairInsideStyleString() {
        let engine = EditorCommandEngine()
        let prefix = "<style>body::before { content: \"hello"
        let source = prefix + "</style>"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: prefix.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.html
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses HTML quote auto-pair in raw text closing tags")
    func editorCommandEngineSuppressHTMLQuoteAutoPairInRawTextClosingTags() {
        let engine = EditorCommandEngine()
        let cases = [
            "<script>const answer = 42;</script>",
            "<style>body::before { content: none; }</style>",
        ]

        for source in cases {
            let nsSource = source as NSString
            let closingTagRange = nsSource.range(of: "</")
            let result = engine.transformInput(
                source: source,
                range: NSRange(location: closingTagRange.location + closingTagRange.length, length: 0),
                replacementText: "\"",
                language: SyntaxLanguage.html
            )

            #expect(result == nil)
        }
    }

    @Test("EditorCommandEngine auto-pairs XML quote in attribute assignment")
    func editorCommandEngineAutoPairXMLQuoteInAttributeAssignment() {
        let engine = EditorCommandEngine()
        let source = "<node attr="
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<node attr=\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs XML quote in processing instruction attribute assignment")
    func editorCommandEngineAutoPairXMLQuoteInProcessingInstructionAttributeAssignment() {
        let engine = EditorCommandEngine()
        let source = "<?xml-stylesheet href="
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<?xml-stylesheet href=\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs XML quote in DTD declaration literals")
    func editorCommandEngineAutoPairXMLQuoteInDTDDeclarationLiterals() {
        let engine = EditorCommandEngine()
        let cases = [
            "<!ENTITY foo ",
            "<!ENTITY logo SYSTEM ",
            "<!DOCTYPE note PUBLIC ",
        ]

        for source in cases {
            let result = engine.transformInput(
                source: source,
                range: NSRange(location: source.utf16.count, length: 0),
                replacementText: "\"",
                language: SyntaxLanguage.xml
            )

            #expect(applying(result, to: source) == source + "\"\"")
            #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
        }
    }

    @Test("EditorCommandEngine does not auto-pair XML quote after parameter entity markers")
    func editorCommandEngineDoesNotAutoPairXMLQuoteAfterParameterEntityMarkers() {
        let engine = EditorCommandEngine()
        let source = "<!ENTITY % "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs XML quote for non-ASCII tag names")
    func editorCommandEngineAutoPairXMLQuoteForNonASCIINameStart() {
        let engine = EditorCommandEngine()
        let source = "<élement attr="
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<élement attr=\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs XML quote for extender tag names")
    func editorCommandEngineAutoPairXMLQuoteForXMLNameExtenders() {
        let engine = EditorCommandEngine()
        let source = "<a·b attr="
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<a·b attr=\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs XML quote for supplementary-plane tag names")
    func editorCommandEngineAutoPairXMLQuoteForSupplementaryPlaneNameStart() {
        let engine = EditorCommandEngine()
        let source = "<𐐷node attr="
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<𐐷node attr=\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs XML quote for extender DTD names")
    func editorCommandEngineAutoPairXMLQuoteForXMLNameExtenderDTDNames() {
        let engine = EditorCommandEngine()
        let source = "<!ENTITY foo·bar SYSTEM "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs XML quote for supplementary-plane DTD names")
    func editorCommandEngineAutoPairXMLQuoteForSupplementaryPlaneDTDNames() {
        let engine = EditorCommandEngine()
        let source = "<!ENTITY 𐐷foo "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(applying(result, to: source) == "<!ENTITY 𐐷foo \"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine does not auto-pair XML quote after DTD attribute types")
    func editorCommandEngineDoesNotAutoPairXMLQuoteAfterDTDAttributeTypes() {
        let engine = EditorCommandEngine()
        let source = "<!ATTLIST note category CDATA "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses XML quote auto-pair in comment")
    func editorCommandEngineSuppressXMLQuoteAutoPairInComment() {
        let engine = EditorCommandEngine()
        let source = "<!-- note "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses XML quote auto-pair in text node")
    func editorCommandEngineSuppressXMLQuoteAutoPairInTextNode() {
        let engine = EditorCommandEngine()
        let source = "<node>Hello "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses XML quote auto-pair in attribute value")
    func editorCommandEngineSuppressXMLQuoteAutoPairInAttributeValue() {
        let engine = EditorCommandEngine()
        let source = "<node attr=\"value"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.xml
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs Swift quote after URL literal prefix")
    func editorCommandEngineAutoPairSwiftQuoteAfterURLLiteral() {
        let engine = EditorCommandEngine()
        let source = "let url = \"https://a\"; let value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.swift
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses Swift quote auto-pair inside multiline string")
    func editorCommandEngineSuppressSwiftQuoteAutoPairInsideMultilineString() {
        let engine = EditorCommandEngine()
        let source = "let text = \"\"\"\nhello "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.swift
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs Swift quote inside interpolation expression")
    func editorCommandEngineAutoPairSwiftQuoteInsideInterpolationExpression() {
        let engine = EditorCommandEngine()
        let source = "let value = \"foo \\(bar + "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.swift
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses Swift quote auto-pair after escaped interpolation marker")
    func editorCommandEngineSuppressSwiftQuoteAutoPairAfterEscapedInterpolationMarker() {
        let engine = EditorCommandEngine()
        let source = "let value = \"foo \\\\("
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.swift
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine keeps raw multiline Swift string open until hash-delimited close")
    func editorCommandEngineKeepsRawMultilineSwiftStringOpenUntilHashClose() {
        let engine = EditorCommandEngine()
        let source = "let text = #\"\"\"\ninner \"\"\" still open "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.swift
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs CSS quote after comment marker inside string literal")
    func editorCommandEngineAutoPairCssQuoteAfterCommentMarkerInsideStringLiteral() {
        let engine = EditorCommandEngine()
        let source = "content: \"/*\"; color: "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.css
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after apostrophe in double-quoted literal")
    func editorCommandEngineAutoPairQuoteAfterApostropheInDoubleQuotedLiteral() {
        let engine = EditorCommandEngine()
        let source = "const msg = \"don't\"; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after block-comment marker in literal")
    func editorCommandEngineAutoPairQuoteAfterBlockCommentMarkerLiteral() {
        let engine = EditorCommandEngine()
        let source = "const marker = \"/*\"; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after template literal comment-like text")
    func editorCommandEngineAutoPairQuoteAfterTemplateLiteralCommentLikeText() {
        let engine = EditorCommandEngine()
        let source = "const x = \"*/\"; const t = `/*`; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after URL-like regex literal")
    func editorCommandEngineAutoPairQuoteAfterURLRegexLiteral() {
        let engine = EditorCommandEngine()
        let source = "const re = /https?:\\/\\//; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex char class with leading bracket")
    func editorCommandEngineAutoPairQuoteAfterRegexCharClassWithLeadingBracket() {
        let engine = EditorCommandEngine()
        let source = "const re = /[]//]/; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after division with keyword-like property name")
    func editorCommandEngineAutoPairQuoteAfterDivisionWithKeywordLikeProperty() {
        let engine = EditorCommandEngine()
        let source = "const ratio = obj.return / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after optional-chaining keyword-like property division")
    func editorCommandEngineAutoPairQuoteAfterOptionalChainingKeywordLikePropertyDivision() {
        let engine = EditorCommandEngine()
        let source = "const ratio = obj?.return / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after divide-assignment expression")
    func editorCommandEngineAutoPairQuoteAfterDivideAssignment() {
        let engine = EditorCommandEngine()
        let source = "let x = 4; x /= 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex literal beginning with equals")
    func editorCommandEngineAutoPairQuoteAfterRegexLiteralBeginningWithEquals() {
        let engine = EditorCommandEngine()
        let source = "const re = /=/; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex-division expression")
    func editorCommandEngineAutoPairQuoteAfterRegexDivisionExpression() {
        let engine = EditorCommandEngine()
        let source = "let x = /foo/ / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses quote auto-pair inside regex after line comment line")
    func editorCommandEngineSuppressQuoteAutoPairInsideRegexAfterLineCommentLine() {
        let engine = EditorCommandEngine()
        let source = "// note\n/ab"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine suppresses quote auto-pair inside regex after else branch")
    func editorCommandEngineSuppressQuoteAutoPairInsideRegexAfterElseBranch() {
        let engine = EditorCommandEngine()
        let source = "if (ready) {} else /ab"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs quote after regex following if condition")
    func editorCommandEngineAutoPairQuoteAfterRegexFollowingIfCondition() {
        let engine = EditorCommandEngine()
        let source = "if (ok) /[//]/.test(path); const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex following if condition with block comment")
    func editorCommandEngineAutoPairQuoteAfterRegexFollowingIfConditionWithBlockComment() {
        let engine = EditorCommandEngine()
        let source = "if /*c*/ (ok) /[//]/.test(path); const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex following if condition with line comment")
    func editorCommandEngineAutoPairQuoteAfterRegexFollowingIfConditionWithLineComment() {
        let engine = EditorCommandEngine()
        let source = "if // note\n(ok) /[//]/.test(path); const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex following return with inline block comment")
    func editorCommandEngineAutoPairQuoteAfterRegexFollowingReturnWithInlineBlockComment() {
        let engine = EditorCommandEngine()
        let source = "return /* note */ /[//]/.test(path); const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex following return with inline line comment")
    func editorCommandEngineAutoPairQuoteAfterRegexFollowingReturnWithInlineLineComment() {
        let engine = EditorCommandEngine()
        let source = "return // note\n/[//]/.test(path); const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex following if condition with escaped template backtick")
    func editorCommandEngineAutoPairQuoteAfterRegexFollowingIfConditionWithEscapedTemplateBacktick() {
        let engine = EditorCommandEngine()
        let source = "if (`a\\`b`) /[//]/.test(path); const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex following if condition with template text brace")
    func editorCommandEngineAutoPairQuoteAfterRegexFollowingIfConditionWithTemplateTextBrace() {
        let engine = EditorCommandEngine()
        let source = "if (`x}y`) /[//]/.test(path); const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex following if condition with nested template placeholder braces")
    func editorCommandEngineAutoPairQuoteAfterRegexFollowingIfConditionWithNestedTemplatePlaceholderBraces() {
        let engine = EditorCommandEngine()
        let source = "if (`${(function(){ return 1 })}`) /[//]/.test(path); const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after member-call division with keyword-like name")
    func editorCommandEngineAutoPairQuoteAfterMemberCallDivisionWithKeywordLikeName() {
        let engine = EditorCommandEngine()
        let source = "const ratio = obj.if(1) / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after division in object literal keyword-like key")
    func editorCommandEngineAutoPairQuoteAfterDivisionInObjectLiteralKeywordLikeKey() {
        let engine = EditorCommandEngine()
        let source = "const o = { if: (value) / 2 }; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after division following string literal")
    func editorCommandEngineAutoPairQuoteAfterDivisionFollowingStringLiteral() {
        let engine = EditorCommandEngine()
        let source = "const ratio = \"a\" / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after line-broken division expression")
    func editorCommandEngineAutoPairQuoteAfterLineBrokenDivisionExpression() {
        let engine = EditorCommandEngine()
        let source = "let x = 1\n / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after division with Unicode identifier")
    func editorCommandEngineAutoPairQuoteAfterDivisionWithUnicodeIdentifier() {
        let engine = EditorCommandEngine()
        let source = "const result = \u{5024} / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after division with non-BMP identifier")
    func editorCommandEngineAutoPairQuoteAfterDivisionWithNonBMPIdentifier() {
        let engine = EditorCommandEngine()
        let source = "const result = \u{10437} / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after division with trailing decimal dot")
    func editorCommandEngineAutoPairQuoteAfterDivisionWithTrailingDecimalDot() {
        let engine = EditorCommandEngine()
        let source = "const x = 1. / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex char class with escaped first content")
    func editorCommandEngineAutoPairQuoteAfterRegexCharClassWithEscapedFirstContent() {
        let engine = EditorCommandEngine()
        let source = "const re = /[\\s]/; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after regex char class containing bracket literal")
    func editorCommandEngineAutoPairQuoteAfterRegexCharClassContainingBracketLiteral() {
        let engine = EditorCommandEngine()
        let source = "const re = /[[]/; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine auto-pairs quote after divide expression following postfix increment")
    func editorCommandEngineAutoPairQuoteAfterDivideExpressionFollowingPostfixIncrement() {
        let engine = EditorCommandEngine()
        let source = "let i = 1; i++ / 2; const value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine suppresses quote auto-pair in template placeholder comments")
    func editorCommandEngineSuppressQuoteAutoPairInTemplatePlaceholderComment() {
        let engine = EditorCommandEngine()
        let source = "const tpl = `${value // comment"
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs quote inside template placeholder expressions")
    func editorCommandEngineAutoPairQuoteInsideTemplatePlaceholderExpression() {
        let engine = EditorCommandEngine()
        let source = "const tpl = `${value + "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: SyntaxLanguage.javascript
        )

        #expect(applying(result, to: source) == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("BracketMatcher returns matching pair around caret")
    func bracketMatcherReturnsPair() {
        let source = "function test() { return [1]; }"
        let nsSource = source as NSString
        let braceLocation = nsSource.range(of: "{").location

        let ranges = BracketMatcher.matchedRanges(
            in: source,
            caretUTF16Offset: braceLocation + 1
        )

        #expect(ranges.count == 2)
        #expect(ranges[0].length == 1)
        #expect(ranges[1].length == 1)
    }

}

private let sharedSyntaxHighlighterEngine = SyntaxHighlighterEngine()

@Suite("SyntaxHighlighterEngine", .serialized)
struct SyntaxHighlighterEngineTests {
    @Test("SyntaxHighlighterEngine returns no tokens for empty source")
    func highlighterReturnsNoTokensForEmptySource() async {
        let engine = sharedSyntaxHighlighterEngine
        let tokens = await engine.render(source: "", language: SyntaxLanguage.javascript)
        #expect(tokens.isEmpty)
    }

    @Test("SyntaxHighlighterEngine produces highlight tokens for lightweight direct languages")
    func highlighterProducesTokensForLightweightDirectLanguages() async {
        let engine = sharedSyntaxHighlighterEngine
        let cases: [(language: SyntaxLanguage, source: String)] = [
            (SyntaxLanguage.css, "body { color: red; }"),
            (SyntaxLanguage.javascript, "const answer = 42;"),
            (SyntaxLanguage.json, "{\"enabled\": true, \"count\": 1}"),
            (SyntaxLanguage.swift, "let answer = 42"),
        ]

        for testCase in cases {
            let tokens = await engine.render(source: testCase.source, language: testCase.language)
            #expect(tokens.isEmpty == false)
            #expect(tokens.allSatisfy { $0.range.length > 0 })
        }
    }

    @Test("SyntaxHighlighterEngine emits canonical reference sample captures")
    func highlighterEmitsCanonicalReferenceSampleCaptures() async throws {
        let engine = sharedSyntaxHighlighterEngine
        let cases: [(language: SyntaxLanguage, filename: String)] = [
            (.css, "Reference.css"),
            (.html, "Reference.html"),
            (.javascript, "Reference.js"),
            (.json, "Reference.json"),
            (.objectiveC, "Reference.m"),
            (.swift, "Reference.swift"),
            (.toml, "Reference.toml"),
            (.xml, "Reference.xml"),
        ]

        for testCase in cases {
            let source = try referenceSampleText(named: testCase.filename)
            let tokens = await engine.render(source: source, language: testCase.language)
            let nonCanonicalCaptures = tokens
                .filter { $0.rawCaptureName.hasPrefix("editor.syntax.") == false }
                .map(\.rawCaptureName)
                .sorted()
            #expect(
                nonCanonicalCaptures.isEmpty,
                "Non-canonical captures for \(testCase.language.rawValue): \(nonCanonicalCaptures.joined(separator: ", "))"
            )

            let unresolvedTokens = tokens
                .filter {
                    SyntaxEditorHighlightTheme.semanticStyleKeys(
                        for: $0.syntaxID,
                        language: $0.language ?? testCase.language
                    ) == nil
                }
                .map { "\($0.rawCaptureName)->\($0.syntaxID.rawValue)" }
                .sorted()

            #expect(
                unresolvedTokens.isEmpty,
                "Unresolved source syntax IDs for \(testCase.language.rawValue): \(unresolvedTokens.joined(separator: ", "))"
            )
        }
    }

    @Test("SyntaxHighlighterEngine classifies Swift reference sample without project symbol resolution")
    func highlighterClassifiesSwiftReferenceSampleWithoutProjectSymbolResolution() async throws {
        let engine = sharedSyntaxHighlighterEngine
        let source = try referenceSampleText(named: "Reference.swift")
        let tokens = await engine.render(source: source, language: SyntaxLanguage.swift)

        let expectations: [(text: String, syntaxID: EditorSourceSyntaxID, styleKey: String, occurrence: String)] = [
            ("MARK:", "mark", "editor.syntax.mark", "// MARK: - Reference highlighting surface"),
            ("Foundation", "plain", "editor.syntax.plain", "import Foundation"),
            ("Observation", "plain", "editor.syntax.plain", "import Observation"),
            ("Reference highlighting surface", "comment", "editor.syntax.comment", "// MARK: - Reference highlighting surface"),
            ("Renders a compact reference model.", "comment.doc", "editor.syntax.comment.doc", "/// Renders a compact reference model."),
            ("Parameters", "comment.doc.keyword", "editor.syntax.comment.doc.keyword", "/// - Parameters:"),
            ("https://example.invalid/reference.", "url", "editor.syntax.url", "https://example.invalid/reference."),
            ("associatedtype", "keyword", "editor.syntax.keyword", "associatedtype Output"),
            ("ReferenceID", "declaration.other", "editor.syntax.declaration.other", "typealias ReferenceID = UUID"),
            ("macro", "keyword", "editor.syntax.keyword", "macro localized"),
            ("localized", "identifier.macro", "editor.syntax.identifier.macro", "macro localized"),
            ("attached", "keyword", "editor.syntax.keyword", "@attached(member"),
            ("member", "plain", "editor.syntax.plain", "@attached(member"),
            ("names", "plain", "editor.syntax.plain", "names: named(CodingKeys)"),
            ("named", "plain", "editor.syntax.plain", "names: named(CodingKeys)"),
            ("CodingKeys", "plain", "editor.syntax.plain", "names: named(CodingKeys)"),
            ("conformances", "plain", "editor.syntax.plain", "conformances: Codable"),
            ("Codable", "plain", "editor.syntax.plain", "conformances: Codable"),
            ("module", "plain", "editor.syntax.plain", #"#externalMacro(module: "ReferenceMacros""#),
            ("type", "plain", "editor.syntax.plain", #"type: "AutoCodableMacro""#),
            ("freestanding", "keyword", "editor.syntax.keyword", "@freestanding(expression)"),
            ("propertyWrapper", "keyword", "editor.syntax.keyword", "@propertyWrapper"),
            ("precedencegroup", "keyword", "editor.syntax.keyword", "precedencegroup ReferencePrecedence"),
            ("ReferencePrecedence", "declaration.type", "editor.syntax.declaration.type", "precedencegroup ReferencePrecedence"),
            ("associativity", "keyword", "editor.syntax.keyword", "associativity: left"),
            ("left", "keyword", "editor.syntax.keyword", "associativity: left"),
            ("higherThan", "keyword", "editor.syntax.keyword", "higherThan: AdditionPrecedence"),
            ("AdditionPrecedence", "identifier.type.system", "editor.syntax.identifier.type.system", "higherThan: AdditionPrecedence"),
            ("assignment", "keyword", "editor.syntax.keyword", "assignment: false"),
            ("infix", "keyword", "editor.syntax.keyword", "infix operator <+>"),
            ("init", "keyword", "editor.syntax.keyword", "init(wrappedValue: Value"),
            ("ReferenceStore", "declaration.type", "editor.syntax.declaration.type", "final class ReferenceStore"),
            ("OpenReferenceBase", "identifier.type.system", "editor.syntax.identifier.type.system", "OpenReferenceBase, @unchecked"),
            ("ReferenceRenderable", "identifier.type.system", "editor.syntax.identifier.type.system", "any ReferenceRenderable"),
            ("ReferenceID", "identifier.type.system", "editor.syntax.identifier.type.system", "Item<ReferenceID>"),
            ("UUID", "identifier.type.system", "editor.syntax.identifier.type.system", "typealias ReferenceID = UUID"),
            ("Value", "identifier.type.system", "editor.syntax.identifier.type.system", "Clamped<Value: Comparable>"),
            ("ID", "identifier.type.system", "editor.syntax.identifier.type.system", "struct Item<ID: Hashable>"),
            ("load", "identifier.function.system", "editor.syntax.identifier.function.system", "try await load().map"),
            ("min", "identifier.function.system", "editor.syntax.identifier.function.system", "min(max"),
            ("items", "plain", "editor.syntax.plain", "items.first"),
            ("ready", "plain", "editor.syntax.plain", "state: State = .ready"),
            ("rawValue", "identifier.variable.system", "editor.syntax.identifier.variable.system", "state.rawValue"),
            ("@", "identifier.type.system", "editor.syntax.identifier.type.system", "@AutoCodable"),
            ("AutoCodable", "identifier.type.system", "editor.syntax.identifier.type.system", "@AutoCodable"),
            ("Observable", "identifier.type.system", "editor.syntax.identifier.type.system", "@Observable"),
            ("Clamped", "identifier.type.system", "editor.syntax.identifier.type.system", "@Clamped(0...globalLimit)"),
            ("sourceLocation", "identifier.macro.system", "editor.syntax.identifier.macro.system", "#sourceLocation(file:"),
            ("wrappedValue", "plain", "editor.syntax.plain", "max(wrappedValue"),
            ("range", "plain", "editor.syntax.plain", "range.lowerBound"),
            ("rows", "plain", "editor.syntax.plain", "{ rows }"),
            ("platform", "plain", "editor.syntax.plain", #"let platform = "iOS""#),
            ("=", "plain", "editor.syntax.plain", "progress = 42"),
            ("->", "plain", "editor.syntax.plain", "render() async throws -> [String]"),
            ("<+>", "plain", "editor.syntax.plain", "infix operator <+>"),
            ("#if", "preprocessor", "editor.syntax.preprocessor", "#if os(iOS)"),
            ("iOS", "preprocessor", "editor.syntax.preprocessor", "#if os(iOS)"),
            ("#available", "keyword", "editor.syntax.keyword", "if #available(macOS"),
            ("self", "keyword", "editor.syntax.keyword", "self.items = value.items"),
            ("Any", "keyword", "editor.syntax.keyword", "sourceLocationCheck: Any?"),
            ("nil", "keyword", "editor.syntax.keyword", "Any? = nil"),
            ("false", "keyword", "editor.syntax.keyword", "assignment: false"),
            ("item-(?<number>\\d+)-(?<kind>[A-Z]+)", "string", "editor.syntax.string", #"let pattern = #/item-(?<number>\d+)-(?<kind>[A-Z]+)/#"#),
            ("42", "number", "editor.syntax.number", "progress = 42"),
            ("reference.title", "string", "editor.syntax.string", #"#localized("reference.title")"#),
            ("AutoCodable", "identifier.macro", "editor.syntax.identifier.macro", "macro AutoCodable()"),
        ]

        for expectation in expectations {
            let snapshot = try semanticSnapshot(
                in: tokens,
                source: source,
                text: expectation.text,
                syntaxID: expectation.syntaxID,
                language: .swift,
                inOccurrenceOf: expectation.occurrence
            )
            #expect(snapshot.styleKeys.first == expectation.styleKey)
        }

        let effectiveExpectations: [(text: String, syntaxID: EditorSourceSyntaxID, styleKey: String, occurrence: String)] = [
            ("isolated", "keyword", "editor.syntax.keyword", "isolated deinit"),
            ("defer", "keyword", "editor.syntax.keyword", "defer { state = .ready }"),
            ("#if", "preprocessor", "editor.syntax.preprocessor", "#if os(iOS)"),
            ("iOS", "preprocessor", "editor.syntax.preprocessor", "#if os(iOS)"),
            ("macOS", "preprocessor", "editor.syntax.preprocessor", "#elseif os(macOS)"),
            ("#else", "preprocessor", "editor.syntax.preprocessor", "#else"),
            ("#endif", "preprocessor", "editor.syntax.preprocessor", "#endif"),
            ("swift", "preprocessor", "editor.syntax.preprocessor", "#if swift(>=5.9)"),
            (">=", "preprocessor", "editor.syntax.preprocessor", "#if swift(>=5.9)"),
            ("5.9", "preprocessor", "editor.syntax.preprocessor", "#if swift(>=5.9)"),
            ("&&", "preprocessor", "editor.syntax.preprocessor", "&& compiler(>=6.0)"),
            ("compiler", "preprocessor", "editor.syntax.preprocessor", "&& compiler(>=6.0)"),
            ("6.0", "preprocessor", "editor.syntax.preprocessor", "&& compiler(>=6.0)"),
            ("#if", "preprocessor", "editor.syntax.preprocessor", "#if canImport(UIKit"),
            ("#", "keyword", "editor.syntax.keyword", "if #available(macOS"),
            ("#available", "keyword", "editor.syntax.keyword", "if #available(macOS"),
        ]

        for expectation in effectiveExpectations {
            let snapshot = try effectiveSemanticSnapshot(
                in: tokens,
                source: source,
                text: expectation.text,
                syntaxID: expectation.syntaxID,
                language: .swift,
                inOccurrenceOf: expectation.occurrence
            )
            #expect(snapshot.syntaxID == expectation.syntaxID)
            #expect(snapshot.styleKeys.first == expectation.styleKey)
        }

        #expect(syntaxIDs(
            in: tokens,
            source: source,
            text: "@",
            inOccurrenceOf: "@attached(member"
        ).last == .keyword)

        let zeroLengthTokens = tokens.filter { $0.range.length == 0 }
        if zeroLengthTokens.isEmpty == false {
            let nsSource = source as NSString
            let details = zeroLengthTokens.map { token in
                "\(token.range.location):\(nsSource.substring(with: token.range)):\(token.rawCaptureName)"
            }
            Issue.record("Zero-length tokens: \(details.joined(separator: ", "))")
        }
        #expect(zeroLengthTokens.isEmpty)
    }

    @Test("SyntaxHighlighterEngine classifies Swift directive condition operators")
    func highlighterClassifiesSwiftDirectiveConditionOperators() async throws {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        #if !DEBUG
        let mode = "release"
        #elseif canImport(UIKit, _version: 17.0)
        let mode = "versioned"
        #elseif swift(>=5.9) && compiler(>=6.0)
        let mode = "modern"
        #endif
        """
        let tokens = await engine.render(source: source, language: SyntaxLanguage.swift)

        let expectations: [(text: String, syntaxID: EditorSourceSyntaxID, styleKey: String, occurrence: String)] = [
            ("#if", "preprocessor", "editor.syntax.preprocessor", "#if !DEBUG"),
            ("!", "preprocessor", "editor.syntax.preprocessor", "#if !DEBUG"),
            ("DEBUG", "preprocessor", "editor.syntax.preprocessor", "#if !DEBUG"),
            ("#elseif", "preprocessor", "editor.syntax.preprocessor", "#elseif canImport(UIKit"),
            ("canImport", "preprocessor", "editor.syntax.preprocessor", "#elseif canImport(UIKit"),
            ("_version", "preprocessor", "editor.syntax.preprocessor", "_version: 17.0"),
            (":", "preprocessor", "editor.syntax.preprocessor", "_version: 17.0"),
            ("17.0", "preprocessor", "editor.syntax.preprocessor", "_version: 17.0"),
            ("#elseif", "preprocessor", "editor.syntax.preprocessor", "#elseif swift(>=5.9)"),
            (">=", "preprocessor", "editor.syntax.preprocessor", "#elseif swift(>=5.9)"),
            ("5.9", "preprocessor", "editor.syntax.preprocessor", "#elseif swift(>=5.9)"),
            ("&&", "preprocessor", "editor.syntax.preprocessor", "&& compiler(>=6.0)"),
            ("6.0", "preprocessor", "editor.syntax.preprocessor", "&& compiler(>=6.0)"),
            ("#endif", "preprocessor", "editor.syntax.preprocessor", "#endif"),
        ]

        for expectation in expectations {
            let snapshot = try effectiveSemanticSnapshot(
                in: tokens,
                source: source,
                text: expectation.text,
                syntaxID: expectation.syntaxID,
                language: .swift,
                inOccurrenceOf: expectation.occurrence
            )
            #expect(snapshot.syntaxID == expectation.syntaxID)
            #expect(snapshot.styleKeys.first == expectation.styleKey)
        }
    }

    @Test("SyntaxHighlighterEngine keeps contextual Swift keywords as identifiers")
    func highlighterKeepsContextualSwiftKeywordsAsIdentifiers() async throws {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        func contextualNames() -> Int {
            let async = 1
            let get = 2
            let left = 3
            let `defer` = 4
            return async + get + left + `defer`
        }

        struct KeywordMembers {
            var `defer`: Int
        }

        func read(_ value: KeywordMembers) -> Int {
            value.defer
        }

        precedencegroup ContextualPrecedence {
            associativity: left
            higherThan: AdditionPrecedence
            assignment: false
        }
        """
        let tokens = await engine.render(source: source, language: SyntaxLanguage.swift)

        for (text, occurrence) in [
            ("async", "let async = 1"),
            ("get", "let get = 2"),
            ("left", "let left = 3"),
            ("defer", "let `defer` = 4"),
            ("defer", "value.defer"),
        ] {
            let ids = syntaxIDs(
                in: tokens,
                source: source,
                text: text,
                inOccurrenceOf: occurrence
            )
            #expect(ids.contains(.keyword) == false)
            #expect(ids.contains(.plain))
        }

        let precedenceLeft = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "left",
            syntaxID: "keyword",
            language: .swift,
            inOccurrenceOf: "associativity: left"
        )
        #expect(precedenceLeft.styleKeys.first == "editor.syntax.keyword")
    }

    @Test("SyntaxHighlighterEngine leaves Swift current-file references unsplit from external references")
    func highlighterLeavesSwiftCurrentFileReferencesUnsplitFromExternalReferences() async throws {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        struct Collision {
            let id: String

            init(id: String) {
                self.id = id
            }

            func copy() -> String {
                return id
            }
        }
        """
        let tokens = await engine.render(source: source, language: SyntaxLanguage.swift)

        let memberID = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "id",
            syntaxID: "identifier.variable.system",
            language: .swift,
            inOccurrenceOf: "self.id = id"
        )
        #expect(memberID.styleKeys.first == "editor.syntax.identifier.variable.system")

        let propertyID = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "id",
            syntaxID: "plain",
            language: .swift,
            inOccurrenceOf: "return id"
        )
        #expect(propertyID.styleKeys.first == "editor.syntax.plain")
    }

    @Test("SyntaxHighlighterEngine does not duplicate Swift semantic overlays during incremental updates")
    func highlighterKeepsSwiftSemanticOverlaysStableAcrossIncrementalUpdates() async throws {
        let source = try referenceSampleText(named: "Reference.swift")
        let updatedSource = source.replacingOccurrences(
            of: "Reference highlighting surface",
            with: "Reference highlighting surface updated"
        )
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.swift)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.swift,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.swift)

        #expect(incremental.tokens == full.tokens)
        #expect(Set(incremental.tokens.map { "\($0.range.location):\($0.range.length):\($0.rawCaptureName)" }).count == incremental.tokens.count)
    }

    @Test("SyntaxHighlighterEngine keeps Swift comment overlays in large comment ranges")
    func highlighterKeepsSwiftCommentOverlaysInLargeCommentRanges() async {
        let lines = (0..<400).map { index in
            switch index {
            case 24:
                return "// MARK: - Batched paste surface"
            case 120:
                return "/// - Warning: See https://example.invalid/paste/\(index)."
            default:
                return "/// Documentation line \(index)"
            }
        }
        let source = lines.joined(separator: "\n")
        let nsSource = source as NSString
        let tokens = await SyntaxHighlighterEngine().render(source: source, language: SyntaxLanguage.swift)

        let markRange = nsSource.range(of: "MARK:")
        let warningRange = nsSource.range(of: "Warning:")
        let urlRange = nsSource.range(of: "https://example.invalid/paste/120.")

        #expect(tokens.contains { tokenIntersects($0, range: markRange, syntaxID: .mark, language: .swift) })
        #expect(tokens.contains { tokenIntersects($0, range: warningRange, syntaxID: .documentationCommentKeyword, language: .swift) })
        #expect(tokens.contains { tokenIntersects($0, range: urlRange, syntaxID: .url, language: .swift) })
    }

    @Test("SyntaxHighlighterEngine emits semantic CSS captures for the reference sample")
    func highlighterEmitsSemanticCSSCapturesForReferenceSample() async throws {
        let engine = sharedSyntaxHighlighterEngine
        let source = try referenceSampleText(named: "Reference.css")
        let tokens = await engine.render(source: source, language: SyntaxLanguage.css)

        let elementSelector = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "body",
            syntaxID: "declaration.other",
            language: .css
        )
        let classSelector = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "page",
            syntaxID: "declaration.other",
            language: .css
        )
        let idSelector = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "hero",
            syntaxID: "declaration.other",
            language: .css
        )
        let property = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "min-height",
            syntaxID: "keyword",
            language: .css
        )
        let customProperty = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "--brand-accent",
            syntaxID: "plain",
            language: .css
        )
        let function = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "linear-gradient",
            syntaxID: "plain",
            language: .css
        )
        let attributeValue = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "\"page\"",
            syntaxID: "string",
            language: .css
        )
        let attributeName = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "aria-current",
            syntaxID: "plain",
            language: .css,
            inOccurrenceOf: #"nav a[aria-current="page"]"#
        )
        let childCombinator = try semanticSnapshot(
            in: tokens,
            source: source,
            text: ">",
            syntaxID: "plain",
            language: .css,
            inOccurrenceOf: "main > section"
        )
        let rgbaFunction = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "rgba",
            syntaxID: "keyword",
            language: .css
        )
        let repeatFunction = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "repeat",
            syntaxID: "keyword",
            language: .css
        )
        let supportsAtRule = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "@supports",
            syntaxID: "declaration.other",
            language: .css
        )
        let supportsFeature = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "backdrop-filter",
            syntaxID: "plain",
            language: .css,
            inOccurrenceOf: "@supports (backdrop-filter: blur(12px))"
        )
        let mediaFeature = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "min-width",
            syntaxID: "keyword",
            language: .css
        )
        let keyframesAtRule = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "@keyframes",
            syntaxID: "declaration.other",
            language: .css
        )
        let keyframesName = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "reveal",
            syntaxID: "declaration.other",
            language: .css
        )
        let atRule = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "@media",
            syntaxID: "keyword",
            language: .css
        )
        let unit = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "vh",
            syntaxID: "keyword",
            language: .css
        )

        #expect(elementSelector.styleKeys.first == "editor.syntax.declaration.other")
        #expect(classSelector.styleKeys.first == "editor.syntax.declaration.other")
        #expect(idSelector.styleKeys.first == "editor.syntax.declaration.other")
        #expect(property.styleKeys.first == "editor.syntax.keyword")
        #expect(customProperty.styleKeys.first == "editor.syntax.plain")
        #expect(function.styleKeys.first == "editor.syntax.plain")
        #expect(attributeValue.text == "\"page\"")
        #expect(attributeValue.styleKeys.first == "editor.syntax.string")
        #expect(attributeName.styleKeys.first == "editor.syntax.plain")
        #expect(childCombinator.styleKeys.first == "editor.syntax.plain")
        #expect(rgbaFunction.styleKeys.first == "editor.syntax.keyword")
        #expect(repeatFunction.styleKeys.first == "editor.syntax.keyword")
        #expect(supportsAtRule.styleKeys.first == "editor.syntax.declaration.other")
        #expect(supportsFeature.styleKeys.first == "editor.syntax.plain")
        #expect(mediaFeature.styleKeys.first == "editor.syntax.keyword")
        #expect(keyframesAtRule.styleKeys.first == "editor.syntax.declaration.other")
        #expect(keyframesName.styleKeys.first == "editor.syntax.declaration.other")
        #expect(atRule.styleKeys.first == "editor.syntax.keyword")
        #expect(unit.styleKeys.first == "editor.syntax.keyword")
        let theme = SyntaxEditorColorTheme.default.resolved(for: .css, appearance: .dark)
        #expect(classSelector.resolvedStyle.foreground == elementSelector.resolvedStyle.foreground)
        #expect(idSelector.resolvedStyle.foreground == elementSelector.resolvedStyle.foreground)
        #expect(childCombinator.resolvedStyle.foreground == theme.base.foreground)
        #expect(rgbaFunction.resolvedStyle.foreground == theme.keyword.foreground)
        #expect(repeatFunction.resolvedStyle.foreground == theme.keyword.foreground)
        #expect(supportsAtRule.resolvedStyle.foreground == elementSelector.resolvedStyle.foreground)
        #expect(supportsFeature.resolvedStyle.foreground == theme.base.foreground)
        #expect(mediaFeature.resolvedStyle.foreground == property.resolvedStyle.foreground)
        #expect(keyframesAtRule.resolvedStyle.foreground == elementSelector.resolvedStyle.foreground)
        #expect(keyframesName.resolvedStyle.foreground == elementSelector.resolvedStyle.foreground)
        #expect(function.resolvedStyle.foreground == theme.base.foreground)
        #expect(tokens.allSatisfy { $0.range.length > 0 })
    }

    @Test("SyntaxHighlighterEngine emits semantic HTML and injected captures for the reference sample")
    func highlighterEmitsSemanticHTMLCapturesForReferenceSample() async throws {
        let engine = sharedSyntaxHighlighterEngine
        let source = try referenceSampleText(named: "Reference.html")
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)

        let doctype = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "<!DOCTYPE html>",
            syntaxID: "keyword",
            language: .html
        )
        let tag = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "main",
            syntaxID: "keyword",
            language: .html
        )
        let attribute = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "data-state",
            syntaxID: "attribute",
            language: .html
        )
        let attributeValue = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "\"ready\"",
            syntaxID: "string",
            language: .html
        )
        let bracket = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "<",
            syntaxID: "keyword",
            language: .html,
            inOccurrenceOf: #"<main class="page" id="hero">"#
        )
        let embeddedCSSProperty = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "margin",
            syntaxID: "keyword",
            language: .html,
            inOccurrenceOf: "margin: 0;"
        )
        let embeddedCSSColor = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "#007aff",
            syntaxID: "number",
            language: .html
        )
        let embeddedCSSAttributeValue = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "\"page\"",
            syntaxID: "string",
            language: .html,
            inOccurrenceOf: #"nav a[aria-current="page"]"#
        )
        let embeddedCSS = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "--brand-accent",
            syntaxID: "plain",
            language: .html
        )
        let embeddedJavaScript = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "const",
            syntaxID: "keyword",
            language: .html
        )

        #expect(doctype.styleKeys.first == "editor.syntax.keyword")
        #expect(tag.styleKeys.first == "editor.syntax.keyword")
        #expect(attribute.styleKeys.first == "editor.syntax.attribute")
        #expect(attributeValue.styleKeys.first == "editor.syntax.string")
        #expect(bracket.styleKeys.first == "editor.syntax.keyword")
        #expect(embeddedCSSProperty.styleKeys.first == "editor.syntax.keyword")
        #expect(embeddedCSSColor.styleKeys.first == "editor.syntax.number")
        #expect(embeddedCSSAttributeValue.text == "\"page\"")
        #expect(embeddedCSSAttributeValue.styleKeys.first == "editor.syntax.string")
        #expect(embeddedCSS.styleKeys.first == "editor.syntax.plain")
        #expect(embeddedJavaScript.styleKeys.first == "editor.syntax.keyword")
        let nsSource = source as NSString
        #expect(tokens.contains {
            $0.syntaxID == .string
                && $0.language == .html
                && nsSource.substring(with: $0.range) == "\"ready\""
        })
        let theme = SyntaxEditorColorTheme.default.resolved(for: .html, appearance: .dark)
        #expect(bracket.resolvedStyle.foreground == theme.keyword.foreground)
        #expect(embeddedCSSProperty.resolvedStyle.foreground == theme.keyword.foreground)
        #expect(embeddedCSSColor.resolvedStyle.foreground == theme.number.foreground)
        #expect(tokens.allSatisfy { $0.range.length > 0 })
    }

    @Test("SyntaxHighlighterEngine is stable for repeated renders")
    func highlighterRepeatedRenderStability() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = "const value = 42; const message = 'ok';"

        let first = await engine.render(source: source, language: SyntaxLanguage.javascript)
        let second = await engine.render(source: source, language: SyntaxLanguage.javascript)

        #expect(first.isEmpty == false)
        #expect(first.count == second.count)
    }

    @Test("SyntaxHighlighterEngine incrementally updates JavaScript like a full reset")
    func highlighterIncrementallyUpdatesJavaScript() async throws {
        let source = "const value = 42;\nconst message = 'ok';"
        let updatedSource = "const value = 42;\nlet message = 'ok';"
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.javascript)

        #expect(incremental.tokens == full.tokens)
        #expect(incremental.refreshRange.location <= mutation.range.location)
    }

    @Test("SyntaxHighlighterEngine queries full touched lines for partial token edits")
    func highlighterIncrementallyRefreshesPartialTokenEdits() async throws {
        let source = "const value = 42;\nconst message = value;"
        let updatedSource = "const label = 42;\nconst message = value;"
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.javascript)

        #expect(incremental.tokens == full.tokens)
        #expect(incremental.refreshRange.length < updatedSource.utf16.count)
    }

    @Test("SyntaxHighlighterEngine re-queries expanded JavaScript template coverage")
    func highlighterIncrementallyRefreshesExpandedTemplateCoverage() async throws {
        let source = "const message = `${first}-${second}-${third}`;"
        let updatedSource = "const message = `${first}-${secondValue}-${third}`;"
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.javascript)
        let nsSource = updatedSource as NSString
        let firstRange = nsSource.range(of: "first")
        let thirdRange = nsSource.range(of: "third")

        #expect(incremental.tokens == full.tokens)
        #expect(full.tokens.contains {
            SyntaxEditorRangeUtilities.intersection(of: $0.range, and: firstRange).length > 0
        })
        #expect(incremental.tokens.contains {
            SyntaxEditorRangeUtilities.intersection(of: $0.range, and: firstRange).length > 0
        })
        #expect(full.tokens.contains {
            SyntaxEditorRangeUtilities.intersection(of: $0.range, and: thirdRange).length > 0
        })
        #expect(incremental.tokens.contains {
            SyntaxEditorRangeUtilities.intersection(of: $0.range, and: thirdRange).length > 0
        })
    }

    @Test("SyntaxHighlighterEngine repaints dropped JavaScript comment captures")
    func highlighterRepaintsDroppedCommentCaptureExtents() async throws {
        let source = "/* comment */\nconst value = 1;"
        let updatedSource = "* comment */\nconst value = 1;"
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.javascript)
        let oldCommentExtent = (updatedSource as NSString).range(of: "* comment */")

        #expect(incremental.tokens == full.tokens)
        #expect(
            SyntaxEditorRangeUtilities.intersection(
                of: incremental.refreshRange,
                and: oldCommentExtent
            ) == oldCommentExtent
        )
    }

    @Test("SyntaxHighlighterEngine keeps incremental refresh ranges local")
    func highlighterIncrementalRefreshRangeStaysLocal() async throws {
        let prefix = (0..<400)
            .map { "const value\($0) = \($0);" }
            .joined(separator: "\n")
        let source = "\(prefix)\nconst tail = 1;"
        let updatedSource = "\(prefix)\nlet tail = 2;"
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.javascript)

        #expect(incremental.tokens == full.tokens)
        #expect(incremental.refreshRange.length < updatedSource.utf16.count / 10)
    }

    @Test("SyntaxHighlighterEngine incrementally updates HTML injected languages")
    func highlighterIncrementallyUpdatesHTMLInjections() async throws {
        let source = """
        <style>body { color: red; }</style>
        <script>const answer = 42;</script>
        """
        let updatedSource = """
        <style>body { color: red; }</style>
        <script>let answer = 43;</script>
        """
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.html)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.html,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.html)
        let nsSource = updatedSource as NSString
        let stylePropertyRange = nsSource.range(of: "color")
        let scriptKeywordRange = nsSource.range(of: "let")

        #expect(incremental.tokens == full.tokens)
        #expect(incremental.tokens.contains {
            tokenIntersects($0, range: stylePropertyRange, syntaxID: .keyword, language: .css)
        })
        #expect(incremental.tokens.contains {
            tokenIntersects($0, range: scriptKeywordRange, syntaxID: .keyword, language: .javascript)
        })
    }

    @Test("SyntaxHighlighterEngine falls back when HTML tag edits can change injections")
    func highlighterResetsForHTMLInjectionBoundaryEdits() async throws {
        let source = "<script>const answer = 42;</script>"
        let updatedSource = "<style>const answer = 42;</script>"
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.html)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.html,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.html)

        #expect(mutation.range == NSRange(location: 2, length: 5))
        #expect(incremental.refreshRange == NSRange(location: 0, length: updatedSource.utf16.count))
        #expect(highlightTokensMatch(incremental.tokens, full.tokens))
    }

    @Test("SyntaxHighlighterEngine handles emoji and newline incremental edit ranges")
    func highlighterIncrementalEditHandlesEmojiAndNewlines() async throws {
        let source = """
        const label = "😀";
        let value = 1;
        """
        let updatedSource = """
        const label = "😀";
        let newer = 2;
        const done = true;
        """
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        let incremental = await incrementalEngine.update(
            previousSource: source,
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.javascript)
        let sourceLength = updatedSource.utf16.count

        #expect(highlightTokensMatch(incremental.tokens, full.tokens))
        #expect(incremental.tokens.allSatisfy { token in
            token.range.location >= 0 &&
                token.range.length > 0 &&
                token.range.upperBound <= sourceLength
            })
    }

    @Test("SyntaxHighlighterEngine keeps incremental state after deleting a line break")
    func highlighterIncrementalEditHandlesDeletedLineBreakFollowedByEdit() async throws {
        let source = "const first = 1;\nconst second = 2;\nconst third = 3;"
        let mergedSource = "const first = 1;const second = 2;\nconst third = 3;"
        let updatedSource = "const first = 1;let second = 2;\nconst third = 3;"
        let deleteLineBreak = try #require(TextMutation.diff(from: source, to: mergedSource))
        let editMergedLine = try #require(TextMutation.diff(from: mergedSource, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        _ = await incrementalEngine.update(
            previousSource: source,
            source: mergedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(deleteLineBreak)
        )
        let incremental = await incrementalEngine.update(
            previousSource: mergedSource,
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(editMergedLine)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.javascript)

        #expect(highlightTokensMatch(incremental.tokens, full.tokens))
    }

    @Test("SyntaxHighlighterEngine keeps incremental state after deleting a final line break")
    func highlighterIncrementalEditHandlesDeletedFinalLineBreakFollowedByEdit() async throws {
        let source = "const first = 1;\n"
        let mergedSource = "const first = 1;"
        let updatedSource = "const first = 1; const second = 2;"
        let deleteLineBreak = try #require(TextMutation.diff(from: source, to: mergedSource))
        let appendStatement = try #require(TextMutation.diff(from: mergedSource, to: updatedSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        _ = await incrementalEngine.update(
            previousSource: source,
            source: mergedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(deleteLineBreak)
        )
        let incremental = await incrementalEngine.update(
            previousSource: mergedSource,
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(appendStatement)
        )
        let full = await fullEngine.reset(source: updatedSource, language: SyntaxLanguage.javascript)

        #expect(highlightTokensMatch(incremental.tokens, full.tokens))
    }

    @Test("SyntaxHighlighterEngine keeps incremental state with carriage-return separators")
    func highlighterIncrementalEditHandlesCarriageReturnSeparators() async throws {
        let source = "const first = 1;\rconst second = 2;"
        let updatedAfterCR = "const first = 1;\rlet second = 2;"
        let finalSource = "let first = 1;\rlet second = 2;"
        let editAfterCR = try #require(TextMutation.diff(from: source, to: updatedAfterCR))
        let editBeforeCR = try #require(TextMutation.diff(from: updatedAfterCR, to: finalSource))
        let incrementalEngine = SyntaxHighlighterEngine()
        let fullEngine = SyntaxHighlighterEngine()

        _ = await incrementalEngine.reset(source: source, language: SyntaxLanguage.javascript)
        _ = await incrementalEngine.update(
            previousSource: source,
            source: updatedAfterCR,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(editAfterCR)
        )
        let incremental = await incrementalEngine.update(
            previousSource: updatedAfterCR,
            source: finalSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(editBeforeCR)
        )
        let full = await fullEngine.reset(source: finalSource, language: SyntaxLanguage.javascript)

        #expect(highlightTokensMatch(incremental.tokens, full.tokens))
    }

    @Test("SyntaxHighlighterEngine keeps invalidation query ranges in UTF-16 coordinates")
    func highlighterUsesUTF16InvalidationQueryRanges() {
        var invalidatedSet = IndexSet()
        invalidatedSet.insert(integersIn: 120..<150)
        let queryRange = SyntaxHighlightInvalidation.queryRange(
            invalidatedSet: invalidatedSet,
            mutation: SyntaxHighlightMutation(location: 180, length: 0, replacement: ""),
            sourceUTF16Length: 240
        )
        #expect(queryRange == NSRange(location: 120, length: 60))

        invalidatedSet = IndexSet()
        invalidatedSet.insert(integersIn: 241..<280)
        #expect(
            SyntaxHighlightInvalidation.queryRange(
                invalidatedSet: invalidatedSet,
                mutation: SyntaxHighlightMutation(location: 180, length: 0, replacement: ""),
                sourceUTF16Length: 240
            ) == NSRange(location: 180, length: 60)
        )
    }

    @Test("SyntaxHighlighterEngine falls back to full reset on stale updates and language changes")
    func highlighterFallsBackToFullResetWhenIncrementalStateDoesNotMatch() async throws {
        let source = "const value = 42;"
        let updatedSource = "let value = 42;"
        let mutation = try #require(TextMutation.diff(from: source, to: updatedSource))
        let engine = SyntaxHighlighterEngine()

        _ = await engine.reset(source: source, language: SyntaxLanguage.javascript)
        let staleUpdate = await engine.update(
            previousSource: "stale",
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(mutation)
        )
        let fullJavaScript = await SyntaxHighlighterEngine()
            .reset(source: updatedSource, language: SyntaxLanguage.javascript)

        #expect(highlightTokensMatch(staleUpdate.tokens, fullJavaScript.tokens))
        #expect(staleUpdate.refreshRange.location <= mutation.range.location)

        let jsonSource = #"{"enabled": true}"#
        let languageChange = await engine.update(
            previousSource: updatedSource,
            source: jsonSource,
            language: SyntaxLanguage.json,
            mutation: SyntaxHighlightMutation(location: 0, length: updatedSource.utf16.count, replacement: jsonSource)
        )
        let fullJSON = await SyntaxHighlighterEngine()
            .reset(source: jsonSource, language: SyntaxLanguage.json)

        #expect(languageChange.language == SyntaxLanguage.json)
        #expect(highlightTokensMatch(languageChange.tokens, fullJSON.tokens))
    }

    @Test("SyntaxHighlighterEngine resets when mutation is not based on the current session source")
    func highlighterResetsWhenMutationBaseDoesNotMatchSessionSource() async throws {
        let sessionSource = "const value = 1;"
        let stalePreviousSource = "let value = 1;"
        let updatedSource = "let value = 2;"
        let staleMutation = try #require(TextMutation.diff(from: stalePreviousSource, to: updatedSource))
        let engine = SyntaxHighlighterEngine()

        _ = await engine.reset(source: sessionSource, language: SyntaxLanguage.javascript)
        let staleUpdate = await engine.update(
            source: updatedSource,
            language: SyntaxLanguage.javascript,
            mutation: SyntaxHighlightMutation(staleMutation),
            revision: 2
        )
        let full = await SyntaxHighlighterEngine()
            .reset(source: updatedSource, language: SyntaxLanguage.javascript, revision: 2)

        #expect(highlightTokensMatch(staleUpdate.tokens, full.tokens))
        #expect(staleUpdate.refreshRange == NSRange(location: 0, length: updatedSource.utf16.count))
    }

    @Test("SyntaxHighlighterEngine keeps unsupported injections in direct highlighting mode")
    func highlighterKeepsUnsupportedInjectionsDirect() async {
        let engine = SyntaxHighlighterEngine()
        let javascriptTokens = await engine.reset(
            source: "const expression = /abc/;",
            language: SyntaxLanguage.javascript
        ).tokens
        let swiftTokens = await engine.reset(
            source: #"let expression = /abc/"#,
            language: SyntaxLanguage.swift
        ).tokens

        #expect(javascriptTokens.contains { $0.syntaxID == .keyword })
        #expect(swiftTokens.contains { $0.syntaxID == .keyword })
    }

    @Test("SyntaxHighlighterEngine returns UTF-16-safe ranges for non-ASCII source")
    func highlighterHandlesNonASCIIRanges() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = "const label = \"こんにちは😀\";"
        let tokens = await engine.render(source: source, language: SyntaxLanguage.javascript)
        let sourceLength = source.utf16.count

        #expect(tokens.isEmpty == false)
        #expect(tokens.allSatisfy { token in
            token.range.location >= 0 &&
                token.range.length > 0 &&
                token.range.upperBound <= sourceLength
        })
    }

    @Test("SyntaxHighlighterEngine highlights Objective-C structures")
    func highlighterSupportsObjectiveC() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        #import <Foundation/Foundation.h>
        __attribute__((visibility("default"))) @interface VisibleSample : NSObject
        @end

        @interface Sample : NSObject
        @property (nonatomic, copy) NSString *name;
        - (NSString *)greetingFor:(NSString *)value;
        @end

        @implementation Sample
        - (NSString *)greetingFor:(NSString *)value {
            // comment
            return [NSString stringWithFormat:@"Hello, %@", value];
        }
        @end
        """

        let tokens = await engine.render(source: source, language: SyntaxLanguage.objectiveC)
        let nsSource = source as NSString
        let importRange = nsSource.range(of: "#import")
        let visibleSampleRange = nsSource.range(of: "VisibleSample")
        let interfaceRange = nsSource.range(of: "@interface")
        let methodRange = nsSource.range(of: "greetingFor")
        let commentRange = nsSource.range(of: "// comment")
        let stringRange = nsSource.range(of: "@\"Hello, %@\"")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            ($0.syntaxID == .preprocessor || $0.syntaxID == .keyword)
                && tokenIntersects($0, range: importRange, language: .objectiveC)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: interfaceRange, syntaxID: .keyword, language: .objectiveC)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: visibleSampleRange, syntaxID: .identifierTypeSystem, language: .objectiveC)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: methodRange, syntaxID: .identifierFunctionSystem, language: .objectiveC)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: commentRange, syntaxID: .comment, language: .objectiveC)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: stringRange, syntaxID: .string, language: .objectiveC)
        })
    }

    @Test("SyntaxHighlighterEngine highlights HTML root and embedded languages")
    func highlighterSupportsHTMLInjections() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        😀
        <!-- note -->
        <style>body { color: red; }</style>
        <script>const answer = 42;</script>
        <div class="hero">Hello</div>
        """

        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let nsSource = source as NSString
        let stylePropertyRange = nsSource.range(of: "color")
        let scriptKeywordRange = nsSource.range(of: "const")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains { $0.syntaxID == .comment && $0.language == .html })
        #expect(tokens.contains { $0.syntaxID == .keyword && $0.language == .html })
        #expect(tokens.contains { $0.syntaxID == .attribute && $0.language == .html })
        #expect(tokens.contains {
            tokenIntersects($0, range: stylePropertyRange, syntaxID: .keyword, language: .css)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: scriptKeywordRange, syntaxID: .keyword, language: .javascript)
        })
    }

    @Test("SyntaxHighlighterEngine resolves recursive injected aliases")
    func highlighterSupportsRecursiveInjectedAliases() async {
        let engine = SyntaxHighlighterEngine()
        let source = """
        <script>
        const view = html`<span class="hero">Hello</span>`;
        </script>
        """

        let tokens = await engine.reset(source: source, language: SyntaxLanguage.html).tokens
        let nsSource = source as NSString
        let nestedTagRange = nsSource.range(of: "<span")
        let nestedAttributeRange = nsSource.range(of: "class")

        #expect(tokens.contains {
            tokenIntersects($0, range: nestedTagRange, syntaxID: .keyword, language: .html)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: nestedAttributeRange, syntaxID: .attribute, language: .html)
        })
    }

    @Test("SyntaxHighlighterEngine highlights XML structures")
    func highlighterSupportsXML() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE note [
            <!ELEMENT note (#PCDATA)>
        ]>
        <note priority="high"><!-- reminder --><![CDATA[<escaped/>]]></note>
        """

        let tokens = await engine.render(source: source, language: SyntaxLanguage.xml)

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains { $0.syntaxID == .keyword })
        #expect(tokens.contains { $0.syntaxID == .attribute })
        #expect(tokens.contains { $0.syntaxID == .comment })
    }

    @Test("SyntaxHighlighterEngine highlights TOML structures")
    func highlighterSupportsTOML() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        # comment
        [package]
        name = "SyntaxEditorUI"
        enabled = true
        count = 1
        """

        let tokens = await engine.render(source: source, language: SyntaxLanguage.toml)
        let nsSource = source as NSString
        let commentRange = nsSource.range(of: "# comment")
        let propertyRange = nsSource.range(of: "name")
        let stringRange = nsSource.range(of: "\"SyntaxEditorUI\"")
        let booleanRange = nsSource.range(of: "true")
        let numberRange = nsSource.range(of: "1")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            tokenIntersects($0, range: commentRange, syntaxID: .comment, language: .toml)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: propertyRange, syntaxID: .attribute, language: .toml)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: stringRange, syntaxID: .string, language: .toml)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: booleanRange, syntaxID: .keyword, language: .toml)
        })
        #expect(tokens.contains {
            tokenIntersects($0, range: numberRange, syntaxID: .number, language: .toml)
        })
    }

    @Test("SyntaxHighlighterEngine maps TOML captures through generated editor syntax vocabulary")
    func highlighterMapsTOMLCapturesToEditorSyntaxVocabulary() async throws {
        let engine = sharedSyntaxHighlighterEngine
        let source = try referenceSampleText(named: "Reference.toml")
        let tokens = await engine.render(source: source, language: SyntaxLanguage.toml)

        let sectionName = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "package",
            syntaxID: "plain",
            language: .toml,
            inOccurrenceOf: "[package]"
        )
        let key = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "name",
            syntaxID: "attribute",
            language: .toml,
            inOccurrenceOf: #"name = "ReferencePreview""#
        )
        let operatorToken = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "=",
            syntaxID: "plain",
            language: .toml,
            inOccurrenceOf: #"name = "ReferencePreview""#
        )
        let string = try semanticSnapshot(
            in: tokens,
            source: source,
            text: #""ReferencePreview""#,
            syntaxID: "string",
            language: .toml
        )
        let boolean = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "true",
            syntaxID: "keyword",
            language: .toml,
            inOccurrenceOf: "enabled = true"
        )
        let number = try semanticSnapshot(
            in: tokens,
            source: source,
            text: "2",
            syntaxID: "number",
            language: .toml,
            inOccurrenceOf: "count = 2"
        )

        #expect(sectionName.styleKeys.first == "editor.syntax.plain")
        #expect(key.styleKeys.first == "editor.syntax.attribute")
        #expect(operatorToken.styleKeys.first == "editor.syntax.plain")
        #expect(string.styleKeys.first == "editor.syntax.string")
        #expect(boolean.styleKeys.first == "editor.syntax.keyword")
        #expect(number.styleKeys.first == "editor.syntax.number")
    }

    @Test("SyntaxHighlighterEngine does not inject unsupported script types")
    func highlighterSkipsUnsupportedScriptTypeInjections() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = #"<script type="application/json">{"enabled": true}</script>"#
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            $0.language == .html && ($0.syntaxID == .keyword || $0.syntaxID == .attribute)
        })
        #expect(tokens.contains {
            tokenIsInjectedKeyword($0, in: trueRange)
        } == false)
    }

    @Test("SyntaxHighlighterEngine does not inject non-JavaScript script types")
    func highlighterSkipsNonJavaScriptScriptTypeInjections() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = #"<script type="text/plain">const answer = true;</script>"#
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let constRange = (source as NSString).range(of: "const")
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            tokenIsInjectedKeyword($0, in: constRange)
        } == false)
        #expect(tokens.contains {
            tokenIsInjectedKeyword($0, in: trueRange)
        } == false)
    }

    @Test("SyntaxHighlighterEngine masks unsupported script types through EOF when closing tags are missing")
    func highlighterMasksUnsupportedScriptTypesThroughEOFWithoutClosingTag() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = #"<script type="application/json">{"enabled": true}"#
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            tokenIsInjectedKeyword($0, in: trueRange)
        } == false)
    }

    @Test("SyntaxHighlighterEngine keeps highlighting supported script content past literal closing tag text")
    func highlighterKeepsHighlightingSupportedScriptContentPastLiteralClosingTagText() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = #"<script>const marker = "</script>"; const answer = 42;</script>"#
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let answerConstRange = (source as NSString).range(of: "const answer")

        #expect(tokens.contains {
            tokenIntersects($0, range: answerConstRange, syntaxID: .keyword, language: .javascript)
        })
    }

    @Test("SyntaxHighlighterEngine keeps highlighting supported script content past repeated literal closing tag text")
    func highlighterKeepsHighlightingSupportedScriptContentPastRepeatedLiteralClosingTagText() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = #"<script>const markers = ["</script>", "</script>"]; const answer = 42;</script>"#
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let answerConstRange = (source as NSString).range(of: "const answer")

        #expect(tokens.contains {
            tokenIntersects($0, range: answerConstRange, syntaxID: .keyword, language: .javascript)
        })
    }

    @Test("SyntaxHighlighterEngine ignores commented-out raw text tags")
    func highlighterIgnoresCommentedOutRawTextTags() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        <!-- <script type="text/plain"> -->
        <div class="hero">Hello</div>
        """
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let divRange = (source as NSString).range(of: "<div")

        #expect(tokens.contains {
            tokenIntersects($0, range: divRange, syntaxID: .keyword, language: .html)
        })
    }

    @Test("SyntaxHighlighterEngine does not stop masking on longer unsupported script closing prefixes")
    func highlighterKeepsMaskingUnsupportedScriptContentPastLongerClosingPrefixes() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = #"<script type="application/json">{"marker":"</scripted>","enabled":true}</script>"#
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            tokenIsInjectedKeyword($0, in: trueRange)
        } == false)
    }

    @Test("SyntaxHighlighterEngine does not inject unsupported script types when start tags contain quoted angle brackets")
    func highlighterSkipsUnsupportedScriptTypeInjectionsWithQuotedAngleBracketInStartTag() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = #"<script data="a>b" type="application/json">{"enabled": true}</script>"#
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            tokenIsInjectedKeyword($0, in: trueRange)
        } == false)
    }

    @Test("SyntaxHighlighterEngine ignores raw-text-like attribute text")
    func highlighterIgnoresRawTextLikeAttributeText() async {
        let engine = sharedSyntaxHighlighterEngine
        let source = """
        <div data='<script type="application/json">'>Container</div>
        <span class="hero">Hello</span>
        """
        let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
        let spanRange = (source as NSString).range(of: "<span")

        #expect(tokens.contains {
            tokenIntersects($0, range: spanRange, syntaxID: .keyword, language: .html)
        })
    }

    @Test("SyntaxHighlighterEngine skips malformed attribute tokens in unsupported script tags")
    func highlighterSkipsMalformedAttributeTokensInUnsupportedScriptTags() async {
        let engine = sharedSyntaxHighlighterEngine
        let cases = [
            #"<script async !foo type="application/json">{"enabled": true}</script>"#,
            #"<script !foo=http://example.com type="application/json">{"enabled": true}</script>"#,
            #"<script !foo=/assets/ type="application/json">{"enabled": true}</script>"#,
            #"<script !foo="a>b" type="application/json">{"enabled": true}</script>"#,
            #"<script !foo="bar"" type="application/json">{"enabled": true}</script>"#,
            #"<script !foo="bar"type="application/json">{"enabled": true}</script>"#,
            #"<script!type="application/json">{"enabled": true}</script>"#,
        ]

        for source in cases {
            let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
            let trueRange = (source as NSString).range(of: "true")

            #expect(tokens.isEmpty == false)
            #expect(tokens.contains {
                tokenIsInjectedKeyword($0, in: trueRange)
            } == false, "Unexpected injected keyword in unsupported script case: \(source)")
        }
    }

    @Test("SyntaxHighlighterEngine ignores malformed type-like attribute suffixes")
    func highlighterIgnoresMalformedTypeLikeAttributeSuffixes() async {
        let engine = sharedSyntaxHighlighterEngine
        let cases = [
            #"<script !type="application/json">const answer = 42;</script>"#,
            #"<script data!type="application/json">const answer = 42;</script>"#,
            #"<script !foo="bar type="application/json">const answer = 42;</script>"#,
        ]

        for source in cases {
            let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
            let constRange = (source as NSString).range(of: "const")

            #expect(tokens.contains {
                tokenIntersects($0, range: constRange, syntaxID: .keyword, language: .javascript)
            })
        }
    }

    @Test("SyntaxHighlighterEngine treats malformed unquoted unsupported script types as unsupported")
    func highlighterTreatsMalformedUnquotedUnsupportedScriptTypesAsUnsupported() async {
        let engine = sharedSyntaxHighlighterEngine
        let cases = [
            #"<script type=module=foo>const answer = true;</script>"#,
            #"<script type=text/plain/>const answer = true;</script>"#,
        ]

        for source in cases {
            let tokens = await engine.render(source: source, language: SyntaxLanguage.html)
            let constRange = (source as NSString).range(of: "const")

            #expect(tokens.contains {
                tokenIsInjectedKeyword($0, in: constRange)
            } == false)
        }
    }

}
