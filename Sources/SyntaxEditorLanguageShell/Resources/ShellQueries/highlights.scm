; Remapped from tree-sitter-bash v0.25.1 queries/highlights.scm into this
; package's editor.syntax.<language>.<kind> capture scheme.

[
  (string)
  (raw_string)
  (heredoc_body)
  (heredoc_start)
] @editor.syntax.shell.string

(command_name) @editor.syntax.shell.identifier.function

(variable_name) @editor.syntax.shell.identifier.variable

[
  "case"
  "do"
  "done"
  "elif"
  "else"
  "esac"
  "export"
  "fi"
  "for"
  "function"
  "if"
  "in"
  "select"
  "then"
  "unset"
  "until"
  "while"
] @editor.syntax.shell.keyword

(comment) @editor.syntax.shell.comment

(function_definition name: (word) @editor.syntax.shell.identifier.function)

(file_descriptor) @editor.syntax.shell.number

(
  (command (_) @editor.syntax.shell.identifier.constant)
  (#match? @editor.syntax.shell.identifier.constant "^-")
)
