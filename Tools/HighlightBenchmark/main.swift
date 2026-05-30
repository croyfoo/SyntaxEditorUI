import Dispatch
import Foundation
import SyntaxEditorCore

@main
struct HighlightBenchmark {
    static func main() async throws {
        let arguments = BenchmarkArguments(CommandLine.arguments.dropFirst())
        let source = try String(contentsOfFile: arguments.filePath, encoding: .utf8)
        let benchmarkSource = repeatedSource(source, count: arguments.repeatSource)

        _ = await SyntaxHighlighterEngine().reset(
            source: benchmarkSource,
            language: arguments.language,
            revision: 0
        )

        let updatedSource = incrementalEditSource(from: benchmarkSource)
        let mutation = TextMutation.diff(from: benchmarkSource, to: updatedSource).map(SyntaxHighlightMutation.init)

        let fullSamples = await measureFullReset(
            source: benchmarkSource,
            language: arguments.language,
            iterations: arguments.iterations
        )
        let incrementalSamples = await measureIncrementalUpdate(
            source: benchmarkSource,
            updatedSource: updatedSource,
            mutation: mutation,
            language: arguments.language,
            iterations: arguments.iterations
        )
        let typingSamples = arguments.typingEdits > 0
            ? await measureTypingUpdates(
                source: benchmarkSource,
                language: arguments.language,
                editCount: arguments.typingEdits
            )
            : nil

        print("\(arguments.language.displayName) highlight benchmark")
        print("file: \(arguments.filePath)")
        print("language: \(arguments.language.identifier)")
        print("utf16Length: \((benchmarkSource as NSString).length)")
        print("repeatSource: \(arguments.repeatSource)")
        print("iterations: \(arguments.iterations)")
        print("fullResetMedianMs: \(format(fullSamples.medianMilliseconds))")
        print("incrementalUpdateMedianMs: \(format(incrementalSamples.medianMilliseconds))")
        print("fullTokenCount: \(fullSamples.lastTokenCount)")
        print("incrementalTokenCount: \(incrementalSamples.lastTokenCount)")
        print("incrementalRefreshRange: \(incrementalSamples.lastRefreshRange)")
        if let typingSamples {
            print("typingEdits: \(arguments.typingEdits)")
            print("typingMedianMs: \(format(typingSamples.medianMilliseconds))")
            print("typingP95Ms: \(format(typingSamples.p95Milliseconds))")
            print("typingMaxMs: \(format(typingSamples.maxMilliseconds))")
            print("typingTokenCount: \(typingSamples.lastTokenCount)")
            print("typingRefreshRange: \(typingSamples.lastRefreshRange)")
        }
    }

    @MainActor
    private static func measureFullReset(
        source: String,
        language: SyntaxLanguage,
        iterations: Int
    ) async -> BenchmarkSamples {
        await measure(iterations: iterations) {
            await SyntaxHighlighterEngine().reset(source: source, language: language, revision: 0)
        }
    }

    @MainActor
    private static func measureIncrementalUpdate(
        source: String,
        updatedSource: String,
        mutation: SyntaxHighlightMutation?,
        language: SyntaxLanguage,
        iterations: Int
    ) async -> BenchmarkSamples {
        var durations: [Double] = []
        durations.reserveCapacity(iterations)
        var lastResult: SyntaxHighlightResult?

        for _ in 0..<iterations {
            let engine = SyntaxHighlighterEngine()
            _ = await engine.reset(source: source, language: language, revision: 0)

            let start = DispatchTime.now().uptimeNanoseconds
            let result: SyntaxHighlightResult
            if let mutation {
                result = await engine.update(
                    source: updatedSource,
                    language: language,
                    mutation: mutation,
                    revision: 1
                )
            } else {
                result = await engine.reset(source: updatedSource, language: language, revision: 1)
            }
            let end = DispatchTime.now().uptimeNanoseconds
            durations.append(Double(end - start) / 1_000_000)
            lastResult = result
        }

        return BenchmarkSamples(
            milliseconds: durations,
            lastTokenCount: lastResult?.tokens.count ?? 0,
            lastRefreshRange: lastResult?.refreshRange ?? NSRange(location: 0, length: 0)
        )
    }

