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
        let mutation = SyntaxEditorTextChange.Replacement.singleReplacement(from: benchmarkSource, to: updatedSource).map(SyntaxHighlightMutation.init)

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
        let phasedFullSamples = await measurePhasedFullReset(
            source: benchmarkSource,
            language: arguments.language,
            iterations: arguments.iterations
        )
        let phasedIncrementalSamples = await measurePhasedIncrementalUpdate(
            source: benchmarkSource,
            updatedSource: updatedSource,
            mutation: mutation,
            language: arguments.language,
            iterations: arguments.iterations
        )
        if let typeText = arguments.typeText {
            if arguments.typePhases {
                await runPhasedTypingScenario(
                    source: benchmarkSource,
                    language: arguments.language,
                    typeText: typeText,
                    typeAfter: arguments.typeAfter,
                    repeats: arguments.typeRepeat
                )
            } else {
                for _ in 0..<arguments.typeRepeat {
                    await runCharacterTypingScenario(
                        source: benchmarkSource,
                        language: arguments.language,
                        typeText: typeText,
                        typeAfter: arguments.typeAfter
                    )
                }
            }
        }
        let typingSamples = arguments.typingEdits > 0
            ? await measureTypingUpdates(
                source: benchmarkSource,
                language: arguments.language,
                editCount: arguments.typingEdits,
                anchor: arguments.typingAnchor
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
        if let syntacticFastPassMedianMilliseconds = phasedFullSamples.syntacticFastPassMedianMilliseconds {
            print("syntacticFastPassMedianMs: \(format(syntacticFastPassMedianMilliseconds))")
        }
        print("completeMedianMs: \(format(phasedFullSamples.completeMedianMilliseconds))")
        if let syntacticFastPassMedianMilliseconds = phasedIncrementalSamples.syntacticFastPassMedianMilliseconds {
            print("incrementalSyntacticFastPassMedianMs: \(format(syntacticFastPassMedianMilliseconds))")
        }
        print("incrementalCompleteMedianMs: \(format(phasedIncrementalSamples.completeMedianMilliseconds))")
        print("fullTokenCount: \(fullSamples.lastTokenCount)")
        print("incrementalTokenCount: \(incrementalSamples.lastTokenCount)")
        print("incrementalRefreshRange: \(incrementalSamples.lastRefreshRange)")
        if let typingSamples {
            print("typingEdits: \(arguments.typingEdits)")
            print("typingAnchor: \(arguments.typingAnchor.rawValue)")
            print("typingMedianMs: \(format(typingSamples.medianMilliseconds))")
            print("typingP95Ms: \(format(typingSamples.p95Milliseconds))")
            print("typingMaxMs: \(format(typingSamples.maxMilliseconds))")
            print("typingTokenCount: \(typingSamples.lastTokenCount)")
            print("typingRefreshRange: \(typingSamples.lastRefreshRange)")
        }
    }


    /// Emulates the editor's cancel-on-keystroke scheduling: each keystroke spawns
    /// updatePhases, waits only for the syntactic fast pass, then issues the next
    /// keystroke (cancelling the previous stream). Measures time-to-fastPass — the
    /// latency a user actually feels — independent of semantic spikes. Afterwards the
    /// final update runs to completion and the result is compared against a fresh
    /// engine reset (cancellation-debt correctness под real timing).
    @MainActor
    private static func runPhasedTypingScenario(
        source: String,
        language: SyntaxLanguage,
        typeText: String,
        typeAfter: String?,
        repeats: Int
    ) async {
        var current = source
        let insertionPoint: Int
        if let typeAfter {
            let markerRange = (current as NSString).range(of: typeAfter)
            insertionPoint = markerRange.location == NSNotFound
                ? (current as NSString).length / 2
                : markerRange.upperBound
        } else {
            insertionPoint = (current as NSString).length / 2
        }

        let engine = SyntaxHighlighterEngine()
        _ = await engine.reset(source: current, language: language, revision: 0)

        var caret = insertionPoint
        var fastPassDurations: [Double] = []
        var revision = 1
        var pendingTask: Task<Void, Never>?

        for _ in 0..<repeats {
            for character in typeText {
                let insertion = String(character)
                let mutation = SyntaxHighlightMutation(location: caret, length: 0, replacement: insertion)
                let next = (current as NSString).replacingCharacters(
                    in: NSRange(location: caret, length: 0),
                    with: insertion
                )
                pendingTask?.cancel()
                let start = DispatchTime.now().uptimeNanoseconds
                let fastPassMs: Double = await withCheckedContinuation { continuation in
                    pendingTask = Task { @MainActor in
                        var resumed = false
                        let stream = await engine.updatePhases(
                            source: next,
                            language: language,
                            mutation: mutation,
                            revision: revision
                        )
                        for await _ in stream where !resumed {
                            resumed = true
                            continuation.resume(
                                returning: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                            )
                        }
                        if !resumed {
                            continuation.resume(
                                returning: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                            )
                        }
                    }
                }
                fastPassDurations.append(fastPassMs)
                current = next
                caret += (insertion as NSString).length
                revision += 1
            }
        }
        // Let the final stream complete, then verify settle-equality.
        await pendingTask?.value
        let settled = await engine.update(
            source: current,
            language: language,
            mutation: SyntaxHighlightMutation(location: 0, length: 0, replacement: ""),
            revision: revision
        )
        _ = settled
        let settledTokens = await engine.currentTokensForTesting()
        let freshEngine = SyntaxHighlighterEngine()
        _ = await freshEngine.reset(source: current, language: language, revision: 0)
        let freshTokens = await freshEngine.currentTokensForTesting()

        let samples = BenchmarkSamples(
            milliseconds: fastPassDurations,
            lastTokenCount: settledTokens.count,
            lastRefreshRange: NSRange(location: 0, length: 0)
        )
        print("typePhasesEdits: \(fastPassDurations.count)")
        print("typePhasesFastPassMedianMs: \(format(samples.medianMilliseconds))")
        print("typePhasesFastPassP95Ms: \(format(samples.p95Milliseconds))")
        print("typePhasesFastPassMaxMs: \(format(samples.maxMilliseconds))")
        print("typePhasesSettleEqualsFresh: \(settledTokens == freshTokens)")
    }

    @MainActor
    private static func runCharacterTypingScenario(
        source: String,
        language: SyntaxLanguage,
        typeText: String,
        typeAfter: String?
    ) async {
        var current = source
        let insertionPoint: Int
        if let typeAfter, let markerRange = (current as NSString).range(of: typeAfter) as NSRange?,
           markerRange.location != NSNotFound {
            insertionPoint = markerRange.upperBound
        } else {
            insertionPoint = (current as NSString).length / 2
        }

        let engine = SyntaxHighlighterEngine()
        let resetStart = DispatchTime.now().uptimeNanoseconds
        _ = await engine.reset(source: current, language: language, revision: 0)
        let resetMs = Double(DispatchTime.now().uptimeNanoseconds - resetStart) / 1_000_000

        var caret = insertionPoint
        var durations: [Double] = []
        var refreshLengths: [Int] = []
        var revision = 1
        for character in typeText {
            let insertion = String(character)
            let mutation = SyntaxHighlightMutation(location: caret, length: 0, replacement: insertion)
            let next = (current as NSString).replacingCharacters(
                in: NSRange(location: caret, length: 0),
                with: insertion
            )
            let start = DispatchTime.now().uptimeNanoseconds
            let result = await engine.update(
                source: next,
                language: language,
                mutation: mutation,
                revision: revision
            )
            let end = DispatchTime.now().uptimeNanoseconds
            durations.append(Double(end - start) / 1_000_000)
            refreshLengths.append(result.refreshRange.length)
            current = next
            caret += (insertion as NSString).length
            revision += 1
        }

        let samples = BenchmarkSamples(
            milliseconds: durations,
            lastTokenCount: 0,
            lastRefreshRange: NSRange(location: 0, length: refreshLengths.last ?? 0)
        )
        print("typeScenarioResetMs: \(format(resetMs))")
        print("typeScenarioEdits: \(durations.count)")
        print("typeScenarioMedianMs: \(format(samples.medianMilliseconds))")
        print("typeScenarioP95Ms: \(format(samples.p95Milliseconds))")
        print("typeScenarioMaxMs: \(format(samples.maxMilliseconds))")
        print("typeScenarioPerEditMs: \(durations.map { format($0) }.joined(separator: ","))")
        print("typeScenarioRefreshLengths: \(refreshLengths.map(String.init).joined(separator: ","))")
    }

    @MainActor
    private static func measurePhasedFullReset(
        source: String,
        language: SyntaxLanguage,
        iterations: Int
    ) async -> PhasedBenchmarkSamples {
        var syntacticFastPassDurations: [Double] = []
        var completeDurations: [Double] = []
        syntacticFastPassDurations.reserveCapacity(iterations)
        completeDurations.reserveCapacity(iterations)
        var lastCompleteResult: SyntaxHighlightResult?

        for _ in 0..<iterations {
            let engine = SyntaxHighlighterEngine()
            let start = DispatchTime.now().uptimeNanoseconds
            let phases = await engine.resetPhases(source: source, language: language, revision: 0)
            for await result in phases {
                let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                switch result.phase {
                case .syntacticFastPass:
                    syntacticFastPassDurations.append(duration)
                case .complete:
                    completeDurations.append(duration)
                    lastCompleteResult = result
                }
            }
        }

        return PhasedBenchmarkSamples(
            syntacticFastPassMilliseconds: syntacticFastPassDurations,
            completeMilliseconds: completeDurations,
            lastTokenCount: lastCompleteResult?.tokens.count ?? 0,
            lastRefreshRange: lastCompleteResult?.refreshRange ?? NSRange(location: 0, length: 0)
        )
    }

    @MainActor
    private static func measurePhasedIncrementalUpdate(
        source: String,
        updatedSource: String,
        mutation: SyntaxHighlightMutation?,
        language: SyntaxLanguage,
        iterations: Int
    ) async -> PhasedBenchmarkSamples {
        var syntacticFastPassDurations: [Double] = []
        var completeDurations: [Double] = []
        syntacticFastPassDurations.reserveCapacity(iterations)
        completeDurations.reserveCapacity(iterations)
        var lastCompleteResult: SyntaxHighlightResult?

        for _ in 0..<iterations {
            let engine = SyntaxHighlighterEngine()
            _ = await engine.reset(source: source, language: language, revision: 0)

            let start = DispatchTime.now().uptimeNanoseconds
            let phases: AsyncStream<SyntaxHighlightResult>
            if let mutation {
                phases = await engine.updatePhases(
                    source: updatedSource,
                    language: language,
                    mutation: mutation,
                    revision: 1
                )
            } else {
                phases = await engine.resetPhases(source: updatedSource, language: language, revision: 1)
            }
            for await result in phases {
                let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                switch result.phase {
                case .syntacticFastPass:
                    syntacticFastPassDurations.append(duration)
                case .complete:
                    completeDurations.append(duration)
                    lastCompleteResult = result
                }
            }
        }

        return PhasedBenchmarkSamples(
            syntacticFastPassMilliseconds: syntacticFastPassDurations,
            completeMilliseconds: completeDurations,
            lastTokenCount: lastCompleteResult?.tokens.count ?? 0,
            lastRefreshRange: lastCompleteResult?.refreshRange ?? NSRange(location: 0, length: 0)
        )
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
        editCount: Int,
        anchor: TypingAnchor
    ) async -> BenchmarkSamples {
        var currentSource = typingBenchmarkSeededSource(source, language: language, anchor: anchor)
        let engine = SyntaxHighlighterEngine()
        var lastResult = await engine.reset(source: currentSource, language: language, revision: 0)
        var durations: [Double] = []
        durations.reserveCapacity(editCount)

        for editIndex in 0..<editCount {
            let updatedSource = typingEditSource(from: currentSource)
            let mutation = SyntaxEditorTextChange.Replacement.singleReplacement(from: currentSource, to: updatedSource)
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

    private static func typingBenchmarkSeededSource(
        _ source: String,
        language: SyntaxLanguage,
        anchor: TypingAnchor
    ) -> String {
        guard source.contains(typingValueMarker) == false else { return source }
        let insertion = switch language {
        case .objectiveC:
            """

            NSInteger ReferenceTypingBenchmark(void) {
                NSInteger ReferenceTypingBenchmarkValue = 1;
                return ReferenceTypingBenchmarkValue;
            }
            """
        case .swift:
            """

            func referenceTypingBenchmark() -> Int {
                let ReferenceTypingBenchmarkValue = 1
                return ReferenceTypingBenchmarkValue
            }
            """
        default:
            "\n// \(typingValueMarker)1\n"
        }
        return insertingTypingBenchmark(insertion, into: source, anchor: anchor)
    }

    private static func insertingTypingBenchmark(
        _ insertion: String,
        into source: String,
        anchor: TypingAnchor
    ) -> String {
        switch anchor {
        case .start:
            return insertion + "\n" + source
        case .middle:
            let utf16Length = (source as NSString).length
            guard utf16Length > 0 else { return insertion }
            let nsSource = source as NSString
            let middle = utf16Length / 2
            let lineRange = nsSource.lineRange(for: NSRange(location: middle, length: 0))
            let index = String.Index(utf16Offset: lineRange.location, in: source)
            return String(source[..<index]) + insertion + "\n" + String(source[index...])
        case .end:
            return source + insertion
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
    let typingAnchor: TypingAnchor
    let typeText: String?
    let typeAfter: String?
    let typeRepeat: Int
    let typePhases: Bool

    init(_ arguments: ArraySlice<String>) {
        var filePath = "Tools/Mini/Mini/ReferenceSamples/Reference.swift"
        var explicitLanguage: SyntaxLanguage?
        var iterations = 20
        var repeatSource = 1
        var typingEdits = 0
        var typingAnchor: TypingAnchor = .end
        var typeText: String?
        var typeAfter: String?
        var typeRepeat = 1
        var typePhases = false
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
            case "--typing-anchor" where nextIndex < arguments.endIndex:
                typingAnchor = TypingAnchor(rawValue: arguments[nextIndex].lowercased()) ?? typingAnchor
                index = arguments.index(after: nextIndex)
            case "--type-text" where nextIndex < arguments.endIndex:
                typeText = arguments[nextIndex]
                    .replacingOccurrences(of: "\\n", with: "\n")
                index = arguments.index(after: nextIndex)
            case "--type-phases":
                typePhases = true
                index = nextIndex
            case "--type-repeat" where nextIndex < arguments.endIndex:
                typeRepeat = max(1, Int(arguments[nextIndex]) ?? 1)
                index = arguments.index(after: nextIndex)
            case "--type-after" where nextIndex < arguments.endIndex:
                typeAfter = arguments[nextIndex]
                    .replacingOccurrences(of: "\\n", with: "\n")
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
        self.typingAnchor = typingAnchor
        self.typeText = typeText
        self.typeAfter = typeAfter
        self.typeRepeat = typeRepeat
        self.typePhases = typePhases
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

private enum TypingAnchor: String {
    case start
    case middle
    case end
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

private struct PhasedBenchmarkSamples {
    let syntacticFastPassMilliseconds: [Double]
    let completeMilliseconds: [Double]
    let lastTokenCount: Int
    let lastRefreshRange: NSRange

    var syntacticFastPassMedianMilliseconds: Double? {
        guard !syntacticFastPassMilliseconds.isEmpty else { return nil }
        return Self.median(syntacticFastPassMilliseconds)
    }

    var completeMedianMilliseconds: Double {
        Self.median(completeMilliseconds)
    }

    private static func median(_ milliseconds: [Double]) -> Double {
        guard !milliseconds.isEmpty else { return 0 }
        let sorted = milliseconds.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
