import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

package struct SyntaxHighlightToken: Equatable, Sendable {
    package let range: NSRange
    package let captureName: String
}

package struct SyntaxHighlightMutation: Equatable, Sendable {
    package let location: Int
    package let length: Int
    package let replacement: String

    package init(location: Int, length: Int, replacement: String) {
        self.location = location
        self.length = length
        self.replacement = replacement
    }

    package init(_ mutation: TextMutation) {
        self.init(
            location: mutation.range.location,
            length: mutation.range.length,
            replacement: mutation.replacement
        )
    }
}

package struct SyntaxHighlightResult: Sendable {
    package let tokens: [SyntaxHighlightToken]
    package let source: String
    package let language: SyntaxLanguage
    package let refreshRange: NSRange
}

package actor SyntaxHighlighterEngine {
    private var session: SyntaxHighlightSession?
    private let registry: LanguageConfigurationRegistry

    package init() {
        self.registry = .shared
    }

    package func reset(source: String, language: SyntaxLanguage) async -> SyntaxHighlightResult {
        guard let setup = await registry.highlightingSetup(for: language) else {
            session = nil
            return SyntaxHighlightResult.empty(source: source, language: language)
        }

        let nextSession = SyntaxHighlightSession(language: language, setup: setup)
        let result = nextSession.reset(source: source)
        session = nextSession
        return result
    }

    package func update(
        previousSource: String,
        source: String,
        language: SyntaxLanguage,
        mutation: SyntaxHighlightMutation
    ) async -> SyntaxHighlightResult {
        if let session,
           let result = session.update(
               previousSource: previousSource,
               source: source,
               language: language,
               mutation: mutation
           ) {
            return result
        }

        return await reset(source: source, language: language)
    }

    package func render(source: String, language: SyntaxLanguage) async -> [SyntaxHighlightToken] {
        await reset(source: source, language: language).tokens
    }
}

private struct HighlightingSetup: Sendable {
    let rootConfiguration: LanguageConfiguration
    let injectedLanguageProvider: InjectedLanguageProvider
    let supportsLayeredHighlighting: Bool
    let usesHTMLPreprocessing: Bool
}

private enum CachedLanguageConfiguration {
    case resolved(LanguageConfiguration)
    case missing
}

private final class SyntaxHighlightSession {
    private let setup: HighlightingSetup
    private(set) var language: SyntaxLanguage
    private var source = ""
    private var layeredSource = ""
    private var layer: LanguageLayer?
    private var tokens: [SyntaxHighlightToken] = []

    init(language: SyntaxLanguage, setup: HighlightingSetup) {
        self.language = language
        self.setup = setup
    }

    func reset(source: String) -> SyntaxHighlightResult {
        self.source = source
        layeredSource = layeredSource(for: source)

        guard !layeredSource.isEmpty else {
            layer = nil
            tokens = []
            return SyntaxHighlightResult.empty(source: source, language: language)
        }

        do {
            let layer = try makeLayer()
            layer.replaceContent(with: layeredSource)
            self.layer = layer
            tokens = highlightTokens(in: fullRange(for: layeredSource), source: layeredSource)
        } catch {
            layer = nil
            tokens = []
        }

        return SyntaxHighlightResult(
            tokens: tokens,
            source: source,
            language: language,
            refreshRange: fullRange(for: source)
        )
    }

