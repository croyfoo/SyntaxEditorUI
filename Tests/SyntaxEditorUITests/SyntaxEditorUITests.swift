import Foundation
import Testing
@testable import SyntaxEditorUI

#if canImport(AppKit)
import AppKit
#endif

private final class CustomLanguageRecorder: @unchecked Sendable {
    var toggleCommentCallCount = 0
    var literalCheckLocations: [Int] = []
}

private struct RecordingLanguage: SyntaxLanguage {
    let recorder: CustomLanguageRecorder
    let shouldTreatLocationAsLiteral: Bool

    var identifier: String { "recording-language" }
    var displayName: String { "Recording" }
    var treeSitterSupport: SyntaxTreeSitterSupport { BuiltinSyntaxLanguages.json.treeSitterSupport }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        recorder.toggleCommentCallCount += 1
        return SyntaxLanguageEdit(
            text: "// " + source,
            selectedRange: NSRange(location: selection.location + 3, length: selection.length)
        )
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        recorder.literalCheckLocations.append(location)
        return shouldTreatLocationAsLiteral
    }
}

private struct WrappedJSONLanguage: SyntaxLanguage {
    var identifier: String { "wrapped-json" }
    var displayName: String { "Wrapped JSON" }
    var treeSitterSupport: SyntaxTreeSitterSupport { BuiltinSyntaxLanguages.json.treeSitterSupport }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        nil
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        BuiltinSyntaxLanguages.json.isInsideLiteralOrComment(source: source, location: location)
    }
}

private struct WrappedHTMLLanguage: SyntaxLanguage {
    var identifier: String { "wrapped-html" }
    var displayName: String { "Wrapped HTML" }
    var treeSitterSupport: SyntaxTreeSitterSupport { BuiltinSyntaxLanguages.html.treeSitterSupport }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        BuiltinSyntaxLanguages.html.toggleComment(source: source, selection: selection)
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        BuiltinSyntaxLanguages.html.isInsideLiteralOrComment(source: source, location: location)
    }
}

private struct CustomCachedHTMLLanguage: SyntaxLanguage {
    var identifier: String { "custom-cached-html" }
    var displayName: String { "Custom Cached HTML" }
    var treeSitterSupport: SyntaxTreeSitterSupport {
        let support = BuiltinSyntaxLanguages.html.treeSitterSupport
        return SyntaxTreeSitterSupport(
            name: support.name,
            bundleName: "CustomTreeSitterHTML",
            queryDirectories: [Self.htmlQueriesURL],
            cacheKey: "custom-cached-html-with-query-directory",
            makeLanguage: support.makeLanguage
        )
    }

    private static var htmlQueriesURL: URL {
        let fileManager = FileManager.default
        let bundleName = "\(BuiltinSyntaxLanguages.html.treeSitterSupport.bundleName).bundle"

        let bundleURLs =
            [Bundle.main.bundleURL] +
            Bundle.allBundles.map(\.bundleURL) +
            Bundle.allFrameworks.map(\.bundleURL)
        for bundleURL in bundleURLs where bundleURL.lastPathComponent == bundleName {
            let candidates = [
                bundleURL.appendingPathComponent("queries", isDirectory: true),
                bundleURL.appendingPathComponent("Contents/Resources/queries", isDirectory: true),
            ]
            if let queriesURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
                return queriesURL
            }
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildRoot = repoRoot.appendingPathComponent(".build", isDirectory: true)
        if let enumerator = fileManager.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: nil
        ) {
            for case let candidate as URL in enumerator {
                guard candidate.lastPathComponent == "queries",
                      candidate.deletingLastPathComponent().lastPathComponent == bundleName
                else {
                    continue
                }
                return candidate
            }
        }

        return buildRoot
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        BuiltinSyntaxLanguages.html.toggleComment(source: source, selection: selection)
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        BuiltinSyntaxLanguages.html.isInsideLiteralOrComment(source: source, location: location)
    }
}

private struct SharedIdentifierLanguage: SyntaxLanguage {
    let identifier: String
    let displayName: String
    let treeSitterSupport: SyntaxTreeSitterSupport

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguageEdit? {
        nil
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        false
    }
}

