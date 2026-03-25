import Foundation
import SwiftTreeSitter

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

    func render(source: String, language: any SyntaxLanguage) -> [SyntaxHighlightToken] {
        guard !source.isEmpty else { return [] }
        guard let configuration = configuration(for: language) else { return [] }
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
}

private extension SyntaxHighlighterEngine {
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

        for queriesURL in support.queryDirectories + queryDirectoryCandidates(for: support.bundleName) {
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

    static func queryDirectoryCandidates(for bundleName: String) -> [URL] {
        let bundleFilename = "\(bundleName).bundle"
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

        for root in uniqueRoots {
            let bundleURL = root.appendingPathComponent(bundleFilename, isDirectory: true)
            candidates.append(contentsOf: bundleQueryDirectories(for: bundleURL))
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

                candidates.append(contentsOf: bundleQueryDirectories(for: bundleURL))
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

    static func bundleQueryDirectories(for bundleURL: URL) -> [URL] {
        let fileManager = FileManager.default
        let queryDirectories = [
            bundleURL.appendingPathComponent("queries", isDirectory: true),
            bundleURL.appendingPathComponent("Contents/Resources/queries", isDirectory: true),
        ]

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