    func update(
        previousSource: String,
        source nextSource: String,
        language nextLanguage: SyntaxLanguage,
        mutation originalMutation: SyntaxHighlightMutation
    ) -> SyntaxHighlightResult? {
        guard nextLanguage == language, previousSource == source else {
            return nil
        }

        guard let layer else {
            return nil
        }

        let nextLayeredSource = layeredSource(for: nextSource)
        let layeredMutation: SyntaxHighlightMutation
        if setup.usesHTMLPreprocessing {
            guard let mutation = TextMutation.diff(from: layeredSource, to: nextLayeredSource) else {
                source = nextSource
                layeredSource = nextLayeredSource
                return SyntaxHighlightResult(
                    tokens: tokens,
                    source: nextSource,
                    language: language,
                    refreshRange: refreshRange(
                        in: nextSource,
                        from: originalMutation.location
                    )
                )
            }
            layeredMutation = SyntaxHighlightMutation(mutation)
        } else {
            layeredMutation = originalMutation
        }

        if setup.supportsLayeredHighlighting,
           Self.mutationTouchesMarkupBoundary(
               mutation: layeredMutation,
               previousSource: layeredSource,
               nextSource: nextLayeredSource
           ) {
            return nil
        }

        guard let inputEdit = Self.inputEdit(
            mutation: layeredMutation,
            previousSource: layeredSource,
            nextSource: nextLayeredSource
        ) else {
            return nil
        }

        let invalidatedSet = layer.didChangeContent(
            .init(string: nextLayeredSource),
            using: inputEdit,
            resolveSublayers: setup.supportsLayeredHighlighting
        )

        source = nextSource
        layeredSource = nextLayeredSource
        tokens = highlightTokens(in: fullRange(for: nextLayeredSource), source: nextLayeredSource)

        return SyntaxHighlightResult(
            tokens: tokens,
            source: nextSource,
            language: language,
            refreshRange: refreshRange(
                in: nextSource,
                from: min(
                    originalMutation.location,
                    invalidatedSet.rangeView.first?.lowerBound ?? originalMutation.location
                )
            )
        )
    }
}

private extension SyntaxHighlightSession {
    func makeLayer() throws -> LanguageLayer {
        let layerConfiguration = LanguageLayer.Configuration(
            maximumLanguageDepth: setup.supportsLayeredHighlighting ? 4 : 0,
            languageProvider: { [provider = setup.injectedLanguageProvider] name in
                provider.configuration(named: name)
            }
        )
        return try LanguageLayer(
            languageConfig: setup.rootConfiguration,
            configuration: layerConfiguration
        )
    }

    func layeredSource(for source: String) -> String {
        setup.usesHTMLPreprocessing
            ? HTMLLanguage.sourceByMaskingUnsupportedEmbeddedContent(source)
            : source
    }

    func highlightTokens(in range: NSRange, source: String) -> [SyntaxHighlightToken] {
        guard range.length > 0, let layer else { return [] }

        do {
            let sourceUTF16Length = source.utf16.count
            return try layer.highlights(
                in: range,
                provider: source.predicateTextProvider
            ).compactMap {
                guard let range = Self.utf16Range(
                    fromByteRange: $0.tsRange.bytes,
                    sourceUTF16Length: sourceUTF16Length
                ) else {
                    return nil
                }
                return SyntaxHighlightToken(range: range, captureName: $0.name)
            }
        } catch {
            return []
        }
    }

    func fullRange(for source: String) -> NSRange {
        NSRange(location: 0, length: source.utf16.count)
    }

    func refreshRange(in source: String, from location: Int) -> NSRange {
        let sourceLength = source.utf16.count
        let clampedLocation = min(max(0, location), sourceLength)
        let lineStart = SyntaxEditorRangeUtilities.lineStartUTF16Offset(
            in: source,
            around: clampedLocation
        )
        return NSRange(location: lineStart, length: sourceLength - lineStart)
    }

    static func inputEdit(
        mutation: SyntaxHighlightMutation,
        previousSource: String,
        nextSource: String
    ) -> InputEdit? {
        let previousLength = previousSource.utf16.count
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location <= previousLength,
              mutation.location + mutation.length <= previousLength else {
            return nil
        }

        let replacementLength = mutation.replacement.utf16.count
        let oldEnd = mutation.location + mutation.length
        let newEnd = mutation.location + replacementLength

        guard oldEnd <= previousLength,
              newEnd <= nextSource.utf16.count,
              mutation.location <= Int(UInt32.max / 2),
              oldEnd <= Int(UInt32.max / 2),
              newEnd <= Int(UInt32.max / 2) else {
            return nil
        }

        return InputEdit(
            startByte: mutation.location * 2,
            oldEndByte: oldEnd * 2,
            newEndByte: newEnd * 2,
            startPoint: point(in: previousSource, at: mutation.location),
            oldEndPoint: point(in: previousSource, at: oldEnd),
            newEndPoint: point(in: nextSource, at: newEnd)
        )
    }

