import Foundation
@_exported import SyntaxEditorCoreTypes
import SyntaxEditorLanguageCSS
import SyntaxEditorLanguageHTML
import SyntaxEditorLanguageJavaScript
import SyntaxEditorLanguageJSON
import SyntaxEditorLanguageMarkdown
import SyntaxEditorLanguageMarkdownInline
import SyntaxEditorLanguageObjectiveC
import SyntaxEditorLanguagePHP
import SyntaxEditorLanguagePlainText
import SyntaxEditorLanguageShell
import SyntaxEditorLanguageSupport
import SyntaxEditorLanguageSwift
import SyntaxEditorLanguageTOML
import SyntaxEditorLanguageXML
import SyntaxEditorLanguageYAML

package extension SyntaxLanguage {
    var support: any SyntaxLanguageSupport {
        switch self {
        case .plainText:
            PlainTextLanguage()
        case .css:
            CSSLanguage()
        case .html:
            HTMLLanguage()
        case .javascript:
            JavaScriptLanguage()
        case .json:
            JSONLanguage()
        case .objectiveC:
            ObjectiveCLanguage()
        case .php:
            PHPLanguage()
        case .swift:
            SwiftLanguage()
        case .toml:
            TOMLLanguage()
        case .xml:
            XMLLanguage()
        case .yaml:
            YAMLLanguage()
        case .shell:
            ShellLanguage()
        case .markdown:
            MarkdownLanguage()
        case .markdownInline:
            MarkdownInlineLanguage()
        }
    }

    var treeSitterSupport: SyntaxLanguageTreeSitterSupport? {
        support.treeSitterSupport
    }

    func toggleComment(source: String, selection: NSRange) -> SyntaxLanguage.EditResult? {
        support.toggleComment(source: source, selection: selection)
    }

    func isInsideLiteralOrComment(source: String, location: Int) -> Bool {
        support.isInsideLiteralOrComment(source: source, location: location)
    }
}
