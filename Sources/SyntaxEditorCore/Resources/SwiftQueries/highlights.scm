[
  "."
  ";"
  ":"
  ","
] @editor.syntax.swift.plain

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @editor.syntax.swift.plain

; Identifiers
(type_identifier) @editor.syntax.swift.identifier.type.system

[
  (self_expression)
  (super_expression)
] @editor.syntax.swift.keyword

; Declarations
[
  "func"
  "deinit"
] @editor.syntax.swift.keyword

[
  (visibility_modifier)
  (member_modifier)
  (function_modifier)
  (property_modifier)
  (parameter_modifier)
  (inheritance_modifier)
  (mutation_modifier)
] @editor.syntax.swift.keyword

(operator_declaration
  [
    "prefix"
    "infix"
    "postfix"
  ] @editor.syntax.swift.keyword)

(simple_identifier) @editor.syntax.swift.plain

(class_declaration
  name: (type_identifier) @editor.syntax.swift.declaration.type)

(protocol_declaration
  name: (type_identifier) @editor.syntax.swift.declaration.type)

(typealias_declaration
  name: (type_identifier) @editor.syntax.swift.declaration.other)

(typealias_declaration
  (type_identifier) @editor.syntax.swift.declaration.other)

(associatedtype_declaration
  name: (type_identifier) @editor.syntax.swift.declaration.other)

(associatedtype_declaration
  (type_identifier) @editor.syntax.swift.declaration.other)

(class_declaration
  "extension"
  name: (user_type
    (type_identifier) @editor.syntax.swift.declaration.type))

(function_declaration
  name: (simple_identifier) @editor.syntax.swift.declaration.other)

(protocol_function_declaration
  name: (simple_identifier) @editor.syntax.swift.declaration.other)

(macro_declaration
  (simple_identifier) @editor.syntax.swift.identifier.macro)

(source_file
  (property_declaration
    (value_binding_pattern
      "let")
    (pattern
      (simple_identifier) @editor.syntax.swift.declaration.other)))

(source_file
  (property_declaration
    (value_binding_pattern
      "var")
    (pattern
      (simple_identifier) @editor.syntax.swift.declaration.other)))

(class_body
  (property_declaration
    (value_binding_pattern
      "let")
    (pattern
      (simple_identifier) @editor.syntax.swift.declaration.other)))

(class_body
  (property_declaration
    (value_binding_pattern
      "var")
    (pattern
      (simple_identifier) @editor.syntax.swift.declaration.other)))

(enum_class_body
  (property_declaration
    (value_binding_pattern
      "let")
    (pattern
      (simple_identifier) @editor.syntax.swift.declaration.other)))

(enum_class_body
  (property_declaration
    (value_binding_pattern
      "var")
    (pattern
      (simple_identifier) @editor.syntax.swift.declaration.other)))

(protocol_property_declaration
  (pattern
    (simple_identifier) @editor.syntax.swift.declaration.other))

(enum_entry
  name: (simple_identifier) @editor.syntax.swift.declaration.other)

(enum_entry
  "case" @editor.syntax.swift.keyword)

(init_declaration
  "init" @editor.syntax.swift.keyword)

(parameter
  external_name: (simple_identifier) @editor.syntax.swift.plain)

(parameter
  name: (simple_identifier) @editor.syntax.swift.plain)

(type_parameter
  (type_identifier) @editor.syntax.swift.plain)

(inheritance_constraint
  (identifier
    (simple_identifier) @editor.syntax.swift.plain))

(equality_constraint
  (identifier
    (simple_identifier) @editor.syntax.swift.plain))

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
] @editor.syntax.swift.keyword

(associatedtype_declaration
  "associatedtype" @editor.syntax.swift.keyword)

(macro_declaration
  "macro" @editor.syntax.swift.keyword)

(operator_declaration
  "operator" @editor.syntax.swift.keyword)

(precedence_group_declaration
  "precedencegroup" @editor.syntax.swift.keyword)

(precedence_group_declaration
  (simple_identifier) @editor.syntax.swift.declaration.type)

((precedence_group_attribute
  (simple_identifier) @editor.syntax.swift.keyword)
 (#any-of? @editor.syntax.swift.keyword
   "associativity"
   "assignment"
   "higherThan"
   "left"
   "lowerThan"
   "none"
   "right"))