    static func mutationTouchesMarkupBoundary(
        mutation: SyntaxHighlightMutation,
        previousSource: String,
        nextSource: String
    ) -> Bool {
        let sourceLength = previousSource.utf16.count
        guard mutation.location >= 0,
              mutation.length >= 0,
              mutation.location + mutation.length <= sourceLength else {
            return true
        }

        let changedText = (previousSource as NSString).substring(
            with: NSRange(location: mutation.location, length: mutation.length)
        )
        return changedText.contains("<") ||
            changedText.contains(">") ||
            mutation.replacement.contains("<") ||
            mutation.replacement.contains(">") ||
            isInsideMarkupTag(in: previousSource, at: mutation.location) ||
            isInsideMarkupTag(in: previousSource, at: mutation.location + mutation.length) ||
            isInsideMarkupTag(in: nextSource, at: mutation.location) ||
            isInsideMarkupTag(in: nextSource, at: mutation.location + mutation.replacement.utf16.count)
    }

    static func isInsideMarkupTag(in source: String, at utf16Offset: Int) -> Bool {
        let nsSource = source as NSString
        let location = min(max(0, utf16Offset), nsSource.length)
        let prefixRange = NSRange(location: 0, length: location)
        let previousOpen = nsSource.range(
            of: "<",
            options: [.backwards],
            range: prefixRange
        )
        guard previousOpen.location != NSNotFound else {
            return false
        }

        let previousClose = nsSource.range(
            of: ">",
            options: [.backwards],
            range: prefixRange
        )
        guard previousClose.location == NSNotFound || previousOpen.location > previousClose.location else {
            return false
        }

        let suffixRange = NSRange(location: location, length: nsSource.length - location)
        let nextClose = nsSource.range(of: ">", options: [], range: suffixRange)
        guard nextClose.location != NSNotFound else {
            return false
        }

        let nextOpen = nsSource.range(of: "<", options: [], range: suffixRange)
        return nextOpen.location == NSNotFound || nextClose.location < nextOpen.location
    }

    static func point(in source: String, at utf16Offset: Int) -> Point {
        let clampedOffset = min(max(0, utf16Offset), source.utf16.count)
        var row = 0
        var lineStart = 0

        for (index, codeUnit) in source.utf16.enumerated() {
            guard index < clampedOffset else { break }
            if codeUnit == 10 {
                row += 1
                lineStart = index + 1
            }
        }

        return Point(row: row, column: (clampedOffset - lineStart) * 2)
    }

    // SwiftTreeSitter parses String input as UTF-16 by default, so byte offsets map
    // to UTF-16 offsets by dividing by 2.
    static func utf16Range(
        fromByteRange byteRange: Range<UInt32>,
        sourceUTF16Length: Int
    ) -> NSRange? {
        guard byteRange.lowerBound % 2 == 0, byteRange.upperBound % 2 == 0 else {
            return nil
        }

        let start = Int(byteRange.lowerBound / 2)
        let end = Int(byteRange.upperBound / 2)
        guard start <= end, end <= sourceUTF16Length else {
            return nil
        }

        return NSRange(location: start, length: end - start)
    }
}

