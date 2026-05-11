[
  "."
  ";"
  ":"
  ","
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Identifiers
(type_identifier) @type.swift.reference

[
  (self_expression)
  (super_expression)
] @keyword

; Declarations
[
  "func"
  "deinit"
] @keyword.function

[
  (visibility_modifier)
  (member_modifier)
  (function_modifier)
  (property_modifier)
  (parameter_modifier)
  (inheritance_modifier)
  (mutation_modifier)
] @keyword.modifier

(operator_declaration
  [
    "prefix"
    "infix"
    "postfix"
  ] @keyword.modifier)

(simple_identifier) @variable

(class_declaration
  name: (type_identifier) @declaration.swift.type.name)

(protocol_declaration
  name: (type_identifier) @declaration.swift.type.name)

(typealias_declaration
  name: (type_identifier) @declaration.swift.other.name)

(typealias_declaration
  (type_identifier) @declaration.swift.other.name)

(associatedtype_declaration
  name: (type_identifier) @declaration.swift.other.name)

(associatedtype_declaration
  (type_identifier) @declaration.swift.other.name)

(class_declaration
  "extension"
  name: (user_type
    (type_identifier) @declaration.swift.type.name))

(function_declaration
  name: (simple_identifier) @declaration.swift.function.name)

(protocol_function_declaration
  name: (simple_identifier) @declaration.swift.function.name)

(macro_declaration
  (simple_identifier) @declaration.swift.macro.name)

(source_file
  (property_declaration
    (value_binding_pattern
      "let")
    (pattern
      (simple_identifier) @declaration.swift.constant.name)))

(source_file
  (property_declaration
    (value_binding_pattern
      "var")
    (pattern
      (simple_identifier) @declaration.swift.property.name)))

(class_body
  (property_declaration
    (value_binding_pattern
      "let")
    (pattern
      (simple_identifier) @declaration.swift.constant.name)))

(class_body
  (property_declaration
    (value_binding_pattern
      "var")
    (pattern
      (simple_identifier) @declaration.swift.property.name)))

(enum_class_body
  (property_declaration
    (value_binding_pattern
      "let")
    (pattern
      (simple_identifier) @declaration.swift.constant.name)))

(enum_class_body
  (property_declaration
    (value_binding_pattern
      "var")
    (pattern
      (simple_identifier) @declaration.swift.property.name)))

(protocol_property_declaration
  (pattern
    (simple_identifier) @declaration.swift.property.name))

(enum_entry
  name: (simple_identifier) @declaration.swift.constant.name)

(enum_entry
  "case" @keyword)

(init_declaration
  "init" @constructor)

(parameter
  external_name: (simple_identifier) @variable.parameter)

(parameter
  name: (simple_identifier) @variable.parameter)

(type_parameter
  (type_identifier) @variable.parameter)

(inheritance_constraint
  (identifier
    (simple_identifier) @variable.parameter))

(equality_constraint
  (identifier
    (simple_identifier) @variable.parameter))

[
  "protocol"
  "extension"
  "indirect"
  "nonisolated"
  "override"
  "convenience"
  "required"
  "some"
  "any"
  "weak"
  "unowned"
  "didSet"
  "willSet"
  "subscript"
  "let"
  "var"
  (throws)
  (where_keyword)
  (getter_specifier)
  (setter_specifier)
  (modify_specifier)
  (else)
  (as_operator)
] @keyword

(associatedtype_declaration
  "associatedtype" @keyword.function)

(macro_declaration
  "macro" @keyword.function)

(operator_declaration
  "operator" @keyword.function)

(precedence_group_declaration
  "precedencegroup" @keyword.function)

(class_declaration
  declaration_kind: "actor" @keyword.type)

[
  "enum"
  "struct"
  "class"
  "typealias"
] @keyword.type

((type_identifier) @keyword.swift.type.builtin
  (#any-of? @keyword.swift.type.builtin
    "Any"
    "Self"
    "Type"
    "Protocol"))

(function_declaration
  "async" @keyword.coroutine)

(protocol_function_declaration
  "async" @keyword.coroutine)

(init_declaration
  "async" @keyword.coroutine)

(function_type
  "async" @keyword.coroutine)

(lambda_function_type
  "async" @keyword.coroutine)

(getter_specifier
  "async" @keyword.coroutine)

(await_expression
  "await" @keyword.coroutine)

(shebang_line) @keyword.directive

(class_body
  (property_declaration
    (pattern
      (simple_identifier) @variable.member)))

(protocol_property_declaration
  (pattern
    (simple_identifier) @variable.member))

(navigation_expression
  (navigation_suffix
    (simple_identifier) @variable.member))

(value_argument
  name: (value_argument_label
    (simple_identifier) @variable.member))

(import_declaration
  "import" @keyword.import)

((modifiers
  (attribute
    "@" @keyword.swift.attribute.builtin.punctuation
    (user_type
      (type_identifier) @keyword.swift.attribute.builtin)))
  (#any-of? @keyword.swift.attribute.builtin
    "available"
    "backDeployed"
    "discardableResult"
    "dynamicCallable"
    "dynamicMemberLookup"
    "frozen"
    "GKInspectable"
    "inlinable"
    "main"
    "nonobjc"
    "NSApplicationMain"
    "NSCopying"
    "NSManaged"
    "objc"
    "objcMembers"
    "preconcurrency"
    "propertyWrapper"
    "resultBuilder"
    "requires_stored_property_inits"
    "testable"
    "UIApplicationMain"
    "unchecked"
    "usableFromInline"
    "warn_unqualified_access"
    "IBAction"
    "IBSegueAction"
    "IBOutlet"
    "IBDesignable"
    "IBInspectable"
    "attached"
    "autoclosure"
    "convention"
    "escaping"
    "freestanding"
    "Sendable"
    "unknown"))

(modifiers
  (attribute
    "@" @attribute.swift.punctuation
    (user_type
      (type_identifier) @attribute.swift.name)))

(macro_invocation
  "#" @function.swift.macro
  (simple_identifier) @function.swift.macro)

(external_macro_definition) @function.swift.macro

; Function calls
(call_expression
  (simple_identifier) @function.swift.call)

(call_expression
  (navigation_expression
    (navigation_suffix
      (simple_identifier) @function.swift.call)))

(call_expression
  (prefix_expression
    (simple_identifier) @function.swift.call))

((navigation_expression
  (simple_identifier) @type.swift.reference)
  (#match? @type.swift.reference "^[A-Z]"))

(directive) @keyword.directive

[
  (diagnostic)
  (availability_condition)
  (playground_literal)
  (key_path_string_expression)
  (selector_expression)
] @function.swift.macro

(special_literal) @constant.macro

; Statements
(for_statement
  "for" @keyword.repeat)

(for_statement
  "in" @keyword.repeat)

[
  "while"
  "repeat"
  "continue"
  "break"
] @keyword.repeat

(guard_statement
  "guard" @keyword.conditional)

(if_statement
  "if" @keyword.conditional)

(switch_statement
  "switch" @keyword.conditional)

(switch_entry
  "case" @keyword)

(switch_entry
  "fallthrough" @keyword)

(switch_entry
  (default_keyword) @keyword)

"return" @keyword.return

(ternary_expression
  [
    "?"
    ":"
  ] @keyword.conditional.ternary)

[
  (try_operator)
  "do"
  (throw_keyword)
  (catch_keyword)
] @keyword.exception

(statement_label) @label

; Comments
[
  (comment)
  (multiline_comment)
] @comment @spell

((comment) @comment.documentation
  (#match? @comment.documentation "^///[^/]"))

((comment) @comment.documentation
  (#match? @comment.documentation "^///$"))

((multiline_comment) @comment.documentation
  (#match? @comment.documentation "^/[*][*][^*].*[*]/$"))

; String literals
(line_str_text) @string

(str_escaped_char) @string.escape

(multi_line_str_text) @string

(raw_str_part) @string

(raw_str_end_part) @string

(line_string_literal
  [
    "\\("
    ")"
  ] @punctuation.special)

(multi_line_string_literal
  [
    "\\("
    ")"
  ] @punctuation.special)

(raw_str_interpolation
  [
    (raw_str_interpolation_start)
    ")"
  ] @punctuation.special)

[
  "\""
  "\"\"\""
] @string

; Lambda literals
(lambda_literal
  "in" @keyword.operator)

; Basic literals
[
  (integer_literal)
  (hex_literal)
  (oct_literal)
  (bin_literal)
] @number

(real_literal) @number.float

(boolean_literal) @boolean

"nil" @constant.builtin

(wildcard_pattern) @character.special

; Regex literals
(regex_literal) @string.regexp

; Operators
(custom_operator) @operator

[
  "+"
  "-"
  "*"
  "/"
  "%"
  "="
  "+="
  "-="
  "*="
  "/="
  "<"
  ">"
  "<<"
  ">>"
  "<="
  ">="
  "++"
  "--"
  "^"
  "&"
  "&&"
  "|"
  "||"
  "~"
  "%="
  "!="
  "!=="
  "=="
  "==="
  "?"
  "??"
  "->"
  "..<"
  "..."
  (bang)
] @operator

(type_arguments
  [
    "<"
    ">"
  ] @punctuation.bracket)