((precedence_group_attribute
  (simple_identifier) @editor.syntax.swift.identifier.type.system)
 (#match? @editor.syntax.swift.identifier.type.system "^[A-Z]"))

(class_declaration
  declaration_kind: "actor" @editor.syntax.swift.keyword)

[
  "enum"
  "struct"
  "class"
  "typealias"
] @editor.syntax.swift.keyword

((type_identifier) @editor.syntax.swift.keyword
  (#any-of? @editor.syntax.swift.keyword
    "Any"
    "Self"
    "Type"
    "Protocol"))

(function_declaration
  "async" @editor.syntax.swift.keyword)

(protocol_function_declaration
  "async" @editor.syntax.swift.keyword)

(init_declaration
  "async" @editor.syntax.swift.keyword)

(function_type
  "async" @editor.syntax.swift.keyword)

(lambda_function_type
  "async" @editor.syntax.swift.keyword)

(getter_specifier
  "async" @editor.syntax.swift.keyword)

(await_expression
  "await" @editor.syntax.swift.keyword)

((simple_identifier) @editor.syntax.swift.keyword
 (#eq? @editor.syntax.swift.keyword "isolated"))

((call_expression
  (simple_identifier) @editor.syntax.swift.keyword)
 (#eq? @editor.syntax.swift.keyword "defer"))

(shebang_line) @editor.syntax.swift.preprocessor

(navigation_expression
  (navigation_suffix
    (simple_identifier) @editor.syntax.swift.identifier.variable.system))

(value_argument
  name: (value_argument_label
    (simple_identifier) @editor.syntax.swift.plain))

(import_declaration
  "import" @editor.syntax.swift.keyword)

; BEGIN GENERATED EDITOR SYNTAX WORDS: swift-attributes
((modifiers
  (attribute
    "@" @editor.syntax.swift.keyword
    (user_type
      (type_identifier) @editor.syntax.swift.keyword)))
  (#any-of? @editor.syntax.swift.keyword
    "@"
    "GKInspectable"
    "IBAction"
    "IBDesignable"
    "IBInspectable"
    "IBOutlet"
    "IBSegueAction"
    "NSApplicationMain"
    "NSCopying"
    "NSManaged"
    "Sendable"
    "UIApplicationMain"
    "_implementationOnly"
    "_spi"
    "actorIndependent"
    "asyncHandler"
    "attached"
    "autoclosure"
    "available"
    "backDeployed"
    "concurrent"
    "convention"
    "discardableResult"
    "dynamicCallable"
    "dynamicMemberLookup"
    "escaping"
    "freestanding"
    "frozen"
    "globalActor"
    "implementation"
    "inlinable"
    "inline"
    "isolated"
    "main"
    "nonobjc"
    "noreturn"
    "objc"
    "objcMembers"
    "preconcurrency"
    "propertyWrapper"
    "requires_stored_property_inits"
    "resultBuilder"
    "retroactive"
    "safe"
    "specialized"
    "storageRestrictions"
    "testable"
    "unchecked"
    "unknown"
    "unsafe"
    "usableFromInline"
    "warn_unqualified_access"
  ))

((attribute
  "@" @editor.syntax.swift.keyword
  (user_type
    (type_identifier) @editor.syntax.swift.keyword))
  (#any-of? @editor.syntax.swift.keyword
    "@"
    "GKInspectable"
    "IBAction"
    "IBDesignable"
    "IBInspectable"
    "IBOutlet"
    "IBSegueAction"
    "NSApplicationMain"
    "NSCopying"
    "NSManaged"
    "Sendable"
    "UIApplicationMain"
    "_implementationOnly"
    "_spi"
    "actorIndependent"
    "asyncHandler"
    "attached"
    "autoclosure"
    "available"
    "backDeployed"
    "concurrent"
    "convention"
    "discardableResult"
    "dynamicCallable"
    "dynamicMemberLookup"
    "escaping"
    "freestanding"
    "frozen"
    "globalActor"
    "implementation"
    "inlinable"
    "inline"
    "isolated"
    "main"
    "nonobjc"
    "noreturn"
    "objc"
    "objcMembers"
    "preconcurrency"
    "propertyWrapper"
    "requires_stored_property_inits"
    "resultBuilder"
    "retroactive"
    "safe"
    "specialized"
    "storageRestrictions"
    "testable"
    "unchecked"
    "unknown"
    "unsafe"
    "usableFromInline"
    "warn_unqualified_access"
  ))
; END GENERATED EDITOR SYNTAX WORDS: swift-attributes

(modifiers
  (attribute
    "@" @editor.syntax.swift.identifier.type.system
    (user_type
      (type_identifier) @editor.syntax.swift.identifier.type.system)))

(macro_invocation
  "#" @editor.syntax.swift.identifier.macro.system
  (simple_identifier) @editor.syntax.swift.identifier.macro.system)

(external_macro_definition) @editor.syntax.swift.identifier.macro.system

; Function calls
(call_expression
  (simple_identifier) @editor.syntax.swift.identifier.function.system)

(call_expression
  (navigation_expression
    (navigation_suffix
      (simple_identifier) @editor.syntax.swift.identifier.function.system)))

(call_expression
  (prefix_expression
    (simple_identifier) @editor.syntax.swift.identifier.function.system))

((navigation_expression
  (simple_identifier) @editor.syntax.swift.identifier.type.system)
  (#match? @editor.syntax.swift.identifier.type.system "^[A-Z]"))

(directive) @editor.syntax.swift.preprocessor

(directive
  [
    "#if"
    "#elseif"
    "#else"
    "#endif"
  ] @editor.syntax.swift.preprocessor)

(directive
  [
    "!"
    ">="
    "<="
    "=="
    "!="
    ">"
    "<"
    "&&"
    "||"
    "."
    ":"
    "("
    ")"
    ","
    "swift"
    "compiler"
    "os"
    "canImport"
  ] @editor.syntax.swift.preprocessor)

(directive
  (simple_identifier) @editor.syntax.swift.preprocessor)

(directive
  (integer_literal) @editor.syntax.swift.preprocessor)

(directive
  (real_literal) @editor.syntax.swift.preprocessor)

(directive
  (wildcard_pattern) @editor.syntax.swift.preprocessor)

(ERROR
  [
    "#if"
    "#elseif"
    "#else"
    "#endif"
    "!"
    ">="
    "<="
    "=="
    "!="
    ">"
    "<"
    "&&"
    "||"
    "."
    ":"
    "("
    ")"
    ","
    "swift"
    "compiler"
    "os"
    "canImport"
  ] @editor.syntax.swift.preprocessor)

(ERROR
  (simple_identifier) @editor.syntax.swift.preprocessor)

(ERROR
  (integer_literal) @editor.syntax.swift.preprocessor)

(ERROR
  (real_literal) @editor.syntax.swift.preprocessor)

(ERROR
  (wildcard_pattern) @editor.syntax.swift.preprocessor)

(availability_condition
  "#" @editor.syntax.swift.keyword)

(availability_condition
  [
    "available"
    "unavailable"
  ] @editor.syntax.swift.keyword)

[
  (diagnostic)
  (availability_condition)
  (playground_literal)
  (key_path_string_expression)
  (selector_expression)
] @editor.syntax.swift.identifier.macro.system

(special_literal) @editor.syntax.swift.identifier.macro.system

; Statements
(for_statement
  "for" @editor.syntax.swift.keyword)

(for_statement
  "in" @editor.syntax.swift.keyword)

[
  "while"
  "repeat"
  "continue"
  "break"
] @editor.syntax.swift.keyword

(guard_statement
  "guard" @editor.syntax.swift.keyword)

(if_statement
  "if" @editor.syntax.swift.keyword)

(switch_statement
  "switch" @editor.syntax.swift.keyword)

(switch_entry
  "case" @editor.syntax.swift.keyword)

(switch_entry
  "fallthrough" @editor.syntax.swift.keyword)

(switch_entry
  (default_keyword) @editor.syntax.swift.keyword)

"return" @editor.syntax.swift.keyword

(ternary_expression
  [
    "?"
    ":"
  ] @editor.syntax.swift.keyword)

[
  (try_operator)
  "do"
  (throw_keyword)
  (catch_keyword)
] @editor.syntax.swift.keyword

(statement_label) @editor.syntax.swift.plain

; Comments
[
  (comment)
  (multiline_comment)
] @editor.syntax.swift.comment

((comment) @editor.syntax.swift.comment.doc
  (#match? @editor.syntax.swift.comment.doc "^///[^/]"))

((comment) @editor.syntax.swift.comment.doc
  (#match? @editor.syntax.swift.comment.doc "^///$"))

((multiline_comment) @editor.syntax.swift.comment.doc
  (#match? @editor.syntax.swift.comment.doc "^/[*][*][^*].*[*]/$"))

; String literals
(line_str_text) @editor.syntax.swift.string

(str_escaped_char) @editor.syntax.swift.string

(multi_line_str_text) @editor.syntax.swift.string

(raw_str_part) @editor.syntax.swift.string

(raw_str_end_part) @editor.syntax.swift.string

(line_string_literal
  [
    "\\("
    ")"
  ] @editor.syntax.swift.plain)

(multi_line_string_literal
  [
    "\\("
    ")"
  ] @editor.syntax.swift.plain)

(raw_str_interpolation
  [
    (raw_str_interpolation_start)
    ")"
  ] @editor.syntax.swift.plain)

[
  "\""
  "\"\"\""
] @editor.syntax.swift.string

; Lambda literals
(lambda_literal
  "in" @editor.syntax.swift.keyword)

; Basic literals
[
  (integer_literal)
  (hex_literal)
  (oct_literal)
  (bin_literal)
] @editor.syntax.swift.number

(real_literal) @editor.syntax.swift.number

(boolean_literal) @editor.syntax.swift.keyword

"nil" @editor.syntax.swift.keyword

(wildcard_pattern) @editor.syntax.swift.character

; Regex literals
(regex_literal) @editor.syntax.swift.string

; Operators
(custom_operator) @editor.syntax.swift.plain

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
] @editor.syntax.swift.plain

(type_arguments
  [
    "<"
    ">"
  ] @editor.syntax.swift.plain)