private actor LanguageConfigurationRegistry {
    static let shared = LanguageConfigurationRegistry()

    private let resolver = LanguageConfigurationResolver.shared
    private var layeredSetupCache: [SyntaxLanguage: HighlightingSetup?] = [:]

    func highlightingSetup(for language: SyntaxLanguage) -> HighlightingSetup? {
        if let cached = layeredSetupCache[language] {
            return cached
        }

        guard let rootConfiguration = resolver.configuration(for: language) else {
            layeredSetupCache[language] = nil
            return nil
        }

        let support = language.treeSitterSupport
        let injectedAliases = resolver.supportedInjectedAliases(
            for: support,
            rootConfiguration: rootConfiguration
        )
        let injectedLanguageProvider = InjectedLanguageProvider(resolver: resolver)

        if let injectedAliases {
            for alias in injectedAliases {
                guard injectedLanguageProvider.configuration(named: alias) != nil else {
                    let setup = HighlightingSetup(
                        rootConfiguration: rootConfiguration,
                        injectedLanguageProvider: injectedLanguageProvider,
                        supportsLayeredHighlighting: false,
                        usesHTMLPreprocessing: false
                    )
                    layeredSetupCache[language] = setup
                    return setup
                }
            }
        }

        let setup = HighlightingSetup(
            rootConfiguration: rootConfiguration,
            injectedLanguageProvider: injectedLanguageProvider,
            supportsLayeredHighlighting: injectedAliases?.isEmpty == false,
            usesHTMLPreprocessing: resolver.supportsHTMLRawTextPreprocessing(for: rootConfiguration.language)
        )
        layeredSetupCache[language] = setup
        return setup
    }
}

private final class InjectedLanguageProvider: @unchecked Sendable {
    private let resolver: LanguageConfigurationResolver
    private let lock = NSRecursiveLock()
    private var aliases: [String: CachedLanguageConfiguration] = [:]

    init(resolver: LanguageConfigurationResolver) {
        self.resolver = resolver
    }

    func configuration(named rawName: String) -> LanguageConfiguration? {
        let alias = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let language = SyntaxLanguage.named(alias) else {
            return nil
        }

        lock.lock()
        if let cached = aliases[alias] {
            lock.unlock()
            switch cached {
            case .resolved(let configuration):
                return configuration
            case .missing:
                return nil
            }
        }
        lock.unlock()

        guard let configuration = resolver.configuration(for: language) else {
            lock.lock()
            aliases[alias] = .missing
            lock.unlock()
            return nil
        }

        lock.lock()
        aliases[alias] = .resolved(configuration)
        lock.unlock()
        return configuration
    }
}

private final class LanguageConfigurationResolver: @unchecked Sendable {
    static let shared = LanguageConfigurationResolver()

    private let lock = NSRecursiveLock()
    private var configurations: [SyntaxLanguage: CachedLanguageConfiguration] = [:]
    private var queryDirectoryCandidateCache: [SyntaxLanguage: [URL]] = [:]

    private init() {}
}

private extension LanguageConfigurationResolver {
    func configuration(for language: SyntaxLanguage) -> LanguageConfiguration? {
        lock.lock()
        defer { lock.unlock() }

        switch configurations[language] {
        case .resolved(let configuration):
            return configuration
        case .missing:
            return nil
        case nil:
            break
        }

        let support = language.treeSitterSupport
        let configuration = makeConfiguration(for: language, support: support)
        if let configuration {
            configurations[language] = .resolved(configuration)
            return configuration
        }

        configurations[language] = .missing
        return nil
    }

    func makeConfiguration(
        for language: SyntaxLanguage,
        support: SyntaxTreeSitterSupport
    ) -> LanguageConfiguration? {
        let treeSitterLanguage = support.makeLanguage()

        for queriesURL in support.queryDirectories {
            if let configuration = makeConfiguration(
                treeSitterLanguage,
                support: support,
                queriesURL: queriesURL
            ) {
                return configuration
            }
        }

        if let configuration = try? LanguageConfiguration(
            treeSitterLanguage,
            name: support.name,
            bundleName: support.bundleName
        ), configuration.queries[.highlights] != nil {
            return configuration
        }

        for queriesURL in queryDirectoryCandidates(for: language, support: support) {
            if let configuration = makeConfiguration(
                treeSitterLanguage,
                support: support,
                queriesURL: queriesURL
            ) {
                return configuration
            }
        }

        return nil
    }

