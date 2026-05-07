import SyntaxEditorUI

extension MiniPreviewPreset:Hashable,Identifiable{
    nonisolated static func == (lhs: MiniPreviewPreset, rhs: MiniPreviewPreset) -> Bool {
        lhs.id == rhs.id
    }
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct MiniPreviewPreset {
    enum ID: String, CaseIterable, Sendable {
        case css
        case html
        case javascript
        case json
        case objectiveC = "objective-c"
        case swift
        case toml
        case xml
    }

    let id: ID
    let sampleText: String
    let language: SyntaxLanguage

    var title: String {
        language.displayName
    }

    var accessibilityIdentifier: String {
        "mini.language.\(id.rawValue)"
    }

    static let css = MiniPreviewPreset(
        id: .css,
        sampleText: "body {\n    color: red;\n    background: white;\n}\n",
        language: SyntaxLanguage.css
    )

    static let html = MiniPreviewPreset(
        id: .html,
        sampleText: """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
            body { color: red; }
            </style>
        </head>
        <body>
            <!-- greeting -->
            <script>
            const answer = 42;
            </script>
            <div class=\"message\">Hello</div>
        </body>
        </html>
        """,
        language: SyntaxLanguage.html
    )

    static let javascript = MiniPreviewPreset(
        id: .javascript,
        sampleText: """
        const answer = 42;
        function greet(name) {
            return `Hello, ${name}! ` + "\(String(repeating: "Hello, ", count: 120))";
        }
        """,
        language: SyntaxLanguage.javascript
    )

    static let json = MiniPreviewPreset(
        id: .json,
        sampleText: """
        {
          \"enabled\": true,
          \"count\": 1
        }
        """,
        language: SyntaxLanguage.json
    )

    static let objectiveC = MiniPreviewPreset(
        id: .objectiveC,
        sampleText: """
        #import <Foundation/Foundation.h>
        @interface Sample : NSObject
        @end
        """,
        language: SyntaxLanguage.objectiveC
    )

    static let swift = MiniPreviewPreset(
        id: .swift,
        sampleText: """
        struct Greeting {
            let message = \"Hello\"
        }
        """,
        language: SyntaxLanguage.swift
    )

    static let toml = MiniPreviewPreset(
        id: .toml,
        sampleText: """
        [package]
        name = \"SyntaxEditorUI\"
        enabled = true
        """,
        language: SyntaxLanguage.toml
    )

    static let xml = MiniPreviewPreset(
        id: .xml,
        sampleText: """
        <?xml version=\"1.0\"?>
        <note priority=\"high\">Hello</note>
        """,
        language: SyntaxLanguage.xml
    )

    static let all: [MiniPreviewPreset] = [
        css,
        html,
        javascript,
        json,
        objectiveC,
        swift,
        toml,
        xml,
    ]

    static func preset(for id: ID) -> MiniPreviewPreset? {
        all.first { $0.id == id }
    }
}
