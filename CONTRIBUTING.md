# Contributing

Use this guide to run package checks, preview changes in Mini, and build the documentation site.

## Requirements

Use Swift 6.3 or later and Xcode with the SDKs needed for the platform you are checking.

## Tests

```bash
swift test
xcrun simctl list devices available
DESTINATION='platform=iOS Simulator,id=<simulator-udid>'
xcodebuild test -workspace SyntaxEditorUI.xcworkspace -scheme SyntaxEditorUITests -testPlan SyntaxEditorUITests -only-testing:SyntaxEditorCorePlatformTests -only-testing:SyntaxEditorUITests -destination "$DESTINATION" -enableCodeCoverage NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1
```

GitHub Actions runs `swift test` on macOS for package-wide coverage, then runs `SyntaxEditorCorePlatformTests` and `SyntaxEditorUITests` on the latest available iOS simulator for UIKit-specific coverage.

`Mini` is a lightweight manual verification app for iOS/macOS. It is not a public product and does not own package regression tests.

## Performance Benchmarks

Highlighting performance benchmarks are exposed through the SwiftPM `benchmark` plugin:

```bash
swift package benchmark list --target HighlightBenchmark
swift package benchmark run --target HighlightBenchmark --filter 'fixture-swift-structural-edit/highlight/incremental-update' --time-units microseconds --no-progress
swift package --allow-writing-to-package-directory benchmark baseline update before --target HighlightBenchmark --filter 'fixture-swift-structural-edit/highlight/incremental-update'
swift package benchmark baseline compare before --target HighlightBenchmark --filter 'fixture-swift-structural-edit/highlight/incremental-update'
SYNTAX_EDITOR_BENCHMARK_FILE=/path/to/file.swift swift package benchmark run --target HighlightBenchmark
```

The benchmark suite uses bundled reference samples by default and repeats them to around 10,000 lines. Large cases repeat to around 50,000 lines. Set `SYNTAX_EDITOR_BENCHMARK_FILE` to benchmark a custom file, and optionally set `SYNTAX_EDITOR_BENCHMARK_LANGUAGE`, `SYNTAX_EDITOR_BENCHMARK_REPEAT_SOURCE`, `SYNTAX_EDITOR_BENCHMARK_ITERATIONS`, `SYNTAX_EDITOR_BENCHMARK_TYPING_EDITS`, `SYNTAX_EDITOR_BENCHMARK_TYPING_ANCHOR`, `SYNTAX_EDITOR_BENCHMARK_TYPE_TEXT`, `SYNTAX_EDITOR_BENCHMARK_TYPE_AFTER`, or `SYNTAX_EDITOR_BENCHMARK_TYPE_REPEAT` to adjust the run. `SYNTAX_EDITOR_BENCHMARK_REPEAT_SOURCE` overrides the default sample amplification.

Benchmarks are intended for local development and are not part of regular CI. Performance regression checks should run on a dedicated machine or a manually triggered workflow to avoid shared-runner noise.

## Documentation

Build the same static DocC site that the deployment workflow publishes:

```bash
./Tools/build-documentation.sh .build/documentation/SyntaxEditorUI /SyntaxEditorUI
python3 -m http.server 8000 --bind 127.0.0.1 --directory .build/documentation
```

The output directory must not already exist. Open `http://localhost:8000/SyntaxEditorUI/` to preview the site. For a site hosted at the domain root, omit the second argument and serve the output directory itself.

The build compiles the public product for UIKit and AppKit, extracts its re-exported public symbols, and converts the catalogs with warnings treated as errors. It also checks comments on package-defined APIs, using compiler metadata to distinguish overrides and implementations of external protocol requirements.

Documentation has three homes:

- Public declaration comments describe each symbol's contract.
- `Documentation/Shared` contains guides used by both platform references.
- `Documentation/UIKit.docc` and `Documentation/AppKit.docc` contain platform-specific integration guides; `Documentation/SyntaxEditorUI.docc` is the site entry point.

Keep README focused on installation and the first editor. Put detailed usage and migration guidance in DocC, and development commands in this guide.

## Publishing documentation

The documentation workflow deploys after every push to `main` and can also be run manually on `main`. Configure the repository's GitHub Pages source as **GitHub Actions** before the first deployment.

The published site is served at [SyntaxEditorUI documentation](https://lynnswap.github.io/SyntaxEditorUI/).