    @MainActor
    private static func measureTypingUpdates(
        source: String,
        language: SyntaxLanguage,
        editCount: Int
    ) async -> BenchmarkSamples {
        var currentSource = typingBenchmarkSeededSource(source, language: language)
        let engine = SyntaxHighlighterEngine()
        var lastResult = await engine.reset(source: currentSource, language: language, revision: 0)
        var durations: [Double] = []
        durations.reserveCapacity(editCount)

        for editIndex in 0..<editCount {
            let updatedSource = typingEditSource(from: currentSource)
            let mutation = TextMutation.diff(from: currentSource, to: updatedSource)
                .map(SyntaxHighlightMutation.init)
            let start = DispatchTime.now().uptimeNanoseconds
            let result: SyntaxHighlightResult
            if let mutation {
                result = await engine.update(
                    source: updatedSource,
                    language: language,
                    mutation: mutation,
                    revision: editIndex + 1
                )
            } else {
                result = await engine.reset(
                    source: updatedSource,
                    language: language,
                    revision: editIndex + 1
                )
            }
            let end = DispatchTime.now().uptimeNanoseconds
            durations.append(Double(end - start) / 1_000_000)
            currentSource = updatedSource
            lastResult = result
        }

        return BenchmarkSamples(
            milliseconds: durations,
            lastTokenCount: lastResult.tokens.count,
            lastRefreshRange: lastResult.refreshRange
        )
    }

    @MainActor
    private static func measure(
        iterations: Int,
        operation: () async -> SyntaxHighlightResult
    ) async -> BenchmarkSamples {
        var durations: [Double] = []
        durations.reserveCapacity(iterations)
        var lastResult: SyntaxHighlightResult?

        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = await operation()
            let end = DispatchTime.now().uptimeNanoseconds
            durations.append(Double(end - start) / 1_000_000)
            lastResult = result
        }

        return BenchmarkSamples(
            milliseconds: durations,
            lastTokenCount: lastResult?.tokens.count ?? 0,
            lastRefreshRange: lastResult?.refreshRange ?? NSRange(location: 0, length: 0)
        )
    }

    private static func incrementalEditSource(from source: String) -> String {
        if source.contains("Reference highlighting surface") {
            return source.replacingOccurrences(
                of: "Reference highlighting surface",
                with: "Reference highlighting surface benchmark",
                options: [],
                range: source.range(of: "Reference highlighting surface")
            )
        }
        if let range = source.range(of: "ReferenceTokenBase + 1") {
            return source.replacingOccurrences(
                of: "ReferenceTokenBase + 1",
                with: "ReferenceTokenBase + 2",
                options: [],
                range: range
            )
        }
        if let range = source.range(of: "ReferenceItem") {
            return source.replacingOccurrences(
                of: "ReferenceItem",
                with: "ReferenceItemBenchmark",
                options: [],
                range: range
            )
        }
        return source + "\n// benchmark edit\n"
    }

    private static let typingValueMarker = "ReferenceTypingBenchmarkValue = "

    private static func typingBenchmarkSeededSource(_ source: String, language: SyntaxLanguage) -> String {
        guard source.contains(typingValueMarker) == false else { return source }
        switch language {
        case .objectiveC:
            return source + """

            NSInteger ReferenceTypingBenchmark(void) {
                NSInteger ReferenceTypingBenchmarkValue = 1;
                return ReferenceTypingBenchmarkValue;
            }
            """
        case .swift:
            return source + """

            func referenceTypingBenchmark() -> Int {
                let ReferenceTypingBenchmarkValue = 1
                return ReferenceTypingBenchmarkValue
            }
            """
        default:
            return source + "\n// \(typingValueMarker)1\n"
        }
    }

    private static func typingEditSource(from source: String) -> String {
        guard let markerRange = source.range(of: typingValueMarker) else {
            return source + " "
        }
        let valueStart = markerRange.upperBound
        var valueEnd = valueStart
        while valueEnd < source.endIndex, source[valueEnd].isNumber {
            valueEnd = source.index(after: valueEnd)
        }
        let currentValue = Int(source[valueStart..<valueEnd]) ?? 1
        let nextValue = currentValue == 9 ? 1 : currentValue + 1
        return source.replacingCharacters(in: valueStart..<valueEnd, with: String(nextValue))
    }

    private static func repeatedSource(_ source: String, count: Int) -> String {
        guard count > 1 else { return source }
        return Array(repeating: source, count: count).joined(separator: "\n\n")
    }

    private static func format(_ value: Double) -> String {
        let scaled = Int((value * 1_000).rounded())
        let whole = scaled / 1_000
        let fraction = scaled % 1_000
        let paddedFraction = String(fraction + 1_000).dropFirst()
        return "\(whole).\(paddedFraction)"
    }
}