@Suite("SyntaxEditorUI")
struct SyntaxEditorUITests {
    @Test("BuiltinSyntaxLanguages.named maps supported values")
    func builtinSyntaxLanguagesNamed() {
        #expect(BuiltinSyntaxLanguages.named("css")?.identifier == BuiltinSyntaxLanguages.css.identifier)
        #expect(BuiltinSyntaxLanguages.named("html")?.identifier == BuiltinSyntaxLanguages.html.identifier)
        #expect(BuiltinSyntaxLanguages.named("HTM")?.identifier == BuiltinSyntaxLanguages.html.identifier)
        #expect(BuiltinSyntaxLanguages.named(" javascript ")?.identifier == BuiltinSyntaxLanguages.javascript.identifier)
        #expect(BuiltinSyntaxLanguages.named("JS")?.identifier == BuiltinSyntaxLanguages.javascript.identifier)
        #expect(BuiltinSyntaxLanguages.named("JSON")?.identifier == BuiltinSyntaxLanguages.json.identifier)
        #expect(BuiltinSyntaxLanguages.named("Swift")?.identifier == BuiltinSyntaxLanguages.swift.identifier)
    }

    @Test("BuiltinSyntaxLanguages.named rejects unsupported values")
    func builtinSyntaxLanguagesRejectUnsupportedValue() {
        #expect(BuiltinSyntaxLanguages.named("toml") == nil)
    }

    @Test("SyntaxEditorModel stores and mutates state on MainActor")
    @MainActor
    func syntaxEditorModelState() {
        let model = SyntaxEditorModel(text: "{}", language: BuiltinSyntaxLanguages.json)

        #expect(model.text == "{}")
        #expect(model.language.identifier == BuiltinSyntaxLanguages.json.identifier)
        #expect(model.isEditable == true)
        #expect(model.lineWrappingEnabled == false)

        model.text = "body { color: red; }"
        model.language = BuiltinSyntaxLanguages.css
        model.isEditable = false
        model.lineWrappingEnabled = true

        #expect(model.text == "body { color: red; }")
        #expect(model.language.identifier == BuiltinSyntaxLanguages.css.identifier)
        #expect(model.isEditable == false)
        #expect(model.lineWrappingEnabled == true)
    }

