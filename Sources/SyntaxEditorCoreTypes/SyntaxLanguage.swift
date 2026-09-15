import Foundation

/// A built-in language mode for syntax highlighting and code editing.
///
/// Use ``plainText`` for text without code-aware editing transforms. Resolve
/// user-supplied identifiers with ``init(identifier:)``, and use `allCases`
/// to populate a language picker.
public enum SyntaxLanguage: String, Sendable, CaseIterable, Identifiable {
    /// Plain text without syntax highlighting or code-aware editing commands.
    case plainText = "plain-text"
    /// Basic ARM assembly highlighting, including common ARM64 syntax.
    ///
    /// This mode highlights directives, labels, literals, and comments. It does
    /// not validate instructions or cover every assembler dialect.
    case assemblyARM = "assembly-arm"
    /// Cascading Style Sheets.
    case css
    /// HTML, including embedded JavaScript and CSS highlighting.
    case html
    /// JavaScript source code.
    case javascript
    /// JSON data, without comment toggling.
    case json
    /// Objective-C source code.
    case objectiveC = "objective-c"
    case php
    /// Swift source code.
    case swift
    /// TOML configuration files.
    case toml
    /// XML documents.
    case xml
    case yaml
    case shell
    case markdown
    case markdownInline = "markdown-inline"

    /// The language's canonical identifier, suitable for an identifiable list.
    public var id: String {
        identifier
    }

    /// The canonical string used to store or restore this language selection.
    public var identifier: String {
        rawValue
    }

    /// The human-readable name for a language picker or editor label.
    public var displayName: String {
        switch self {
        case .plainText:
            "Plain Text"
        case .assemblyARM:
            "Assembly (ARM)"
        case .css:
            "CSS"
        case .html:
            "HTML"
        case .javascript:
            "JavaScript"
        case .json:
            "JSON"
        case .objectiveC:
            "Objective-C"
        case .php:
            "PHP"
        case .swift:
            "Swift"
        case .toml:
            "TOML"
        case .xml:
            "XML"
        case .yaml:
            "YAML"
        case .shell:
            "Shell"
        case .markdown:
            "Markdown"
        case .markdownInline:
            "Markdown (inline)"
        }
    }

    /// Resolves a canonical identifier or a supported alias.
    ///
    /// Matching ignores case and leading or trailing whitespace. Aliases
    /// include `js`, `htm`, `objc`, `txt`, and `text/plain`. Assembly aliases
    /// such as `asm`, `s`, `arm64`, and `aarch64` select ``assemblyARM``.
    /// Pass an identifier or file extension without a leading period, rather
    /// than a full filename.
    ///
    /// - Parameter rawIdentifier: The identifier or alias to resolve.
    /// - Returns: `nil` when the identifier is unsupported.
    public init?(identifier rawIdentifier: String) {
        let lowered = rawIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let language = Self.allCases.first(where: { $0.identifiers.contains(lowered) }) else {
            return nil
        }

        self = language
    }
}

extension SyntaxLanguage {
    package struct EditResult {
        package let edits: [SyntaxEditorTextChange.Replacement]
        package let selectedRange: NSRange

        package init(edits: [SyntaxEditorTextChange.Replacement], selectedRange: NSRange) {
            self.edits = edits
            self.selectedRange = selectedRange
        }
    }

    package var syntaxHighlightCacheKey: String {
        identifier
    }

    package static var syntaxHighlightedCases: [SyntaxLanguage] {
        allCases.filter(\.supportsSyntaxHighlighting)
    }

    /// Whether this mode provides syntax highlighting.
    ///
    /// This is `false` only for ``plainText``.
    public var supportsSyntaxHighlighting: Bool {
        switch self {
        case .plainText:
            false
        default:
            true
        }
    }

    /// Whether this mode enables code-aware editing transforms.
    ///
    /// This is `false` only for ``plainText``. Individual commands still depend
    /// on the language; for example, ``json`` does not support comment toggling.
    public var supportsCodeEditingCommands: Bool {
        self != .plainText
    }

    package var identifiers: Set<String> {
        switch self {
        case .plainText:
            ["plain-text", "plain", "plaintext", "text", "txt", "text/plain"]
        case .assemblyARM:
            ["assembly-arm", "arm-assembly", "asm", "assembly", "arm", "arm64", "aarch64", "s"]
        case .css:
            ["css"]
        case .html:
            ["html", "htm"]
        case .javascript:
            ["javascript", "js"]
        case .json:
            ["json"]
        case .objectiveC:
            ["objective-c", "objectivec", "objc"]
        case .php:
            ["php", "phtml"]
        case .swift:
            ["swift"]
        case .toml:
            ["toml"]
        case .xml:
            ["xml"]
        case .yaml:
            ["yaml", "yml"]
        case .shell:
            ["shell", "bash", "sh", "zsh"]
        case .markdown:
            ["markdown", "md", "mdown", "mkd"]
        case .markdownInline:
            ["markdown-inline", "markdown_inline"]
        }
    }
}
