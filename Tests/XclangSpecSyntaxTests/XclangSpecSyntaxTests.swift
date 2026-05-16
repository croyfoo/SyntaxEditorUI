import Foundation
import Testing
@testable import XclangSpecSyntax

@Suite("XclangSpecSyntax")
struct XclangSpecSyntaxTests {
    @Test("Document parser preserves Swift attribute lexer rules")
    func parsesSwiftAttributeRuleShape() throws {
        let document = try XclangSpecDocument(propertyList: [
            [
                "Identifier": "xcode.lang.swift.identifier.attribute",
                "Syntax": [
                    "StartChars": "@",
                    "Chars": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",
                    "Words": ["@available", "@attached", "@Observable"],
                    "Type": "xcode.syntax.keyword",
                    "AltType": "xcode.syntax.identifier",
                ],
            ],
        ])

        let rule = try #require(document.rules.first)
        let syntax = try #require(rule.syntax)
        #expect(rule.identifier == "xcode.lang.swift.identifier.attribute")
        #expect(syntax.startChars == "@")
        #expect(syntax.chars?.contains("_") == true)
        #expect(syntax.words == ["@available", "@attached", "@Observable"])
        #expect(syntax.type == "xcode.syntax.keyword")
        #expect(syntax.altType == "xcode.syntax.identifier")
    }

    @Test("Rule index resolves references from xclangspec rule fields")
    func ruleIndexResolvesReferenceClosureInputs() throws {
        let document = try XclangSpecDocument(propertyList: [
            [
                "Identifier": "xcode.lang.root",
                "BasedOn": "xcode.lang.base",
                "Syntax": [
                    "BasedOn": "xcode.lang.syntax-base",
                    "Tokenizer": "xcode.lang.lexer",
                    "IncludeRules": ["xcode.lang.include"],
                    "Rules": [
                        "xcode.lang.child|literal-token",
                        "xcode.lang.optional?",
                        "xcode.lang.repeated+",
                        "\n*",
                    ],
                    "Start": "xcode.lang.start",
                    "End": ["xcode.lang.end", "}"],
                    "AltUntil": "xcode.lang.alt-until",
                    "EntityNameMap": [
                        "amp": "xcode.lang.entity",
                    ],
                    "LanguageEmbeddings": [
                        "xcode.lang.embedded-z": ["zig"],
                        "xcode.lang.embedded": ["swift", "swiftui"],
                    ],
                    "Type": "xcode.syntax.definition.function",
                    "AltType": "xcode.syntax.identifier",
                    "CaptureTypes": [
                        "xcode.syntax.mark",
                        "xcode.syntax.url",
                    ],
                ],
            ],
            ["Identifier": "xcode.lang.base", "Syntax": ["Type": "xcode.syntax.plain"]],
            ["Identifier": "xcode.lang.syntax-base", "Syntax": ["Type": "xcode.syntax.plain"]],
            ["Identifier": "xcode.lang.lexer", "Syntax": ["Type": "xcode.syntax.plain"]],
            ["Identifier": "xcode.lang.include", "Syntax": ["Type": "xcode.syntax.keyword"]],
            ["Identifier": "xcode.lang.child", "Syntax": ["Type": "xcode.syntax.string"]],
            ["Identifier": "xcode.lang.optional", "Syntax": ["Type": "xcode.syntax.number"]],
            ["Identifier": "xcode.lang.repeated", "Syntax": ["Type": "xcode.syntax.identifier"]],
            ["Identifier": "xcode.lang.start", "Syntax": ["Type": "xcode.syntax.keyword"]],
            ["Identifier": "xcode.lang.end", "Syntax": ["Type": "xcode.syntax.keyword"]],
            ["Identifier": "xcode.lang.alt-until", "Syntax": ["Type": "xcode.syntax.keyword"]],
            ["Identifier": "xcode.lang.entity", "Syntax": ["Type": "xcode.syntax.entity"]],
            ["Identifier": "xcode.lang.embedded", "Syntax": ["Type": "xcode.syntax.plain"]],
            ["Identifier": "xcode.lang.embedded-z", "Syntax": ["Type": "xcode.syntax.plain"]],
        ])

        let index = XclangSpecRuleIndex(document: document)

        #expect(index.directRuleReferences(for: "xcode.lang.root") == [
            "xcode.lang.base",
            "xcode.lang.syntax-base",
            "xcode.lang.lexer",
            "xcode.lang.include",
            "xcode.lang.child",
            "xcode.lang.optional",
            "xcode.lang.repeated",
            "xcode.lang.start",
            "xcode.lang.end",
            "xcode.lang.alt-until",
            "xcode.lang.entity",
            "xcode.lang.embedded",
            "xcode.lang.embedded-z",
        ])
        #expect(index.ruleClosure(rootIdentifier: "xcode.lang.root").first == "xcode.lang.root")
        #expect(index.ruleClosure(rootIdentifier: "xcode.lang.root").contains("xcode.lang.optional"))
        #expect(index.syntaxTypes(in: ["xcode.lang.root"]) == [
            "xcode.syntax.definition.function",
            "xcode.syntax.identifier",
            "xcode.syntax.mark",
            "xcode.syntax.url",
        ])
    }

    @Test("Document parser accepts XML plist data")
    func documentParserAcceptsPropertyListData() throws {
        let propertyList: [[String: Any]] = [
            [
                "Identifier": "xcode.lang.test",
                "Name": "Test",
                "Syntax": [
                    "Start": "\"",
                    "End": "\"|\n",
                    "Type": "xcode.syntax.string",
                    "Foldable": true,
                ],
            ],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        let document = try XclangSpecDocument(data: data)
        let syntax = try #require(document.rules.first?.syntax)

        #expect(document.rules.first?.name == "Test")
        #expect(syntax.string("Start") == "\"")
        #expect(syntax.string("End") == "\"|\n")
        #expect(syntax.value(for: "Foldable")?.bool == true)
    }

    @Test("Document parser accepts old-style Xcode property lists")
    func documentParserAcceptsOldStylePropertyListData() throws {
        let source = """
        (
            {
                Identifier = "xcode.lang.test";
                IncludeInMenu = YES;
                Syntax = {
                    Foldable = YES;
                    IndentWidth = 4;
                    Match = ("^TODO:", "^FIXME:");
                    Type = "xcode.syntax.comment";
                };
            }
        )
        """

        let document = try XclangSpecDocument(data: Data(source.utf8))
        let rule = try #require(document.rules.first)
        let syntax = try #require(rule.syntax)

        #expect(rule.includeInMenu == true)
        #expect(syntax.foldable == true)
        #expect(syntax.indentWidth == 4)
        #expect(syntax.match == ["^TODO:", "^FIXME:"])
    }
}
