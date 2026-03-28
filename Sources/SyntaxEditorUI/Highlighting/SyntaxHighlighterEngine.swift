import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

struct SyntaxHighlightToken {
    let range: NSRange
    let captureName: String
}

private enum CachedLanguageConfiguration {
    case resolved(LanguageConfiguration)
    case missing
}

actor SyntaxHighlighterEngine {
    private let parser = Parser()
    private var configurations: [String: CachedLanguageConfiguration] = [:]
    private var layeredHighlightingSupport: [String: Bool] = [:]
    private var htmlPreprocessingSupport: [String: Bool] = [:]

    func render(source: String, language: any SyntaxLanguage) -> [SyntaxHighlightToken] {
        guard !source.isEmpty else { return [] }
        guard let configuration = configuration(for: language) else { return [] }

        if usesLayeredHighlighting(
            for: language,
            configuration: configuration
        ) {
            let layeredSource =
                usesHTMLPreprocessing(for: language, configuration: configuration)
                ? HTMLLanguage.sourceByMaskingUnsupportedEmbeddedContent(source)
                : source
            return renderWithInjections(
                source: layeredSource,
                originalSource: source,
                rootConfiguration: configuration
            )
        }

        return renderDirect(source: source, configuration: configuration)
    }
}

private extension SyntaxHighlighterEngine {
    func usesLayeredHighlighting(
        for language: any SyntaxLanguage,
        configuration: LanguageConfiguration
    ) -> Bool {
        guard configuration.queries[.injections] != nil else {
            return false
        }

        let cacheKey = language.treeSitterSupport.cacheKey
        if let cached = layeredHighlightingSupport[cacheKey] {
            return cached
        }

        let resolved = canResolveLayeredInjections(for: language.treeSitterSupport)
        layeredHighlightingSupport[cacheKey] = resolved
        return resolved
    }

    func usesHTMLPreprocessing(
        for language: any SyntaxLanguage,
        configuration: LanguageConfiguration
    ) -> Bool {
        let cacheKey = language.treeSitterSupport.cacheKey
        if let cached = htmlPreprocessingSupport[cacheKey] {
            return cached
        }

        let resolved = supportsHTMLRawTextPreprocessing(for: configuration.language)
        htmlPreprocessingSupport[cacheKey] = resolved
        return resolved
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

    func canResolveLayeredInjections(for support: SyntaxTreeSitterSupport) -> Bool {
        guard let querySource = injectionsQuerySource(for: support) else {
            return false
        }
        guard querySource.contains("@injection.language") == false else {
            return false
        }
        guard containsOnlySupportedInjectionCaptures(in: querySource) else {
            return false
        }

        let injectedLanguages = explicitInjectedLanguages(in: querySource)
        guard injectedLanguages.isEmpty == false else {
            return false
        }

        let availableLanguages = Set(injectedLanguageConfigurations().keys)
        return injectedLanguages.isSubset(of: availableLanguages)
    }

    func injectionsQuerySource(for support: SyntaxTreeSitterSupport) -> String? {
        var candidates: [URL] = []
        var seenPaths = Set<String>()
        let bundleFilename = "\(support.bundleName).bundle"

        for queriesURL in support.queryDirectories + Self.queryDirectoryCandidates(for: support) {
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

    func renderDirect(source: String, configuration: LanguageConfiguration) -> [SyntaxHighlightToken] {
        guard let highlightsQuery = configuration.queries[.highlights] else { return [] }

        do {
            try parser.setLanguage(configuration.language)
        } catch {
            return []
        }

        guard let tree = parser.parse(source) else { return [] }

        let cursor = highlightsQuery.execute(in: tree)
        let highlights = cursor
            .resolve(with: .init(string: source))
            .highlights()

        let sourceUTF16Length = source.utf16.count
        return highlights.compactMap {
            guard let range = Self.utf16Range(
                fromByteRange: $0.tsRange.bytes,
                sourceUTF16Length: sourceUTF16Length
            ) else {
                return nil
            }
            return SyntaxHighlightToken(range: range, captureName: $0.name)
        }
    }

    func renderWithInjections(
        source: String,
        originalSource: String,
        rootConfiguration: LanguageConfiguration
    ) -> [SyntaxHighlightToken] {
        let injectedConfigurations = injectedLanguageConfigurations()

        do {
            let layerConfiguration = LanguageLayer.Configuration(
                languageProvider: { name in
                    injectedConfigurations[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
                }
            )
            let layer = try LanguageLayer(
                languageConfig: rootConfiguration,
                configuration: layerConfiguration
            )
            layer.replaceContent(with: source)

            return try layer.highlights(
                in: NSRange(location: 0, length: source.utf16.count),
                provider: source.predicateTextProvider
            ).compactMap {
                guard let range = Self.utf16Range(
                    fromByteRange: $0.tsRange.bytes,
                    sourceUTF16Length: source.utf16.count
                ) else {
                    return nil
                }
                return SyntaxHighlightToken(range: range, captureName: $0.name)
            }
        } catch {
            return renderDirect(source: originalSource, configuration: rootConfiguration)
        }
    }

    func injectedLanguageConfigurations() -> [String: LanguageConfiguration] {
        let aliases = [
            "css",
            "html",
            "htm",
            "javascript",
            "js",
            "json",
            "objective-c",
            "objectivec",
            "objc",
            "swift",
            "xml",
        ]
        var resolved: [String: LanguageConfiguration] = [:]

        for alias in aliases {
            guard let language = BuiltinSyntaxLanguages.named(alias),
                  let configuration = configuration(for: language)
            else {
                continue
            }
            resolved[alias] = configuration
        }

        return resolved
    }

    func configuration(for language: any SyntaxLanguage) -> LanguageConfiguration? {
        switch configurations[language.syntaxHighlightCacheKey] {
        case .resolved(let configuration):
            return configuration
        case .missing:
            return nil
        case nil:
            break
        }

        let support = language.treeSitterSupport
        let configuration = Self.makeConfiguration(from: support)
        if let configuration {
            configurations[language.syntaxHighlightCacheKey] = .resolved(configuration)
            return configuration
        }

        configurations[language.syntaxHighlightCacheKey] = .missing
        return nil
    }

    static func makeConfiguration(from support: SyntaxTreeSitterSupport) -> LanguageConfiguration? {
        let language = support.makeLanguage()
        var candidates: [URL] = []
        var seenPaths = Set<String>()

        for queriesURL in support.queryDirectories + queryDirectoryCandidates(for: support) {
            let standardized = queriesURL.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else {
                continue
            }
            guard FileManager.default.fileExists(atPath: standardized.path) else {
                continue
            }
            candidates.append(standardized)
        }

        for queriesURL in candidates {
            if let configuration = try? LanguageConfiguration(
                language,
                name: support.name,
                queriesURL: queriesURL
            ), configuration.queries[.highlights] != nil {
                return configuration
            }
        }

        if let configuration = try? LanguageConfiguration(
            language,
            name: support.name,
            bundleName: support.bundleName
        ), configuration.queries[.highlights] != nil {
            return configuration
        }

        return nil
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
