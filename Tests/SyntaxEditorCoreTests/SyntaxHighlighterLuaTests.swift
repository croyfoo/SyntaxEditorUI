import Foundation
import Testing
@testable import SyntaxEditorCore

extension SyntaxHighlighterEngineTests {
    @Test("SyntaxHighlighterEngine classifies Lua keywords, strings, comments and calls")
    func highlighterClassifiesLua() async {
        let source = "-- greet\nlocal function greet(name)\n  print(\"hi \" .. name)\nend\n"
        let tokens = await sharedSyntaxHighlighterEngine.render(source: source, language: .lua)
        let ns = source as NSString
        let kinds = Dictionary(tokens.map { (ns.substring(with: $0.range), $0.syntaxID) },
                               uniquingKeysWith: { _, last in last })
        #expect(kinds["-- greet"] == .comment)
        #expect(kinds["local"] == .keyword)
        #expect(kinds["end"] == .keyword)
        #expect(kinds["\"hi \""] == .string)
        #expect(kinds["greet"] == .identifierFunction)
        #expect(kinds["print"] == .identifierFunctionSystem)
    }
}
