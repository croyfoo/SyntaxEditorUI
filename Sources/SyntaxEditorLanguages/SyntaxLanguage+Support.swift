import Foundation
@_exported import SyntaxEditorCoreTypes
import SyntaxEditorLanguageCSS
import SyntaxEditorLanguageHTML
import SyntaxEditorLanguageJavaScript
import SyntaxEditorLanguageJSON
import SyntaxEditorLanguageObjectiveC
import SyntaxEditorLanguagePlainText
import SyntaxEditorLanguageSupport
import SyntaxEditorLanguageSwift
import SyntaxEditorLanguageTOML
import SyntaxEditorLanguageXML

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
        case .swift:
            SwiftLanguage()
        case .toml:
            TOMLLanguage()
        case .xml:
            XMLLanguage()
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

