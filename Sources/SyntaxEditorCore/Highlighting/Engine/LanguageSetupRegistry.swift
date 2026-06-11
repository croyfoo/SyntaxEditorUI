import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

// Language configuration resolution (query discovery, injected-language support,
// HTML preprocessing detection) relocated verbatim from the previous engine file.
// Cold path: results are cached per language for the process lifetime.

struct HighlightingSetup: Sendable {
    let rootConfiguration: LanguageConfiguration
    let injectedLanguageProvider: InjectedLanguageProvider
    let supportsLayeredHighlighting: Bool
    let usesHTMLPreprocessing: Bool
}

extension HighlightingSetup {
    static func resolved(
        for language: SyntaxLanguage,
        resolver: LanguageConfigurationResolver = .shared
    ) -> HighlightingSetup? {
        guard language.supportsSyntaxHighlighting else {
            return nil
        }

        guard let rootConfiguration = resolver.configuration(for: language) else {
            return nil
        }

        guard let support = language.treeSitterSupport else {
            return nil
        }
        let injectedAliases = resolver.supportedInjectedAliases(
            for: support,
            rootConfiguration: rootConfiguration
        )
        let injectedLanguageProvider = InjectedLanguageProvider(resolver: resolver)

        if let injectedAliases {
            for alias in injectedAliases {
                guard injectedLanguageProvider.configuration(named: alias) != nil else {
                    return HighlightingSetup(
                        rootConfiguration: rootConfiguration,
                        injectedLanguageProvider: injectedLanguageProvider,
                        supportsLayeredHighlighting: false,
                        usesHTMLPreprocessing: false
                    )
                }
            }
        }

        return HighlightingSetup(
            rootConfiguration: rootConfiguration,
            injectedLanguageProvider: injectedLanguageProvider,
            supportsLayeredHighlighting: injectedAliases?.isEmpty == false,
            usesHTMLPreprocessing: resolver.supportsHTMLRawTextPreprocessing(for: rootConfiguration.language)
        )
    }
}

enum CachedLanguageConfiguration {
    case resolved(LanguageConfiguration)
    case missing
}

enum CachedHighlightingSetup: Sendable {
    case resolved(HighlightingSetup)
    case missing

    var setup: HighlightingSetup? {
        switch self {
        case .resolved(let setup):
            setup
        case .missing:
            nil
        }
    }
}

actor LanguageConfigurationRegistry {
    static let shared = LanguageConfigurationRegistry()

    private let resolver = LanguageConfigurationResolver.shared
    private var layeredSetupCache: [SyntaxLanguage: CachedHighlightingSetup] = [:]
    private var setupTasks: [SyntaxLanguage: Task<HighlightingSetup?, Never>] = [:]

    func highlightingSetup(for language: SyntaxLanguage) async -> HighlightingSetup? {
        if let cached = layeredSetupCache[language] {
            return cached.setup
        }

        if let task = setupTasks[language] {
            return await task.value
        }

        let resolver = resolver
        let task = Task.detached {
            HighlightingSetup.resolved(for: language, resolver: resolver)
        }
        setupTasks[language] = task

        let setup = await task.value
        setupTasks[language] = nil
        cache(setup, for: language)
        return setup
    }

    private func cache(_ setup: HighlightingSetup?, for language: SyntaxLanguage) {
        guard let setup else {
            layeredSetupCache[language] = .missing
            return
        }

        layeredSetupCache[language] = .resolved(setup)
    }
}

final class InjectedLanguageProvider: @unchecked Sendable {
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

final class LanguageConfigurationResolver: @unchecked Sendable {
    static let shared = LanguageConfigurationResolver()

    private let lock = NSRecursiveLock()
    private var configurations: [SyntaxLanguage: CachedLanguageConfiguration] = [:]
    private var queryDirectoryCandidateCache: [SyntaxLanguage: [URL]] = [:]

    private init() {}
}

extension LanguageConfigurationResolver {
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

        guard let support = language.treeSitterSupport else {
            configurations[language] = .missing
            return nil
        }
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