private struct BenchmarkArguments {
    let filePath: String
    let language: SyntaxLanguage
    let iterations: Int
    let repeatSource: Int
    let typingEdits: Int

    init(_ arguments: ArraySlice<String>) {
        var filePath = "Tools/Mini/Mini/ReferenceSamples/Reference.swift"
        var explicitLanguage: SyntaxLanguage?
        var iterations = 20
        var repeatSource = 1
        var typingEdits = 0
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            let nextIndex = arguments.index(after: index)

            switch argument {
            case "--file" where nextIndex < arguments.endIndex:
                filePath = arguments[nextIndex]
                index = arguments.index(after: nextIndex)
            case "--language" where nextIndex < arguments.endIndex:
                explicitLanguage = Self.language(named: arguments[nextIndex])
                index = arguments.index(after: nextIndex)
            case "--iterations" where nextIndex < arguments.endIndex:
                iterations = max(1, Int(arguments[nextIndex]) ?? iterations)
                index = arguments.index(after: nextIndex)
            case "--repeat-source" where nextIndex < arguments.endIndex:
                repeatSource = max(1, Int(arguments[nextIndex]) ?? repeatSource)
                index = arguments.index(after: nextIndex)
            case "--typing-edits" where nextIndex < arguments.endIndex:
                typingEdits = max(0, Int(arguments[nextIndex]) ?? typingEdits)
                index = arguments.index(after: nextIndex)
            default:
                index = nextIndex
            }
        }

        self.filePath = filePath
        self.language = explicitLanguage ?? Self.language(forFilePath: filePath)
        self.iterations = iterations
        self.repeatSource = repeatSource
        self.typingEdits = typingEdits
    }

    private static func language(named name: String) -> SyntaxLanguage? {
        switch name.lowercased() {
        case "css":
            .css
        case "html":
            .html
        case "javascript", "js":
            .javascript
        case "json":
            .json
        case "objective-c", "objectivec", "objc", "m", "h":
            .objectiveC
        case "swift":
            .swift
        case "toml":
            .toml
        case "xml":
            .xml
        default:
            SyntaxLanguage.named(name)
        }
    }

    private static func language(forFilePath filePath: String) -> SyntaxLanguage {
        switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
        case "css":
            .css
        case "html", "htm":
            .html
        case "js", "mjs", "cjs":
            .javascript
        case "json":
            .json
        case "m", "h":
            .objectiveC
        case "toml":
            .toml
        case "xml":
            .xml
        default:
            .swift
        }
    }
}

private struct BenchmarkSamples {
    let milliseconds: [Double]
    let lastTokenCount: Int
    let lastRefreshRange: NSRange

    var medianMilliseconds: Double {
        guard !milliseconds.isEmpty else { return 0 }
        let sorted = milliseconds.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    var p95Milliseconds: Double {
        guard !milliseconds.isEmpty else { return 0 }
        let sorted = milliseconds.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1))
        return sorted[index]
    }

    var maxMilliseconds: Double {
        milliseconds.max() ?? 0
    }
}