    func makeConfiguration(
        _ language: Language,
        support: SyntaxTreeSitterSupport,
        queriesURL: URL
    ) -> LanguageConfiguration? {
        let standardized = queriesURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            return nil
        }
        guard let configuration = try? LanguageConfiguration(
            language,
            name: support.name,
            queriesURL: standardized
        ), configuration.queries[.highlights] != nil else {
            return nil
        }
        return configuration
    }

    func supportedInjectedAliases(
        for support: SyntaxTreeSitterSupport,
        rootConfiguration: LanguageConfiguration
    ) -> Set<String>? {
        guard rootConfiguration.queries[.injections] != nil else {
            return nil
        }
        guard let querySource = injectionsQuerySource(for: support) else {
            return nil
        }
        guard querySource.contains("@injection.language") == false else {
            return nil
        }
        guard containsOnlySupportedInjectionCaptures(in: querySource) else {
            return nil
        }

        let aliases = explicitInjectedLanguages(in: querySource)
        guard aliases.isEmpty == false else {
            return nil
        }
        guard aliases.allSatisfy({ SyntaxLanguage.named($0) != nil }) else {
            return nil
        }

        return aliases
    }

    func injectionsQuerySource(for support: SyntaxTreeSitterSupport) -> String? {
        var candidates: [URL] = []
        var seenPaths = Set<String>()
        let bundleFilename = "\(support.bundleName).bundle"

        for queriesURL in support.queryDirectories {
            let standardized = queriesURL.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else {
                continue
            }
            candidates.append(standardized)
        }

        let bundleURLs =
            [Bundle.main.bundleURL] +
            Bundle.allBundles.map(\.bundleURL) +
            Bundle.allFrameworks.map(\.bundleURL)
        for bundleURL in bundleURLs where bundleURL.lastPathComponent == bundleFilename {
            for queriesURL in Self.bundleQueryDirectories(
                for: bundleURL,
                preferredSubdirectoryNames: Set([support.name.lowercased()])
            ) {
                let standardized = queriesURL.standardizedFileURL
                guard seenPaths.insert(standardized.path).inserted else {
                    continue
                }
                candidates.append(standardized)
            }
        }

        for queriesURL in queryDirectoryCandidates(for: nil, support: support) {
            let standardized = queriesURL.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else {
                continue
            }
            candidates.append(standardized)
        }

        for queriesURL in candidates {
            let injectionsURL = queriesURL.appendingPathComponent("injections.scm")
            if let source = try? String(contentsOf: injectionsURL, encoding: .utf8) {
                return source
            }
        }

        return nil
    }

    func containsOnlySupportedInjectionCaptures(in querySource: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"@[A-Za-z0-9_.-]+"#) else {
            return false
        }

        let sourceRange = NSRange(location: 0, length: querySource.utf16.count)
        return regex.matches(in: querySource, range: sourceRange).allSatisfy { match in
            guard let range = Range(match.range, in: querySource) else {
                return false
            }

            let capture = String(querySource[range])
            return capture == "@injection.content" || capture == "@injection.language" || capture.hasPrefix("@_")
        }
    }

    func explicitInjectedLanguages(in querySource: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: #"#set!\s+injection\.language\s+"([^"]+)""#
        ) else {
            return []
        }

        let sourceRange = NSRange(location: 0, length: querySource.utf16.count)
        let matches = regex.matches(in: querySource, range: sourceRange)
        return Set(matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: querySource)
            else {
                return nil
            }

            return String(querySource[range]).lowercased()
        })
    }

    func supportsHTMLRawTextPreprocessing(for language: Language) -> Bool {
        let requiredSymbols = Set(["raw_text", "script_element", "style_element"])
        var resolvedSymbols = Set<String>()

        for symbolID in 0..<language.symbolCount {
            guard let symbolName = language.symbolName(for: symbolID),
                  requiredSymbols.contains(symbolName)
            else {
                continue
            }

            resolvedSymbols.insert(symbolName)
            if resolvedSymbols == requiredSymbols {
                return true
            }
        }

        return false
    }

    func queryDirectoryCandidates(
        for language: SyntaxLanguage?,
        support: SyntaxTreeSitterSupport
    ) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        if let language, let cached = queryDirectoryCandidateCache[language] {
            return cached
        }

        let candidates = Self.queryDirectoryCandidates(for: support)
        if let language {
            queryDirectoryCandidateCache[language] = candidates
        }
        return candidates
    }

    static func queryDirectoryCandidates(for support: SyntaxTreeSitterSupport) -> [URL] {
        let bundleFilename = "\(support.bundleName).bundle"
        var roots: [URL] = []
        let fileManager = FileManager.default
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL)
        }
        roots.append(Bundle.main.bundleURL)
        roots.append(currentDirectoryURL)

        roots.append(contentsOf: Bundle.allBundles.map(\.bundleURL))
        roots.append(contentsOf: Bundle.allFrameworks.map(\.bundleURL))

        var seen = Set<String>()
        var uniqueRoots: [URL] = []
        for root in roots {
            for candidate in searchRoots(from: root) {
                if seen.insert(candidate.path).inserted {
                    uniqueRoots.append(candidate)
                }
            }
        }

        var candidates: [URL] = []
        let preferredSubdirectoryNames = Set([support.name.lowercased()])

        for root in uniqueRoots {
            let bundleURL = root.appendingPathComponent(bundleFilename, isDirectory: true)
            candidates.append(
                contentsOf: bundleQueryDirectories(
                    for: bundleURL,
                    preferredSubdirectoryNames: preferredSubdirectoryNames
                )
            )
        }

        let buildRoot = currentDirectoryURL.appendingPathComponent(".build", isDirectory: true)
        if fileManager.fileExists(atPath: buildRoot.path),
           let enumerator = fileManager.enumerator(
               at: buildRoot,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           )
        {
            for case let bundleURL as URL in enumerator {
                guard bundleURL.lastPathComponent == bundleFilename else {
                    continue
                }

                candidates.append(
                    contentsOf: bundleQueryDirectories(
                        for: bundleURL,
                        preferredSubdirectoryNames: preferredSubdirectoryNames
                    )
                )
                enumerator.skipDescendants()
            }
        }

        return candidates
    }

    static func searchRoots(from root: URL) -> [URL] {
        var result: [URL] = []
        var currentURL: URL? = root.standardizedFileURL

        for _ in 0..<6 {
            guard let current = currentURL else { break }
            result.append(current)

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                break
            }
            currentURL = parent
        }

        return result
    }

    static func bundleQueryDirectories(
        for bundleURL: URL,
        preferredSubdirectoryNames: Set<String>
    ) -> [URL] {
        let fileManager = FileManager.default
        var queryDirectories = [
            bundleURL.appendingPathComponent("queries", isDirectory: true),
            bundleURL.appendingPathComponent("Contents/Resources/queries", isDirectory: true),
        ]

        var searchRoots = [
            bundleURL,
            bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true),
        ]
        searchRoots.append(contentsOf: queryDirectories)

        var preferredDirectories: [URL] = []
        var fallbackDirectories: [URL] = []

        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children {
                guard let resourceValues = try? child.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true
                else {
                    continue
                }

                let hasHighlights = fileManager.fileExists(
                    atPath: child.appendingPathComponent("highlights.scm").path
                )
                let hasInjections = fileManager.fileExists(
                    atPath: child.appendingPathComponent("injections.scm").path
                )
                if hasHighlights || hasInjections {
                    if preferredSubdirectoryNames.contains(child.lastPathComponent.lowercased()) {
                        preferredDirectories.append(child)
                    } else {
                        fallbackDirectories.append(child)
                    }
                }
            }
        }

        queryDirectories.append(contentsOf: preferredDirectories)
        queryDirectories.append(contentsOf: fallbackDirectories)
        return queryDirectories.filter { fileManager.fileExists(atPath: $0.path) }
    }
}

private extension SyntaxHighlightResult {
    static func empty(source: String, language: SyntaxLanguage) -> SyntaxHighlightResult {
        SyntaxHighlightResult(
            tokens: [],
            source: source,
            language: language,
            refreshRange: NSRange(location: 0, length: source.utf16.count)
        )
    }
}
