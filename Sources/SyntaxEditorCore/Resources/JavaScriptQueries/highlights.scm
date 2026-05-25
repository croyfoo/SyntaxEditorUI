; Variables
;----------

(identifier) @editor.syntax.javascript.plain

; Properties
;-----------

(property_identifier) @editor.syntax.javascript.attribute

; Function and method definitions
;--------------------------------

(function_expression
  name: (identifier) @editor.syntax.javascript.identifier.function.system)
(function_declaration
  name: (identifier) @editor.syntax.javascript.identifier.function.system)
(method_definition
  name: (property_identifier) @editor.syntax.javascript.identifier.function.system)

(pair
  key: (property_identifier) @editor.syntax.javascript.identifier.function.system
  value: [(function_expression) (arrow_function)])

(assignment_expression
  left: (member_expression
    property: (property_identifier) @editor.syntax.javascript.identifier.function.system)
  right: [(function_expression) (arrow_function)])

(variable_declarator
  name: (identifier) @editor.syntax.javascript.identifier.function.system
  value: [(function_expression) (arrow_function)])

(assignment_expression
  left: (identifier) @editor.syntax.javascript.identifier.function.system
  right: [(function_expression) (arrow_function)])

; Function and method calls
;--------------------------

(call_expression
  function: (identifier) @editor.syntax.javascript.identifier.function.system)

(call_expression
  function: (member_expression
    property: (property_identifier) @editor.syntax.javascript.identifier.function.system))

; Special identifiers
;--------------------

((identifier) @editor.syntax.javascript.identifier.type.system
 (#match? @editor.syntax.javascript.identifier.type.system "^[A-Z]"))

([
    (identifier)
    (shorthand_property_identifier)
    (shorthand_property_identifier_pattern)
 ] @editor.syntax.javascript.identifier.constant
 (#match? @editor.syntax.javascript.identifier.constant "^[A-Z_][A-Z\\d_]+$"))

((identifier) @editor.syntax.javascript.plain
 (#match? @editor.syntax.javascript.plain "^(arguments|module|console|window|document)$")
 (#is-not? local))

((identifier) @editor.syntax.javascript.identifier.function.system
 (#eq? @editor.syntax.javascript.identifier.function.system "require")
 (#is-not? local))

; Literals
;---------

(this) @editor.syntax.javascript.plain
(super) @editor.syntax.javascript.plain

[
  (true)
  (false)
  (null)
  (undefined)
] @editor.syntax.javascript.keyword

(comment) @editor.syntax.javascript.comment

[
  (string)
  (template_string)
] @editor.syntax.javascript.string

(regex) @editor.syntax.javascript.string
(number) @editor.syntax.javascript.number

; Tokens
;-------

[
  ";"
  (optional_chain)
  "."
  ","
] @editor.syntax.javascript.plain

[
  "-"
  "--"
  "-="
  "+"
  "++"
  "+="
  "*"
  "*="
  "**"
  "**="
  "/"
  "/="
  "%"
  "%="
  "<"
  "<="
  "<<"
  "<<="
  "="
  "=="
  "==="
  "!"
  "!="
  "!=="
  "=>"
  ">"
  ">="
  ">>"
  ">>="
  ">>>"
  ">>>="
  "~"
  "^"
  "&"
  "|"
  "^="
  "&="
  "|="
  "&&"
  "||"
  "??"
  "&&="
  "||="
  "??="
] @editor.syntax.javascript.plain

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
]  @editor.syntax.javascript.plain

(template_substitution
  "${" @editor.syntax.javascript.plain
  "}" @editor.syntax.javascript.plain) @editor.syntax.javascript.plain

[
  "as"
  "async"
  "await"
  "break"
  "case"
  "catch"
  "class"
  "const"
  "continue"
  "debugger"
  "default"
  "delete"
  "do"
  "else"
  "export"
  "extends"
  "finally"
  "for"
  "from"
  "function"
  "get"
  "if"
  "import"
  "in"
  "instanceof"
  "let"
  "new"
  "of"
  "return"
  "set"
  "static"
  "switch"
  "target"
  "throw"
  "try"
  "typeof"
  "var"
  "void"
  "while"
  "with"
  "yield"
] @editor.syntax.javascript.keyword