    @Test("SyntaxEditorHighlightTheme maps representative captures to Xcode-like palette")
    func syntaxEditorHighlightThemeMapping() {
        #expect(
            SyntaxEditorHighlightTheme.colorPair(for: "keyword.control")
                == SyntaxEditorHexColorPair(light: 0xAD3DA4, dark: 0xFC5FA3)
        )
        #expect(
            SyntaxEditorHighlightTheme.colorPair(for: "string.quoted")
                == SyntaxEditorHexColorPair(light: 0xC41A16, dark: 0xFC6A5D)
        )
        #expect(
            SyntaxEditorHighlightTheme.colorPair(for: "number")
                == SyntaxEditorHexColorPair(light: 0x1C00CF, dark: 0xD0BF69)
        )
        #expect(SyntaxEditorHighlightTheme.colorPair(for: "unknown.capture") == nil)
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

    @Test("EditorCommandEngine auto-pairs opening braces")
    func editorCommandEngineAutoPair() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "",
            range: NSRange(location: 0, length: 0),
            replacementText: "{",
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == "{}")
        #expect(result?.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("EditorCommandEngine wraps selected text with quote")
    func editorCommandEngineWrapSelection() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "value",
            range: NSRange(location: 0, length: 5),
            replacementText: "\"",
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == "\"value\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine skips duplicate closing brace")
    func editorCommandEngineSkipClosingBrace() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "{}",
            range: NSRange(location: 1, length: 0),
            replacementText: "}",
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == "{}")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source)
        #expect(result?.selectedRange == NSRange(location: 8, length: 0))
    }

    @Test("EditorCommandEngine inserts smart newline in brace block")
    func editorCommandEngineSmartNewline() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "{}",
            range: NSRange(location: 1, length: 0),
            replacementText: "\n",
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == "{\n    \n}")
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
                language: BuiltinSyntaxLanguages.javascript
            ) else {
                Issue.record("Smart newline unexpectedly returned nil")
                return
            }
            source = result.text
            selection = result.selectedRange
        }

        #expect(source.contains("\n"))
    }

    @Test("EditorCommandEngine outdents closing brace at line start")
    func editorCommandEngineClosingBraceOutdent() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "    ",
            range: NSRange(location: 4, length: 0),
            replacementText: "}",
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == "}")
        #expect(result?.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("EditorCommandEngine outdents closing brace by one tab width")
    func editorCommandEngineClosingBraceOutdentWithTabs() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "\t\t",
            range: NSRange(location: 2, length: 0),
            replacementText: "}",
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == "\t}")
        #expect(result?.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test("EditorCommandEngine deletes paired symbols together")
    func editorCommandEnginePairBackspace() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "()",
            range: NSRange(location: 0, length: 1),
            replacementText: "",
            language: BuiltinSyntaxLanguages.javascript,
            deletionIntent: .backward
        )

        #expect(result?.text == "")
        #expect(result?.selectedRange == NSRange(location: 0, length: 0))
    }

    @Test("EditorCommandEngine does not pair-delete one-character selections")
    func editorCommandEngineSelectionDeleteDoesNotPairBackspace() {
        let engine = EditorCommandEngine()
        let result = engine.transformInput(
            source: "{}",
            range: NSRange(location: 0, length: 1),
            replacementText: "",
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine indents selected lines")
    func editorCommandEngineIndentSelection() {
        let engine = EditorCommandEngine()
        let result = engine.indentSelection(
            source: "a\nb\n",
            selection: NSRange(location: 0, length: 3)
        )

        #expect(result?.text == "    a\n    b\n")
    }

    @Test("EditorCommandEngine indents trailing empty line at document end")
    func editorCommandEngineIndentTrailingEmptyLine() {
        let engine = EditorCommandEngine()
        let source = "a\n"
        let result = engine.indentSelection(
            source: source,
            selection: NSRange(location: source.utf16.count, length: 0)
        )

        #expect(result?.text == "a\n    ")
    }

    @Test("EditorCommandEngine outdents selected lines")
    func editorCommandEngineOutdentSelection() {
        let engine = EditorCommandEngine()
        let result = engine.outdentSelection(
            source: "    a\n    b\n",
            selection: NSRange(location: 0, length: 11)
        )

        #expect(result?.text == "a\nb\n")
    }

    @Test("EditorCommandEngine keeps caret on current line when outdenting overlapping indent")
    func editorCommandEngineOutdentSelectionClampsCaretInsideRemovedIndent() {
        let engine = EditorCommandEngine()
        let source = "x\n    y"
        let result = engine.outdentSelection(
            source: source,
            selection: NSRange(location: 4, length: 0)
        )

        #expect(result?.text == "x\ny")
        #expect(result?.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test("EditorCommandEngine toggles JavaScript line comments")
    func editorCommandEngineToggleJavaScriptComments() {
        let engine = EditorCommandEngine()
        let source = "let a = 1;\nlet b = 2;\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(first?.text == "// let a = 1;\n// let b = 2;\n")

        let second = engine.toggleComment(
            source: first?.text ?? "",
            selection: NSRange(location: 0, length: first?.text.utf16.count ?? 0),
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(second?.text == source)
    }

    @Test("EditorCommandEngine toggles Swift line comments")
    func editorCommandEngineToggleSwiftComments() {
        let engine = EditorCommandEngine()
        let source = "let a = 1\nlet b = 2\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: BuiltinSyntaxLanguages.swift
        )

        #expect(first?.text == "// let a = 1\n// let b = 2\n")

        let second = engine.toggleComment(
            source: first?.text ?? "",
            selection: NSRange(location: 0, length: first?.text.utf16.count ?? 0),
            language: BuiltinSyntaxLanguages.swift
        )

        #expect(second?.text == source)
    }

    @Test("EditorCommandEngine toggles CSS block comment")
    func editorCommandEngineToggleCSSComment() {
        let engine = EditorCommandEngine()
        let source = "color: red;\n"

        let first = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: BuiltinSyntaxLanguages.css
        )

        #expect(first?.text.contains("/*") == true)
        #expect(first?.text.contains("*/") == true)

        let second = engine.toggleComment(
            source: first?.text ?? "",
            selection: NSRange(location: 0, length: first?.text.utf16.count ?? 0),
            language: BuiltinSyntaxLanguages.css
        )

        #expect(second?.text == source)
    }

    @Test("EditorCommandEngine does not unwrap multiple CSS comments as one block")
    func editorCommandEngineCssCommentToggleNoopForMultipleIndependentBlocks() {
        let engine = EditorCommandEngine()
        let source = "/* a */\n/* b */\n"
        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: BuiltinSyntaxLanguages.css
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
            language: BuiltinSyntaxLanguages.css
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(first?.text == "<!-- <div>hello</div>\n -->")

        let second = engine.toggleComment(
            source: first?.text ?? "",
            selection: NSRange(location: 0, length: first?.text.utf16.count ?? 0),
            language: BuiltinSyntaxLanguages.html
        )

        #expect(second?.text == source)
    }

    @Test("EditorCommandEngine does not wrap HTML comments around double hyphen text")
    func editorCommandEngineDoesNotWrapHTMLCommentAroundDoubleHyphenText() {
        let engine = EditorCommandEngine()
        let source = "alpha -- beta\n"

        let result = engine.toggleComment(
            source: source,
            selection: NSRange(location: 0, length: source.utf16.count),
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result == nil)
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == "\(startTag)// const answer = 42;\n</script>")
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == "<script/>// const answer = 42;\n</script>")
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == "\(startTag)// const answer = 42;\n</script>")
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == "\(startTag)// const answer = 42;\n</script>")
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text.contains("<!-- <span>Hello</span>") == true)
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == "<style>/* body { color: red; }\n */</style>")
    }

    @Test("EditorCommandEngine does not fall back to HTML comments for blank script lines")
    func editorCommandEngineDoesNotFallbackToHTMLCommentsForBlankScriptLines() {
        let engine = EditorCommandEngine()
        let source = "<script>\n</script>"
        let selection = NSRange(location: 8, length: 0)

        let result = engine.toggleComment(
            source: source,
            selection: selection,
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == """
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == """
        <script>const marker = \"</script>\";
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == """
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == """
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == """
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == """
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == """
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == source + "\"\"")
        #expect(result?.selectedRange == NSRange(location: source.utf16.count + 1, length: 0))
    }

    @Test("EditorCommandEngine returns no-op for JSON comments")
    func editorCommandEngineJsonCommentNoop() {
        let engine = EditorCommandEngine()
        let result = engine.toggleComment(
            source: "{\"a\":1}",
            selection: NSRange(location: 0, length: 7),
            language: BuiltinSyntaxLanguages.json
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.swift
        )

        #expect(result == nil)
    }

    @Test("EditorCommandEngine auto-pairs HTML quote in attribute assignment")
    func editorCommandEngineAutoPairHTMLQuoteInAttributeAssignment() {
        let engine = EditorCommandEngine()
        let source = "<div class="
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == "<div class=\"\"")
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == prefix + "\"\"" + "</script>")
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
            language: BuiltinSyntaxLanguages.html
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
            language: BuiltinSyntaxLanguages.html
        )

        #expect(result?.text == prefix + "\"\"" + "</style>")
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
            language: BuiltinSyntaxLanguages.html
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
                language: BuiltinSyntaxLanguages.html
            )

            #expect(result == nil)
        }
    }

    @Test("EditorCommandEngine auto-pairs Swift quote after URL literal prefix")
    func editorCommandEngineAutoPairSwiftQuoteAfterURLLiteral() {
        let engine = EditorCommandEngine()
        let source = "let url = \"https://a\"; let value = "
        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: BuiltinSyntaxLanguages.swift
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.swift
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
            language: BuiltinSyntaxLanguages.swift
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.swift
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
            language: BuiltinSyntaxLanguages.swift
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
            language: BuiltinSyntaxLanguages.css
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
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
            language: BuiltinSyntaxLanguages.javascript
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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
            language: BuiltinSyntaxLanguages.javascript
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
            language: BuiltinSyntaxLanguages.javascript
        )

        #expect(result?.text == source + "\"\"")
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

    @Test("SyntaxHighlighterEngine returns no tokens for empty source")
    func highlighterReturnsNoTokensForEmptySource() async {
        let engine = SyntaxHighlighterEngine()
        let tokens = await engine.render(source: "", language: BuiltinSyntaxLanguages.javascript)
        #expect(tokens.isEmpty)
    }

    @Test("SyntaxHighlighterEngine produces highlight tokens for supported languages")
    func highlighterProducesTokens() async {
        let engine = SyntaxHighlighterEngine()
        let cases: [(language: any SyntaxLanguage, source: String)] = [
            (BuiltinSyntaxLanguages.css, "body { color: red; }"),
            (BuiltinSyntaxLanguages.html, "<!-- note --><div class=\"hero\">Hello</div>"),
            (BuiltinSyntaxLanguages.javascript, "const answer = 42;"),
            (BuiltinSyntaxLanguages.json, "{\"enabled\": true, \"count\": 1}"),
            (BuiltinSyntaxLanguages.swift, "let answer = 42"),
        ]

        for testCase in cases {
            let tokens = await engine.render(source: testCase.source, language: testCase.language)
            #expect(tokens.isEmpty == false)
            #expect(tokens.allSatisfy { $0.range.length > 0 })
        }
    }

    @Test("SyntaxHighlighterEngine is stable for repeated renders")
    func highlighterRepeatedRenderStability() async {
        let engine = SyntaxHighlighterEngine()
        let source = "const value = 42; const message = 'ok';"

        let first = await engine.render(source: source, language: BuiltinSyntaxLanguages.javascript)
        let second = await engine.render(source: source, language: BuiltinSyntaxLanguages.javascript)

        #expect(first.isEmpty == false)
        #expect(first.count == second.count)
    }

    @Test("SyntaxHighlighterEngine returns UTF-16-safe ranges for non-ASCII source")
    func highlighterHandlesNonASCIIRanges() async {
        let engine = SyntaxHighlighterEngine()
        let source = "const label = \"こんにちは😀\";"
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.javascript)
        let sourceLength = source.utf16.count

        #expect(tokens.isEmpty == false)
        #expect(tokens.allSatisfy { token in
            token.range.location >= 0 &&
            token.range.length > 0 &&
            token.range.upperBound <= sourceLength
        })
    }

    @Test("SyntaxHighlighterEngine highlights HTML root and embedded languages")
    func highlighterSupportsHTMLInjections() async {
        let engine = SyntaxHighlighterEngine()
        let source = """
        😀
        <!-- note -->
        <style>body { color: red; }</style>
        <script>const answer = 42;</script>
        <div class="hero">Hello</div>
        """

        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let nsSource = source as NSString
        let stylePropertyRange = nsSource.range(of: "color")
        let scriptKeywordRange = nsSource.range(of: "const")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains { $0.captureName.hasPrefix("comment") })
        #expect(tokens.contains { $0.captureName.hasPrefix("tag") })
        #expect(tokens.contains { $0.captureName.hasPrefix("attribute") })
        #expect(tokens.contains {
            $0.captureName.hasPrefix("property") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: stylePropertyRange).length > 0
        })
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: scriptKeywordRange).length > 0
        })
    }

    @Test("SyntaxHighlighterEngine highlights embedded languages for wrapped HTML")
    func highlighterSupportsWrappedHTMLInjections() async {
        let engine = SyntaxHighlighterEngine()
        let language = WrappedHTMLLanguage()
        let source = """
        <style>body { color: red; }</style>
        <script>const answer = 42;</script>
        <section class="hero">Hello</section>
        """

        let tokens = await engine.render(source: source, language: language)
        let nsSource = source as NSString
        let stylePropertyRange = nsSource.range(of: "color")
        let scriptKeywordRange = nsSource.range(of: "const")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            $0.captureName.hasPrefix("property") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: stylePropertyRange).length > 0
        })
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: scriptKeywordRange).length > 0
        })
    }

    @Test("SyntaxHighlighterEngine does not inject unsupported script types")
    func highlighterSkipsUnsupportedScriptTypeInjections() async {
        let engine = SyntaxHighlighterEngine()
        let source = #"<script type="application/json">{"enabled": true}</script>"#
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            $0.captureName.hasPrefix("tag") || $0.captureName.hasPrefix("attribute")
        })
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: trueRange).length > 0
        } == false)
    }

    @Test("SyntaxHighlighterEngine does not inject non-JavaScript script types")
    func highlighterSkipsNonJavaScriptScriptTypeInjections() async {
        let engine = SyntaxHighlighterEngine()
        let source = #"<script type="text/plain">const answer = true;</script>"#
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let constRange = (source as NSString).range(of: "const")
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: constRange).length > 0
        } == false)
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: trueRange).length > 0
        } == false)
    }

    @Test("SyntaxHighlighterEngine masks unsupported script types through EOF when closing tags are missing")
    func highlighterMasksUnsupportedScriptTypesThroughEOFWithoutClosingTag() async {
        let engine = SyntaxHighlighterEngine()
        let source = #"<script type="application/json">{"enabled": true}"#
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: trueRange).length > 0
        } == false)
    }

    @Test("SyntaxHighlighterEngine keeps highlighting supported script content past literal closing tag text")
    func highlighterKeepsHighlightingSupportedScriptContentPastLiteralClosingTagText() async {
        let engine = SyntaxHighlighterEngine()
        let source = #"<script>const marker = "</script>"; const answer = 42;</script>"#
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let answerConstRange = (source as NSString).range(of: "const answer")

        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: answerConstRange).length > 0
        })
    }

    @Test("SyntaxHighlighterEngine ignores commented-out raw text tags")
    func highlighterIgnoresCommentedOutRawTextTags() async {
        let engine = SyntaxHighlighterEngine()
        let source = """
        <!-- <script type="text/plain"> -->
        <div class="hero">Hello</div>
        """
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let divRange = (source as NSString).range(of: "<div")

        #expect(tokens.contains {
            $0.captureName.hasPrefix("tag") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: divRange).length > 0
        })
    }

    @Test("SyntaxHighlighterEngine does not stop masking on longer unsupported script closing prefixes")
    func highlighterKeepsMaskingUnsupportedScriptContentPastLongerClosingPrefixes() async {
        let engine = SyntaxHighlighterEngine()
        let source = #"<script type="application/json">{"marker":"</scripted>","enabled":true}</script>"#
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: trueRange).length > 0
        } == false)
    }

    @Test("SyntaxHighlighterEngine does not inject unsupported script types when start tags contain quoted angle brackets")
    func highlighterSkipsUnsupportedScriptTypeInjectionsWithQuotedAngleBracketInStartTag() async {
        let engine = SyntaxHighlighterEngine()
        let source = #"<script data="a>b" type="application/json">{"enabled": true}</script>"#
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: trueRange).length > 0
        } == false)
    }

    @Test("SyntaxHighlighterEngine ignores raw-text-like attribute text")
    func highlighterIgnoresRawTextLikeAttributeText() async {
        let engine = SyntaxHighlighterEngine()
        let source = """
        <div data='<script type="application/json">'>Container</div>
        <span class="hero">Hello</span>
        """
        let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
        let spanRange = (source as NSString).range(of: "<span")

        #expect(tokens.contains {
            $0.captureName.hasPrefix("tag") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: spanRange).length > 0
        })
    }

    @Test("SyntaxHighlighterEngine masks unsupported script types for custom HTML support")
    func highlighterMasksUnsupportedScriptTypesForCustomHTMLSupport() async {
        let engine = SyntaxHighlighterEngine()
        let source = #"<script type="application/json">{"enabled": true}</script>"#
        let tokens = await engine.render(source: source, language: CustomCachedHTMLLanguage())
        let trueRange = (source as NSString).range(of: "true")

        #expect(tokens.isEmpty == false)
        #expect(tokens.contains {
            $0.captureName.hasPrefix("keyword") &&
                SyntaxEditorRangeUtilities.intersection(of: $0.range, and: trueRange).length > 0
        } == false)
    }

    @Test("SyntaxHighlighterEngine skips malformed attribute tokens in unsupported script tags")
    func highlighterSkipsMalformedAttributeTokensInUnsupportedScriptTags() async {
        let engine = SyntaxHighlighterEngine()
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
            let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
            let trueRange = (source as NSString).range(of: "true")

            #expect(tokens.isEmpty == false)
            #expect(tokens.contains {
                $0.captureName.hasPrefix("keyword") &&
                    SyntaxEditorRangeUtilities.intersection(of: $0.range, and: trueRange).length > 0
            } == false)
        }
    }

    @Test("SyntaxHighlighterEngine ignores malformed type-like attribute suffixes")
    func highlighterIgnoresMalformedTypeLikeAttributeSuffixes() async {
        let engine = SyntaxHighlighterEngine()
        let cases = [
            #"<script !type="application/json">const answer = 42;</script>"#,
            #"<script data!type="application/json">const answer = 42;</script>"#,
            #"<script !foo="bar type="application/json">const answer = 42;</script>"#,
        ]

        for source in cases {
            let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
            let constRange = (source as NSString).range(of: "const")

            #expect(tokens.contains {
                $0.captureName.hasPrefix("keyword") &&
                    SyntaxEditorRangeUtilities.intersection(of: $0.range, and: constRange).length > 0
            })
        }
    }

    @Test("SyntaxHighlighterEngine treats malformed unquoted unsupported script types as unsupported")
    func highlighterTreatsMalformedUnquotedUnsupportedScriptTypesAsUnsupported() async {
        let engine = SyntaxHighlighterEngine()
        let cases = [
            #"<script type=module=foo>const answer = true;</script>"#,
            #"<script type=text/plain/>const answer = true;</script>"#,
        ]

        for source in cases {
            let tokens = await engine.render(source: source, language: BuiltinSyntaxLanguages.html)
            let constRange = (source as NSString).range(of: "const")

            #expect(tokens.contains {
                $0.captureName.hasPrefix("keyword") &&
                    SyntaxEditorRangeUtilities.intersection(of: $0.range, and: constRange).length > 0
            } == false)
        }
    }

    @Test("EditorCommandEngine delegates toggle comment to custom language")
    func editorCommandEngineDelegatesToggleCommentToCustomLanguage() {
        let engine = EditorCommandEngine()
        let recorder = CustomLanguageRecorder()
        let language = RecordingLanguage(recorder: recorder, shouldTreatLocationAsLiteral: false)

        let result = engine.toggleComment(
            source: "value = 1",
            selection: NSRange(location: 0, length: 5),
            language: language
        )

        #expect(recorder.toggleCommentCallCount == 1)
        #expect(result?.text == "// value = 1")
        #expect(result?.selectedRange == NSRange(location: 3, length: 5))
    }

    @Test("EditorCommandEngine delegates quote suppression to custom language")
    func editorCommandEngineDelegatesLiteralDetectionToCustomLanguage() {
        let engine = EditorCommandEngine()
        let recorder = CustomLanguageRecorder()
        let source = "value = "
        let language = RecordingLanguage(recorder: recorder, shouldTreatLocationAsLiteral: true)

        let result = engine.transformInput(
            source: source,
            range: NSRange(location: source.utf16.count, length: 0),
            replacementText: "\"",
            language: language
        )

        #expect(result == nil)
        #expect(recorder.literalCheckLocations == [source.utf16.count])
    }

    @Test("SyntaxHighlighterEngine supports custom language wrappers")
    func highlighterSupportsCustomLanguageWrappers() async {
        let engine = SyntaxHighlighterEngine()
        let language = WrappedJSONLanguage()
        let tokens = await engine.render(
            source: "{\"enabled\": true, \"count\": 1}",
            language: language
        )

        #expect(tokens.isEmpty == false)
        #expect(tokens.allSatisfy { $0.range.length > 0 })
    }

    @Test("SyntaxLanguage highlight cache key changes when support changes")
    func syntaxLanguageHighlightCacheKeyReflectsSupport() {
        let json = SharedIdentifierLanguage(
            identifier: "shared-language",
            displayName: "Shared JSON",
            treeSitterSupport: BuiltinSyntaxLanguages.json.treeSitterSupport
        )
        let css = SharedIdentifierLanguage(
            identifier: "shared-language",
            displayName: "Shared CSS",
            treeSitterSupport: BuiltinSyntaxLanguages.css.treeSitterSupport
        )

        #expect(json.syntaxHighlightCacheKey != css.syntaxHighlightCacheKey)
    }

    @Test("SyntaxHighlighterEngine separates shared identifiers by support")
    func highlighterSeparatesSharedIdentifiersBySupport() async {
        let engine = SyntaxHighlighterEngine()
        let json = SharedIdentifierLanguage(
            identifier: "shared-language",
            displayName: "Shared JSON",
            treeSitterSupport: BuiltinSyntaxLanguages.json.treeSitterSupport
        )
        let css = SharedIdentifierLanguage(
            identifier: "shared-language",
            displayName: "Shared CSS",
            treeSitterSupport: BuiltinSyntaxLanguages.css.treeSitterSupport
        )

        let jsonTokens = await engine.render(source: "{\"enabled\": true}", language: json)
        let cssTokens = await engine.render(source: "body { color: red; }", language: css)

        #expect(jsonTokens.isEmpty == false)
        #expect(cssTokens.isEmpty == false)
    }

#if canImport(AppKit)
    @MainActor
    private func waitUntilViewControllerCondition(
        nanoseconds: UInt64 = 5_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .nanoseconds(Int64(nanoseconds)))

        while !condition() {
            guard clock.now < deadline else {
                return false
            }
            await Task.yield()
        }

        return true
    }

    @Test("SyntaxEditorViewController enables undo support on macOS")
    @MainActor
    func syntaxEditorViewControllerMacUndo() {
        let model = SyntaxEditorModel(text: "{}", language: BuiltinSyntaxLanguages.javascript)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        let textView = controller.textView
        #expect(textView.allowsUndo == true)
    }

    @Test("SyntaxEditorViewController reflects model text mutations on macOS")
    @MainActor
    func syntaxEditorViewControllerMacTextObservation() async {
        let model = SyntaxEditorModel(text: "const answer = 42;", language: BuiltinSyntaxLanguages.javascript)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.text = "{\"enabled\":true}"

        #expect(await waitUntilViewControllerCondition {
            controller.textView.string == "{\"enabled\":true}"
        })
    }

    @Test("SyntaxEditorViewController reflects editable and wrapping changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacEditorStateObservation() async {
        let model = SyntaxEditorModel(text: "body {}", language: BuiltinSyntaxLanguages.css)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.isEditable = false
        model.lineWrappingEnabled = true

        #expect(await waitUntilViewControllerCondition {
            controller.textView.isEditable == false
        })
        #expect(await waitUntilViewControllerCondition {
            controller.scrollView.hasHorizontalScroller == false
        })

        model.lineWrappingEnabled = false

        #expect(await waitUntilViewControllerCondition {
            controller.scrollView.hasHorizontalScroller == true
        })
    }

    @Test("SyntaxEditorViewController keeps synchronizing after language changes on macOS")
    @MainActor
    func syntaxEditorViewControllerMacLanguageChangeKeepsObservationAlive() async {
        let model = SyntaxEditorModel(text: "let answer = 42", language: BuiltinSyntaxLanguages.swift)
        let controller = SyntaxEditorViewController(model: model)
        controller.loadViewIfNeeded()

        model.language = BuiltinSyntaxLanguages.json
        model.isEditable = false

        #expect(await waitUntilViewControllerCondition {
            controller.textView.isEditable == false
        })

        model.text = "{\"answer\":42}"

        #expect(await waitUntilViewControllerCondition {
            controller.textView.string == "{\"answer\":42}"
        })
    }
#endif
}
